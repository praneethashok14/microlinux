#!/usr/bin/env python3
"""Generate the Buildroot packages of the KDE edition (KDE Frameworks, Plasma,
KDE Gear apps) from KDE's own data, and write:

  external/package/<name>/{<name>.mk,<name>.hash,Config.in}   one per package
  external/kde/Config.in                                        sources them all
  external/configs/fragments/kde-packages.config                the root packages

    python3 scripts/kde-gen.py            (re-run after changing ROOTS or versions)

Which KDE packages: ROOTS plus everything they need according to KDE's
dependency metadata (sysadmin/repo-metadata, dependency-data-kf6-qt6).
Versions and SHA-256: the release directories on download.kde.org (their
.sha256 files). Other dependencies: each tarball's CMakeLists.txt files
(find_package), mapped to Buildroot packages by FIND_MAP; names it can't map
are printed, so nothing is silently left out. Per-package additions: EXTRA.
Tarballs are cached in ~/.cache/microlinux-kde.
"""
import io, os, re, sys, tarfile, urllib.request

KF = "6.32"            # KDE Frameworks
PLASMA = "6.8.3"
GEAR = "26.08.3"       # KDE Gear (release service)
DL = "https://download.kde.org/stable"
META = "https://invent.kde.org/sysadmin/repo-metadata/-/raw/master/dependencies/dependency-data-kf6-qt6"
CACHE = os.path.expanduser("~/.cache/microlinux-kde")
TOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PKG = os.path.join(TOP, "external", "package")

# What the KDE edition has (their KDE dependencies are added automatically)
ROOTS = """
plasma-desktop plasma-workspace kwin systemsettings kscreen libkscreen powerdevil
plasma-nm plasma-pa bluedevil breeze kinfocenter kmenuedit
kscreenlocker polkit-kde-agent-1 xdg-desktop-portal-kde plasma-systemmonitor
ksystemstats kdeplasma-addons plasma-workspace-wallpapers discover sddm-kcm
plasma-disks plasma-integration qqc2-breeze-style kde-cli-tools milou kwrited
ocean-sound-theme spectacle kglobalacceld plasma-welcome kwallet-pam
dolphin konsole kate ark gwenview okular elisa kcalc kcharselect filelight
partitionmanager ksystemlog kwalletmanager kfind kdialog sweeper kcolorchooser
kruler dragon kio-extras ffmpegthumbs kdegraphics-thumbnailers kpat kmines
kmahjongg ksudoku keditbookmarks
""".split()

# never packaged (not useful here, or replaced): repositories named in the
# metadata that an included package lists but doesn't need on MicroLinux
SKIP = set("""
kapidox oxygen-icons kdav drkonqi plasma-firewall plasma-vault plasma-thunderbolt kup
krdp print-manager plymouth-kcm breeze-plymouth breeze-grub flatpak-kcm kuserfeedback
union cxx-rust-cssparser plasma-sdk plasma-nano kaccounts-integration selenium-webdriver-at-spi
kdsoap-ws-discovery-client libqaccessibilityclient phonon breeze-gtk kde-gtk-config kdoctools
""".split())
# KDE libraries released on their own (download.kde.org/stable/NAME)
OTHER = {
    "plasma-wayland-protocols": f"{DL}/plasma-wayland-protocols/plasma-wayland-protocols-1.23.0.tar.xz",
    "kirigami-addons": f"{DL}/kirigami-addons/kirigami-addons-1.16.1.tar.xz",
    "pulseaudio-qt": f"{DL}/pulseaudio-qt/pulseaudio-qt-1.9.0.tar.xz",
    "kquickimageeditor": f"{DL}/kquickimageeditor/kquickimageeditor-0.7.0.tar.xz",
    "qca": f"{DL}/qca/2.3.12/qca-2.3.12.tar.xz",
}

# Buildroot package names: frameworks kf6-NAME, other KDE packages kde-NAME,
# except these (existing names)
NAME = {"layer-shell-qt": "layer-shell-qt", "polkit-qt-1": "polkit-qt6"}

# optional extras (features MicroLinux doesn't use, other platforms, docs and tools)
OPTIONAL_FINDS = set("""
Git IcoTool ReuseTool Gradle PySide6 Shiboken6 Strigi SwitcherooControl SDL2 Sass PythonCairo GTKEngine
GSettingSchemas XSettingsd AppMenuGtkModule SoundThemeFreedesktop FontNotoSans FontNotoColorEmoji FontHack
Libeis-1.0 QAccessibilityClient6 Kapsule DDCUtil PackageKitQt6 ApkQt IMobileDevice PList IOKit Procstat
Devinfo Audit Journald CatDoc EditorConfig LibJXR OpenJPEG CFitsio LIBVLC UPNPQT BlackHoleSolver
FreecellSolver ImageMagick 7Zip 7z Dmtx HUNSPELL OpenMP Corrosion MediaPlayerInfo TIRPC LibSnoreToast
ConsoleKit LibKLookAndFeel LibNotificationManager LibTaskManager Aurorae Union SystemSettings
XDGDesktopPortalKDE XdgUserDir DocBookXML4 DocBookXSL PerlModules Inotify Xattr LibIntl Vulkan
HWY Pkcs11Helper XercesC kColorPicker-Qt6 kImageAnnotator-Qt6 libappimage libavif libpcap svgcleaner gzip
aha clinfo di-edid-decode dmidecode eglinfo fwupdmgr glxinfo ip libva-utils loginctl lsblk lscpu lspci
pciconf pipewire sensors smartctl vulkaninfo wayland-info xdpyinfo Phonon4Qt6 IsoCodes
""".split())

# find_package(NAME) -> Buildroot packages (empty: nothing to add, e.g. a part of
# Qt base or a KDE package, which the metadata covers)
FIND_MAP = {
    "ECM": [], "Qt6": [], "KF6": [], "Gettext": ["host-gettext"], "Intl": [], "Python3": ["host-python3"],
    "Wayland": ["wayland"], "WaylandScanner": ["host-wayland"], "WaylandProtocols": ["wayland-protocols"],
    "PlasmaWaylandProtocols": ["kde-plasma-wayland-protocols"], "XCB": ["libxcb", "xcb-util-wm", "xcb-util-keysyms", "xcb-util-image", "xcb-util-cursor"],
    "X11": ["xlib_libX11"], "XKB": ["libxkbcommon"], "XkbCommon": ["libxkbcommon"], "xkbcommon": ["libxkbcommon"],
    "ZLIB": ["zlib"], "BZip2": ["bzip2"], "LibLZMA": ["xz"], "zstd": ["zstd"], "Zstd": ["zstd"],
    "LibXml2": ["libxml2"], "LibXslt": ["libxslt"], "LibArchive": ["libarchive"], "Canberra": ["libcanberra"],
    "PipeWire": ["pipewire"], "Libinput": ["libinput"], "UDev": ["eudev"], "epoxy": ["libepoxy"],
    "Libdrm": ["libdrm"], "gbm": ["mesa3d"], "lcms2": ["lcms2"], "libdisplayinfo": ["libdisplay-info"],
    "Freetype": ["freetype"], "Fontconfig": ["fontconfig"], "Exiv2": ["exiv2"], "Poppler": ["poppler"],
    "Taglib": ["taglib"], "TagLib": ["taglib"], "QCoro6": ["kde-qcoro"], "KF6KirigamiAddons": ["kde-kirigami-addons"],
    "AppStreamQt": ["kde-appstream"], "Flatpak": ["kde-flatpak"], "NetworkManager": ["network-manager"],
    "ModemManager": ["modem-manager"], "PulseAudio": ["pulseaudio"], "GLIB2": ["libglib2"], "Sensors": ["lm-sensors"],
    "Boost": ["boost"], "yaml-cpp": ["yaml-cpp"], "KPMcore": ["kde-kpmcore"], "LibGit2": ["libgit2"],
    "Qalculate": ["libqalculate"], "GMP": ["gmp"], "MPFR": ["mpfr"], "Phonon4Qt6": ["kde-phonon"],
    "Qt6Keychain": ["kde-qtkeychain"], "Gpgmepp": [], "PolkitQt6-1": ["polkit-qt6"], "Polkit": ["polkit"],
    "LibKWorkspace": [], "KDecoration3": [], "Breeze": [], "KSysGuard": [], "Plasma": [], "PlasmaQuick": [],
    "PlasmaActivities": [], "PlasmaActivitiesStats": [], "Plasma5Support": [], "KScreenLocker": [], "KWinDBusInterface": [],
    "ScreenSaverDBusInterface": [], "KRunnerAppDBusInterface": [], "KPipeWire": [], "KWayland": [], "LayerShellQt": [],
    "KScreen": [], "KF6Kirigami": [], "Baloo": [], "KUserFeedback": [], "PlasmaQuick6": [],
    "PkgConfig": ["host-pkgconf"], "Threads": [], "OpenGL": [], "EGL": ["mesa3d"], "Perl": [], "Sqlite": ["sqlite"],
    "SQLite3": ["sqlite"], "FFmpeg": ["ffmpeg"], "Mpv": ["mpv"], "LibMPV": ["mpv"], "JPEG": ["jpeg"], "PNG": ["libpng"],
    "TIFF": ["tiff"], "OpenEXR": [], "LibRaw": [], "Kdcraw": [], "KDcrawQt6": [], "WebP": ["webp"], "AVIF": ["libavif"],
    "libheif": [], "JXL": [], "LibUSB": ["libusb"], "UDisks2": ["udisks"], "UPower": ["upower"],
    "Libmtp": [], "Samba": [], "NFS": [], "LibSSH": ["libssh"], "Taglib2": ["taglib"], "Discount": [],
    "QMobipocket6": [], "DjVuLibre": [], "CHM": [], "LibSpectre": [], "EPub": [], "QGpgme": [], "LibZip": [],
    "Markdown": [], "KExiv2Qt6": [], "Freerdp": [], "LibVNCServer": [], "Sasl2": [], "packagekitqt6": [],
    "Snapd": [], "fwupd": [], "Markdown": [], "LibAccountsQt6": [], "AccountsQt6": [], "SignOnQt6": [],
    "KAccounts6": [], "LibKGAPI": [], "KF6NetworkManagerQt": [], "LibXfixes": [], "XCursor": [],
    "Iso_codes": ["iso-codes"], "IsoCodes": ["iso-codes"], "SharedMimeInfo": ["shared-mime-info"],
    "Libcap": ["libcap"], "PAM": ["linux-pam"], "Doxygen": [], "QHelpGenerator": [], "Sphinx": [],
    "AppArmor": [], "LibSeccomp": [], "Valgrind": [], "Systemd": [], "DBus": ["dbus"], "Qt5": [],
    "KF5": [], "LibUnwind": [], "Libdw": [], "ICU": ["icu"], "Hunspell": [], "ASPELL": [], "HSPELL": [],
    "VOIKKO": [], "SeleniumWebDriverATSPI": [], "Wayland_Scanner": ["host-wayland"],
    "OpenSSL": ["openssl"], "LibMount": ["util-linux"], "ACL": ["acl"], "LibGcrypt": ["libgcrypt"],
    "Qca-qt6": ["kde-qca"], "QRencode": ["libqrencode"], "LMDB": ["lmdb"], "Avahi": ["avahi"], "DNSSD": ["avahi"],
    "NL": ["libnl"], "USB1": ["libusb"], "X11_XCB": ["xlib_libX11"], "MPC": ["mpc"], "BISON": ["host-bison"],
    "FLEX": ["host-flex"], "Gperf": ["host-gperf"], "Python": ["host-python3"], "LCMS2": ["lcms2"],
    "LibExiv2": ["exiv2"], "UTEMPTER": ["libutempter"], "AccountsService": ["kde-accountsservice"],
    "OpenAL": ["openal"], "SndFile": ["libsndfile"], "CanberraPulse": ["libcanberra"],
    "Xwayland": ["xwayland"], "hwdata": ["hwdata"], "ZXing": ["zxing-cpp"], "exiv2": ["exiv2"], "libssh": ["libssh"],
    "QtWaylandScanner": ["qt6wayland"], "PulseAudioQt": ["kde-pulseaudio-qt"], "KQuickImageEditor": ["kde-kquickimageeditor"],
}
# Qt6 COMPONENTS -> Buildroot packages (Core, Gui, Widgets, DBus, ... are qt6base)
QT_MAP = {"Qml": ["qt6declarative"], "Quick": ["qt6declarative"], "QuickControls2": ["qt6declarative"],
          "QuickTemplates2": ["qt6declarative"], "QuickWidgets": ["qt6declarative"], "QmlModels": ["qt6declarative"],
          "Svg": ["qt6svg"], "SvgWidgets": ["qt6svg"], "WaylandClient": ["qt6wayland"], "WaylandCompositor": ["qt6wayland"],
          "ShaderTools": ["qt6shadertools"], "Core5Compat": ["qt6core5compat"], "Multimedia": ["qt6multimedia"],
          "Positioning": [], "Location": [], "WebEngineWidgets": [], "WebEngineQuick": [], "WebView": [],
          "TextToSpeech": [], "SerialPort": ["qt6serialport"], "Charts": ["qt6charts"], "Graphs": ["qt6graphs"],
          "Quick3D": ["qt6quick3d"], "Tools": [], "LinguistTools": ["host-qt6tools"], "UiTools": [],
          "Designer": [], "Help": [], "WebSockets": ["qt6websockets"], "Test": [], "QuickTest": []}

# per package: extra dependencies / CMake options (lists) and make text
EXTRA = {
    "extra-cmake-modules": {"mk": "KF6_EXTRA_CMAKE_MODULES_INSTALL_TARGET = NO\n", "deps": ["host-pkgconf"]},
    "solid": {"deps": ["host-flex", "host-bison", "udev", "util-linux"], "conf": ["-DUSE_DBUS=ON"]},
    "kidletime": {"mk": """ifeq ($(BR2_PACKAGE_QT6WAYLAND),y)
KF6_KIDLETIME_DEPENDENCIES += qt6wayland wayland wayland-protocols kde-plasma-wayland-protocols
else
KF6_KIDLETIME_CONF_OPTS += -DWITH_WAYLAND=OFF
endif
""", "deps": ["xlib_libX11", "libxcb"], "conf": ["-DWITH_X11=ON"],
                  "optional": ["qt6wayland", "wayland", "wayland-protocols", "kde-plasma-wayland-protocols"]},
    "layer-shell-qt": {"deps": ["qt6wayland", "wayland", "wayland-protocols", "host-wayland", "libxkbcommon"]},
    "kwindowsystem": {"mk": """ifeq ($(BR2_PACKAGE_QT6DECLARATIVE),y)
KF6_KWINDOWSYSTEM_DEPENDENCIES += qt6declarative
else
KF6_KWINDOWSYSTEM_CONF_OPTS += -DKWINDOWSYSTEM_QML=OFF
endif
ifeq ($(BR2_PACKAGE_QT6WAYLAND),y)
KF6_KWINDOWSYSTEM_DEPENDENCIES += qt6wayland wayland wayland-protocols kde-plasma-wayland-protocols
else
KF6_KWINDOWSYSTEM_CONF_OPTS += -DKWINDOWSYSTEM_WAYLAND=OFF
endif
""", "optional": ["qt6declarative", "qt6wayland", "wayland", "wayland-protocols", "kde-plasma-wayland-protocols"]},
}

def fetch(url, binary=False):
    with urllib.request.urlopen(url, timeout=300) as f:
        d = f.read()
    return d if binary else d.decode()

def listing(url, ver):
    """name -> (version, tarball url) of a download.kde.org release directory"""
    html = fetch(url + "/")
    out = {}
    for m in re.finditer(r'href="([A-Za-z0-9_.+-]+?)-(' + re.escape(ver) + r'(?:\.\d+)?)\.tar\.xz"', html):
        out[m.group(1)] = (m.group(2), f"{url}/{m.group(1)}-{m.group(2)}.tar.xz")
    return out

def bname(n, kind):
    return NAME.get(n) or (f"kf6-{n}" if kind == "frameworks" else f"kde-{n}")

def sym(b):
    return "BR2_PACKAGE_" + re.sub(r"[^A-Za-z0-9]", "_", b).upper()

def scan(tarball):
    """find_package names and Qt6 components used by a source tarball"""
    finds, qt = set(), set()
    with tarfile.open(tarball) as t:
        for m in t.getmembers():
            if not (m.name.endswith("CMakeLists.txt") or m.name.endswith(".cmake")) or "/autotests/" in m.name \
               or "/tests/" in m.name or "/examples/" in m.name:
                continue
            text = t.extractfile(m).read().decode(errors="replace")
            for call in re.findall(r"find_package\s*\(([^)]*)\)", text, re.I):
                words = call.split()
                if not words:
                    continue
                name = words[0]
                if name in ("Qt6", "KF6", "Qt${QT_MAJOR_VERSION}", "KF${KF_MAJOR_VERSION}") or "QT_MAJOR" in name:
                    comps = [w for w in words[1:] if re.match(r"^[A-Z][A-Za-z0-9]+$", w)
                             and w not in ("REQUIRED", "COMPONENTS", "CONFIG", "OPTIONAL_COMPONENTS", "NO_MODULE", "QUIET")]
                    if name.startswith("Qt"):
                        qt.update(comps)
                    continue
                name = name.replace("${QT_MAJOR_VERSION}", "6").replace("${KF_MAJOR_VERSION}", "6")
                finds.add(name)
    return finds, qt

def main():
    os.makedirs(CACHE, exist_ok=True)
    rel = {"frameworks": listing(f"{DL}/frameworks/{KF}", KF),
           "plasma": listing(f"{DL}/plasma/{PLASMA}", PLASMA),
           "gear": listing(f"{DL}/release-service/{GEAR}/src", GEAR)}
    rel["other"] = {n: (re.search(r"-([0-9][0-9.]*)\.tar\.xz$", u).group(1), u) for n, u in OTHER.items()}
    kind_of = {}
    for k, l in rel.items():
        for n in l:
            kind_of.setdefault(n, k)
    deps = {}
    for line in fetch(META).splitlines():
        if ":" not in line or line.startswith("#"):
            continue
        a, b = (x.strip() for x in line.split(":", 1))
        deps.setdefault(a.split("/")[-1], set()).add(b.split("/")[-1] if not b.startswith("third-party/") else "3p:" + b.split("/")[-1])
    # the KDE packages: ROOTS and what they need
    want, todo, unknown = set(), list(ROOTS), set()
    while todo:
        n = todo.pop()
        if n in want or n in SKIP:
            continue
        if n not in kind_of:
            unknown.add(n)
            continue
        want.add(n)
        todo += [d for d in deps.get(n, ()) if not d.startswith("3p:")]
    if unknown:
        print("not in the releases (add a package by hand, or to SKIP):", " ".join(sorted(unknown)))
    report = {}
    cfg_sources = []
    for n in sorted(want):
        kind = kind_of[n]
        ver, url = rel[kind][n]
        b = bname(n, kind)
        tb = os.path.join(CACHE, url.rsplit("/", 1)[1])
        if not os.path.exists(tb):
            print("download", url.rsplit("/", 1)[1], file=sys.stderr)
            data = fetch(url, True)
            open(tb + ".part", "wb").write(data)
            os.rename(tb + ".part", tb)
        sha = fetch(url + ".sha256").split()[0]
        finds, qt = scan(tb)
        d = {bname(x, kind_of[x]) for x in deps.get(n, ()) if not x.startswith("3p:") and x in want}
        d.add("kf6-extra-cmake-modules") if n != "extra-cmake-modules" else None
        d.add("qt6base")
        for f in sorted(finds):
            if f.startswith("Qt5") or f in OPTIONAL_FINDS:
                continue
            if f.startswith("Qt6"):
                d.update(QT_MAP.get(f[3:].replace("Private", ""), []))
                continue
            if f in FIND_MAP:
                d.update(FIND_MAP[f])
            elif not (f.startswith("KF6") or f.startswith("Plasma") or f.startswith("K") and f[1:2].isupper()):
                report.setdefault(f, []).append(n)
        for c in qt:
            d.update(QT_MAP.get(c, []))
        ex = EXTRA.get(n, {})
        d -= set(ex.get("optional", []))
        d.update(ex.get("deps", []))
        d.discard(b)
        V = re.sub(r"[^A-Za-z0-9]", "_", b).upper()
        site = url.rsplit("/", 1)[0]
        tdeps = sorted(x for x in d if not x.startswith("host-"))
        hdeps = sorted(x for x in d if x.startswith("host-"))
        pdir = os.path.join(PKG, b)
        os.makedirs(pdir, exist_ok=True)
        with open(os.path.join(pdir, f"{b}.mk"), "w") as f:
            f.write(f"""{'#' * 80}
#
# {b}: {n} {ver} (KDE {kind}). GENERATED by scripts/kde-gen.py: change that.
#
{'#' * 80}

{V}_VERSION = {ver}
{V}_SITE = {site}
{V}_SOURCE = {n}-$({V}_VERSION).tar.xz
{V}_LICENSE = see LICENSES/
{V}_LICENSE_FILES = LICENSES
{V}_INSTALL_STAGING = YES
{V}_DEPENDENCIES = {' '.join(tdeps + hdeps)}
{V}_CONF_OPTS = $(KDE_CONF_OPTS) {' '.join(ex.get('conf', []))}
""".rstrip() + "\n" + ex.get("mk", "") + "\n$(eval $(cmake-package))\n")
        with open(os.path.join(pdir, f"{b}.hash"), "w") as f:
            f.write(f"# from {url}.sha256\nsha256  {sha}  {n}-{ver}.tar.xz\n")
        with open(os.path.join(pdir, "Config.in"), "w") as f:
            f.write(f"config {sym(b)}\n\tbool \"{b}\"\n")
            for x in tdeps:
                f.write(f"\tselect {sym(x)}\n")
            f.write(f"\thelp\n\t  KDE {kind}: {n} {ver}. GENERATED by scripts/kde-gen.py.\n")
        cfg_sources.append(b)
    # generated packages that are no longer wanted (only those this script wrote)
    for dname in sorted(os.listdir(PKG)):
        mk = os.path.join(PKG, dname, f"{dname}.mk")
        if dname not in cfg_sources and os.path.isfile(mk) and "GENERATED by scripts/kde-gen.py" in open(mk).read():
            for x in os.listdir(os.path.join(PKG, dname)):
                os.remove(os.path.join(PKG, dname, x))
            os.rmdir(os.path.join(PKG, dname))
            print("removed", dname)
    os.makedirs(os.path.join(TOP, "external", "kde"), exist_ok=True)
    with open(os.path.join(TOP, "external", "kde", "Config.in"), "w") as f:
        f.write("# GENERATED by scripts/kde-gen.py\nmenu \"KDE (MicroLinux KDE edition)\"\n")
        for b in cfg_sources:
            f.write(f'source "$BR2_EXTERNAL_MICROLINUX_PATH/package/{b}/Config.in"\n')
        f.write("endmenu\n")
    with open(os.path.join(TOP, "external", "configs", "fragments", "kde-packages.config"), "w") as f:
        f.write("# KDE edition: the packages of scripts/kde-gen.py ROOTS. GENERATED.\n")
        for n in ROOTS:
            if n in want:
                f.write(f"{sym(bname(n, kind_of[n]))}=y\n")
    print(f"{len(want)} KDE packages: " + " ".join(sorted(bname(n, kind_of[n]) for n in want)))
    if report:
        print("\nfind_package names not mapped (add to FIND_MAP):")
        for k in sorted(report):
            print(f"  {k}: {' '.join(sorted(report[k]))}")

main()
