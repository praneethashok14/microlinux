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
# user's desktop session (startx from tty1), so remove it.
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
ln -sf ../usr/lib/os-release "$T/etc/os-release"

# login banner
printf '\nMicroLinux %s (%s) - \\l\n\n' "$VERSION" "$ARCH" > "$T/etc/issue"

# default user files: the home in the overlay is created before mkusers chowns it
mkdir -p "$T/home/user/Downloads" "$T/home/user/Desktop" "$T/root"
cp -a "$T/home/user/." "$T/etc/skel/" 2>/dev/null || true
rm -rf "$T/etc/skel/Downloads/"* "$T/etc/skel/Desktop/"*

# JWM draws the desktop, so PCManFM's desktop manager never runs and its
# "Desktop Preferences" only says "Desktop manager is not active": hide it
f="$T/usr/share/applications/pcmanfm-desktop-pref.desktop"
[ -f "$f" ] && ! grep -q '^NoDisplay=true' "$f" && echo 'NoDisplay=true' >> "$f"

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

# GTK / desktop caches that would otherwise be generated at every boot
if [ -x "$HOST_DIR/bin/gtk-update-icon-cache" ]; then
	for d in "$T"/usr/share/icons/*/; do
		[ -f "$d/index.theme" ] && "$HOST_DIR/bin/gtk-update-icon-cache" -q -f -t "$d" || true
	done
fi
if [ -x "$HOST_DIR/bin/update-mime-database" ]; then
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
