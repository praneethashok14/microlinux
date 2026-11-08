# Licensing

- **MicroLinux's own files** (configuration, scripts in `external/`, `scripts/`,
  `tests/`, docs): MIT.
- **Buildroot-built packages**: their own licenses. Buildroot generates a full
  manifest with license texts: `./scripts/build.sh legal-info`
  (→ `/mnt/lima-mlbuild/out/legal-info/`). GPL/LGPL sources are included there.
- **Firefox**: Mozilla's official, unmodified binary release (MPL 2.0). Mozilla
  permits redistribution of unmodified official builds. We only add a
  `distribution/policies.json` (Mozilla's supported enterprise policy
  mechanism) that disables the self-updater, which can't work on a read-only
  image. "Firefox" is a Mozilla trademark, used here only to identify the
  unmodified product.
- **el7-runtime**: unmodified binaries from CentOS 7.9.2009 AltArch RPMs (GPL,
  LGPL, MIT, BSD, OpenSSL, MPL and public-domain licenses; each package's
  license is listed in `/opt/el7/SOURCES.txt` and `el7.lock`). The corresponding
  source RPMs are published by the CentOS project on vault.centos.org (see
  `SOURCES.txt` for the exact SRPM names). No Red Hat branding packages
  (`redhat-release`, logos) are included.
- **Firmware** (linux-firmware subsets): redistributable under each vendor's
  license, as shipped by linux-firmware (`WHENCE` in legal-info).
