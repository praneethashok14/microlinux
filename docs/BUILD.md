# Building MicroLinux

## Requirements

- A Linux build host (arm64 or x86_64), or a Mac running one in a VM. Both
  MicroLinux architectures (aarch64 and x86_64) build on either host:
  Buildroot builds its own cross toolchain, so the host distro only needs the
  basics:
  `build-essential git wget cpio unzip rsync bc file python3 perl patch gzip bzip2 xz-utils zstd
  libncurses-dev cmake ninja-build rpm2cpio rpm dpkg` (Ubuntu/Debian names).
  `rpm2cpio` unpacks the pinned CentOS 7 and AlmaLinux 10 RPMs for the
  `el7-runtime` and `el10-runtime` packages, and `rpm` writes the rpm database
  of `el10-runtime`. `dpkg-deb` (from `dpkg`) unpacks the Debian packages for
  `debian-runtime`.
- ~35 GB of disk space per architecture (~70 GB for both) and 8 GB of RAM.
- Network access for the first build (sources are cached afterwards).

## On a Mac (as set up in this repository)

```sh
brew install qemu lima
limactl start --name=builder --cpus=8 --memory=8 --disk=80 \
  --set '.mounts=[{"location":"'"$PWD"'","writable":true}]' template:ubuntu-lts
limactl disk create mlbuild --size 110GiB --format raw  # build disk (ext4, case-sensitive)
limactl edit builder --set '.additionalDisks=[{"name":"mlbuild","format":true,"fsType":"ext4"}]'
limactl shell builder sudo apt-get install -y build-essential git wget cpio unzip rsync bc file \
  python3 libncurses-dev perl patch gzip bzip2 xz-utils zstd cmake ninja-build rpm2cpio
limactl shell builder git clone -b 2026.02.3 https://gitlab.com/buildroot.org/buildroot.git /mnt/lima-mlbuild/buildroot
./scripts/build.sh                  # both architectures
./scripts/build.sh --arch x86_64    # or just one: aarch64 | x86_64
```

The build can't run directly on the shared Mac folder: APFS is
case-insensitive (the kernel tree has files that differ only by case), and
Lima's file sharing mangles symlinks. So the build runs on a raw ext4 disk image.
In this checkout that image is `build-disk.img` in the project folder, linked
from `~/.lima/_disks/mlbuild/datadisk`.

`scripts/build.sh` regenerates the defconfigs, mirrors the source tree onto
the build disk (Buildroot can't handle the space in the project path),
re-applies each architecture's defconfig and runs `make -j$(nproc)`. Each
architecture has its own output directory on the build disk
(`/mnt/lima-mlbuild/out` for aarch64, `/mnt/lima-mlbuild/out-x86_64`), so
they build incrementally and independently. The ISOs and size reports are
copied to `out/`: `microlinux-<arch>.iso`, `microlinux-<arch>-base.iso`,
`size-report-<arch>.txt`. `./scripts/progress.sh -w [arch]` shows a progress bar.

Other targets: `./scripts/build.sh --arch x86_64 menuconfig`, `linux-menuconfig`,
`lxqt-panel-rebuild`, … (any Buildroot make target).

## Configuration: one source, two architectures

The system definition lives in `external/configs/fragments/`: `common.config`
(everything shared: packages, desktop, EL7 layer) plus `aarch64.config` and
`x86_64.config` (CPU, kernel image, firmware, boot loader).
`scripts/gen-defconfigs.sh` concatenates them into
`external/configs/microlinux_<arch>_defconfig`, which are ordinary Buildroot
defconfigs. Edit the fragments, not the generated files.

| | aarch64 | x86_64 |
|---|---|---|
| CPU baseline | ARMv8.0-A (`cortex_a53`) | x86-64 (v1, as RHEL 7) |
| Kernel | arm64 defconfig, EFI zboot `vmlinuz.efi` | x86_64_defconfig, `bzImage` (EFI stub) |
| Firmware | UEFI | BIOS **and** UEFI (GRUB i386-pc + x86_64-efi) |
| Extra drivers | SoC platforms (Raspberry Pi, Rockchip, Allwinner, Amlogic, Qualcomm), Broadcom Wi-Fi | Intel Wi-Fi/Bluetooth (iwlwifi, ibt), Intel/AMD/VMware/VirtualBox graphics, Atheros |
| Firefox / EL7 runtime | linux-aarch64 build / CentOS 7 AltArch | linux-x86_64 build / CentOS 7 main tree |

## On a Linux machine

```sh
git clone -b 2026.02.3 https://gitlab.com/buildroot.org/buildroot.git
cd buildroot
make O=$PWD/../out-x86_64 BR2_EXTERNAL=/path/to/microlinux/external microlinux_x86_64_defconfig
make O=$PWD/../out-x86_64 -j$(nproc)
# result: ../out-x86_64/images/microlinux-x86_64.iso   (same with aarch64)
```

Edit `BR2_CCACHE_DIR` in `fragments/common.config` (then run
`scripts/gen-defconfigs.sh`) if `/mnt/lima-mlbuild` doesn't exist. Any host
architecture can build either target: Buildroot cross-compiles everything, and
`firefox-bin`/`el7-runtime` download the prebuilt binaries for the target
architecture.

## Reproducibility

- Buildroot release pinned (2026.02.3 LTS). All package versions and SHA-256
  hashes come from it or from `external/package/*/*.hash`.
- Kernel version pinned (6.18.62). Firefox pinned with Mozilla's published SHA-256.
- CentOS 7 / AlmaLinux 10 RPMs and Debian 13 packages pinned by URL and
  SHA-256 (from the repository metadata) in
  `external/package/{el7,el10,debian}-runtime/<name>-<arch>.lock`. Regenerate
  deliberately with `python3 scripts/runtime-lock.py el7|el10|debian aarch64|x86_64`.
  Debian comes from snapshot.debian.org, so its URLs never change. AlmaLinux
  10.2 moves to vault.almalinux.org once 10.3 is out: then change `base` in the
  script and run it again.
- Images are built with fixed timestamps (`mksquashfs -mkfs-time 0 -all-time 0`,
  `cpio --reproducible`, `gzip -n`).

## Source tree

```
VERSION                               release number
external/                             BR2_EXTERNAL tree
  configs/fragments/*.config         the whole system definition (common + per arch)
  configs/microlinux_<arch>_defconfig  generated from the fragments
  board/microlinux/
    linux-common.fragment             kernel config shared by both architectures
    linux-aarch64.fragment            ... on top of arm64 defconfig
    linux-x86_64.fragment             ... on top of x86_64_defconfig
    busybox.fragment                  BusyBox applets
    grub.cfg, grub-embed.cfg          boot menu, config embedded in the GRUB images
    initramfs/init                    live/installed root mounting
    rootfs-overlay/                   /etc, init scripts, desktop config, tools
    users.txt                         the 'user' account
    post-build.sh                     rootfs tweaks (setuid Xorg, EL7 paths, caches)
    post-image.sh                     initramfs, packages, dependency checks, ISOs, size report
  package/
    lxqt-*/, kf6-*/, ...              LXQt desktop and its libraries
    libxcrypt-compat/                 libcrypt.so.1 for old binaries
    ncurses5-compat/                  ncurses ABI 5 libraries
    firefox-bin/                      Firefox ESR → firefox.mlp
    el7-runtime/                      CentOS 7 runtime → el7-runtime.mlp
    el10-runtime/                     AlmaLinux 10 runtime → el10-runtime.mlp
    debian-runtime/                   Debian 13 runtime → debian-runtime.mlp
scripts/build.sh                      build in the Lima VM
scripts/gen-defconfigs.sh             fragments -> defconfigs
scripts/progress.sh                   build progress bar
scripts/run-qemu.sh                   run the ISO / installed disk
scripts/runtime-lock.py               pin the EL7 / EL10 / Debian packages
tests/run-tests.py                    automated QEMU test suite
```

## Kernel configuration

`linux-common.fragment` plus `linux-<arch>.fragment` document every change
against the architecture's default config. Everything on the path to the root
filesystem is built in
(virtio, SCSI/CD-ROM, AHCI, NVMe, USB storage, SquashFS, overlayfs, ISO 9660,
ext4, FAT), so the initramfs needs no modules. To change it interactively:
`./scripts/build.sh linux-menuconfig`. Changes made there are lost at the next
defconfig, so copy the options you want to keep into a fragment.
