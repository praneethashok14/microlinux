#!/bin/sh
# Boot MicroLinux in QEMU (macOS or Linux).
#
#   ./scripts/run-qemu.sh                  boot out/microlinux-<arch>.iso as a CD
#   ./scripts/run-qemu.sh --arch x86_64    pick the architecture (default: the host's,
#                                          aarch64 on Apple Silicon)
#   ./scripts/run-qemu.sh --bios           x86_64 only: legacy BIOS (SeaBIOS) instead of UEFI
#   ./scripts/run-qemu.sh --usb            boot it as a USB stick instead
#   ./scripts/run-qemu.sh --disk           also attach out/disk-<arch>.qcow2 (20G, created
#                                          if missing) to test ml-install
#   ./scripts/run-qemu.sh --hd             boot only from out/disk-<arch>.qcow2 (installed system)
#   ./scripts/run-qemu.sh --serial         no window; console on this terminal
#   ISO=path MEM=2048 CPUS=4 ./scripts/run-qemu.sh
#
# A guest of the host's architecture runs with hardware virtualisation
# (HVF/KVM). x86_64 on Apple Silicon is emulated (TCG): it works, but
# expect it to be several times slower.
set -e
cd "$(dirname "$0")/.."
case "$(uname -m)" in arm64|aarch64) HOSTARCH=aarch64 ;; *) HOSTARCH=x86_64 ;; esac
ARCH=$HOSTARCH BIOS= USB= ADDDISK= HD= DISPLAY_OPT=
while [ $# -gt 0 ]; do
	case "$1" in
		--arch)   ARCH=$2; shift ;;
		--bios)   BIOS=1 ;;
		--usb)    USB=1 ;;
		--disk)   ADDDISK=1 ;;
		--hd)     HD=1 ;;
		--serial) DISPLAY_OPT="-display none" ;;
		*) echo "unknown option $1"; exit 1 ;;
	esac
	shift
done
MEM=${MEM:-2048}
CPUS=${CPUS:-4}
ISO=${ISO:-out/microlinux-$ARCH.iso}
DISK=out/disk-$ARCH.qcow2
mkdir -p out
# files from before x86_64 support belong to the aarch64 build
[ "$ARCH" = aarch64 ] && [ -f out/disk.qcow2 ] && [ ! -f "$DISK" ] && mv out/disk.qcow2 "$DISK"
[ -f out/efivars.fd ] && [ ! -f out/efivars-aarch64.fd ] && mv out/efivars.fd out/efivars-aarch64.fd

QEMU=$(command -v qemu-system-$ARCH) || { echo "qemu-system-$ARCH not found: brew install qemu"; exit 1; }
SHARE=$(dirname "$QEMU")/../share/qemu

case "$(uname -s)" in
	Darwin) HWACCEL="-accel hvf -cpu host"; [ -n "$DISPLAY_OPT" ] || DISPLAY_OPT="-display cocoa,zoom-to-fit=on" ;;
	Linux)  HWACCEL="-accel kvm -cpu host"; [ -w /dev/kvm ] || HWACCEL=; [ -n "$DISPLAY_OPT" ] || DISPLAY_OPT="-display gtk" ;;
esac
if [ "$ARCH" = "$HOSTARCH" ] && [ -n "$HWACCEL" ]; then ACCEL=$HWACCEL
else ACCEL="-accel tcg,thread=multi -cpu max"; fi

if [ -n "$HD" ]; then
	MEDIA="-drive if=none,id=hd,file=$DISK,format=qcow2 -device virtio-blk-pci,drive=hd"
	[ -f "$DISK" ] || { echo "$DISK not found - install with --disk first"; exit 1; }
else
	[ -f "$ISO" ] || { echo "$ISO not found - run ./scripts/build.sh first"; exit 1; }
	if [ -n "$USB" ]; then
		MEDIA="-drive if=none,id=stick,file=$ISO,format=raw,readonly=on -device usb-storage,drive=stick"
	else
		MEDIA="-device virtio-scsi-pci,id=scsi0 -drive if=none,id=cd,file=$ISO,media=cdrom,readonly=on -device scsi-cd,drive=cd,bus=scsi0.0"
	fi
fi
if [ -n "$ADDDISK" ]; then
	[ -f "$DISK" ] || qemu-img create -f qcow2 "$DISK" 20G >/dev/null
	MEDIA="$MEDIA -drive if=none,id=hd,file=$DISK,format=qcow2 -device virtio-blk-pci,drive=hd"
fi

case "$ARCH" in
	aarch64)
		[ -z "$BIOS" ] || { echo "--bios: arm64 has no BIOS (UEFI only)"; exit 1; }
		[ -f out/efivars-aarch64.fd ] || cp "$SHARE/edk2-arm-vars.fd" out/efivars-aarch64.fd
		MACHINE="-M virt"
		FIRMWARE="-drive if=pflash,format=raw,readonly=on,file=$SHARE/edk2-aarch64-code.fd -drive if=pflash,format=raw,file=out/efivars-aarch64.fd"
		GPU="-device virtio-gpu-pci" ;;
	x86_64)
		MACHINE="-M q35"
		if [ -n "$BIOS" ]; then FIRMWARE=   # QEMU's default firmware is SeaBIOS
		else
			[ -f out/efivars-x86_64.fd ] || cp "$SHARE/edk2-i386-vars.fd" out/efivars-x86_64.fd
			FIRMWARE="-drive if=pflash,format=raw,readonly=on,file=$SHARE/edk2-x86_64-code.fd -drive if=pflash,format=raw,file=out/efivars-x86_64.fd"
		fi
		GPU="-vga none -device virtio-vga" ;;
	*) echo "unknown arch $ARCH (aarch64, x86_64)"; exit 1 ;;
esac

exec "$QEMU" $MACHINE $ACCEL -smp "$CPUS" -m "$MEM" $FIRMWARE \
	$GPU -device qemu-xhci -device usb-kbd -device usb-tablet \
	-device virtio-rng-pci \
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
	$MEDIA $DISPLAY_OPT -serial mon:stdio
