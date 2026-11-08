# Using MicroLinux

## Boot menu

| Entry | Use |
|-------|-----|
| live desktop | default; boots to the JWM desktop as `user` |
| copy system to RAM | loads the system (and packages) into RAM; the medium can be removed |
| safe graphics | `nomodeset`: firmware framebuffer only (try this if the screen stays black) |
| text mode | no desktop (`ml.nox`); log in on tty1-3 or serial |
| persistent | keeps changes on an ext4 partition labelled `MLPERSIST` (`mkfs.ext4 -L MLPERSIST /dev/sdX2`) |
| Troubleshooting → Recovery | root shell, only logging and udev started |
| Troubleshooting → Emergency | shell inside the initramfs, before the root filesystem is mounted |
| Troubleshooting → Verbose | all kernel and init messages |
| Troubleshooting → no optional modules | skip Firefox/EL7 packages |

x86_64 images boot from BIOS and UEFI, as a CD/DVD or written to a USB stick
(`dd if=microlinux-x86_64.iso of=/dev/sdX bs=4M`). aarch64 images boot from UEFI.

Logins: `user` / `live`, `root` / `microlinux`. In the live system `user` can
use `sudo` without a password. Installed systems ask you to set both passwords.

## Desktop

The menu opens from the **MicroLinux** button, a right-click on the desktop, or
the Super key. Shortcuts: Super+Enter terminal, Super+E files, Super+W Firefox,
Alt+Tab, Alt+F4, Ctrl+Alt+Del task manager. Resolution: menu → Display, or
`ml-display set 1920x1080` (add `ml.res=1920x1080` to the kernel command line to
set it at boot).

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
partition with the "persistent" boot entry). On an installed system they are
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

`sudo ml-install` (or menu → System → Install MicroLinux to disk). It asks
for the disk, then creates a GPT with a 256 MiB EFI partition and an ext4 root,
copies the system and active packages, and sets passwords. The disk then boots
through the UEFI removable-media path (`EFI/BOOT/BOOTAA64.EFI` on arm64,
`EFI/BOOT/BOOTX64.EFI` on x86_64), so no firmware boot entries are needed. On
x86_64 it also adds a 1 MiB BIOS boot partition and installs GRUB for BIOS, so
the same disk boots on BIOS and UEFI PCs.

## System information and logs

`ml-sysinfo`, `sudo ml-hwinfo`, `htop`, `lsblk -f`, `lspci -k`, `lsusb`,
`sudo logread -f` (syslog), `dmesg`.
