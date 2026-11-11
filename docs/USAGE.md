# Using MicroLinux

## Boot menu

| Entry | Use |
|-------|-----|
| live desktop | default; boots to the LXQt desktop as `user` |
| copy system to RAM | loads the system (and packages) into RAM; the medium can be removed |
| safe graphics | `nomodeset`: firmware framebuffer only (try this if the screen stays black) |
| text mode | no desktop (`ml.nox`); log in on tty1-3 or serial |
| Troubleshooting → Recovery | root shell, only logging and udev started |
| Troubleshooting → Emergency | shell inside the initramfs, before the root filesystem is mounted |
| Troubleshooting → Verbose | all kernel and init messages |
| Troubleshooting → no optional modules | skip Firefox/EL7 packages |
| Troubleshooting → live without saved changes | ignore the `ml-persist` partition for this boot (`ml.nopersist`) |

x86_64 images boot from BIOS and UEFI, as a CD/DVD or written to a USB stick
(`dd if=microlinux-x86_64.iso of=/dev/sdX bs=4M`). aarch64 images boot from UEFI.

### Keeping changes on the USB stick (persistence)

By default the live system keeps changes in RAM, so they are lost at reboot.
On a USB stick, run once:

```sh
sudo ml-persist              # or: sudo ml-persist --size 4G
```

It creates an ext4 partition labelled `MLPERSIST` in the free space after the
image (the system part of the stick isn't changed) and copies this session's
changes to it. Every following boot from that stick keeps your files,
settings and installed packages there automatically. Only a `MLPERSIST`
partition on the stick you booted from is used. To start clean once, choose
Troubleshooting → "Live without saved changes". To discard the changes for
good, delete the partition.

Logins: `user` / `live`, `root` / `microlinux`. In the live system `user` can
use `sudo` without a password. On an installed system the desktop account has
the username chosen in the installer (`ml-install --user NAME --fullname "Full
Name"`; default `user`), and the passwords are the ones set while installing.

The desktop starts without asking for a password. After logging out (menu →
Leave → Log out) the login screen (LightDM) appears: log in again with
`user`'s password. Ctrl+Alt+L locks the screen the same way. Text consoles:
Ctrl+Alt+F1 to F3, back to the desktop with Ctrl+Alt+F7.

## Desktop

The menu opens from the button at the left of the panel, the Super (Windows)
key, or Alt+F1. Shortcuts: Ctrl+Alt+T terminal, Ctrl+Alt+E files, Ctrl+Alt+L
lock, Alt+Tab, Alt+F4. A laptop touchpad clicks on a tap. Resolution: menu → Display, or
`ml-display set 1920x1080` (add `ml.res=1920x1080` to the kernel command line to
set it at boot).

## Settings

**Settings** (menu → Preferences → Settings, or the panel button; `ml-settings` from a
terminal) covers the common configuration:

| Page | |
|------|--|
| Network | interfaces and addresses, Wi-Fi scan and connect, connection test |
| Bluetooth | power, scan, pair/connect/remove devices |
| Display | resolution, or automatic; kept for future logins |
| Sound | volume and mute |
| Appearance | wallpaper (default gradient, solid colour or a picture), dark mode for applications |
| Keyboard | layout; kept for future logins |
| Date & Time | clock, time zone, synchronise now |
| Users | change your password |
| Packages | browse, search, install and remove packages (mlpkg) |
| About | system information; live system: install to disk, keep changes on USB; installed system: update the system; system log |

Changes that need administrator rights go through `sudo`: on an installed
system a password dialog asks for your password. `ml-settings PAGE` opens a
page directly (e.g. `ml-settings packages`).

## Network

Wired interfaces get DHCP automatically. `netcfg status`, `netcfg test`.

```sh
sudo netcfg wifi-scan
sudo netcfg wifi "My SSID" "passphrase"      # saved, reconnects at boot
sudo netcfg static eth0 192.168.1.50/24 192.168.1.1 1.1.1.1
ssh user@host                                 # OpenSSH client
```

## Bluetooth

```sh
bluetoothctl
[bluetooth]# power on
[bluetooth]# scan on
[bluetooth]# pair AA:BB:CC:DD:EE:FF
[bluetooth]# trust AA:BB:CC:DD:EE:FF
[bluetooth]# connect AA:BB:CC:DD:EE:FF
```

Keyboards, mice and other HID devices work (HID/HoG plugins). Bluetooth audio
isn't included.

## Packages

MicroLinux has an online package repository with about 75 applications and
tools (plus the libraries they need), built from source for aarch64 and x86_64.
Among them: Python 3 (with pip and requests), Perl, Ruby, Lua, Tcl, PHP, git,
tig, make, gdb, valgrind, vim, tmux, screen, Midnight Commander, ranger,
ripgrep, rsync, 7-Zip, nmap, tcpdump, iperf3, mtr, dig, WireGuard, OpenVPN,
Tor, nginx, lighttpd, an SSH server (dropbear), irssi, lynx, transmission, mpv
(with ffmpeg), feh, MuPDF, ImageMagick, NetSurf and Dillo (browsers), gnuplot,
filesystem tools (btrfs, xfs, ntfs, exfat, LVM, cryptsetup, mdadm), and games.

```sh
sudo mlpkg update          # fetch the package lists
mlpkg list                 # applications (mlpkg list -a: also libraries)
mlpkg search editor
mlpkg info mpv             # version, size, dependencies
sudo mlpkg install python3 git mpv      # dependencies are installed automatically
mlpkg list -i              # installed
sudo mlpkg remove mpv
sudo mlpkg autoremove      # remove dependencies nothing needs any more
mlpkg verify
```

The online repository is
`https://github.com/praneethashok14/microlinux-packagerepo/releases/download/packages-<arch>`,
already listed in `/etc/mlpkg/repos.conf` (after the packages on the live
medium). Every download is checked against the SHA-256 in the repository's INDEX.

Two kinds of packages:

- **Repository packages** (`type=files`) are installed into the system like on
  any distribution: the files are copied to `/usr`, `/etc`, … and recorded in
  `/var/lib/mlpkg/installed/<name>.files`, and removing the package deletes
  exactly those files. A package can't overwrite a file of the base system or
  of another package. Where it replaces a BusyBox applet (`wget`, `bc`, `diff`,
  `unzip`, …), the BusyBox version comes back when the package is removed.
  Servers (nginx, dropbear, tor, …) are never started automatically.
- **Image packages** (Firefox, the EL7 runtime) stay compressed and are mounted
  under `/opt/<name>`.

On the live system, installed packages live in RAM (or on the persistence
partition made by `ml-persist`). On an installed system they are
on disk. `ml-install` copies image packages to the new installation;
repository packages are installed on the installed system itself.

Other repositories: `sudo mlpkg repo add https://host/path` (or `file:///mnt/usb/repo-x86_64`),
`mlpkg repo list`, `sudo mlpkg repo remove URL`.

### Making packages

- Repository packages are Buildroot packages: add `BR2_PACKAGE_<NAME>=y` to
  `external/configs/fragments/repo.config` and rebuild. After the build,
  `board/microlinux/repo-split.py` moves every package the base system doesn't
  need out of the root filesystem. Their dependencies become packages too, and
  the result is written to `../microlinux-repo/<arch>/` (a folder next to this
  project, which is the local copy of the GitHub repository).
  `./scripts/publish-repo.sh` uploads the packages to the GitHub releases and
  pushes the folder (README, INDEX, SOURCES.txt).
- Your own package: a directory with the files under their final paths (`usr/bin/...`)
  and a `.mlpkg/info` with `name=`, `version=`, `type=files`, `depends=`,
  `description=`; then `mksquashfs dir name-version.mlp -comp xz -all-root` and
  `sudo mlpkg install ./name-version.mlp`. A self-contained `/opt` application:
  leave out `type=` and set `mountpoint=/opt/<name>`, `bin=`, `desktop=`.

## Installing to a disk

**Install MicroLinux** (menu → System, or Settings → About) opens the
graphical installer, `ml-installer` (Rust + egui): choose the disk and whether
to erase it or install alongside the systems on it, enter your name, username,
the computer name and a password, check the summary, and watch the progress. It runs `ml-install`
(through sudo) to do the work, so everything below applies to both.

`sudo ml-install` is the same installer on the command line. It asks
for the disk, then creates a GPT with a 256 MiB EFI partition and an ext4 root,
copies the system and active packages, and sets passwords. The disk then boots
through the UEFI removable-media path (`EFI/BOOT/BOOTAA64.EFI` on arm64,
`EFI/BOOT/BOOTX64.EFI` on x86_64), so no firmware boot entries are needed. On
x86_64 it also adds a 1 MiB BIOS boot partition and installs GRUB for BIOS, so
the same disk boots on BIOS and UEFI PCs.

**Dual boot** (UEFI, GPT): `sudo ml-install --alongside DISK`, or answer "1"
when `ml-install` finds partitions and free space on the disk. Make room first
(Windows: Disk Management → Shrink Volume; turn off Fast Startup). It keeps
every existing partition and puts the ext4 root into the largest free region
(2 GiB or more). The boot loader goes to `EFI/microlinux/` on the existing EFI
partition (shim + signed GRUB on x86_64, so Secure Boot keeps working), with
GRUB's `grub.cfg` next to it and the kernel on the ext4 root. A firmware boot
entry "MicroLinux" is added first in the boot order (efibootmgr). The GRUB menu
shows MicroLinux (default, 5 s) and Windows (chainloads
`\EFI\Microsoft\Boot\bootmgfw.efi`). See the
[wiki](https://github.com/praneethashok14/microlinux/wiki/Installing#dual-boot-with-windows)
for the Windows-side steps (BitLocker, AHCI, clock).

## Updating the system

`sudo mlpkg system-update` (or Settings → About → Update system) updates an installed MicroLinux to the newest
release on GitHub, then upgrades the packages (`--check` only reports whether
there is one, `-y` doesn't ask). It reads `BUILD-<arch>` and the checksums of
the release (signed with the repository key), downloads the base ISO only when
the build differs from `/etc/microlinux-build`, and replaces the system files
one by one (new file, then rename, so running programs keep working). It keeps
/home, /root, /var, /opt, /usr/local, the users and passwords, the host name,
fstab, sudo rules, Wi-Fi and repository settings, and the files of packages
installed with mlpkg; system users new in the release are added. Files of the
old system that the new one no longer has are removed. The kernel and the boot
loader are updated last; restart afterwards. The live system can't update
itself: write the new ISO to the stick instead. The release address is in
`/etc/mlpkg/system-update.conf`.

## System information and logs

`ml-sysinfo`, `sudo ml-hwinfo`, `htop`, `lsblk -f`, `lspci -k`, `lsusb`,
`sudo logread -f` (syslog), `dmesg`.
