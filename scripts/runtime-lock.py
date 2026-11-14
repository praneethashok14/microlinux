#!/usr/bin/env python3
"""Resolve the packages used by a compatibility runtime module (el7-runtime,
el10-runtime, debian-runtime) to exact package URLs + SHA-256 checksums taken
from the official repository metadata, and write
external/package/NAME-runtime/NAME-ARCH.lock and NAME-runtime-ARCH.hash.
Run again only to deliberately update the pin.

    python3 scripts/runtime-lock.py el7 aarch64     # CentOS 7.9.2009 (AltArch tree)
    python3 scripts/runtime-lock.py el7 x86_64      # CentOS 7.9.2009 (main tree)
    python3 scripts/runtime-lock.py el10 aarch64    # AlmaLinux 10.2
    python3 scripts/runtime-lock.py el10 x86_64     # AlmaLinux 10.2 (x86_64_v2 tree)
    python3 scripts/runtime-lock.py debian aarch64  # Debian 13 (snapshot.debian.org)
    python3 scripts/runtime-lock.py debian x86_64

el7 pins exactly the listed packages. el10 and debian add every package they
depend on (from the repository metadata), except EXCLUDE.
"""
import gzip, io, lzma, os, re, sys, urllib.request, xml.etree.ElementTree as ET

RELEASES = {
    "el7": {
        "title": "CentOS 7.9.2009", "format": "rpm",
        "base": {"aarch64": "https://vault.centos.org/altarch/7.9.2009",
                 "x86_64": "https://vault.centos.org/7.9.2009"},
        "repos": ["updates", "os"],        # updates first: newest builds win
        "tree": "{base}/{repo}/{arch}",
        "rpmarch": {"aarch64": "aarch64", "x86_64": "x86_64"},
        "closure": False,
        # Runtime libraries + the real EL7 programs used by the compatibility tests.
        "packages": """
glibc glibc-common libgcc libstdc++ zlib bzip2-libs xz-libs lz4
ncurses-libs ncurses-base readline pcre libselinux libsepol libattr libacl libcap
openssl openssl-libs krb5-libs keyutils-libs libcom_err libverto
nss-softokn-freebl libuuid libblkid libffi sqlite expat gmp mpfr elfutils-libelf
bash coreutils gawk sed grep tree bc which zip unzip file file-libs findutils
""",
    },
    "el10": {
        "title": "AlmaLinux 10.2", "format": "rpm",
        # moves to https://vault.almalinux.org/10.2 when 10.3 is released
        "base": {"aarch64": "https://repo.almalinux.org/almalinux/10.2",
                 "x86_64": "https://repo.almalinux.org/almalinux/10.2"},
        "repos": ["BaseOS", "AppStream"],
        # x86_64: the x86_64_v2 rebuild, so the runtime also works on CPUs
        # without AVX2 (RHEL 10 itself needs x86-64-v3)
        "tree": "{base}/{repo}/{rpmarch}/os",
        "rpmarch": {"aarch64": "aarch64", "x86_64": "x86_64_v2"},
        "closure": True,
        # Runtime libraries, everyday programs, and rpm to unpack/install RPMs
        # inside el10-chroot. Their dependencies are added automatically.
        "packages": """
glibc glibc-minimal-langpack libgcc libstdc++ zlib-ng-compat bzip2-libs xz-libs
lz4-libs libzstd ncurses-libs ncurses-base readline pcre2 libselinux libattr libacl
libcap openssl openssl-libs krb5-libs libuuid libblkid libmount libffi sqlite-libs
expat gmp mpfr elfutils-libelf libxcrypt glib2 libtool-ltdl
bash coreutils gawk sed grep which file findutils tree bc zip unzip tar gzip
cpio less rpm
""",
    },
    "debian": {
        "title": "Debian 13.7 (trixie)", "format": "deb",
        # a fixed snapshot: every file stays downloadable at these URLs
        "base": "https://snapshot.debian.org/archive/debian/20260913T000000Z",
        "security": "https://snapshot.debian.org/archive/debian-security/20260913T000000Z",
        "dist": "trixie",
        "debarch": {"aarch64": "arm64", "x86_64": "amd64"},
        "closure": True,
        # Runtime libraries, everyday programs, and dpkg to install .deb
        # packages inside deb-chroot. Their dependencies are added automatically.
        "packages": """
base-files libc6 libc-bin libgcc-s1 libstdc++6 zlib1g libbz2-1.0 liblzma5 liblz4-1
libzstd1 libtinfo6 libncursesw6 libreadline8t64 libpcre2-8-0 libselinux1 libacl1
libattr1 libcap2 libssl3t64 openssl libgssapi-krb5-2 libuuid1 libblkid1 libmount1
libffi8 libsqlite3-0 libexpat1 libgmp10 libmpfr6 libelf1t64 libcrypt1
libglib2.0-0t64 libltdl7 libcurl4t64
bash coreutils gawk sed grep debianutils file findutils tree bc zip unzip tar
gzip cpio less curl dpkg dash diffutils
""",
    },
}

# never pulled in as a dependency (services, other language packs, the CA
# store, which the runtimes link to the system one, ...)
EXCLUDE = re.compile(r"^(systemd(?!-libs$).*|libsystemd-shared|dbus.*|python3.*|perl.*|glibc-langpack-.*|"
                     r"glibc-all-langpacks|glibc-gconv-extra|ca-certificates|"
                     r"p11-kit-trust|crypto-policies-scripts|tzdata|kernel.*|grub.*|"
                     r"dracut.*|util-linux-core|shadow-utils|setup|basesystem|"
                     r"filesystem|almalinux-.*|redhat-release.*|libsemanage|"
                     r"policycoreutils|selinux-policy.*|authselect.*|pam|"
                     r"rpm-plugin-.*|gnupg2|ima-evm-utils|gpgme|"
                     r"debconf|debconf-2.0|libpam-.*|login|passwd|adduser|init-system-helpers|"
                     r"sensible-utils|media-types|netbase|libdebconfclient0)$")

NAMES = {"7": "el7", "10": "el10"}
args = sys.argv[1:]
rel = NAMES.get(args[0], args[0]) if args and NAMES.get(args[0], args[0]) in RELEASES else "el7"
args = [a for a in args if NAMES.get(a, a) not in RELEASES]
ARCH = args[0] if args else "aarch64"
R = RELEASES[rel]
PACKAGES = R["packages"].split()

def fetch(url):
    with urllib.request.urlopen(url, timeout=300) as f:
        return f.read()

def rpmvercmp(a, b):
    """rpm's version comparison: alphanumeric segments, digits newer than
    letters, '~' sorts before everything."""
    while a or b:
        a = re.sub(r"^[^A-Za-z0-9~]+", "", a); b = re.sub(r"^[^A-Za-z0-9~]+", "", b)
        if a[:1] == "~" or b[:1] == "~":
            if a[:1] != "~": return 1
            if b[:1] != "~": return -1
            a, b = a[1:], b[1:]; continue
        if not a or not b:
            break
        pat = r"\d+" if a[0].isdigit() else r"[A-Za-z]+"
        ma, mb = re.match(pat, a), re.match(pat, b)
        if not mb:
            return 1 if a[0].isdigit() else -1
        x, y = ma.group(), mb.group()
        if a[0].isdigit():
            x, y = int(x), int(y)
        if x != y:
            return 1 if x > y else -1
        a, b = a[ma.end():], b[mb.end():]
    return (len(a) > 0) - (len(b) > 0)

def debvercmp(a, b):
    """dpkg's version comparison: non-digit runs character by character
    (letters before other characters, '~' before everything), digit runs
    numerically."""
    def order(c):
        if c == "~": return -1
        if c.isalpha(): return ord(c)
        return ord(c) + 256 if c else 0
    while a or b:
        na = re.match(r"^\D*", a).group(); nb = re.match(r"^\D*", b).group()
        for i in range(max(len(na), len(nb))):
            ca = na[i] if i < len(na) else ""; cb = nb[i] if i < len(nb) else ""
            if ca != cb: return 1 if order(ca) > order(cb) else -1
        a, b = a[len(na):], b[len(nb):]
        da = re.match(r"^\d*", a).group(); db = re.match(r"^\d*", b).group()
        if int(da or 0) != int(db or 0): return 1 if int(da or 0) > int(db or 0) else -1
        a, b = a[len(da):], b[len(db):]
    return 0

vercmp = debvercmp if R["format"] == "deb" else rpmvercmp

class EVR:
    def __init__(self, e, v, r): self.t = (int(e or 0), v, r or "")
    def __gt__(self, o):
        if self.t[0] != o.t[0]: return self.t[0] > o.t[0]
        c = vercmp(self.t[1], o.t[1])
        return c > 0 if c else vercmp(self.t[2], o.t[2]) > 0

def debevr(v):
    e, _, rest = v.rpartition(":") if ":" in v else ("0", "", v)
    up, _, rev = rest.rpartition("-") if "-" in rest else (rest, "", "")
    return EVR(e, up, rev)

best = {}          # name -> package record (newest build)
def offer(name, rec):
    if name not in best or rec["evr"] > best[name]["evr"]:
        best[name] = rec

if R["format"] == "rpm":
    C = "{http://linux.duke.edu/metadata/common}"
    P = "{http://linux.duke.edu/metadata/rpm}"
    NS = {"r": "http://linux.duke.edu/metadata/repo"}
    RPMARCH = R["rpmarch"][ARCH]
    for repo in R["repos"]:
        root = R["tree"].format(base=R["base"][ARCH], repo=repo, arch=ARCH, rpmarch=RPMARCH)
        repomd = ET.fromstring(fetch(f"{root}/repodata/repomd.xml"))
        href = next(d.find("r:location", NS).get("href")
                    for d in repomd.findall("r:data", NS) if d.get("type") == "primary")
        data = fetch(f"{root}/{href}")
        data = gzip.decompress(data) if href.endswith(".gz") else data
        for _, p in ET.iterparse(io.BytesIO(data)):
            if p.tag != C + "package":
                continue
            name, arch = p.find(C + "name").text, p.find(C + "arch").text
            if arch in (RPMARCH, "noarch") and (R["closure"] or name in PACKAGES):
                v = p.find(C + "version")
                cs = p.find(C + "checksum")
                if cs.get("type") != "sha256":
                    sys.exit(f"{name}: unexpected checksum type {cs.get('type')}")
                fmt = p.find(C + "format")
                lic, src = fmt.find(P + "license"), fmt.find(P + "sourcerpm")
                ent = lambda tag: [e.get("name") for e in fmt.findall(f"{P}{tag}/{P}entry")]
                offer(name, {"evr": EVR(v.get("epoch"), v.get("ver"), v.get("rel")),
                             "url": f"{root}/{p.find(C + 'location').get('href')}", "sha": cs.text,
                             "lic": lic.text if lic is not None else "?",
                             "src": src.text if src is not None else "?",
                             # rpm requires: one capability each
                             "req": [[r] for r in ent("requires")],
                             "prov": ent("provides") + [f.text for f in fmt.findall(C + "file")]})
            p.clear()
else:
    DEBARCH = R["debarch"][ARCH]
    for base, dist in ((R["base"], R["dist"]), (R["security"], R["dist"] + "-security")):
        text = lzma.decompress(fetch(f"{base}/dists/{dist}/main/binary-{DEBARCH}/Packages.xz")).decode()
        for stanza in text.split("\n\n"):
            f = {}
            for line in stanza.splitlines():
                if line[:1] not in (" ", "\t") and ":" in line:
                    k, _, v = line.partition(":"); f[k] = v.strip()
            if "Package" not in f or f.get("Architecture") not in (DEBARCH, "all"):
                continue
            rel_ = lambda k: [[re.sub(r"[\s(:].*", "", alt.strip()) for alt in dep.split("|")]
                              for dep in f.get(k, "").split(",") if dep.strip()]
            src = f.get("Source", f["Package"]).split(" ")[0]
            offer(f["Package"], {"evr": debevr(f["Version"]), "url": f"{base}/{f['Filename']}",
                                 "sha": f["SHA256"], "lic": "see_/usr/share/doc/" + f["Package"] + "/copyright",
                                 "src": f"{src}_{f['Version']}",
                                 # deb depends: lists of alternatives
                                 "req": rel_("Pre-Depends") + rel_("Depends"),
                                 "prov": [re.sub(r"[\s(].*", "", p.strip()) for p in f.get("Provides", "").split(",") if p.strip()]})

missing = sorted(set(PACKAGES) - set(best))
if missing:
    sys.exit("not found in repos: " + " ".join(missing))

chosen = set(PACKAGES)
if R["closure"]:
    providers = {}
    for n, rec in best.items():
        providers.setdefault(n, []).append(n)
        for c in rec["prov"]:
            providers.setdefault(c, []).append(n)
    todo = list(PACKAGES)
    while todo:
        for alts in best[todo.pop()]["req"]:
            alts = [a for a in alts if not a.startswith(("rpmlib(", "("))]
            cands = [c for a in alts for c in providers.get(a, [])]
            if not cands or any(c in chosen for c in cands):
                continue
            cands = [c for c in cands if not EXCLUDE.match(c)]
            if not cands:
                continue
            # the first alternative's own package, else the shortest name
            n = next((a for a in alts if a in cands), None) or min(cands, key=lambda c: (len(c), c))
            chosen.add(n); todo.append(n)

pins = {n: best[n] for n in sorted(chosen)}
out = os.path.join(os.path.dirname(__file__), "..", "external", "package", f"{rel}-runtime")
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, f"{rel}-{ARCH}.lock"), "w") as f:
    f.write(f"# name url sha256 license source  (generated by scripts/runtime-lock.py)\n")
    for n, r in pins.items():
        f.write(f"{n} {r['url']} {r['sha']} {r['lic'].replace(' ', '_')} {r['src']}\n")
with open(os.path.join(out, f"{rel}-runtime-{ARCH}.hash"), "w") as f:
    f.write(f"# From {R['title']} {ARCH} repository metadata (sha256)\n")
    for n, r in pins.items():
        f.write(f"sha256  {r['sha']}  {r['url'].rsplit('/', 1)[1]}\n")
print(f"pinned {len(pins)} {ARCH} packages")
