#!/bin/sh
# Buildroot post-build hook: final tweaks to the target root filesystem.
# $1 = TARGET_DIR
set -e
T="$1"
VERSION=$(cat "$BR2_EXTERNAL_MICROLINUX_PATH/../VERSION" 2>/dev/null || echo dev)
ARCH=$(sed -n 's/^BR2_ARCH="\(.*\)"/\1/p' "$BR2_CONFIG")

# Package repository: move every package the base system doesn't need out of
# the rootfs into BINARIES_DIR/repo-root/<name> (see repo-split.py). First, so
# that the caches below are built for the base system only.
python3 "$BR2_EXTERNAL_MICROLINUX_PATH/board/microlinux/repo-split.py" "$T"

# Xorg runs without logind/seatd, so it needs to be setuid root to open the VT.
# Buildroot's S40xorg would start a root X server on :0 at boot and block the
# desktop session (started by LightDM), so remove it.
chmod 4755 "$T/usr/bin/Xorg"
rm -f "$T/etc/init.d/S40xorg"

# sudo: wheel group + live-session rule, with the permissions sudo insists on
grep -q '^@includedir /etc/sudoers.d' "$T/etc/sudoers" || echo '@includedir /etc/sudoers.d' >> "$T/etc/sudoers"
chmod 0440 "$T"/etc/sudoers.d/*
chmod 0600 "$T/etc/wpa_supplicant/wpa_supplicant.conf"
chmod 0700 "$T/root"

# EL7 filesystem conventions: CA bundle locations used by RHEL-built binaries
mkdir -p "$T/etc/pki/tls/certs" "$T/etc/pki/ca-trust/extracted/pem"
ln -sf /etc/ssl/certs/ca-certificates.crt "$T/etc/pki/tls/certs/ca-bundle.crt"
ln -sf certs/ca-bundle.crt "$T/etc/pki/tls/cert.pem"
ln -sf /etc/ssl/certs/ca-certificates.crt "$T/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

# RHEL patches bzip2's soname to libbz2.so.1 (upstream: libbz2.so.1.0)
if [ -e "$T/usr/lib/libbz2.so.1.0" ] && [ ! -e "$T/usr/lib/libbz2.so.1" ]; then
	ln -s libbz2.so.1.0 "$T/usr/lib/libbz2.so.1"
fi

# RHEL keeps 64-bit libraries in /usr/lib64; make it resolve here too
[ -e "$T/usr/lib64" ] || ln -s lib "$T/usr/lib64"
[ -e "$T/lib64" ] || ln -s usr/lib64 "$T/lib64"

# public keys: mlpkg checks repository INDEX signatures with repo.pub; MOK.cer
# is the Secure Boot certificate (for mokutil / MOK Manager)
mkdir -p "$T/usr/share/microlinux/keys"
cp "$BR2_EXTERNAL_MICROLINUX_PATH"/board/microlinux/keys/* "$T/usr/share/microlinux/keys/"

# package repositories: the live medium first, then the online repository
grep -v '^#' "$BR2_EXTERNAL_MICROLINUX_PATH/board/microlinux/repo-url" | sed "s/@ARCH@/$ARCH/" >> "$T/etc/mlpkg/repos.conf"

rm -f "$T/etc/os-release"
cat > "$T/usr/lib/os-release" <<EOR
NAME="MicroLinux"
ID=microlinux
VERSION="$VERSION"
VERSION_ID="$VERSION"
PRETTY_NAME="MicroLinux $VERSION ($ARCH)"
HOME_URL="https://example.invalid/microlinux"
EOR
echo "$VERSION" > "$T/etc/microlinux-release"
# which build this is (scripts/build.sh sets ML_BUILD_ID); mlpkg system-update compares it
echo "${ML_BUILD_ID:-$(date -u +%Y%m%d.%H%M)-local}" > "$T/etc/microlinux-build"
# the packages the full ISO has (pkgroot/*): a system update installs the ones
# a new release adds (ml-system-update)
mkdir -p "$T/usr/share/microlinux"
for f in "$BINARIES_DIR"/pkgroot/*/.mlpkg/info; do
	[ -f "$f" ] && sed -n 's/^name=//p' "$f"
done | sort > "$T/usr/share/microlinux/iso-packages"
ln -sf ../usr/lib/os-release "$T/etc/os-release"

# login banner
printf '\nMicroLinux %s (%s) - \\l\n\n' "$VERSION" "$ARCH" > "$T/etc/issue"

# default user files: the home in the overlay is created before mkusers chowns it
mkdir -p "$T/home/user/Downloads" "$T/home/user/Desktop" "$T/root"
cp -a "$T/home/user/." "$T/etc/skel/" 2>/dev/null || true
rm -rf "$T/etc/skel/Downloads/"* "$T/etc/skel/Desktop/"*

# x86_64 Xorg has glamor: the modesetting driver uses GBM functions without
# linking libgbm itself (glamor's module does), and with -z now it fails to
# load ("undefined symbol: gbm_bo_get_offset", no screens). Load glamor first:
# Xorg opens modules RTLD_GLOBAL, so libgbm is then there for modesetting.
if [ -f "$T/usr/lib/xorg/modules/libglamoregl.so" ]; then
	cat > "$T/etc/X11/xorg.conf.d/05-glamor.conf" <<'EOX'
# written by post-build.sh: load glamor (and libgbm) before modesetting
Section "Module"
	Load "glamoregl"
EndSection
EOX
fi

# LXQt: the image has English only, drop the other translations (several MiB)
find "$T/usr/share/lxqt/translations" "$T/usr/share/qtermwidget6/translations" \
	"$T/usr/share/qterminal/translations" "$T/usr/share/pcmanfm-qt/translations" \
	"$T/usr/share/libfm-qt/translations" -name '*.qm' -delete 2>/dev/null || true

# default wallpaper (pcmanfm-qt draws the LXQt desktop): the dark blue-grey
# gradient of earlier MicroLinux releases, as a small PNG
mkdir -p "$T/usr/share/microlinux"
python3 - "$T/usr/share/microlinux/wallpaper.png" <<'EOP'
import struct, sys, zlib
w, h, top, bottom = 64, 512, (0x43, 0x4c, 0x5e), (0x1b, 0x1f, 0x27)
rows = b"".join(b"\0" + bytes(round(a + (b - a) * y / (h - 1)) for a, b in zip(top, bottom)) * w for y in range(h))
chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
EOP

# gdk-pixbuf's loaders.cache is generated from the build host's loaders, which
# have no SVG loader: register librsvg's (entry as in librsvg 2.50 io-svg.c)
L=usr/lib/gdk-pixbuf-2.0/2.10.0
rm -f "$T/$L/loaders.cache.librsvg"
if [ -f "$T/$L/loaders/libpixbufloader-svg.so" ] && ! grep -q 'pixbufloader-svg' "$T/$L/loaders.cache"; then
	cat >> "$T/$L/loaders.cache" <<'EOC'
"/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so"
"svg" 6 "gdk-pixbuf" "Scalable Vector Graphics" "LGPL"
"image/svg+xml" "image/svg" "image/svg-xml" "image/vnd.adobe.svg+xml" "text/xml-svg" "image/svg+xml-compressed" ""
"svg" "svgz" "svg.gz" ""
" <svg" "*    " 100
" <!DOCTYPE svg" "*             " 100

EOC
fi

# Buildroot's S10udevd starts udevd in the background and triggers the
# coldplug events at once: events sent before udevd listens are lost, and
# drivers that are modules (most real NICs, Wi-Fi, sound) never load. Wait
# for udevd's control socket first.
if ! grep -q 'run/udev/control' "$T/etc/init.d/S10udevd"; then
	sed -i '0,/^\tudevadm trigger --type=subsystems/s//\tn=0; while [ ! -S \/run\/udev\/control ] \&\& [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done\n&/' \
		"$T/etc/init.d/S10udevd"
	grep -q 'run/udev/control' "$T/etc/init.d/S10udevd" || { echo "post-build: could not patch S10udevd"; exit 1; }
fi

# GTK / desktop caches that would otherwise be generated at every boot
if [ -x "$HOST_DIR/bin/gtk-update-icon-cache" ]; then
	for d in "$T"/usr/share/icons/*/; do
		[ -f "$d/index.theme" ] && "$HOST_DIR/bin/gtk-update-icon-cache" -q -f -t "$d" || true
	done
fi
if [ -x "$HOST_DIR/bin/update-mime-database" ]; then
	# shared-mime-info installs only its mime.cache, which this rebuild would replace
	# with one knowing just the types in the target's packages/ (no archives, images...)
	install -D -m 644 "$STAGING_DIR/usr/share/mime/packages/freedesktop.org.xml" \
		"$T/usr/share/mime/packages/freedesktop.org.xml"
	"$HOST_DIR/bin/update-mime-database" "$T/usr/share/mime" || true
fi

# trim: static libs, headers, docs that slipped through
rm -rf "$T/usr/include" "$T/usr/share/doc" "$T/usr/share/gtk-doc" "$T/usr/share/man" \
	"$T/usr/share/info" "$T/usr/lib/cmake" "$T/usr/share/aclocal"
find "$T/usr/lib" -name '*.a' -delete
find "$T/usr/lib" -name '*.la' -delete

# GRUB tools (x86_64: ml-install uses grub-install for BIOS boot). Only the
# i386-pc modules are needed; the EFI loader is copied from the live medium.
if [ -d "$T/usr/lib/grub" ]; then
	rm -rf "$T/usr/lib/grub/x86_64-efi" "$T/share/locale" "$T/share/info" "$T/etc/bash_completion.d"
	find "$T/usr/lib/grub/i386-pc" \( -name '*.module' -o -name '*.image' -o -name '*.exec' \) -delete
fi
