# RHEL 10 and Debian/Ubuntu programs and packages

Besides RHEL/CentOS 7 ([EL7-COMPAT.md](EL7-COMPAT.md)), MicroLinux runs
programs made for the current Enterprise Linux and for Debian/Ubuntu, and
installs their `.rpm` and `.deb` packages. Each comes from a runtime package
in the full ISO:

| Package | System | glibc | Mounted at | Tools |
|---------|--------|-------|------------|-------|
| `el10-runtime` | RHEL 10 compatible: AlmaLinux 10.2 (x86_64: the `x86_64_v2` rebuild, so it also works on CPUs without AVX2) | 2.39 | `/opt/el10` | `el10-run`, `el10-chroot`, `rpm` |
| `debian-runtime` | Debian 13.7 "trixie" | 2.41 | `/opt/debian` | `deb-run`, `deb-chroot`, `dpkg` |

Each runtime has glibc, the C++ runtime, OpenSSL 3, ncurses, readline, pcre2,
libselinux, glib2, libcurl, compression libraries and others, everyday programs
(bash, coreutils, gawk, sed, grep, tar, curl, ...), and the package tool with a
database that lists the runtime's own packages.

## Which package formats are compatible

`.rpm` and `.deb` are only containers. What matters is the libraries a package
was built against:

- **RHEL 10, AlmaLinux 10, Rocky Linux 10, CentOS Stream 10** RPMs: install in
  `el10-chroot`.
- **Fedora** RPMs: EL10 branched from Fedora 40, so Fedora 40 packages often
  work. Packages from newer Fedora releases usually need newer libraries than
  EL10 has.
- **openSUSE / SUSE** RPMs: different package names and library versions;
  `rpm` reports their dependencies as missing. Not supported.
- **Debian 13** `.deb` packages: install in `deb-chroot`. Packages for
  **Ubuntu** 24.04/25.04 often work too (similar library versions); `dpkg`
  says which dependency is missing when one doesn't.

## Running programs

```sh
elfcheck ./tool         # verdict: NATIVE, EL7-RUN, EL10-RUN, DEB-RUN or FAIL
./tool                  # NATIVE: glibc 2.42 runs most of them directly
el10-run ./tool         # EL10-RUN
deb-run ./tool          # DEB-RUN
```

`elfcheck` first checks the system libraries. If something is missing, it
tries the runtimes whose glibc is new enough, starting with the system the
program was built on (GCC records "Red Hat" or "Debian"/"Ubuntu" in the
program's `.comment` section). Double-clicking a program in the file manager
does the same: **Run Program** starts it with `el10-run` or `deb-run` when
`elfcheck` says so.

`EL10_LIBRARY_PATH` / `DEB_LIBRARY_PATH` add further library directories (for
a vendor's private `.so` files).

## Installing packages

**Package files, the easy way:** in **Software**, click **Install .deb…**,
**Install .rpm…** or **Install .mlp…** and pick one or more files, or
double-click a `.deb`, `.rpm` or `.mlp` in the file manager. From a terminal:
`sudo mlpkg install FILE.deb FILE.rpm FILE.mlp...`.

A `.deb` becomes the package `deb-NAME`, an `.rpm` `rpm-NAME` (a `.mlp` is a
MicroLinux package already): its programs show up in the menu and in the
terminal like any others, Software lists it under *From .deb files* / *From
.rpm files*, and **Remove** there (or `sudo mlpkg remove deb-NAME`) takes it
away again. Its programs run with MicroLinux's own libraries when those are
enough, otherwise with those of their system (`deb-run`, `el10-run`, `el7-run`
for RHEL 7 packages); its libraries go to a directory of their own
(`/usr/lib/<arch>-linux-gnu`, `/usr/lib/ml-rpm`), never over MicroLinux's.
If a library it needs is missing, nothing is installed and the message names
the library: get the package that contains it (Debian: packages.debian.org,
"Search the contents of packages"; RHEL/AlmaLinux: usually the package named
like the library) and install both together. Packages' setup scripts are not
run. The installer is `/usr/libexec/ml-file-install`, part of Software
(`mlpkg install FILE` installs Software first when it is missing).

**Inside the chroots** (to use `rpm` or `dpkg` themselves):

```sh
sudo el10-chroot                      # a RHEL 10 shell; /home, /tmp and /root are shared
rpm -ivh /home/user/Downloads/NAME.rpm
NAME

sudo deb-chroot                       # a Debian shell
dpkg -i /home/user/Downloads/NAME.deb
NAME
```

By default, changes inside a chroot are gone when it exits. To keep installed
packages, give a directory:

```sh
sudo EL10_PERSIST=/home/user/.el10 el10-chroot
sudo DEB_PERSIST=/home/user/.debian deb-chroot
```

`rpm` and `dpkg` check dependencies against the runtime's package database.
There's no `dnf` or `apt` in the runtimes. A package that needs others not in
the runtime: download those too and install them together (`rpm -ivh a.rpm
b.rpm`, `dpkg -i a.deb b.deb`). Package scripts that start services (systemd)
don't work in the chroots.

## Tests

`/usr/share/microlinux/tests/el10-compat.sh` and `deb-compat.sh` (run as root,
`-n` without network) run 22 real programs from each runtime natively and with
`el10-run` / `deb-run`, check elfcheck's prediction, verify TLS with OpenSSL 3,
and install a real package from the AlmaLinux / Debian archive with
`rpm -ivh` / `dpkg -i` inside the chroot. Results from the last automated run
are in `tests/results/<arch>/el10-compat.tap` and `deb-compat.tap`.

## Limits

- Only programs for this computer's processor (no emulation).
- `el10-run` / `deb-run` don't carry over to programs that a program starts.
  Use the chroots for those.
- The runtimes have the C.UTF-8 locale only.
- Programs needing a newer glibc than 2.42 (current Fedora rawhide, Debian
  testing) can't run.
- Pinned versions: `scripts/runtime-lock.py` pins exact packages
  (see [BUILD.md](BUILD.md)). Security updates arrive with MicroLinux updates
  that pin newer packages.
