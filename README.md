# MicroLinux

A tiny, fully functional Linux distribution for **x86_64** and **aarch64**
(64-bit ARM), built from upstream sources with Buildroot.

- **Boots anywhere**: x86_64 PCs and VMs from BIOS or UEFI; arm64 machines,
  VMs and boards with UEFI (QEMU, UTM, Parallels, VMware, servers, Raspberry Pi
  with UEFI firmware). The live ISO is also a bootable USB image.
- **Real Linux userland**: glibc, BusyBox, bash, util-linux, e2fsprogs, parted,
  iproute2, wpa_supplicant, BlueZ, OpenSSH client, curl, sudo, htop, nano/vi, strace.
- **Desktop**: Xorg + LXQt 2.4 (Qt 6) with the Openbox window manager: panel,
  application menu, QTerminal, PCManFM-Qt file manager and desktop, LXQt
  Archiver (zip, 7z, tar.gz/xz/bz2/zst; right-click → Extract Here), LXQt
  configuration center, and a MicroLinux Settings app (network/Wi-Fi, Bluetooth, display,
  sound, wallpaper, keyboard, time zone, password, packages).
- **Browser**: official Mozilla Firefox ESR, shipped as an optional package.
- **EL7 binary compatibility**: runs RHEL/CentOS 7 binaries of the same
  architecture natively (glibc symbol versions + compat libraries), with an
  exact EL7 runtime (`el7-run`, `el7-chroot`) for programs that need EL7-only
  libraries. The test suite uses real CentOS 7 RPMs.
- **Packages**: `mlpkg` with dependencies and an online repository of about 90
  applications (Python, Perl, Ruby, git, gdb, vim, tmux, nmap, mpv, …) at
  [praneethashok14/microlinux-packagerepo](https://github.com/praneethashok14/microlinux-packagerepo).
- **Installer**: a graphical installer (`ml-installer`, Rust + egui) in front
  of `ml-install`, which writes a GPT disk with an ESP and an ext4 root
  (x86_64: also bootable from BIOS), or installs **alongside Windows** (dual
  boot: free space, shared EFI partition, GRUB menu with Windows).
- **GPU drivers** (x86_64): hardware OpenGL on Intel, AMD Radeon and NVIDIA
  GeForce/RTX (Mesa iris/crocus/radeonsi/r600/nouveau, llvmpipe otherwise);
  AMD/NVIDIA firmware from the repository.
- **Minecraft**: Prism Launcher and Java 25/21/17/8 in the repository
  (`sudo mlpkg install prismlauncher`).

## Download

Ready-made ISOs are on the [releases page](https://github.com/praneethashok14/microlinux/releases/latest):

| | Full (base + Firefox + EL7 runtime) | Base only |
|---|---|---|
| PCs (x86_64) | [microlinux-x86_64.iso](https://github.com/praneethashok14/microlinux/releases/latest/download/microlinux-x86_64.iso) | [microlinux-x86_64-base.iso](https://github.com/praneethashok14/microlinux/releases/latest/download/microlinux-x86_64-base.iso) |
| ARM (aarch64) | [microlinux-aarch64.iso](https://github.com/praneethashok14/microlinux/releases/latest/download/microlinux-aarch64.iso) | [microlinux-aarch64-base.iso](https://github.com/praneethashok14/microlinux/releases/latest/download/microlinux-aarch64-base.iso) |

Checksums: `SHA256SUMS-<arch>` (GPG-signed, `.asc`) on the same page. Logins
on the live system: `user` / `live`, `root` / `microlinux`.

## Quick start (macOS)

```sh
brew install qemu lima                    # one time
./scripts/build.sh                        # build both architectures (see docs/BUILD.md)
./scripts/run-qemu.sh                     # boot the host architecture's ISO in a QEMU window
./scripts/run-qemu.sh --arch x86_64       # x86_64 (emulated on Apple Silicon); --bios for legacy BIOS
python3 tests/run-tests.py --arch x86_64  # automated test suite
```

Live session logins: `user` / `live` (auto-login to the desktop), `root` / `microlinux`.

Outputs in `out/`:

| File | What |
|------|------|
| `microlinux-<arch>.iso` | full live image: base system + Firefox + EL7 runtime packages |
| `microlinux-<arch>-base.iso` | base system only (packages installable with `mlpkg`) |
| `size-report-<arch>.txt` | measured sizes of every component |

The package repository is written to `../microlinux-repo/<arch>/` and published
with `./scripts/publish-repo.sh`.

On a real PC: write the x86_64 ISO to a USB stick
(`sudo dd if=out/microlinux-x86_64.iso of=/dev/rdiskN bs=4m` on macOS) and boot
from it. **Secure Boot can stay on**: the first time, enroll the MicroLinux key
in the blue MOK Manager screen (see [docs/SECUREBOOT.md](docs/SECUREBOOT.md)).
The ISO checksums are GPG-signed (`out/SHA256SUMS-<arch>.asc`).

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design and component choices
- [docs/BUILD.md](docs/BUILD.md): build environment, reproducibility, layout
- [docs/USAGE.md](docs/USAGE.md): using the system (network, Wi-Fi, Bluetooth, packages, install)
- [docs/EL7-COMPAT.md](docs/EL7-COMPAT.md): EL7 compatibility layer and how to test your binaries
- [docs/SECUREBOOT.md](docs/SECUREBOOT.md): Secure Boot, signed packages, verifying downloads, keys
- [docs/TESTING.md](docs/TESTING.md): test suite and latest results
- [docs/LICENSES.md](docs/LICENSES.md): licensing of bundled components

## Measured results: aarch64 (v0.1.0, 2026-11-07, QEMU virt on Apple Silicon, 2 GiB RAM)

| | |
|---|---|
| Full ISO (base + Firefox + EL7 runtime) | **194 MiB** |
| Base ISO | **106 MiB** |
| Kernel / initramfs / root squashfs | 12 / 1 / 83 MiB (285 MiB uncompressed) |
| Firefox package / EL7 runtime package | 79 / 9 MiB |
| Power-on → GRUB → login prompt | 6 s → 13 s |
| Idle RAM, desktop running, no browser | **76 MiB** used (`free`); 150 MiB MemTotal−MemAvailable, which also counts the live system's tmpfs/page cache |
| Automated tests | **27/27 pass**, including the EL7 suite (20/20, real CentOS 7 binaries) and install-to-disk + boot from disk |

The full ISO is above the original 150 MB goal because of Firefox (79 MiB
compressed). Without it the system is 106 MiB.
