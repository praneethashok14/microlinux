# EL7 (RHEL/CentOS 7) binary compatibility

Each MicroLinux build runs EL7 binaries of its own architecture:

- **x86_64**: RHEL 7 / CentOS 7, the most common case.
- **aarch64**: RHEL 7 for ARM / CentOS 7 AltArch.

A binary for the other architecture is reported as such by `elfcheck`; use the
MicroLinux build for that architecture. Everything below applies to both,
except where the table says otherwise.

## What EL7 binaries expect

| Expectation | EL7 | MicroLinux |
|-------------|-----|------------|
| C library | glibc 2.17 (symbol versions up to `GLIBC_2.17`) | glibc 2.42, which still provides every older symbol version (x86_64: from `GLIBC_2.2.5`; aarch64: from `GLIBC_2.17`, its baseline) |
| Dynamic loader | x86_64 `/lib64/ld-linux-x86-64.so.2`, aarch64 `/lib/ld-linux-aarch64.so.1` | same paths |
| Library directories | `/usr/lib64` (`/lib64` → `usr/lib64`) | `/usr/lib64 → lib`, `/lib64 → usr/lib64` |
| Kernel | ≥ 3.10 syscalls | Linux 6.18 (superset). x86_64: the legacy vsyscall page is emulated (kernel default, `vsyscall=xonly`); EL7's glibc uses the vDSO anyway. aarch64 has no vsyscall page |
| Page size | x86_64 4 KiB; EL7 aarch64 kernels use 64 KiB pages and link binaries with 64 KiB segment alignment | 4 KiB pages; 64 KiB-aligned binaries load fine on 4 KiB kernels (not vice versa) |
| `libstdc++.so.6`, `libgcc_s.so.1` | GCC 4.8 (`GLIBCXX_3.4.19`) | GCC 14, backward compatible (provides all older `GLIBCXX_*`/`CXXABI_*` versions) |
| `libcrypt.so.1` | part of glibc | glibc ≥ 2.39 dropped it. Provided by **libxcrypt-compat** with the glibc symbol versions |
| `libtinfo.so.5`, `libncurses(w).so.5`, form/menu/panel | ncurses 5.9 | **ncurses5-compat** (ncurses 6.6 built with `--with-abi-version=5`, separate tinfo like RHEL) |
| `libbz2.so.1` | RHEL-patched soname | symlink to upstream `libbz2.so.1.0` |
| `libz.so.1`, `liblzma.so.5`, `libuuid`, `libblkid`, `libmagic.so.1`, `libgmp.so.10`, `libffi`, `libexpat.so.1` | | same sonames, newer and compatible |
| CA certificates | `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/pki/tls/cert.pem` | symlinks to the system bundle |
| `/bin/bash` | present | bash 5.x present |

## Libraries that *can't* be provided compatibly at the system level

Some EL7 libraries have different, incompatible successors with new sonames, or
RHEL-specific symbol versioning:

`libssl.so.10`/`libcrypto.so.10` (OpenSSL 1.0.2k with RHEL symbol versions),
`libreadline.so.6`, `libmpfr.so.4`, `libpcre.so.1`, `libselinux.so.1`,
`libnsl.so.1`, `libpython2.7.so.1.0`, …

Putting upstream builds of these into the base system would ship unmaintained
crypto (OpenSSL 1.0.2 is end-of-life) and still not match RHEL's symbol
versions. Instead there's an **exact EL7 runtime**:

## The el7-runtime package

`external/package/el7-runtime` downloads 45 CentOS 7.9.2009 RPMs for the
target architecture (x86_64 from the main tree, aarch64 from AltArch). URLs and
SHA-256 come from the official repository metadata and are pinned in
`el7-x86_64.lock` / `el7-aarch64.lock`, and Buildroot verifies every download. The package
unpacks them, drops the 100+ MB locale archive, docs and translations, and
produces `el7-runtime-7.9.2009.mlp`. The package mounts at `/opt/el7`. It
contains glibc 2.17, openssl-libs 1.0.2k, readline 6, pcre, libselinux, mpfr,
gmp, ncurses 5 and others, plus real EL7 programs used by the tests (bash 4.2,
coreutils 8.22, gawk, sed, grep, tree, bc, which, zip, unzip, file, findutils,
openssl).

| Tool | What it does |
|------|--------------|
| `elfcheck FILE…` | Architecture, interpreter, RPATH/RUNPATH, every `NEEDED` library and where it resolves, the newest `GLIBC_x` it needs, and *every versioned symbol requirement* checked against the version definitions of the library that would actually load. Verdict: **NATIVE**, **EL7-RUN** or **FAIL** (with what's missing). |
| `el7-run PROG ARGS…` | Starts PROG through EL7's own `ld-2.17.so` with `--library-path /opt/el7/usr/lib64`, so it gets exactly the libraries it was built for. Child processes run normally. |
| `sudo el7-chroot [CMD]` | A full EL7 userspace in a private mount namespace: `/opt/el7` overlaid with tmpfs, `/dev /proc /sys /tmp /home /root /etc/ssl` and resolv.conf bound in. Use it for scripts and tools that expect a complete EL7 filesystem. `EL7_PERSIST=dir` keeps changes. |

## Testing your own EL7 binaries

```sh
# 1. copy the binary (and any private .so files) to MicroLinux
# 2. inspect it
elfcheck ./mytool              # or elfcheck -v for the full dependency tree
# 3. run according to the verdict
./mytool                       # NATIVE
el7-run ./mytool               # EL7-RUN
sudo el7-chroot /path/in/chroot/mytool   # tools that need EL7 config files/paths
```

Libraries an EL7 program needs that are in neither the system nor the
runtime (for example a vendor's `libfoo.so`) can be added with
`EL7_LIBRARY_PATH=/opt/vendor/lib el7-run ./tool` or `LD_LIBRARY_PATH`.

To get more EL7 packages into the runtime, add their names to `PACKAGES` in
`scripts/el7-lock.py`, run it, and rebuild. Inside `el7-chroot`, `rpm2cpio`
from the host can also unpack extra RPMs into `EL7_PERSIST`.

## Compatibility test suite

`/usr/share/microlinux/tests/el7-compat.sh` (run as root, `-n` to skip network)
runs each EL7 program both natively and through `el7-run`. For each it records
elfcheck's verdict and checks the output against known-good values. A test
passes when the program works in the mode elfcheck predicted, which verifies
the program and the prediction together. Results from the last automated run
are in `tests/results/<arch>/el7-compat.tap` and summarised in [TESTING.md](TESTING.md).

## Limits (by design, and documented)

- Only binaries of the build's own architecture (no cross-architecture emulation).
- `el7-run` doesn't propagate to child processes. Use `el7-chroot` for those.
- The EL7 runtime has no locale archive: programs run in the C locale.
- SELinux: libselinux is present in the runtime, but SELinux is disabled, and
  programs see it as disabled (as on any non-SELinux system).
- glibc NSS: EL7 programs under `el7-run` read `/etc/passwd`, `/etc/group` and
  `/etc/hosts` normally (files + DNS).
