#!/usr/bin/env python3
"""MicroLinux automated test suite.

Boots the ISO in QEMU (UEFI; on x86_64 also BIOS), drives the serial console,
and checks every milestone from the project spec. A guest of the host's
architecture uses HVF/KVM; another architecture is emulated (TCG) and all
timeouts are scaled up. Results go to tests/results/<arch>/: report.md,
serial.log and screenshots (PNG).

    python3 tests/run-tests.py                 # out/microlinux-<host arch>.iso
    python3 tests/run-tests.py --arch x86_64   # out/microlinux-x86_64.iso
    python3 tests/run-tests.py --iso out/microlinux-aarch64-base.iso --no-browser
    python3 tests/run-tests.py --install       # also test ml-install + boot from disk
    python3 tests/run-tests.py --keep          # leave the VM running at the end

Only the Python standard library is used.
"""
import argparse, functools, http.server, json, os, platform, re, shutil, socket, struct, subprocess, sys, threading, time, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN = os.path.join(ROOT, "tests", ".run")
HOSTARCH = "aarch64" if platform.machine() in ("arm64", "aarch64") else "x86_64"
ARCH = HOSTARCH     # set from the command line in main()
RES = None          # tests/results/<arch>
SCALE = 1           # timeout multiplier: >1 when the guest is emulated


def hw_accel():
    if ARCH != HOSTARCH:
        return None
    if platform.system() == "Darwin":
        return ["-accel", "hvf", "-cpu", "host"]
    if os.access("/dev/kvm", os.W_OK):
        return ["-accel", "kvm", "-cpu", "host"]
    return None


# --------------------------------------------------------------------------- QEMU
class VM:
    def __init__(self, media, mem=2048, cpus=4, extra=(), bios=False):
        os.makedirs(RUN, exist_ok=True)
        q = shutil.which(f"qemu-system-{ARCH}")
        if not q:
            sys.exit(f"qemu-system-{ARCH} not found (brew install qemu)")
        share = os.path.join(os.path.dirname(q), "..", "share", "qemu")
        self.ser_path = os.path.join(RUN, "serial.sock")
        self.qmp_path = os.path.join(RUN, "qmp.sock")
        for p in (self.ser_path, self.qmp_path):
            if os.path.exists(p):
                os.unlink(p)
        accel = hw_accel() or ["-accel", "tcg,thread=multi", "-cpu", "max"]
        if ARCH == "aarch64":
            machine, code, vars_t = "virt", "edk2-aarch64-code.fd", "edk2-arm-vars.fd"
            gpu = ["-device", "virtio-gpu-pci,xres=1280,yres=800"]
        else:
            machine, code, vars_t = "q35", "edk2-x86_64-code.fd", "edk2-i386-vars.fd"
            gpu = ["-vga", "none", "-device", "virtio-vga,xres=1280,yres=800"]
        firmware = []
        if not bios:   # UEFI; without pflash QEMU x86 boots its default SeaBIOS
            vars_f = os.path.join(RUN, "efivars.fd")
            shutil.copy(os.path.join(share, vars_t), vars_f)
            firmware = ["-drive", f"if=pflash,format=raw,readonly=on,file={os.path.join(share, code)}",
                        "-drive", f"if=pflash,format=raw,file={vars_f}"]
        cmd = [q, "-M", machine, *accel, "-smp", str(cpus), "-m", str(mem), *firmware, *gpu,
               "-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet",
               "-device", "virtio-rng-pci",
               "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
               # a NIC whose driver is a module (like real hardware): it must load by itself
               "-netdev", "user,id=n1", "-device", "e1000e,netdev=n1",
               # Intel HD Audio, like a PC (output discarded)
               "-audiodev", "none,id=snd0", "-device", "intel-hda", "-device", "hda-output,audiodev=snd0",
               *media, *extra,
               "-display", "none",
               "-chardev", f"socket,id=ser,path={self.ser_path},server=on,wait=off,logfile={os.path.join(RES, 'serial.log')},logappend=on",
               "-serial", "chardev:ser",
               "-qmp", f"unix:{self.qmp_path},server=on,wait=off"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.t0 = time.time()
        for _ in range(100):
            if os.path.exists(self.ser_path) and os.path.exists(self.qmp_path):
                break
            time.sleep(0.1)
        self.ser = socket.socket(socket.AF_UNIX)
        self.ser.connect(self.ser_path)
        self.ser.settimeout(0.5)
        self.buf = ""
        self.qmp = socket.socket(socket.AF_UNIX)
        self.qmp.connect(self.qmp_path)
        self.qmpf = self.qmp.makefile("rw")
        self.qmpf.readline()
        self.qmp_cmd("qmp_capabilities")

    # serial ------------------------------------------------------------------
    def _read(self):
        try:
            d = self.ser.recv(65536)
            if d:
                self.buf += d.decode("utf-8", "replace")
        except socket.timeout:
            pass

    def expect(self, pattern, timeout=60):
        rx = re.compile(pattern)
        end = time.time() + timeout * SCALE
        while time.time() < end:
            m = rx.search(self.buf)
            if m:
                out = self.buf[:m.end()]
                self.buf = self.buf[m.end():]
                return m, out
            if self.proc.poll() is not None:
                raise RuntimeError("QEMU exited: " + self.proc.stderr.read().decode())
            self._read()
        raise TimeoutError(f"timeout ({timeout * SCALE}s) waiting for {pattern!r}; last output: {self.buf[-400:]!r}")

    def send(self, s):
        self.ser.sendall(s.encode())

    def sh(self, cmd, timeout=60):
        """Run a shell command on the serial console, return (rc, output)."""
        tag = f"__ML{int(time.time()*1000) % 10**8}__"
        self.buf = ""
        self.send(f"{cmd}; echo {tag}$?{tag}\n")
        m, out = self.expect(re.escape(tag) + r"(\d+)" + re.escape(tag), timeout)
        out = out[:m.start()]
        # drop the echoed command line (if the terminal echoed it)
        out = "\n".join(l for l in out.split("\n") if f"echo {tag}" not in l)
        out = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", out).replace("\r", "")
        out = re.sub(r"^\$ ", "", out, flags=re.M)   # stray prompts
        return int(m.group(1)), out.strip()

    # QMP ---------------------------------------------------------------------
    def qmp_cmd(self, name, **args):
        self.qmpf.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.qmpf.flush()
        while True:
            r = json.loads(self.qmpf.readline())
            if "return" in r or "error" in r:
                return r

    def screenshot(self, name):
        ppm = os.path.join(RUN, name + ".ppm")
        self.qmp_cmd("screendump", filename=ppm)
        time.sleep(0.5)
        png = os.path.join(RES, name + ".png")
        ppm_to_png(ppm, png)
        return png

    def stop(self):
        try:
            self.qmp_cmd("quit")
        except Exception:
            pass
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def ppm_to_png(src, dst):
    data = open(src, "rb").read()
    parts = data.split(maxsplit=4)
    assert parts[0] == b"P6"
    w, h = int(parts[1]), int(parts[2])
    px = parts[4]
    raw = b"".join(b"\x00" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    open(dst, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


# --------------------------------------------------------------------------- tests
class Report:
    def __init__(self):
        self.rows = []
        self.notes = []

    def check(self, num, name, ok, detail=""):
        self.rows.append((num, name, "PASS" if ok else "FAIL", detail))
        print(f"[{'PASS' if ok else 'FAIL'}] {num} {name}" + (f"  ({detail})" if detail else ""), flush=True)
        return ok

    def write(self, iso):
        with open(os.path.join(RES, "report.md"), "w") as f:
            f.write(f"# MicroLinux {ARCH} test report\n\n- ISO: `{os.path.basename(iso)}` ({os.path.getsize(iso)/1048576:.1f} MiB)\n")
            f.write(f"- Date: {time.strftime('%Y-%m-%d %H:%M:%S')}\n- Host: {platform.platform()}\n")
            f.write(f"- QEMU: {'hardware virtualisation' if hw_accel() else 'emulation (TCG), timeouts x' + str(SCALE)}\n\n")
            f.write("| # | Test | Result | Details |\n|---|------|--------|---------|\n")
            for r in self.rows:
                f.write("| " + " | ".join(str(x).replace("|", "\\|").replace("\n", "<br>") for x in r) + " |\n")
            if self.notes:
                f.write("\n## Notes\n\n" + "\n".join(f"- {n}" for n in self.notes) + "\n")
        passed = sum(r[2] == "PASS" for r in self.rows)
        print(f"\n{passed}/{len(self.rows)} passed - report: {os.path.relpath(os.path.join(RES, 'report.md'), ROOT)}")
        return passed == len(self.rows)


def count_ok(out):
    """True if the last line of out is an integer > 0 (window/match counts)."""
    last = out.strip().splitlines()[-1].strip() if out.strip() else ""
    return last.isdigit() and int(last) > 0


def login(vm, user="root", password="microlinux", timeout=120):
    vm.expect(r"login: ?$|login: ", timeout)
    vm.send(user + "\n")
    vm.expect(r"Password: ?", 15)
    vm.send(password + "\n")
    vm.expect(r"[#$] ?$|[#$] ", 20)
    # no readline (it echoes input itself, regardless of stty -echo) and no tty echo
    vm.send("export PS1='$ '; set +o emacs +o vi 2>/dev/null; stty cols 200 -echo 2>/dev/null\n")
    time.sleep(1)
    vm.buf = ""


def cdrom(iso):
    return ["-device", "virtio-scsi-pci,id=scsi0",
            "-drive", f"if=none,id=cd,file={iso},media=cdrom,readonly=on",
            "-device", "scsi-cd,drive=cd,bus=scsi0.0"]


def usb_stick(image, writable=False):
    ro = "" if writable else ",readonly=on"
    return ["-drive", f"if=none,id=stick,file={image},format=raw{ro}", "-device", "usb-storage,drive=stick"]


def run_persist_tests(args, rep):
    """ml-persist on a USB stick written from the ISO, then reboot (UEFI, and BIOS on x86_64)."""
    stick = os.path.join(RUN, "stick.img")
    shutil.copy(args.iso, stick)
    with open(stick, "r+b") as f:
        f.truncate(2 * 1024 ** 3)            # a 2 GiB stick with the ISO written to its start
    vm = VM(usb_stick(stick, writable=True))
    try:
        login(vm, timeout=180)
        # the marker is made before ml-persist, which saves the session's changes
        rc, out = vm.sh("echo kept-$$ > /home/user/persist-marker; ml-persist -y 2>&1 | tail -n 3; "
                        "cat /home/user/persist-marker; sync", 180)
        marker = out.strip().splitlines()[-1] if out.strip() else ""
        rep.check("S1", "ml-persist creates a persistence partition on the USB stick", rc == 0 and "Done." in out,
                  out.replace("\n", "; ")[:200])
    except Exception as e:
        rep.check("S1", "ml-persist creates a persistence partition on the USB stick", False, str(e)[:200])
        vm.stop()
        return
    vm.stop()
    for num, bios in (("S2", False), ("S3", True)):
        if bios and ARCH != "x86_64":
            continue
        fw = "BIOS" if bios else "UEFI"
        vm = VM(usb_stick(stick, writable=True), bios=bios)
        try:
            login(vm, timeout=180)
            rc, out = vm.sh("cat /home/user/persist-marker; findmnt -no SOURCE,FSTYPE /live/cow; "
                            "[ -d /sys/firmware/efi ] && echo firmware=UEFI || echo firmware=BIOS")
            ok = marker.startswith("kept-") and marker in out and "ext4" in out and f"firmware={fw}" in out
            rep.check(num, f"Changes kept after reboot from the stick ({fw})", ok, out.replace("\n", "; ")[:200])
            if not ok:   # keep the reason in the report
                rc, out = vm.sh("blkid; dmesg | grep -i -E 'sd[a-z]|ext4|initramfs|persist' | tail -n 25", 60)
                rep.notes.append(f"{num} failed - blkid and kernel messages:\n```\n" + out.strip() + "\n```")
        except Exception as e:
            rep.check(num, f"Changes kept after reboot from the stick ({fw})", False, str(e)[:200])
        vm.stop()


def boot_check(num, name, rep, media, bios, shot=None):
    """Boot to a root shell; report firmware type (EFI or BIOS) seen by Linux."""
    vm = VM(media, bios=bios)
    try:
        if shot:   # GRUB menu (BIOS GRUB draws on the VGA console only)
            time.sleep(4 * SCALE)
            vm.screenshot(shot)
        login(vm, timeout=180)
        t = time.time() - vm.t0
        rc, out = vm.sh("[ -d /sys/firmware/efi ] && echo firmware=UEFI || echo firmware=BIOS; uname -m; "
                        "findmnt -no FSTYPE /live/medium")
        want = "firmware=BIOS" if bios else "firmware=UEFI"
        rep.check(num, name, want in out and ARCH in out, f"login at {t:.0f}s; " + out.replace("\n", "; ")
                  + (f"; GRUB screenshot {shot}.png" if shot else ""))
    except Exception as e:
        rep.check(num, name, False, str(e)[:200])
    vm.stop()


def run_bios_tests(args, rep):
    """x86_64: the hybrid ISO must also boot from legacy BIOS, as a CD and as a USB stick."""
    boot_check("2b", "BIOS boot (SeaBIOS, ISO as CD-ROM)", rep, cdrom(args.iso), True, shot="bios-grub")
    boot_check("2c", "BIOS boot (SeaBIOS, ISO written to a USB stick: hybrid MBR)", rep, usb_stick(args.iso), True)
    boot_check("2d", "UEFI boot (ISO written to a USB stick: GPT ESP)", rep, usb_stick(args.iso), False)


def run_live_tests(args, rep):
    cd = cdrom(args.iso)
    extra = []
    if args.install:
        disk = os.path.join(RUN, "disk.qcow2")
        if os.path.exists(disk):
            os.unlink(disk)
        subprocess.run(["qemu-img", "create", "-f", "qcow2", disk, "8G"], check=True, stdout=subprocess.DEVNULL)
        extra = ["-drive", f"if=none,id=hd,file={disk},format=qcow2", "-device", "virtio-blk-pci,drive=hd"]
    vm = VM(cd, extra=extra)
    try:
        # 1-2: UEFI boot through GRUB
        try:
            _, out = vm.expect(r"MicroLinux [0-9.]+ \(live desktop\)", 60)
            # GRUB's messages before the menu: none expected (e.g. "Unknown command")
            errs = sorted(set(re.findall(r"Unknown command[^\r\n]*|error: [^\r\n]*", out)))
            rep.check("1", "Boot in QEMU (UEFI firmware -> GRUB menu, no GRUB errors)", not errs,
                      "; ".join(errs)[:200] or "GRUB menu shown on serial console, no errors")
            t_grub = time.time() - vm.t0
        except Exception as e:
            rep.check("1", "Boot in QEMU (UEFI firmware -> GRUB menu)", False, str(e)[:200])
            return vm
        vm.expect(r"Booting|EFI stub|Linux version", 30)
        try:
            login(vm, timeout=180)
            t_login = time.time() - vm.t0
            rep.check("2", "UEFI boot to login prompt", True, f"GRUB at {t_grub:.0f}s, login at {t_login:.0f}s after power-on")
        except Exception as e:
            rep.check("2", "UEFI boot to login prompt", False, str(e)[:200])
            return vm
        if ARCH == "aarch64":
            rep.check("2b", "BIOS boot", True, "not applicable: arm64 has no legacy BIOS; UEFI is the only boot standard (documented)")
            rep.notes.append("BIOS boot is an x86 concept; on aarch64 all general-purpose firmware is UEFI (or U-Boot's UEFI implementation).")

        # 3: shell
        rc, out = vm.sh("uname -sm; . /etc/os-release; echo $PRETTY_NAME; busybox | head -n1; bash --version | head -n1")
        rep.check("3", "Working shell", rc == 0 and ARCH in out, out.replace("\n", "; ")[:200])

        # 4: filesystems
        rc, out = vm.sh("mount | grep -E ' /live/(medium|rootfs) | / ' | awk '{print $3, $5}' | tr '\\n' ' '")
        rep.check("4a", "Live root: iso9660 medium + squashfs + overlayfs", rc == 0 and "squashfs" in out and "overlay" in out and "iso9660" in out, out)
        rc, out = vm.sh("set -e; dd if=/dev/zero of=/tmp/t.img bs=1M count=64 2>/dev/null; mkfs.ext4 -q -F /tmp/t.img; "
                        "mkdir -p /mnt/t; mount -o loop /tmp/t.img /mnt/t; echo data > /mnt/t/f; sync; umount /mnt/t; "
                        "e2fsck -fn /tmp/t.img >/dev/null; mount -o loop,ro /tmp/t.img /mnt/t; cat /mnt/t/f; umount /mnt/t; "
                        "mkfs.vfat -C /tmp/v.img 8192 >/dev/null; mount -o loop /tmp/v.img /mnt/t; df -h /mnt/t | tail -n1; umount /mnt/t; set +e")
        rep.check("4b", "Create/mount/fsck ext4 and FAT filesystems", rc == 0 and "data" in out, out.replace("\n", "; ")[:200])

        # 5: network
        rc, out = vm.sh("for i in $(seq 30); do ip -4 -br addr | grep -q '10.0.2' && break; sleep 1; done; ip -4 -br addr | grep -v lo; "
                        "cat /etc/resolv.conf | grep nameserver", 45)
        rep.check("5a", "Ethernet + DHCP", rc == 0 and "10.0.2.15" in out, out.replace("\n", "; "))
        rc, out = vm.sh("lsmod | grep -o '^e1000e'; for d in /sys/class/net/*/device/driver; do basename $(readlink $d); done | sort -u | tr '\\n' ' '")
        rep.check("5f", "Driver modules load automatically at boot (Intel e1000e NIC)", "e1000e" in out, out.replace("\n", "; "))
        rc, out = vm.sh("nslookup www.mozilla.org 2>&1 | tail -n 3 | tr '\\n' ' '", 30)
        rep.check("5b", "DNS resolution", rc == 0 and ("Address" in out), out[:200])
        rc, out = vm.sh("curl -sS -o /dev/null -w 'HTTP %{http_code} TLS-verify=%{ssl_verify_result}' https://www.mozilla.org/", 40)
        rep.check("5c", "HTTPS with certificate validation (curl)", rc == 0 and "HTTP 200" in out and "verify=0" in out, out)
        # retried: the public test server sometimes resets the connection
        rc, out = vm.sh("for i in 1 2 3; do o=$(curl -sS -o /dev/null https://self-signed.badssl.com/ 2>&1); "
                        "case \"$o\" in *SSL*|*ertificate*) break;; esac; sleep 3; done; echo \"$o\"", 90)
        rep.check("5d", "Invalid certificate is rejected", "certificate" in out.lower() or "SSL" in out, out[:160])
        rc, out = vm.sh("ssh -V 2>&1; timeout 20 ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | tail -n1", 40)
        rep.check("5e", "SSH client (handshake with github.com)", "OpenSSH" in out and ("Permission denied" in out or "successfully authenticated" in out), out.replace("\n", "; ")[:200])

        # tools
        rc, out = vm.sh("for c in busybox bash vi nano htop lspci lsusb lsblk dmidecode parted mkfs.ext4 mkfs.vfat e2fsck "
                        "ip iw wpa_supplicant udhcpc curl ssh sudo adduser passwd chmod logread syslogd modprobe strace readelf "
                        "elfcheck el7-run mlpkg netcfg ml-install bluetoothctl xrandr; do command -v $c >/dev/null || echo MISSING:$c; done; echo checked")
        rep.check("T", "Essential utilities present", "MISSING" not in out, out.replace("\n", " ")[:200])
        rc, out = vm.sh("logger -t mltest hello-log; sleep 1; ml-log | grep -c hello-log")
        rep.check("T2", "System logging (syslogd/logread)", rc == 0 and out.strip().endswith("1"), out)
        rc, out = vm.sh("adduser -D tuser && echo tuser:pw | chpasswd && su tuser -c 'id -un; touch /root/x' 2>&1; deluser --remove-home tuser; echo done")
        rep.check("T3", "User management and permissions", "tuser" in out and "Permission denied" in out, out.replace("\n", "; ")[:200])
        # as the desktop menu runs it: user, no terminal, no password prompt possible
        rc, out = vm.sh("su user -c 'setsid sh -c \"sudo -n true && echo sudo-ok; sudo -n -l /usr/sbin/poweroff\" </dev/null 2>&1'")
        rep.check("T4", "sudo for the live user without a password (menu actions)", "sudo-ok" in out and "/usr/sbin/poweroff" in out, out.replace("\n", "; ")[:200])
        rc, out = vm.sh("cat /proc/asound/cards | head -n 2; amixer get Master 2>/dev/null | grep -o '\\[on\\]\\|\\[off\\]' | head -n1; "
                        "su user -c 'timeout 20 speaker-test -t wav -c 2 -l 1 >/dev/null 2>&1' && echo played")
        rep.check("S", "Sound: HDA card detected, mixer set up at boot, test sound plays", "HDA" in out and "played" in out and "[off]" not in out,
                  out.replace("\n", "; ")[:200])

        # packages
        rc, out = vm.sh("mlpkg list -i; mlpkg verify")
        rep.check("P", "Package manager: modules active and verified", rc == 0 and "firefox" in out and "el7-runtime" in out
                  and "CORRUPT" not in out if not args.no_browser else rc == 0, out.replace("\n", "; ")[:250])

        # package repository: install from ../microlinux-repo/<arch> (served over HTTP), use, remove
        repo = os.path.join(os.path.dirname(ROOT), "microlinux-repo", ARCH)
        if os.path.exists(os.path.join(repo, "INDEX")):
            handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=repo)
            httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            url = f"http://10.0.2.2:{httpd.server_address[1]}"   # the host, from QEMU user networking
            rc, out = vm.sh(f"mlpkg repo add {url} >/dev/null && mlpkg list | wc -l && mlpkg list -a | wc -l", 120)
            rep.check("P2", "Package repository reachable (mlpkg repo add, list)", rc == 0, out.replace("\n", " apps / ") + " incl. libraries")
            rc, out = vm.sh("mlpkg install python3 git wget 2>&1 | grep -c '^installed'; "
                            "python3 -c 'import ssl, sqlite3, json; print(\"py\", ssl.OPENSSL_VERSION.split()[1])'; "
                            "git --version; readlink /usr/bin/wget || wget --version | head -n1; "
                            "git clone -q --depth 1 https://github.com/git/git.git /tmp/g 2>&1 | tail -n1; ls /tmp/g | grep -c . ; mlpkg verify | grep -c '^ok'", 600)
            rep.check("P3", "Install from the repository with dependencies (python3, git, wget), and use them",
                      rc == 0 and "py " in out and "git version" in out and "GNU Wget" in out, out.replace("\n", "; ")[:300])
            rc, out = vm.sh("mlpkg remove python3 git wget && mlpkg autoremove | grep -c '^removed'; "
                            "ls /usr/bin/python3 /usr/bin/git 2>/dev/null || echo gone; readlink /usr/bin/wget; mlpkg list -i | grep -c 'installed' || true", 300)
            rep.check("P4", "Remove packages + autoremove dependencies (busybox wget restored)",
                      "gone" in out and "/bin/busybox" in out, out.replace("\n", "; ")[:200])
            httpd.shutdown()
        else:
            rep.notes.append(f"package repository tests skipped: {os.path.relpath(repo, ROOT)} not built")

        # 7: graphical environment (LightDM logs the live user in at boot)
        rc, out = vm.sh(f"for i in $(seq {60 * SCALE}); do pgrep -x lxqt-panel >/dev/null && break; sleep 1; done; pgrep -l -x X || pgrep -l -x Xorg; pgrep -l -x openbox; pgrep -l -x lxqt-panel; pgrep -l -x pcmanfm-qt; "
                        "su user -c 'DISPLAY=:0 xdpyinfo' | grep -E 'dimensions|depth of root'", 90)
        # xdpyinfo answering proves the X server is up; pcmanfm-qt draws the desktop
        ok = all(p in out for p in ("openbox", "lxqt-panel", "pcmanfm-qt", "dimensions"))
        time.sleep(3)
        shot = vm.screenshot("desktop")
        rep.check("7", "Graphical environment (Xorg + LXQt + Openbox)", ok, out.replace("\n", "; ") + f" - screenshot {os.path.basename(shot)}")
        if not ok:   # keep the reason in the report
            rc, out = vm.sh("tail -n 25 /home/user/.xsession.log; grep -h -E '\\((EE|WW)\\)' /var/log/Xorg.0.log /home/user/.local/share/xorg/Xorg.0.log 2>/dev/null | tail -n 15", 60)
            rep.notes.append("desktop start failed - ~/.xsession.log and Xorg errors:\n```\n" + out.strip() + "\n```")
        rc, out = vm.sh("su user -c 'DISPLAY=:0 xrandr | head -n 3'; su user -c 'DISPLAY=:0 ml-display set 1024x768' && "
                        "su user -c 'DISPLAY=:0 xrandr | grep \"\\*\"'; su user -c 'DISPLAY=:0 ml-display set 1280x800'")
        rep.check("7b", "Display resolution change (xrandr)", "1024x768" in out, out.replace("\n", "; ")[:200])
        # the window must open and the command must really run in it (a file appears)
        rc, out = vm.sh(f"rm -f /tmp/qterm-ok; su user -c 'cd; DISPLAY=:0 qterminal -e sh -c \"touch /tmp/qterm-ok; sleep {30 * SCALE}\" >/tmp/qterm.log 2>&1 &'; "
                        f"sleep {5 * SCALE}; su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -c '\"qterminal\"'; "
                        "ls /tmp/qterm-ok 2>/dev/null || tail -n 5 /tmp/qterm.log")
        rep.check("7c", "Terminal emulator (QTerminal) opens and runs a command", any(l.strip().isdigit() and int(l) > 0 for l in out.splitlines()) and "/tmp/qterm-ok" in out,
                  out.replace("\n", "; ")[-200:])
        # menu entries with Terminal=true start a program directly: qterminal -e PROGRAM ARGS
        rc, out = vm.sh(f"rm -f /tmp/qterm-ok2; su user -c 'cd; DISPLAY=:0 qterminal -e touch /tmp/qterm-ok2 >/tmp/qterm2.log 2>&1 &'; "
                        f"sleep {5 * SCALE}; ls /tmp/qterm-ok2 2>/dev/null || tail -n 5 /tmp/qterm2.log")
        rep.check("7e", "QTerminal runs a program directly (menu entries with Terminal=true)", "/tmp/qterm-ok2" in out and "CRASHED" not in out,
                  out.replace("\n", "; ")[-200:])
        rc, out = vm.sh(f"su user -c 'DISPLAY=:0 pcmanfm-qt /etc &'; sleep {6 * SCALE}; su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -ci 'etc'")
        vm.screenshot("filemanager")
        rep.check("7d", "File manager (PCManFM-Qt) opens", count_ok(out), out[-150:])
        vm.sh("pkill -f 'pcmanfm-qt /etc'; pkill -f 'qterminal -e'")
        # archive manager: extracts a zip and a 7z archive (what right-click > Extract Here runs)
        # (the archives are made in /tmp/arc-src, extracted in /tmp/arc: only extracted files count)
        rc, out = vm.sh("su user -c 'rm -rf /tmp/arc /tmp/arc-src && mkdir -p /tmp/arc /tmp/arc-src/src && cd /tmp/arc-src && "
                        "echo zip-ok > src/z.txt && echo 7z-ok > src/s.txt && echo tgz-ok > src/g.txt && echo txz-ok > src/x.txt && "
                        "zip -q /tmp/arc/t.zip src/z.txt && 7za a -bd /tmp/arc/t.7z src/s.txt >/dev/null && "
                        "tar czf /tmp/arc/g.tar.gz src/g.txt && tar cJf /tmp/arc/x.tar.xz src/x.txt && rm -r /tmp/arc-src && "
                        f"DISPLAY=:0 timeout {30 * SCALE} lxqt-archiver --extract-here /tmp/arc/t.zip /tmp/arc/t.7z /tmp/arc/g.tar.gz /tmp/arc/x.tar.xz >/tmp/arc.log 2>&1; "
                        "find /tmp/arc -name \"*.txt\" -exec cat {} +; tail -n 2 /tmp/arc.log'; "
                        # the file manager offers Extract Here only for types in the MIME database
                        "grep -q 'x-compressed-tar:[*].tar.gz' /usr/share/mime/globs2 && grep -q 'zip:[*].zip' /usr/share/mime/globs2 && echo mime-ok", 60 * SCALE)
        rep.check("7h", "Archive manager (lxqt-archiver) extracts zip, 7z, tar.gz and tar.xz; archives known to the file manager",
                  all(k in out for k in ("zip-ok", "7z-ok", "tgz-ok", "txz-ok", "mime-ok")), out.replace("\n", "; ")[-150:])
        vm.sh("pkill -x lxqt-archiver")
        # the graphical installer (Rust + egui) opens its window
        rc, out = vm.sh(f"su user -c 'cd; DISPLAY=:0 ml-installer >/tmp/mli.log 2>&1 &'; "
                        f"for i in $(seq {20 * SCALE}); do su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -q 'Install MicroLinux' && break; sleep 1; done; "
                        "tail -n 3 /tmp/mli.log; su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -c 'Install MicroLinux'", 60)
        time.sleep(2 * SCALE)
        shot = vm.screenshot("installer")
        rep.check("7g", "Graphical installer (ml-installer) opens", count_ok(out), out.replace("\n", "; ")[-150:] + f" - screenshot {os.path.basename(shot)}")
        vm.sh("pkill -x ml-installer")

        # idle RAM, desktop running, no browser
        time.sleep(15)
        rc, out = vm.sh("free -m | awk '/^Mem:/ {print $3}'; awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\", (t-a)/1024}' /proc/meminfo")
        lines = out.split()
        used, notavail = (lines + ["?", "?"])[:2]
        rep.check("R", "Idle RAM with desktop (no browser)", used.isdigit() and int(used) < 400,
                  f"{used} MiB used by processes+kernel (free 'used'); {notavail} MiB MemTotal-MemAvailable (also counts tmpfs/page cache that cannot be dropped)")

        # 8: browser
        if not args.no_browser:
            rc, out = vm.sh(f"su user -c 'cd ~ && timeout {120 * SCALE} firefox --headless --screenshot /tmp/ff.png https://www.mozilla.org/' >/dev/null 2>&1; "
                            "ls -l /tmp/ff.png 2>&1 | awk '{print $5, $9}'", 150)
            rep.check("8a", "Firefox renders an HTTPS page (headless)", "/tmp/ff.png" in out and not out.startswith("0 "), out)
            rc, out = vm.sh("su user -c 'DISPLAY=:0 firefox https://www.mozilla.org/ >/tmp/ff.log 2>&1 &'; "
                            f"for i in $(seq {60 * SCALE}); do su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -qi 'mozilla firefox' && break; sleep 1; done; "
                            "su user -c 'DISPLAY=:0 xwininfo -root -tree' | grep -ci 'mozilla firefox'", 90)
            time.sleep(15 * SCALE)
            shot = vm.screenshot("firefox")
            rep.check("8b", "Firefox opens on the desktop", count_ok(out), f"{out[-120:]}; screenshot {os.path.basename(shot)}")
            rc, out = vm.sh("awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\", (t-a)/1024}' /proc/meminfo")
            rep.notes.append(f"RAM in use with Firefox open on mozilla.org: {out} MiB")
            vm.sh("pkill -f /opt/firefox; sleep 2")
            rc, out = vm.sh(f"su user -c 'cd /tmp && timeout {90 * SCALE} firefox --headless --screenshot /tmp/dl.png "
                            "\"https://download-installer.cdn.mozilla.net/pub/firefox/releases/153.6.0esr/SHA256SUMS\"' >/dev/null 2>&1; "
                            "su user -c 'curl -sS -fL -o ~/Downloads/SHA256SUMS https://download-installer.cdn.mozilla.net/pub/firefox/releases/153.6.0esr/SHA256SUMS' && "
                            "wc -l < /home/user/Downloads/SHA256SUMS", 120)
            rep.check("8c", "Downloads (to ~/Downloads)", rc == 0 and out.strip().split()[-1].isdigit(), out[-80:])
            # sound: Firefox plays only through PulseAudio (started on demand); a page
            # with a Web Audio tone must show up as a PulseAudio stream of Firefox
            rc, out = vm.sh("su user -c 'rm -rf /tmp/ffa && mkdir -p /tmp/ffa/p && cd /tmp/ffa && "
                            "echo \"user_pref(\\\"media.autoplay.default\\\", 0); user_pref(\\\"media.autoplay.blocking_policy\\\", 0);\" > p/user.js && "
                            "echo \"<script>var c = new AudioContext(), o = c.createOscillator(); o.connect(c.destination); o.start();</script>\" > tone.html && "
                            f"(timeout {60 * SCALE} firefox --headless --no-remote --profile /tmp/ffa/p file:///tmp/ffa/tone.html >/dev/null 2>&1 &) && "
                            f"for i in $(seq {40 * SCALE}); do pactl list sink-inputs 2>/dev/null | grep -qi firefox && break; sleep 1; done; "
                            "pactl info 2>&1 | grep -E \"Server Name|Default Sink\"; pactl list sink-inputs 2>/dev/null | grep -ci firefox'; "
                            "pkill -f /tmp/ffa/p", 120 * SCALE)
            rep.check("8d", "Firefox plays sound (PulseAudio)", "pulseaudio" in out.lower() and count_ok(out), out.replace("\n", "; ")[-160:])

        # 7f: logging out shows LightDM's login screen; the password logs back in
        vm.sh("pkill -x lxqt-session")
        rc, out = vm.sh(f"for i in $(seq {60 * SCALE}); do pgrep -x lightdm-gtk-gre >/dev/null && ! pgrep -x lxqt-panel >/dev/null && break; sleep 1; done; "
                        "pgrep -l -x lightdm-gtk-gre; pgrep -x lxqt-panel || echo 'session ended'", 90)
        time.sleep(5 * SCALE)
        shot = vm.screenshot("login")
        greeter = "lightdm-gtk-gre" in out and "session ended" in out
        vm.qmp_cmd("send-key", keys=[{"type": "qcode", "data": "ctrl"}, {"type": "qcode", "data": "a"}])
        for k in "live":
            vm.qmp_cmd("send-key", keys=[{"type": "qcode", "data": k}])
            time.sleep(0.2)
        vm.qmp_cmd("send-key", keys=[{"type": "qcode", "data": "ret"}])
        rc, out2 = vm.sh(f"for i in $(seq {60 * SCALE}); do pgrep -x lxqt-panel >/dev/null && break; sleep 1; done; pgrep -l -x lxqt-panel; pgrep -l -x openbox", 90)
        rep.check("7f", "Log out shows the login screen (LightDM), password logs back in",
                  greeter and "lxqt-panel" in out2 and "openbox" in out2,
                  (out + "; " + out2).replace("\n", "; ")[:200] + f" - screenshot {os.path.basename(shot)}")

        # 9-10: ELF / EL7 compatibility
        rc, out = vm.sh("elfcheck /opt/el7/usr/bin/tree /opt/el7/usr/bin/bash | grep -E 'verdict|needs glibc'; /opt/el7/usr/bin/tree --version", 30)
        rep.check("9", "Execute EL7-built ELF binaries natively (CentOS 7 tree, bash)", "NATIVE" in out and "tree v1.6" in out, out.replace("\n", "; ")[:250])
        rc, out = vm.sh("/usr/share/microlinux/tests/el7-compat.sh 2>&1", 240)
        open(os.path.join(RES, "el7-compat.tap"), "w").write(out + "\n")
        summary = [l for l in out.splitlines() if l.startswith("# ") and "passed" in l]
        rep.check("10", "EL7 compatibility suite (20 tests, real CentOS 7 binaries)", rc == 0, (summary[0] if summary else out[-200:]) + " - tests/results/el7-compat.tap")

        if args.install:
            # what the graphical installer sees (as the live user, through sudo)
            rc, out = vm.sh("su user -c 'sudo -n ml-install --probe /dev/vda'", 60)
            rep.check("I0", "Installer disk probe (ml-install --probe, as the GUI runs it)",
                      rc == 0 and "size_mib=8192" in out and "free_mib=" in out, out.replace("\n", "; ")[:200])
            # the passwords as the GUI passes them; I2 logs in with them
            rc, out = vm.sh("printf 'root:microlinux\\nuser:live\\n' | ml-install -y --passwords-stdin --hostname mltest --user tester --fullname 'Test User' /dev/vda 2>&1 | tail -n 4", 300)
            rep.check("I1", "ml-install to virtio disk (GPT, ESP + ext4)", rc == 0 and "Done." in out, out.replace("\n", "; ")[:200])
    except Exception as e:
        rep.check("X", "test harness", False, f"{type(e).__name__}: {e}"[:300])
    return vm


def run_installed_tests(args, rep, num, bios=False):
    disk = os.path.join(RUN, "disk.qcow2")
    name = "Boot installed system from disk (ext4 root, " + ("BIOS" if bios else "UEFI") + ")"
    vm = VM(["-drive", f"if=none,id=hd,file={disk},format=qcow2", "-device", "virtio-blk-pci,drive=hd"], bios=bios)
    try:
        login(vm, timeout=180)
        rc, out = vm.sh("findmnt -no SOURCE,FSTYPE /; hostname; [ -d /sys/firmware/efi ] && echo firmware=UEFI || echo firmware=BIOS; "
                        "mlpkg list -i | tail -n +2 | awk '{print $1}' | tr '\\n' ' '; "
                        f"grep ^tester: /etc/passwd | cut -d: -f5,6; for i in $(seq {60 * SCALE}); do pgrep -u tester -x lxqt-panel >/dev/null && break; sleep 1; done; "
                        "pgrep -u tester -l -x lxqt-panel")
        # the account chosen at installation (ml-install --user) has the desktop
        rep.check(num, name, "ext4" in out and "mltest" in out and ("firmware=BIOS" if bios else "firmware=UEFI") in out
                  and "Test User:/home/tester" in out and "lxqt-panel" in out,
                  out.replace("\n", "; "))
        # shut down as the desktop user would (menu: sudo poweroff, no terminal, no password)
        vm.send("su tester -c 'sudo -n poweroff' </dev/null\n")
        t0 = time.time()
        while vm.proc.poll() is None and time.time() - t0 < 60 * SCALE:
            vm._read()
            time.sleep(0.2)
        rep.check(num + "p", "Power off as 'user' (installed system, " + ("BIOS" if bios else "UEFI") + ")",
                  vm.proc.poll() is not None, f"machine off after {time.time() - t0:.0f}s" if vm.proc.poll() is not None
                  else "still running: " + vm.buf[-200:])
    except Exception as e:
        rep.check(num, name, False, str(e)[:200])
    return vm


def run_system_update_test(args, rep):
    """mlpkg system-update on the installed disk, with out/ served as the GitHub release."""
    disk = os.path.join(RUN, "disk.qcow2")
    out_dir = os.path.join(ROOT, "out")
    repo = os.path.join(os.path.dirname(ROOT), "microlinux-repo", ARCH)
    need = [os.path.join(out_dir, f) for f in (f"BUILD-{ARCH}", f"SHA256SUMS-{ARCH}", f"SHA256SUMS-{ARCH}.sig", f"microlinux-{ARCH}-base.iso")]
    missing = [os.path.relpath(f, ROOT) for f in need + [os.path.join(repo, "INDEX")] if not os.path.exists(f)]
    if missing:
        rep.notes.append("system update test skipped: missing " + ", ".join(missing))
        return
    build = open(os.path.join(out_dir, f"BUILD-{ARCH}")).read().strip()
    servers, urls = [], []
    for d in (out_dir, repo):   # the release (out/) and this build's package repository
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=d)
        servers.append(http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler))
        threading.Thread(target=servers[-1].serve_forever, daemon=True).start()
        urls.append(f"http://10.0.2.2:{servers[-1].server_address[1]}")
    url, repo_url = urls
    media = ["-drive", f"if=none,id=hd,file={disk},format=qcow2", "-device", "virtio-blk-pci,drive=hd"]
    vm = VM(media)
    try:
        login(vm, timeout=180)
        # this build's packages as the repository: nothing to upgrade, no internet needed
        rc, out = vm.sh(f"sed -i 's|^url=.*|url={url}|' /etc/mlpkg/system-update.conf; "
                        f"echo '{repo_url} unsigned' > /etc/mlpkg/repos.conf; "
                        "mlpkg system-update --check 2>&1 | tail -n 3", 120)
        rep.check("U1", "System update check (signed release info, newest build found)",
                  f"newest:    {build}" in out and ("up to date" in out or "update is available" in out), out.replace("\n", "; ")[-200:])
        # installed from an older release (--iso of release-base/): the release's small
        # update from that build; otherwise pretend to be an older build that lacks a
        # file, so that the whole base ISO is used
        # (an updater that knows neither small updates nor running the release's
        # updater, as in 1.0.0, uses the ISO)
        rc, cur = vm.sh("cat /etc/microlinux-build; grep -cE 'tar.zst|ML_SYSTEM_UPDATE_NEW' /usr/libexec/ml-system-update", 30)
        cur, knows = (["", "0"] + cur.strip().splitlines())[-2:]
        sums = open(os.path.join(out_dir, f"SHA256SUMS-{ARCH}")).read()
        small = cur != build and f"update-{ARCH}-from-{cur}.tar.zst" in sums and knows != "0"
        prep = "" if small else "echo 20000101.0000-old > /etc/microlinux-build; rm /usr/bin/ml-sysinfo; "
        # installed from this build: pretend to be the build the small update is made
        # from, with a different updater (it must switch to the release's)
        m = re.search(rf" update-{ARCH}-from-(\S+)\.tar\.zst$", sums, re.M)
        if cur == build and knows != "0" and m:
            cur, small = m.group(1), True
            prep = f"echo {cur} > /etc/microlinux-build; echo '# old' >> /usr/libexec/ml-system-update; "
        # a battery below 20 %: refused without the charger, allowed with it
        bat = ("mkdir -p /tmp/ps/BAT0 /tmp/ps/AC; echo Battery > /tmp/ps/BAT0/type; echo 15 > /tmp/ps/BAT0/capacity; "
               "echo Discharging > /tmp/ps/BAT0/status; echo Mains > /tmp/ps/AC/type; echo 0 > /tmp/ps/AC/online; ")
        rc, low = vm.sh(prep + bat + "ML_POWER_SUPPLY=/tmp/ps mlpkg system-update -y 2>&1 | tail -n 2; echo build=$(cat /etc/microlinux-build)", 300)
        rep.check("U2b", "System update refused on a battery below 20 %",
                  "battery is at 15%" in low and f"build={build}" not in low, low.replace("\n", "; ")[-200:])
        # what Settings > System Update and the update window show (no root needed)
        rc, out = vm.sh("su tester -c '/usr/libexec/ml-system-update --info' 2>&1", 120)
        vfile = os.path.join(out_dir, f"VERSION-{ARCH}")
        ver = open(vfile).read().strip() if os.path.exists(vfile) else ""
        rep.check("U1b", "Update details for the desktop user (ml-system-update --info, no root)",
                  f"newest={build}" in out and "download=" in out and re.search(r"download_bytes=\d+", out) is not None
                  and (not ver or f"newest_version={ver}" in out), out.replace("\n", "; ")[-250:])
        win = "su tester -c 'DISPLAY=:0 xwininfo -root -tree' | grep -c "
        rc, out = vm.sh("su tester -c 'cd; DISPLAY=:0 ml-settings update >/dev/null 2>&1 &'; "
                        f"for i in $(seq {30 * SCALE}); do {win}'\"Settings\"' >/dev/null && break; sleep 1; done; sleep {10 * SCALE}; {win}'\"Settings\"'", 90)
        shot = vm.screenshot("settings-update")
        rep.check("U1c", "Settings > System Update opens", count_ok(out), f"{out[-60:]}; screenshot {os.path.basename(shot)}")
        vm.sh("pkill -x ml-settings")
        rc, out = vm.sh("su tester -c 'cd; DISPLAY=:0 ml-updater >/tmp/mlu.log 2>&1 &'; "
                        f"for i in $(seq {30 * SCALE}); do {win}'\"System Update\"' >/dev/null && break; sleep 1; done; sleep {10 * SCALE}; "
                        f"tail -n 3 /tmp/mlu.log; {win}'\"System Update\"'", 90)
        shot = vm.screenshot("updater")
        rep.check("U1d", "Update window (ml-updater) opens", count_ok(out), f"{out[-150:]}; screenshot {os.path.basename(shot)}")
        vm.sh("pkill -f ml-updater")
        rc, out = vm.sh("echo 1 > /tmp/ps/AC/online; export ML_POWER_SUPPLY=/tmp/ps; touch /usr/share/ml-obsolete; echo /usr/share/ml-obsolete >> /var/lib/mlpkg/system.files; "
                        "echo mine > /home/tester/keep.txt; "
                        "su tester -c \"printf 'live\\n' | sudo -k -S -p '' -- env ML_POWER_SUPPLY=/tmp/ps mlpkg system-update -y\" 2>&1 | grep -E '==>|changed|removed|added|updated|WARNING|system-update:' | tail -n 14; "
                        "echo build=$(cat /etc/microlinux-build); ls /usr/bin/ml-sysinfo /usr/libexec/ml-update-notify; "
                        "ls /usr/share/ml-obsolete 2>&1 | grep -c 'No such'; "
                        "cat /home/tester/keep.txt; hostname; echo liveuser=$(grep -c '^user:' /etc/passwd); sync", 1200)
        # (the live system's account "user" must not come back next to the renamed one)
        ok = ("liveuser=0" in out and f"build={build}" in out and "/usr/bin/ml-sysinfo" in out and "mine" in out and "mltest" in out
              and "\n1\n" in "\n" + out + "\n" and (not small or "==> downloading update-" in out)
              and (not prep.startswith(f"echo {cur}") or "updater of the new release" in out))
        rep.check("U2", ("Small system update from " + cur if small else "System update (mlpkg system-update)")
                  + ": files updated, obsolete removed, user data and settings kept", ok, out.replace("\n", "; ")[-300:])
        vm.stop()
        vm = VM(media)
        login(vm, timeout=180)
        rc, out = vm.sh(f"cat /etc/microlinux-build; for i in $(seq {60 * SCALE}); do pgrep -u tester -x lxqt-panel >/dev/null && break; sleep 1; done; pgrep -u tester -l -x lxqt-panel; "
                        "pgrep -u tester -f ml-update-notify >/dev/null && echo notifier-running", 120)
        rep.check("U3", "Updated system boots to the desktop (with the update notifier)",
                  build in out and "lxqt-panel" in out and "notifier-running" in out, out.replace("\n", "; ")[:200])
    except Exception as e:
        rep.check("U", "system update test", False, f"{type(e).__name__}: {e}"[:300])
    for srv in servers:
        srv.shutdown()
    vm.stop()


def main():
    global ARCH, RES, SCALE
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch", choices=["aarch64", "x86_64"],
                    help="default: from the --iso name, else the host's architecture")
    ap.add_argument("--iso")
    ap.add_argument("--no-browser", action="store_true")
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()
    ARCH = args.arch or next((a for a in ("aarch64", "x86_64") if args.iso and a in os.path.basename(args.iso)), HOSTARCH)
    args.iso = args.iso or os.path.join(ROOT, "out", f"microlinux-{ARCH}.iso")
    if not os.path.exists(args.iso):
        sys.exit(f"{args.iso} not found - run ./scripts/build.sh --arch {ARCH} first")
    SCALE = 1 if hw_accel() else 5
    RES = os.path.join(ROOT, "tests", "results", ARCH)
    os.makedirs(RES, exist_ok=True)
    open(os.path.join(RES, "serial.log"), "w").close()
    rep = Report()
    vm = run_live_tests(args, rep)
    if args.keep and not args.install:
        print("VM left running; serial socket:", vm.ser_path)
        return
    vm.stop()
    if ARCH == "x86_64":
        run_bios_tests(args, rep)
    run_persist_tests(args, rep)
    if args.install and any(r[0] == "I1" and r[2] == "PASS" for r in rep.rows):
        run_installed_tests(args, rep, "I2").stop()
        run_system_update_test(args, rep)
        if ARCH == "x86_64":
            run_installed_tests(args, rep, "I3", bios=True).stop()
    sys.exit(0 if rep.write(args.iso) else 1)


if __name__ == "__main__":
    main()
