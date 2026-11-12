#!/usr/bin/env python3
"""Make the small system update: the files that changed since the last release.

    make-update.py OLD_ROOTFS.sqfs OLD_ISO_DIR NEW_ROOTFS.sqfs NEW_ISO_DIR WORK OUT.tar.zst

OLD_ISO_DIR / NEW_ISO_DIR hold boot/ and EFI/BOOT/ of the two images. The
archive (zstd-compressed tar, numeric owners) has every file, symlink and new
directory of the new root file system that differs from the old one, plus
etc/microlinux-build, etc/passwd and etc/group (ml-system-update reads them),
and under .ml-update/:
    files    every non-directory path of the new image ("/usr/bin/..."), for
             removing files the new release doesn't have
    boot/... the kernel, initramfs and EFI loader files that changed
ml-system-update unpacks it in place of the base ISO's root file system.
"""
import filecmp, io, os, shutil, subprocess, sys, tarfile, time

old_sq, old_iso, new_sq, new_iso, work, out = sys.argv[1:7]
ALWAYS = {"etc/microlinux-build", "etc/passwd", "etc/group"}


def perm(s):
    m = 0
    for i, (c, bit) in enumerate(zip(s[1:], (0o400, 0o200, 0o100, 0o40, 0o20, 0o10, 4, 2, 1))):
        if c in "rwx":
            m |= bit
        elif c in "sS":
            m |= (0o4000 if i == 2 else 0o2000) | (bit if c == "s" else 0)
        elif c in "tT":
            m |= 0o1000 | (bit if c == "t" else 0)
    return m


def listing(sq):
    """path -> (type, mode, uid, gid, link target) from unsquashfs -lln"""
    r = {}
    for line in subprocess.run(["unsquashfs", "-lln", "-d", "", sq], capture_output=True, text=True, check=True).stdout.splitlines():
        f = line.split(None, 5)
        if len(f) < 6 or not f[5].startswith("/"):
            continue
        path, target = f[5], None
        if f[0][0] == "l":
            path, _, target = path.partition(" -> ")
        uid, gid = (int(x) for x in f[1].split("/"))
        r[path.lstrip("/")] = (f[0][0], perm(f[0]), uid, gid, target)
    return r


def extract(sq, d):
    shutil.rmtree(d, ignore_errors=True)
    subprocess.run(["unsquashfs", "-n", "-q", "-d", d, sq], check=True, stdout=subprocess.DEVNULL)


old, new = listing(old_sq), listing(new_sq)
os.makedirs(work, exist_ok=True)
o, n = os.path.join(work, "old"), os.path.join(work, "new")
extract(old_sq, o)
extract(new_sq, n)

changed = []
for p, (t, mode, uid, gid, target) in sorted(new.items()):
    if not p:
        continue
    was = old.get(p)
    if p in ALWAYS or was is None or was[:4] != (t, mode, uid, gid):
        changed.append(p)
    elif t == "l" and was[4] != target:
        changed.append(p)
    elif t == "-" and not filecmp.cmp(os.path.join(o, p), os.path.join(n, p), shallow=False):
        changed.append(p)
# directories that are there already need no entry; new ones keep their mode
changed = [p for p in changed if new[p][0] != "d" or p not in old]

boot = []
for d in ("boot", "EFI/BOOT"):
    for f in sorted(os.listdir(os.path.join(new_iso, d))):
        rel = f"{d}/{f}"
        if f == "grub.cfg" or not os.path.isfile(os.path.join(new_iso, rel)):
            continue
        if f not in ("vmlinuz", "initramfs.cpio.gz") and d == "boot":
            continue
        old_f = os.path.join(old_iso, rel)
        if not os.path.isfile(old_f) or not filecmp.cmp(old_f, os.path.join(new_iso, rel), shallow=False):
            boot.append(rel)

files = "".join(f"/{p}\n" for p, v in sorted(new.items()) if p and v[0] != "d").encode()
z = subprocess.Popen(["zstd", "-q", "-f", "-12", "-T0", "-o", out], stdin=subprocess.PIPE)
with tarfile.open(fileobj=z.stdin, mode="w|", format=tarfile.GNU_FORMAT) as tar:
    for p in changed:
        t, mode, uid, gid, target = new[p]
        ti = tar.gettarinfo(os.path.join(n, p), arcname=p)
        ti.mode, ti.uid, ti.gid, ti.uname, ti.gname = mode, uid, gid, "", ""
        if t == "-":
            with open(os.path.join(n, p), "rb") as fh:
                tar.addfile(ti, fh)
        else:
            if t == "l":
                ti.linkname = target
            tar.addfile(ti)
    ti = tarfile.TarInfo(".ml-update/files")
    ti.size, ti.mode, ti.mtime = len(files), 0o644, int(time.time())
    tar.addfile(ti, io.BytesIO(files))
    for rel in boot:
        ti = tar.gettarinfo(os.path.join(new_iso, rel), arcname=f".ml-update/{rel}")
        ti.mode, ti.uid, ti.gid, ti.uname, ti.gname = 0o644, 0, 0, "", ""
        with open(os.path.join(new_iso, rel), "rb") as fh:
            tar.addfile(ti, fh)
z.stdin.close()
if z.wait() != 0:
    sys.exit("make-update: zstd failed")
shutil.rmtree(o, ignore_errors=True)
shutil.rmtree(n, ignore_errors=True)
os.rmdir(work)
print(f"{len(changed)} files, {len(boot)} boot files, {os.path.getsize(out) // 1048576} MiB")
