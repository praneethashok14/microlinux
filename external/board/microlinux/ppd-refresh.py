#!/usr/bin/env python3
"""Refresh stale dependency copies in Buildroot's per-package directories.

With per-package directories, per-package/<pkg>/{target,staging} hold copies
of the package's dependencies as they were when <pkg> was built. When a
dependency is rebuilt later (for example Mesa after enabling more drivers),
those copies stay old, and target-finalize, which merges every per-package
target into one, can install an old copy: an image that has Mesa's new
iris_dri.so next to an old libgallium without iris.

For every package, its own files (build/packages-file-list*.txt) are copied
into the per-package directories of the other packages that hold an older
copy of them. Run by scripts/build.sh before each full build.

    ppd-refresh.py OUTPUT_DIR
"""
import os, subprocess, sys

O = sys.argv[1]
PP = os.path.join(O, "per-package")
refreshed = 0
for kind, listfile in (("target", "packages-file-list.txt"), ("staging", "packages-file-list-staging.txt")):
    path = os.path.join(O, "build", listfile)
    if not os.path.exists(path):
        continue
    # a file several packages installed belongs to the last one (the list is in build order)
    owner = {}
    for line in open(path):
        pkg, _, f = line.rstrip("\n").partition(",")
        owner[f] = pkg
    owned = {}
    for f, pkg in owner.items():
        owned.setdefault(pkg, []).append(f)
    holders = {q: os.path.join(PP, q, kind) for q in os.listdir(PP)} if os.path.isdir(PP) else {}
    for pkg, files in owned.items():
        src = os.path.join(PP, pkg, kind)
        mine = {}
        for f in files:
            try:
                st = os.lstat(os.path.join(src, f))
            except OSError:
                continue
            if not os.path.islink(os.path.join(src, f)) and os.path.isfile(os.path.join(src, f)):
                mine[f] = st
        if not mine:
            continue
        first = next(iter(mine))
        for q, dst in holders.items():
            if q == pkg or not os.path.lexists(os.path.join(dst, first)):
                continue
            # stale: a copy of one of the package's files that is older and
            # different (data files can keep their times from the source)
            stale = False
            for f, st in mine.items():
                try:
                    cp = os.lstat(os.path.join(dst, f))
                except OSError:
                    continue
                if cp.st_mtime < st.st_mtime and (cp.st_size, int(cp.st_mtime)) != (st.st_size, int(st.st_mtime)):
                    stale = True
                    break
            if not stale:
                continue
            listing = "".join(f + "\n" for f in files if os.path.lexists(os.path.join(src, f)))
            subprocess.run(["rsync", "-a", "--files-from=-", src + "/", dst + "/"],
                           input=listing.encode(), check=True)
            refreshed += 1
            print(f"ppd-refresh: {kind} of {q}: {pkg} updated")
print(f"ppd-refresh: {refreshed} stale copies updated")
