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
READELF="$H/bin/$ARCH-buildroot-linux-gnu-readelf"
VERSION=$(cat "$T/etc/microlinux-release")
export PATH="$H/bin:$H/sbin:$PATH"

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
		firefox) check_deps "$name" "$d" || { echo "firefox: unresolved libraries, fix the defconfig"; exit 1; } ;;
	esac
	f="$name-$ver.mlp"
	mksquashfs "$d" "$P/$f" -comp xz -b 1M -noappend -no-progress -quiet -all-root -mkfs-time 0 -all-time 0 >/dev/null
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
	mksquashfs "$d" "$R/$f" -comp xz -noappend -no-progress -quiet -all-root -mkfs-time 0 -all-time 0 >/dev/null
	echo "$name|$ver|$f|$(sha256sum "$R/$f" | cut -d' ' -f1)|$(stat -c %s "$R/$f")|$desc|$dep|$sec" >> "$R/INDEX"
done
[ $bad = 0 ] || { echo "repository packages have unresolved libraries"; exit 1; }
# the image packages (Firefox, EL7 runtime) are in the online repository too,
# for systems booted from the base ISO
while IFS='|' read -r name ver f sha size desc; do
	cp "$P/$f" "$R/$f"
	echo "$name|$ver|$f|$sha|$size|$desc||app" >> "$R/INDEX"
done < "$P/INDEX"
cp "$B/repo-root/SOURCES.txt" "$R/SOURCES.txt"
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
iso_tree() { # dir with_packages
	local D=$1
	rm -rf "$D"; mkdir -p "$D/boot/grub" "$D/live" "$D/EFI/BOOT"
	cp "$KERNEL" "$D/boot/vmlinuz"
	cp "$B/initramfs.cpio.gz" "$D/boot/initramfs.cpio.gz"
	sed -e "s/@VERSION@/$VERSION/g" -e "s/@SERIAL@/$SERIAL/g" "$BOARD/grub.cfg" > "$D/boot/grub/grub.cfg"
	echo "MicroLinux $VERSION" > "$D/boot/grub/microlinux-live.id"
	cp "$B/rootfs.squashfs" "$D/live/rootfs.sqfs"
	for f in "$B"/efi-part/EFI/BOOT/*.efi; do
		cp "$f" "$D/EFI/BOOT/$(basename "$f" | tr a-z A-Z)"
	done
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
for f in "$B"/efi-part/EFI/BOOT/*.efi; do
	mcopy -i "$B/efiboot.img" "$f" "::/EFI/BOOT/$(basename "$f" | tr a-z A-Z)"
done

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
mkiso "$B/microlinux-$ARCH.iso" "$B/iso-full"
iso_tree "$B/iso-base" no
mkiso "$B/microlinux-$ARCH-base.iso" "$B/iso-base"

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
	echo "ISO (base)             $(mib "$B/microlinux-$ARCH-base.iso")"
	echo "ISO (full)             $(mib "$B/microlinux-$ARCH.iso")"
} | tee "$B/size-report.txt"
