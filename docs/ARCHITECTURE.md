# MicroLinux architecture

## Goals and the decisions that follow from them

| Goal | Decision |
|------|----------|
| Small, but a *real* Linux, maintainable by one person | **Buildroot** (2026.02 LTS) builds everything from upstream source with pinned versions and hashes. No package is reimplemented. Our own code is limited to configuration and a handful of shell tools. |
| Run RHEL/CentOS 7 binaries | **glibc**, not musl. glibc keeps every old symbol version (`GLIBC_2.17` and so on), so binaries linked on EL7 load against today's glibc 2.42. Missing sonames are supplied by compat libraries, and an exact EL7 runtime covers the rest (see [EL7-COMPAT.md](EL7-COMPAT.md)). |
| Two architectures from one tree | **aarch64 and x86_64** are built from the same Buildroot external tree: one shared config fragment plus a short one per architecture (CPU, kernel image, firmware, boot loader). Everything above the kernel (packages, desktop, tools, EL7 layer, tests) is identical. |
| Boot on arbitrary hardware | arm64: **UEFI + GRUB 2 (arm64-efi)**, a kernel from the arm64 `defconfig` with unused SoC families removed, **EFI zboot** image. arm64 has no BIOS; UEFI (native, or U-Boot's EFI layer) is the common denominator. x86_64: **GRUB 2 for BIOS (i386-pc) and UEFI (x86_64-efi)** on one hybrid image, kernel from `x86_64_defconfig` + PC/laptop/VM drivers, `bzImage`. |
| Small ISO, fast boot | Root filesystem is **SquashFS (xz)**, mounted read-only with an **overlayfs** on tmpfs for writes. Large optional software (Firefox, EL7 runtime) lives in separate **SquashFS packages** that are mounted, never unpacked. |
| Small RAM footprint | BusyBox init (no service manager daemons), eudev, LXQt (the lightest Qt desktop environment) with Openbox. No compositor. |

## Boot flow

```
UEFI firmware                                    BIOS (x86_64 only)
  └─ EFI/BOOT/BOOTAA64.EFI | BOOTX64.EFI           └─ El Torito: boot/grub/i386-pc/eltorito.img
     (GRUB 2.12, modules + small config embedded)     USB stick: hybrid MBR (GRUB boot_hybrid.img)
       ├─ grub.cfg next to it?  → installed system (ESP)    installed disk: BIOS boot partition
       └─ else search /boot/grub/microlinux-live.id → live medium
            └─ grub.cfg menu: live / to-RAM / safe graphics / text /
                              recovery / emergency shell / verbose / no saved changes / no-modules / firmware setup
                 └─ /boot/vmlinuz (Linux 6.18 LTS) + initramfs.cpio.gz (BusyBox, ~1.5 MB)
                      /init:
                        live:      find LABEL=MICROLINUX → mount iso9660
                                   → loop-mount /live/rootfs.sqfs (ro)
                                   → overlayfs (upper: the stick's MLPERSIST ext4 partition, else tmpfs)
                        installed: root=UUID=… → mount ext4
                        → switch_root → /sbin/init (BusyBox init)
                             rcS → S01 syslogd, S02 klogd, S10 udev (eudev, module autoload),
                                   S12 mlpkg (mount packages), S30 dbus, S40 network (DHCP),
                                   S40 bluetoothd, S45 ntp
                             vt7: LightDM → autologin → ml-xsession → ~/.xinitrc → startlxqt (Openbox);
                                  after logging out: the login screen (lightdm-gtk-greeter)
                             tty1-3: getty, serial: getty on ttyAMA0/ttyS0
```

Kernel command-line options (all documented in `grub.cfg` and `initramfs/init`):
`ml.live=`, `ml.toram`, `ml.persist=`, `ml.nopersist`, `ml.break`, `ml.debug`, `ml.wait=`,
`ml.nox`, `ml.recovery`, `ml.nomodules`, `ml.nontp`, `ml.res=WxH`, `ml.keymap=`,
plus standard `root=`, `rootfstype=`, `rootflags=`, `nomodeset`, `quiet`, `loglevel=`.

## Filesystem layout

- Merged `/usr` (`/bin`, `/sbin`, `/lib` are symlinks into `/usr`), the same as RHEL 7.
- `/usr/lib64 → lib`, `/lib64 → usr/lib64`, so RHEL-style paths resolve.
- `/etc/pki/tls/certs/ca-bundle.crt` → the system CA bundle (RHEL location).
- Live system: `/live/medium` (ISO), `/live/rootfs` (pristine SquashFS), `/live/cow` (writable layer).
- Packages: `/opt/<name>` (mounted SquashFS), launchers in `/usr/local/bin`,
  menu entries in `/usr/local/share/applications`.

## Components

| Area | Component |
|------|-----------|
| Kernel | Linux 6.18.62 LTS, arch default config + `linux-common.fragment` + `linux-<arch>.fragment` |
| Bootloader | GRUB 2.12. arm64: arm64-efi. x86_64: i386-pc + x86_64-efi. Hybrid ISO via xorriso (El Torito EFI + GPT ESP; x86_64 adds El Torito BIOS + hybrid MBR) |
| libc | glibc 2.42 |
| Init / devices / logging | BusyBox init, eudev, BusyBox syslogd/klogd/logread |
| Shells and core tools | BusyBox ash, bash, util-linux, coreutils (BusyBox), findutils (BusyBox) |
| Disks | e2fsprogs, dosfstools, parted, util-linux (lsblk, wipefs, losetup, fsck), squashfs-tools |
| Networking | iproute2, udhcpc, wpa_supplicant, iw, ethtool, curl, OpenSSH client, ca-certificates, ntpd |
| Bluetooth | BlueZ 5 (bluetoothd, bluetoothctl, HID/HoG) |
| Hardware info | pciutils, usbutils, dmidecode, lscpu, `ml-hwinfo` |
| Graphics | Xorg (modesetting, fbdev fallback, libinput), Mesa softpipe (GL for GTK/Firefox) |
| Desktop | LXQt 2.4 (Qt 6.9, KDE Frameworks 6.30 libraries), Openbox, PCManFM-Qt, QTerminal, xterm, GTK 3 (Firefox, Settings), Adwaita icons, DejaVu + Liberation fonts |
| Browser | Firefox ESR 153 official Mozilla build for the architecture (package `firefox`) |
| EL7 | libxcrypt-compat (`libcrypt.so.1`), ncurses ABI 5, `libbz2.so.1`, package `el7-runtime`, `elfcheck`, `el7-run`, `el7-chroot` |
| Packaging | `mlpkg` |

## Why these choices

- **Buildroot over Alpine/Debian/Yocto.** Alpine is musl, so EL7 binaries would not run. Debian
  netinst-based minimal images are 300 MB+ and would mean "installing another distribution".
  Yocto is heavier to maintain. Buildroot produces exactly the files we choose.
- **LXQt over JWM, Xfce or KDE Plasma.** Earlier releases used JWM (one ~200 KB
  process). LXQt gives a complete desktop (panel, menu, file manager, settings,
  power management) while staying light, needs no logind or systemd, and its Qt 6
  libraries are shared by its parts. Openbox is its usual window manager under X11.
- **Xorg over Wayland.** Without GPU drivers, a Wayland compositor would do software
  compositing for every frame. Xorg with the modesetting driver's shadow
  framebuffer is lighter, and every program here supports X11.
- **Firefox binary over a WebKit browser.** It's a full modern browser with no
  multi-hour WebKit build. It's also a real-world large glibc application, which
  exercises the same compatibility guarantees as the EL7 work.
- **SquashFS packages over a traditional package manager.** The base system is an
  image (as on ChromeOS or Fedora Silverblue). Add-ons stay compressed, install and
  remove atomically, can't conflict with base files, and the live medium can use
  them directly without copying.
- **No PAM, logind or systemd.** BusyBox init and shadow-style `/etc/passwd`
  keep the moving parts few. Xorg is setuid root, because there's no logind to
  hand it device access.

## Hardware support notes

- Wired: virtio-net, Intel e1000e/igb, Realtek r8169, USB Ethernet (r8152, ax88179, CDC).
  x86_64 adds Intel e1000/igc, Atheros alx/atl1c, VMware vmxnet3.
- Wi-Fi: Realtek rtw88/rtw89, MediaTek MT7921/7922, with firmware. arm64 adds
  Broadcom brcmfmac (Raspberry Pi). x86_64 adds Intel iwlwifi (8265, 9xxx, AX200/201/210/211)
  and Atheros ath9k/ath10k.
- Bluetooth: Realtek, MediaTek over USB; arm64 also Broadcom over UART; x86_64
  also Intel (ibt firmware). Raspberry Pi on-board Bluetooth also needs the
  BCM43xx `.hcd` patch files, which are not in linux-firmware and therefore not included.
- Graphics: anything with a firmware framebuffer (UEFI GOP, or on x86 BIOS a
  VESA mode set by GRUB) through simpledrm, plus virtio-gpu and bochs. x86_64
  adds Intel i915, VMware, VirtualBox and Cirrus KMS drivers. No AMD/NVIDIA
  drivers (firmware size); those run on the firmware framebuffer.
