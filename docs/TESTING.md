# Testing

## Automated suite

```sh
python3 tests/run-tests.py                  # full ISO of the host's architecture
python3 tests/run-tests.py --arch x86_64    # out/microlinux-x86_64.iso
python3 tests/run-tests.py --install        # + ml-install to a virtual disk and boot it
python3 tests/run-tests.py --iso out/microlinux-aarch64-base.iso --no-browser
```

The harness (Python standard library only) boots the ISO in QEMU (`virt` for
aarch64, `q35` for x86_64) with UEFI firmware (edk2) or, for the x86_64 BIOS
tests, SeaBIOS. A guest of the host's architecture uses hardware acceleration
(HVF on macOS, KVM on Linux). The other architecture is emulated (TCG), and
all timeouts are multiplied by 5. It logs in on the serial console, drives the
system with shell commands, and grabs screenshots through QMP. It writes, per
architecture:

- `tests/results/<arch>/report.md`: pass/fail table with details
- `tests/results/<arch>/serial.log`: the full console log, from firmware to shutdown
- `tests/results/<arch>/el7-compat.tap`: TAP output of the EL7 suite
- `tests/results/<arch>/*.png`: screenshots of the desktop, file manager and
  Firefox (and the BIOS GRUB menu on x86_64)

| # | Spec milestone | How it's checked |
|---|----------------|------------------|
| 1 | Boots in QEMU | GRUB menu appears after the UEFI firmware |
| 2 | UEFI boot | Kernel → initramfs → live root → login prompt; boot time measured |
| 2b | BIOS boot | x86_64: SeaBIOS boots the ISO as a CD-ROM to a login; Linux confirms it wasn't started by EFI. arm64: not applicable (no legacy BIOS exists), recorded as such |
| 2c, 2d | USB stick | x86_64: the same ISO as a raw USB disk boots under BIOS (hybrid MBR) and UEFI (GPT ESP) |
| 3 | Working shell | `uname`, os-release, BusyBox, bash |
| 4 | Mount filesystems | iso9660 + squashfs + overlayfs live stack; create, mount and fsck ext4 and FAT images |
| 5 | Network | DHCP address, DNS, HTTPS with certificate validation (and rejection of a self-signed cert), SSH handshake |
| 6 | Tools | presence of the essential utilities, syslog round-trip, user and permission management |
| 7 | Graphical environment | Xorg + JWM running, `xdpyinfo`, resolution change, xterm and PCManFM windows; screenshots |
| 8 | Browser | Firefox renders an HTTPS page headless; opens a window on the desktop; download to ~/Downloads |
| 9 | Compatible ELF binary | CentOS 7 `tree` and `bash` run natively (elfcheck verdict NATIVE) |
| 10 | EL7 compatibility | `el7-compat.sh`: 20 tests with real CentOS 7 binaries (native and el7-run), TLS with EL7 OpenSSL 1.0.2k, el7-chroot |
| R | Idle RAM | MemTotal − MemAvailable with the desktop idle, no browser |
| I | Installer | `ml-install` to a virtio disk, then boot that disk alone (x86_64: once with UEFI, once with BIOS) |

## Manual checks on real hardware

Wi-Fi and Bluetooth can't be emulated by QEMU. On hardware:
`sudo netcfg wifi-scan`, `sudo netcfg wifi SSID PASS`, `netcfg test`,
`bluetoothctl` → `power on` / `scan on`, and `sudo ml-hwinfo` for driver and
firmware status.

## Latest results

See `tests/results/report.md` (generated) and the summary in the top-level
README once a run has completed.
