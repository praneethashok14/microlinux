#!/bin/bash
# Buildroot post-image hook: build the initramfs, mlpkg packages and the
# bootable hybrid ISO images (UEFI; plus BIOS on x86_64).
# $1 = BINARIES_DIR
set -euo pipefail
B="$1"
BOARD="$BR2_EXTERNAL_MICROLINUX_PATH/board/microlinux"
T="$TARGET_DIR"
H="$HOST_DIR"
ARCH=$(sed -n 's/^BR2_ARCH="\(.*\)"/\1/p' "$BR2_CONFIG")
# edition: the LXQt one's files are named after the architecture
# (microlinux-x86_64.iso, BUILD-x86_64, ...), the KDE one's after kde-<arch>
if grep -q '^BR2_PACKAGE_KDE_PLASMA_WORKSPACE=y' "$BR2_CONFIG"; then EDITION=kde TAG=kde-$ARCH; else EDITION=lxqt TAG=$ARCH; fi
READELF="$H/bin/$ARCH-buildroot-linux-gnu-readelf"
VERSION=$(cat "$T/etc/microlinux-release")
export PATH="$H/bin:$H/sbin:$PATH"
# private signing keys (scripts/make-keys.sh); without them nothing is signed
KEYS="$BR2_EXTERNAL_MICROLINUX_PATH/../keys"

msg() { echo ">>> microlinux: $*"; }

# --- library resolution helpers ------------------------------------------------
needed() { "$READELF" -d "$1" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'; }
libdirs="$T/usr/lib $T/usr/lib/gconv"
findlib() { local d; for d in $libdirs "$@"; do [ -e "$d/$lib" ] && { echo "$d/$lib"; return 0; }; done; return 1; }

# --- 1. initramfs ---------------------------------------------------------------
msg "initramfs"
I="$B/initramfs-root"
rm -rf "$I"; mkdir -p "$I"/{bin,sbin,lib,dev,proc,sys,run,newroot,live,etc}
ln -s lib "$I/lib64"
cp "$T/usr/bin/busybox" "$I/bin/busybox"
for a in sh mount umount mkdir cat sleep findfs blkid cp ln rmdir switch_root setsid cttyhack readlink basename \
	ls dmesg echo grep losetup mdev ps kill vi less mkfs.ext2 fsck df free test [ ; do
	ln -sf busybox "$I/bin/$a"
done
# copy busybox's shared libraries (recursively) and the dynamic loader
todo=$(needed "$I/bin/busybox"); done_libs=""
while [ -n "$todo" ]; do
	set -- $todo; todo=""
	for lib in "$@"; do
		case " $done_libs " in *" $lib "*) continue ;; esac
		done_libs="$done_libs $lib"
		p=$(findlib) || { echo "initramfs: missing $lib"; exit 1; }
		cp -L "$p" "$I/lib/$lib"
		todo="$todo $(needed "$p")"
	done
done
interp=$("$READELF" -lW "$I/bin/busybox" | sed -n 's/.*interpreter: \(.*\)\]/\1/p')
cp -L "$T$interp" "$I$interp"
install -m 0755 "$BOARD/initramfs/init" "$I/init"
# fakeroot so /dev/console exists as a real device node (needed before /init runs)
fakeroot -- sh -c "mknod -m 600 '$I/dev/console' c 5 1 && cd '$I' && find . | LC_ALL=C sort | cpio -o -H newc --quiet --owner=0:0 --reproducible" \
	| gzip -9 -n > "$B/initramfs.cpio.gz"

# --- 2. mlpkg packages ------------------------------------------------------------
# mksq TREE IMAGE MKSQUASHFS-OPTIONS...: the images are reproducible (fixed
# times, root owner), so a tree with the same contents as in the previous
# build reuses that build's image instead of compressing it again
SQC="$B/squashfs-cache"; mkdir -p "$SQC"
mksq() {
	local d=$1 out=$2 key name; shift 2
	key=$( { echo "$*"; cd "$d" && find . -printf '%y %m %p %l\n' | LC_ALL=C sort &&
		find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum; } | sha256sum | cut -c1-32)
	name=${out##*/}
	if [ -f "$SQC/$name.$key" ]; then
		cp "$SQC/$name.$key" "$out"
		return
	fi
	mksquashfs "$d" "$out" "$@" -noappend -no-progress -quiet -all-root -mkfs-time 0 -all-time 0 >/dev/null
	rm -f "$SQC/$name".*
	cp "$out" "$SQC/$name.$key"
}
msg "packages"
P="$B/packages"; rm -rf "$P"; mkdir -p "$P"
: > "$P/INDEX"
: > "$P/AUTOLOAD"
check_deps() { # name dir: every NEEDED library must be in the rootfs or the package
	local name=$1 dir=$2 missing=0 f lib
	local pkglibs; pkglibs=$(find "$dir" -name '*.so*' -printf '%f\n' | sort -u)
	while IFS= read -r f; do
		for lib in $(needed "$f"); do
			grep -qxF "$lib" <<< "$pkglibs" && continue
			findlib >/dev/null && continue
			echo "  $name: ${f#$dir/} needs $lib (not found)"; missing=1
		done
	done < <(find "$dir" -type f \( -perm -u+x -o -name '*.so*' \) -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
	return $missing
}
for d in "$B"/pkgroot/*/; do
	[ -f "$d/.mlpkg/info" ] || continue
	name=$(sed -n 's/^name=//p' "$d/.mlpkg/info")
	ver=$(sed -n 's/^version=//p' "$d/.mlpkg/info")
	desc=$(sed -n 's/^description=//p' "$d/.mlpkg/info")
	case "$name" in
		firefox) [ -f "$d/libxul.so" ] || { echo "firefox: libxul.so missing (empty build directory? make firefox-bin-dirclean)"; exit 1; }
			check_deps "$name" "$d" || { echo "firefox: unresolved libraries, fix the defconfig"; exit 1; } ;;
	esac
	# compress=zstd in .mlpkg/info: faster to read than xz, slightly bigger
	comp=$(sed -n 's/^compress=//p' "$d/.mlpkg/info"); comp=${comp:-xz}
	copt=; [ "$comp" = zstd ] && copt="-Xcompression-level 19"
	f=$(printf '%s' "$name-$ver" | tr -c 'A-Za-z0-9._-' '_').mlp
	mksq "$d" "$P/$f" -comp "$comp" $copt -b 1M
	sha=$(sha256sum "$P/$f" | cut -d' ' -f1)
	size=$(stat -c %s "$P/$f")
	echo "$name|$ver|$f|$sha|$size|$desc" >> "$P/INDEX"
	echo "$name" >> "$P/AUTOLOAD"
	msg "  $f ($((size / 1048576)) MiB)"
done

# package repository (repo-split.py made one tree per package): .mlp images,
# INDEX lines "name|version|file|sha256|size|description|depends|section"
msg "repository"
R="$B/repo"; rm -rf "$R"; mkdir -p "$R"
: > "$R/INDEX"
repo_libs() { # name: shared library names in the package and all its dependencies
	local n
	for n in "$1" $(sed -n 's/^depends=//p' "$B/repo-root/$1/.mlpkg/info"); do
		find "$B/repo-root/$n" -name '*.so*' -printf '%f\n'
	done | sort -u
}
bad=0
for d in "$B"/repo-root/*/; do
	[ -f "$d/.mlpkg/info" ] || continue
	name=$(basename "$d")
	ver=$(sed -n 's/^version=//p' "$d/.mlpkg/info")
	desc=$(sed -n 's/^description=//p' "$d/.mlpkg/info")
	dep=$(sed -n 's/^depends=//p' "$d/.mlpkg/info")
	sec=$(sed -n 's/^section=//p' "$d/.mlpkg/info")
	# every library an ELF in the package needs: base system, the package, or its dependencies
	libs=$(repo_libs "$name")
	while IFS= read -r f; do
		for lib in $(needed "$f"); do
			grep -qxF "$lib" <<< "$libs" && continue
			findlib >/dev/null && continue
			echo "  repo $name: ${f#$d} needs $lib (not in base, package or dependencies)"; bad=1
		done
	done < <(find "$d" -type f \( -perm -u+x -o -name '*.so*' \) -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
	# GitHub release asset names allow only these characters
	f=$(printf '%s' "$name-$ver" | tr -c 'A-Za-z0-9._-' '_').mlp
	mksq "$d" "$R/$f" -comp xz
	echo "$name|$ver|$f|$(sha256sum "$R/$f" | cut -d' ' -f1)|$(stat -c %s "$R/$f")|$desc|$dep|$sec" >> "$R/INDEX"
done
[ $bad = 0 ] || { echo "repository packages have unresolved libraries"; exit 1; }
cp "$B/repo-root/SOURCES.txt" "$B/repo-root/CATEGORIES" "$R/"
# the image packages (Firefox, EL7 runtime) are in the online repository too,
# for systems booted from the base ISO
while IFS='|' read -r name ver f sha size desc; do
	cp "$P/$f" "$R/$f"
	echo "$name|$ver|$f|$sha|$size|$desc||app" >> "$R/INDEX"
	case "$name" in firefox) echo "$name|Internet & network" ;; *) echo "$name|System" ;; esac >> "$R/CATEGORIES"
done < "$P/INDEX"
# image packages for the repository only (pkgroot-repo/*, e.g. Chromium): mounted
# under /opt like Firefox; "builddeps=" names Buildroot packages, which become
# the repository packages they depend on (plus those packages' dependencies);
# "pkgdeps=" names other repository image packages (e.g. Prism -> Java)
for d in "$B"/pkgroot-repo/*/; do
	[ -f "$d/.mlpkg/info" ] || continue
	inf="$d/.mlpkg/info"
	name=$(sed -n 's/^name=//p' "$inf"); ver=$(sed -n 's/^version=//p' "$inf")
	desc=$(sed -n 's/^description=//p' "$inf"); cat=$(sed -n 's/^category=//p' "$inf")
	dep=""
	for b in $(sed -n 's/^builddeps=//p' "$inf"); do
		[ -f "$B/repo-root/$b/.mlpkg/info" ] || continue   # in the base system
		dep="$dep $b $(sed -n 's/^depends=//p' "$B/repo-root/$b/.mlpkg/info")"
	done
	dep="$dep $(sed -n 's/^pkgdeps=//p' "$inf")"
	dep=$(echo $dep | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ *$//')
	# (builddeps= stays: this step must give the same result every time it runs)
	sed -i '/^depends=/d' "$inf"; echo "depends=$dep" >> "$inf"
	libs=$( { find "$d" -name '*.so*' -printf '%f\n'
		for n in $dep; do if [ -d "$B/repo-root/$n" ]; then find "$B/repo-root/$n" -name '*.so*' -printf '%f\n'; fi; done; } | sort -u)
	while IFS= read -r f; do
		for lib in $(needed "$f"); do
			grep -qxF "$lib" <<< "$libs" && continue
			findlib >/dev/null && continue
			echo "  repo $name: ${f#$d} needs $lib (not in base, package or dependencies)"; bad=1
		done
	done < <(find "$d" -type f \( -perm -u+x -o -name '*.so*' \) -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
	[ $bad = 0 ] || { echo "$name: unresolved libraries"; exit 1; }
	f=$(printf '%s' "$name-$ver" | tr -c 'A-Za-z0-9._-' '_').mlp
	mksq "$d" "$R/$f" -comp xz -b 1M
	echo "$name|$ver|$f|$(sha256sum "$R/$f" | cut -d' ' -f1)|$(stat -c %s "$R/$f")|$desc|$dep|app" >> "$R/INDEX"
	echo "$name|${cat:-Other}" >> "$R/CATEGORIES"
	msg "  $f ($(( $(stat -c %s "$R/$f") / 1048576 )) MiB, repository only; needs: ${dep:-nothing})"
done

if [ -f "$KEYS/repo/repo.key" ]; then
	openssl dgst -sha256 -sign "$KEYS/repo/repo.key" -out "$R/INDEX.sig" "$R/INDEX"
	openssl dgst -sha256 -verify "$BOARD/keys/repo.pub" -signature "$R/INDEX.sig" "$R/INDEX" >/dev/null
	msg "  INDEX signed"
else
	echo "WARNING: $KEYS/repo/repo.key missing: repository INDEX not signed (mlpkg will refuse it online)"
fi
msg "  $(grep -c . "$R/INDEX") packages, $(du -sm "$R" | cut -f1) MiB"

# the base system must keep what it boots with (repo-split.py must never move these)
for f in usr/lib/modules usr/bin/busybox usr/sbin/mkfs.ext4 etc/inittab; do
	[ -e "$T/$f" ] || { echo "base system is missing /$f"; exit 1; }
done

# rootfs-wide check: every ELF's libraries resolve inside the rootfs
msg "checking root filesystem library dependencies"
missing=0
while IFS= read -r f; do
	# honour RPATH/RUNPATH ($ORIGIN relative to the file, absolute paths inside the rootfs)
	rp=$("$READELF" -d "$f" 2>/dev/null | sed -n 's/.*(R\(UN\)\{0,1\}PATH).*\[\(.*\)\]/\2/p' | tr ':' ' ')
	extra=""
	for d in $rp; do
		case "$d" in
			*'$ORIGIN'*) extra="$extra ${d//\$ORIGIN/$(dirname "$f")}" ;;
			/*) extra="$extra $T$d" ;;
		esac
	done
	for lib in $(needed "$f"); do
		findlib "$(dirname "$f")" $extra >/dev/null || { echo "  rootfs: ${f#$T} needs $lib"; missing=1; }
	done
done < <(find "$T/usr" -type f \( -perm -u+x -o -name '*.so*' \) ! -path '*/lib/modules/*' \
	-exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
[ $missing = 0 ] || { echo "root filesystem has unresolved libraries"; exit 1; }

# --- 3. ISO tree --------------------------------------------------------------------
msg "ISO"
case "$ARCH" in
	aarch64) KERNEL="$B/vmlinuz.efi"; SERIAL=ttyAMA0; BOOT="UEFI only (arm64 has no BIOS)." ;;
	x86_64)  KERNEL="$B/bzImage";     SERIAL=ttyS0;   BOOT="BIOS or UEFI, from a CD/DVD or a USB stick." ;;
	*) echo "unsupported arch $ARCH"; exit 1 ;;
esac
# BIOS boot (x86_64): GRUB El Torito image + the MBR boot code that makes the
# image bootable from a USB stick too
HYBRID_MBR=""
if [ -f "$B/grub-eltorito.img" ]; then
	HYBRID_MBR=$(ls "$BUILD_DIR"/grub2-*/build-i386-pc/grub-core/boot_hybrid.img | head -n1)
	[ -f "$HYBRID_MBR" ] || { echo "boot_hybrid.img not found"; exit 1; }
fi
# --- UEFI boot files (efi-boot/) ----------------------------------------------------
# Secure Boot (x86_64, when the shim package and the signing key exist):
#   BOOTX64.EFI  shim, signed by Microsoft (Debian's shim-signed)
#   grubx64.efi  GRUB with SBAT metadata, signed with keys/secureboot/MOK.key
#   mmx64.efi    MOK Manager (Debian-signed), to enroll the MicroLinux key
# and the kernel is signed with the same key. Otherwise: GRUB as built.
E="$B/efi-boot"; rm -rf "$E"; mkdir -p "$E"
SB=""
if [ -f "$B/shim/shimx64.efi" ] && [ -f "$KEYS/secureboot/MOK.key" ]; then
	SB=1
	GRUBCORE=$(ls -d "$BUILD_DIR"/grub2-*/build-x86_64-efi/grub-core | head -n1)
	MODS=$(sed -n 's/^BR2_TARGET_GRUB2_BUILTIN_MODULES_EFI="\(.*\)"/\1/p' "$BR2_CONFIG")
	# SBAT: GRUB 2.12 with Buildroot's backport of the February 2025 security
	# fixes (CVE-2024-45774.. / CVE-2025-0622..), which is generation 5
	cat > "$B/grub-sbat.csv" <<'SBAT'
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
grub,5,Free Software Foundation,grub,2.12,https://www.gnu.org/software/grub/
grub.microlinux,1,MicroLinux,grub2,2.12,https://github.com/praneethashok14/microlinux
SBAT
	grub-mkimage -d "$GRUBCORE" -O x86_64-efi -o "$B/grubx64.efi.unsigned" -p /EFI/BOOT \
		-c "$BOARD/grub-embed.cfg" --sbat "$B/grub-sbat.csv" $MODS
	sbsign --key "$KEYS/secureboot/MOK.key" --cert "$KEYS/secureboot/MOK.crt" \
		--output "$E/grubx64.efi" "$B/grubx64.efi.unsigned" 2>/dev/null
	sbsign --key "$KEYS/secureboot/MOK.key" --cert "$KEYS/secureboot/MOK.crt" \
		--output "$B/vmlinuz.signed" "$KERNEL" 2>/dev/null
	sbverify --cert "$KEYS/secureboot/MOK.crt" "$E/grubx64.efi" >/dev/null
	sbverify --cert "$KEYS/secureboot/MOK.crt" "$B/vmlinuz.signed" >/dev/null
	KERNEL="$B/vmlinuz.signed"
	cp "$B/shim/shimx64.efi" "$E/BOOTX64.EFI"
	cp "$B/shim/mmx64.efi" "$E/mmx64.efi"
	msg "  Secure Boot: shim + signed GRUB and kernel"
else
	[ -f "$B/shim/shimx64.efi" ] && echo "WARNING: $KEYS/secureboot/MOK.key missing: building without Secure Boot support"
	for f in "$B"/efi-part/EFI/BOOT/*.efi; do
		cp "$f" "$E/$(basename "$f" | tr a-z A-Z)"
	done
fi
# grub.cfg next to the loader, read by GRUB's built-in config (which can only
# run plain commands): find the live medium and show its menu. ml-install
# replaces it with the installed system's menu.
printf '%s\n' 'search --no-floppy --set=root --file /boot/grub/microlinux-live.id' \
	'set prefix=($root)/boot/grub' 'configfile $prefix/grub.cfg' > "$E/grub.cfg"
CERT=ENROLL_THIS_KEY_IN_MOK_MANAGER.cer

iso_tree() { # dir with_packages
	local D=$1
	rm -rf "$D"; mkdir -p "$D/boot/grub" "$D/live" "$D/EFI/BOOT"
	cp "$KERNEL" "$D/boot/vmlinuz"
	cp "$B/initramfs.cpio.gz" "$D/boot/initramfs.cpio.gz"
	sed -e "s/@VERSION@/$VERSION/g" -e "s/@SERIAL@/$SERIAL/g" "$BOARD/grub.cfg" > "$D/boot/grub/grub.cfg"
	echo "MicroLinux $VERSION" > "$D/boot/grub/microlinux-live.id"
	cp "$B/rootfs.squashfs" "$D/live/rootfs.sqfs"
	cp "$E"/* "$D/EFI/BOOT/"
	[ -z "$SB" ] || cp "$BOARD/keys/MOK.cer" "$D/$CERT"
	if [ -n "$HYBRID_MBR" ]; then
		mkdir -p "$D/boot/grub/i386-pc"
		cp "$B/grub-eltorito.img" "$D/boot/grub/i386-pc/eltorito.img"
	fi
	sed -e "s/@VERSION@/$VERSION/g" -e "s/@ARCH@/$ARCH/g" -e "s|@BOOT@|$BOOT|" "$BOARD/iso-readme.txt" > "$D/README.txt"
	if [ "$2" = yes ]; then cp -r "$P" "$D/packages"; fi
}
# FAT image with the bootloader, used as El Torito EFI image and as the GPT ESP
rm -f "$B/efiboot.img"
mkfs.vfat -C -n MLEFI "$B/efiboot.img" 8192 >/dev/null
mmd -i "$B/efiboot.img" ::/EFI ::/EFI/BOOT
for f in "$E"/*; do
	mcopy -i "$B/efiboot.img" "$f" "::/EFI/BOOT/$(basename "$f")"
done
[ -z "$SB" ] || mcopy -i "$B/efiboot.img" "$BOARD/keys/MOK.cer" "::/$CERT"

mkiso() { # out dir
	local bios=()
	if [ -n "$HYBRID_MBR" ]; then
		bios=(-b boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table
		      --grub2-boot-info --grub2-mbr "$HYBRID_MBR" --mbr-force-bootable -eltorito-alt-boot)
	fi
	xorriso -as mkisofs -quiet -iso-level 3 -r -J -joliet-long -V MICROLINUX \
		-partition_offset 16 -c boot/boot.cat \
		-append_partition 2 0xef "$B/efiboot.img" -appended_part_as_gpt \
		"${bios[@]}" \
		-e --interval:appended_partition_2:all:: -no-emul-boot \
		-o "$1" "$2"
}
iso_tree "$B/iso-full" yes
mkiso "$B/microlinux-$TAG.iso" "$B/iso-full"
iso_tree "$B/iso-base" no
mkiso "$B/microlinux-$TAG-base.iso" "$B/iso-base"

# small system update: the files that changed since the last release
# (ML_RELEASE_BASE/<arch>/microlinux-<arch>-base.iso, kept by
# scripts/mark-released.sh), for "mlpkg system-update" on systems running it
cp "$T/etc/microlinux-build" "$B/BUILD-$TAG"
# the version number, shown by Settings > System Update
cp "$T/etc/microlinux-release" "$B/VERSION-$TAG"
rm -f "$B/update-$TAG-from-"*.tar.zst
OLDISO="${ML_RELEASE_BASE:-/nonexistent}/$TAG/microlinux-$TAG-base.iso"
UPD=
if [ -f "$OLDISO" ]; then
	OLD="$B/release-old"
	key=$(stat -c %s.%Y "$OLDISO")
	if [ "$(cat "$OLD/key" 2>/dev/null)" != "$key" ]; then
		chmod -R u+w "$OLD" 2>/dev/null || true
		rm -rf "$OLD"; mkdir -p "$OLD/iso"
		xorriso -osirrox on -indev "$OLDISO" -extract /boot "$OLD/iso/boot" -extract /EFI "$OLD/iso/EFI" \
			-extract /live/rootfs.sqfs "$OLD/rootfs.sqfs" 2>/dev/null
		chmod -R u+w "$OLD"
		echo "$key" > "$OLD/key"
	fi
	from=$(unsquashfs -cat "$OLD/rootfs.sqfs" etc/microlinux-build 2>/dev/null || true)
	if [ "$from" != "$(cat "$B/BUILD-$TAG")" ] && echo "$from" | grep -Eq '^[A-Za-z0-9._-]+$'; then
		UPD="update-$TAG-from-$from.tar.zst"
		msg "small update from $from"
		python3 "$BOARD/make-update.py" "$OLD/rootfs.sqfs" "$OLD/iso" "$B/rootfs.squashfs" "$B/iso-base" \
			"$B/update-work" "$B/$UPD" | sed 's/^/  /'
		# not worth it when it is nearly as big as the ISO
		if [ $(stat -c %s "$B/$UPD") -gt $(($(stat -c %s "$B/microlinux-$TAG-base.iso") * 7 / 10)) ]; then
			msg "  too big, left out"; rm -f "$B/$UPD"; UPD=
		fi
	fi
fi

# checksums of the images, the small update and the build ID (BUILD-<arch>,
# for mlpkg system-update), signed with the GPG release key and with the
# repository key (SHA256SUMS-<arch>.sig, which MicroLinux itself can check)
# (and the updater itself: systems run the newest one, see ml-system-update)
cp "$T/usr/libexec/ml-system-update" "$B/ml-system-update"
( cd "$B" && sha256sum "microlinux-$TAG.iso" "microlinux-$TAG-base.iso" "BUILD-$TAG" "VERSION-$TAG" ml-system-update $UPD > "SHA256SUMS-$TAG" )
rm -f "$B/SHA256SUMS-$TAG.sig"
if [ -f "$KEYS/repo/repo.key" ]; then
	openssl dgst -sha256 -sign "$KEYS/repo/repo.key" -out "$B/SHA256SUMS-$TAG.sig" "$B/SHA256SUMS-$TAG"
	openssl dgst -sha256 -verify "$BOARD/keys/repo.pub" -signature "$B/SHA256SUMS-$TAG.sig" "$B/SHA256SUMS-$TAG" >/dev/null
fi
rm -f "$B/SHA256SUMS-$TAG.asc"
if [ -d "$KEYS/gpg" ]; then
	GNUPGHOME="$KEYS/gpg" gpg --batch --quiet --armor --detach-sign --output "$B/SHA256SUMS-$TAG.asc" "$B/SHA256SUMS-$TAG"
	msg "  SHA256SUMS-$TAG signed"
else
	echo "WARNING: $KEYS/gpg missing: SHA256SUMS-$TAG not signed"
fi

# --- 4. size report -----------------------------------------------------------------
mib() { echo "$(( ($(stat -c %s "$1") + 524287) / 1048576 )) MiB"; }
{
	echo "MicroLinux $VERSION $ARCH size report ($(date -u +%Y-%m-%d))"
	printf '%-22s %s\n' "kernel (${KERNEL##*/})" "$(mib "$KERNEL")"
	echo "initramfs              $(mib "$B/initramfs.cpio.gz")"
	echo "rootfs.sqfs (xz)       $(mib "$B/rootfs.squashfs")"
	echo "rootfs uncompressed    $(du -sm --apparent-size "$T" | cut -f1) MiB"
	echo "kernel modules         $(du -sm --apparent-size "$T/usr/lib/modules" | cut -f1) MiB (in rootfs)"
	for f in "$P"/*.mlp; do printf '%-22s %s\n' "$(basename "$f")" "$(mib "$f")"; done
	echo "repository             $(grep -c . "$R/INDEX") packages, $(du -sm "$R" | cut -f1) MiB"
	echo "ISO (base)             $(mib "$B/microlinux-$TAG-base.iso")"
	echo "ISO (full)             $(mib "$B/microlinux-$TAG.iso")"
} | tee "$B/size-report.txt"
