#!/usr/bin/env python3
"""Split the MicroLinux package repository out of the root filesystem.

Called by post-build.sh (Buildroot post-build stage). The base system is
exactly what the system configuration alone enables: Kconfig is run on
configs/fragments/common.config + <arch>.config (without repo.config) and every
package it enables, plus the build dependencies of those packages, is a base
package. Every other target package belongs to the repository; those named in
repo.config are its applications ("app"), the rest are dependencies ("lib"). For each
repository package, the files Buildroot recorded as installed by it
(build/packages-file-list.txt) are moved from TARGET_DIR to
BINARIES_DIR/repo-root/<name>/, with a .mlpkg/info that lists its version,
description and the repository packages it depends on. post-image.sh turns
those trees into .mlp images and the INDEX.

    repo-split.py TARGET_DIR
Environment (set by Buildroot): BASE_DIR BUILD_DIR BINARIES_DIR BR2_EXTERNAL_MICROLINUX_PATH
"""
import glob, json, os, re, shutil, subprocess, sys

T = sys.argv[1]
BASE, BUILD, BIN = os.environ["BASE_DIR"], os.environ["BUILD_DIR"], os.environ["BINARIES_DIR"]
EXT = os.environ["BR2_EXTERNAL_MICROLINUX_PATH"]
OUT = os.path.join(BIN, "repo-root")
# the top of the Buildroot tree (relative package_dir entries are relative to it)
TOPDIR = os.getcwd()
for line in open(os.path.join(BASE, "Makefile")):
    m = re.match(r"MAKEARGS := -C (\S+)", line)
    if m:
        TOPDIR = m.group(1)


def log(msg):
    print(">>> microlinux repo: " + msg, flush=True)


# --- package graph (Buildroot's own) -------------------------------------------------
env = {k: os.environ[k] for k in ("PATH", "HOME") if k in os.environ}
info = json.loads(subprocess.run(["make", "-s", "-C", BASE, "show-info"], env=env, check=True,
                                 capture_output=True, text=True).stdout)
target = {n for n, d in info.items() if d.get("type") == "target"}


# dependencies that external.mk switches off (optional features of base packages)
IGNORED_EDGES = {("util-linux", "python3"), ("parted", "lvm2"), ("libinput", "lua"),
                 ("libdrm", "valgrind"), ("mesa3d", "valgrind"), ("libgtk3", "cups")}


def deps(n):
    d = [x for x in info[n].get("dependencies", []) if x in target and (n, x) not in IGNORED_EDGES]
    if n == "busybox":
        # busybox "depends" on every package that replaces one of its applets,
        # only so that it is installed after them; that is not a real dependency
        d = [x for x in d if x in ("toolchain", "skeleton", "libxcrypt")]
    return d


def closure(roots):
    seen, todo = set(), list(roots)
    while todo:
        n = todo.pop()
        if n not in seen:
            seen.add(n)
            todo.extend(deps(n))
    return seen


# packages named in a config fragment (sub-options are ignored)
# Only symbols that exist: the kernel (BR2_LINUX_KERNEL), GRUB, the toolchain,
# udev and virtual providers have no BR2_PACKAGE_<NAME> and so are always base.
real = set(re.findall(r"^(?:# )?(BR2_PACKAGE_\w+)[= ]", open(os.environ["BR2_CONFIG"]).read(), re.M))
sym = {k: n for n in target for k in ["BR2_PACKAGE_" + n.upper().replace("-", "_")] if k in real}


def named_in(fragment):
    found = set()
    for line in open(os.path.join(EXT, "configs", "fragments", fragment)):
        m = re.match(r"(BR2_PACKAGE_\w+)=y", line)
        if m and m.group(1) in sym:
            found.add(sym[m.group(1)])
    return found


def base_config_packages():
    """Packages enabled by the base configuration alone (Kconfig selects included)."""
    d = os.path.join(BUILD, "microlinux-baseconfig")
    os.makedirs(d, exist_ok=True)
    frag = os.path.join(EXT, "configs", "fragments")
    with open(os.path.join(d, "defconfig"), "w") as f:
        for name in ("common.config", f"{arch}.config"):
            f.write(open(os.path.join(frag, name)).read() + "\n")
    subprocess.run(["make", "-s", "-C", TOPDIR, f"O={d}", f"BR2_EXTERNAL={EXT}",
                    f"BR2_DEFCONFIG={d}/defconfig", "defconfig"], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    on = set(re.findall(r"^(BR2_PACKAGE_\w+)=y", open(os.path.join(d, ".config")).read(), re.M))
    return {sym[x] for x in on if x in sym}


arch = re.search(r'^BR2_ARCH="(.*)"', open(os.environ["BR2_CONFIG"]).read(), re.M).group(1)
roots = named_in("repo.config")
# toolchain, skeleton and other packages without a BR2_PACKAGE_ symbol are base
base = closure(base_config_packages() | (target - set(sym.values())))
repo = target - base
log(f"{len(roots)} requested packages, {len(repo)} repository packages (with dependencies), {len(base)} base packages")
kept = sorted(roots & base)
if kept:
    log("needed by the base system, kept there: " + " ".join(kept))

# --- file ownership --------------------------------------------------------------------
# A file can be listed for several packages (a later package re-installed or
# replaced it). If any of them is a base package, the file stays in the base
# system; otherwise the last repository package that wrote it owns it.
# busybox is listed for programs that replace its applets (it is installed
# after them) but only ever installs links to itself: it owns nothing else.
owners = {}
for line in open(os.path.join(BUILD, "packages-file-list.txt")):
    pkg, _, path = line.rstrip("\n").partition(",")
    owners.setdefault(os.path.normpath(path.lstrip(".")), []).append(pkg)
owner = {}
for path, pkgs in owners.items():
    real = [p for p in pkgs if p != "busybox"] or pkgs
    owner[path] = next((p for p in real if p in base), real[-1])


def owner_of(path):
    o = owner.get(path)
    if o is None:
        # compiled Python bytecode is generated at target-finalize, after the
        # file lists: it belongs to the package of the matching .py
        m = re.match(r"(.*)/__pycache__/([^/.]+)\.[^/]*\.pyc$", path)
        if m:
            o = owner.get(f"{m.group(1)}/{m.group(2)}.py")
    return o


moved = {n: [] for n in repo}
for root, dirs, files in os.walk(T):
    for f in files + [d for d in dirs if os.path.islink(os.path.join(root, d))]:
        full = os.path.join(root, f)
        rel = "/" + os.path.relpath(full, T)
        o = owner_of(rel)
        if o in repo:
            moved[o].append(rel)

if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)
for n, files in moved.items():
    for rel in files:
        # service start scripts are not shipped: nothing starts unless the user starts it
        if rel.startswith("/etc/init.d/"):
            os.unlink(T + rel)
            continue
        dst = os.path.join(OUT, n) + rel
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.rename(T + rel, dst)

# busybox applets that a moved package had replaced: put the busybox links back
links = glob.glob(os.path.join(BUILD, "busybox-*", "busybox.links"))
restored = 0
if links:
    gone = {os.path.realpath(T + rel) for files in moved.values() for rel in files}
    for applet in open(links[0]).read().split():
        p = T + applet
        if os.path.realpath(p) in gone and not os.path.lexists(p):
            os.symlink("/bin/busybox", p)
            restored += 1

# remove directories that are now empty (only those created by moved packages)
for root, dirs, files in os.walk(T, topdown=False):
    for d in dirs:
        p = os.path.join(root, d)
        if not os.path.islink(p) and not os.listdir(p) and any(
                os.path.isdir(os.path.join(OUT, n) + "/" + os.path.relpath(p, T)) for n in repo if moved[n]):
            os.rmdir(p)


# --- metadata -----------------------------------------------------------------------------
def description(n):
    c = os.path.join(TOPDIR, info[n].get("package_dir") or "", "Config.in")
    if os.path.exists(c):
        text, out, on = open(c).read().splitlines(), [], False
        for line in text:
            if re.match(r"\s*help\s*$", line):
                on = True
                continue
            if on:
                if not line.strip():
                    if out:
                        break
                    continue
                if not line.startswith("\t") and not line.startswith("  "):
                    break
                out.append(line.strip())
        s = " ".join(out)
        s = re.split(r"(?<=[a-z0-9)])\.\s", s + " ")[0].strip().rstrip(".")
        if s:
            return s.replace("|", "/")[:100]
    return n


nonempty = {n for n in repo if moved[n]}
for n in sorted(nonempty):
    dep = sorted((closure(deps(n)) - {n}) & nonempty)
    d = os.path.join(OUT, n, ".mlpkg")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "info"), "w") as f:
        f.write(f"name={n}\nversion={info[n].get('version') or '0'}\ntype=files\n"
                f"section={'app' if n in roots else 'lib'}\ndepends={' '.join(dep)}\n"
                f"description={description(n)}\nlicense={info[n].get('licenses') or '?'}\n")
# category of every package, for the package browser: from the
# "[category: ...]" in repo.config's section headings
category, cat = {}, None
for line in open(os.path.join(EXT, "configs", "fragments", "repo.config")):
    m = re.search(r"\[category: ([^\]]+)\]", line)
    if m:
        cat = m.group(1)
    m = re.match(r"(BR2_PACKAGE_\w+)=y", line)
    if m and m.group(1) in sym and cat:
        category.setdefault(sym[m.group(1)], cat)
with open(os.path.join(OUT, "CATEGORIES"), "w") as f:
    for n in sorted(nonempty):
        f.write(f"{n}|{category.get(n, 'Libraries')}\n")

# source of every package in the repository (license compliance: corresponding
# source is the upstream release plus the Buildroot patches, pinned by Buildroot)
with open(os.path.join(OUT, "SOURCES.txt"), "w") as f:
    f.write("MicroLinux package repository: package, version, license, upstream source.\n"
            "Built with Buildroot 2026.02.3; Buildroot's patches for each package are in\n"
            "https://gitlab.com/buildroot.org/buildroot/-/tree/2026.02.3/package\n\n")
    for n in sorted(nonempty):
        urls = []
        for dl in info[n].get("downloads", []):
            # drop Buildroot's method prefix ("https|urlencode+https://..."); upstream before mirrors
            uris = [re.sub(r"^[a-z|]+\+(?=[a-z]+://)", "", u) for u in dl.get("uris", [])]
            uris.sort(key=lambda u: "sources.buildroot.net" in u)
            if uris:
                urls.append(uris[0].rstrip("/") + "/" + dl.get("source", ""))
        f.write(f"{n} {info[n].get('version') or '-'} [{info[n].get('licenses') or '?'}] {' '.join(urls)}\n")

log(f"{len(nonempty)} packages with files, {sum(len(moved[n]) for n in nonempty)} files moved, "
    f"{restored} busybox links restored")
