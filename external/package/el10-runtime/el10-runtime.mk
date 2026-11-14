################################################################################
#
# el10-runtime: AlmaLinux 10.2 runtime (x86_64: x86_64_v2 rebuild)
# as an mlpkg module (/opt/el10)
#
################################################################################

EL10_RUNTIME_VERSION = 10.2
EL10_RUNTIME_LOCK = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/el10-runtime/el10-$(ARCH).lock
EL10_RUNTIME_URLS := $(shell awk 'index($$1, "\043") != 1 {print $$2}' $(EL10_RUNTIME_LOCK))
EL10_RUNTIME_SITE = $(patsubst %/,%,$(dir $(firstword $(EL10_RUNTIME_URLS))))
EL10_RUNTIME_SOURCE = $(notdir $(firstword $(EL10_RUNTIME_URLS)))
EL10_RUNTIME_EXTRA_DOWNLOADS = $(wordlist 2,999,$(EL10_RUNTIME_URLS))
EL10_RUNTIME_LICENSE = GPL-2.0+, GPL-3.0+, LGPL-2.1+, BSD, MIT, Apache-2.0 (per RPM, see SOURCES.txt)
EL10_RUNTIME_INSTALL_TARGET = NO
EL10_RUNTIME_INSTALL_IMAGES = YES
# per-arch download dir: noarch RPMs have the same file name in both trees
EL10_RUNTIME_DL_SUBDIR = el10-runtime-$(ARCH)

EL10_RUNTIME_PKGROOT = $(BINARIES_DIR)/pkgroot/el10-runtime

define EL10_RUNTIME_EXTRACT_CMDS
	mkdir -p $(@D)/root
	for f in $(notdir $(EL10_RUNTIME_URLS)); do \
		rpm2cpio $(EL10_RUNTIME_DL_DIR)/$$f | \
			(cd $(@D)/root && cpio -idm --quiet --no-absolute-filenames) || exit 1; \
	done
	chmod -R u+w $(@D)/root
endef

# Drop what a runtime does not need (translations, documentation); C.UTF-8
# stays. The rpm database lists the runtime's packages, so rpm inside
# el10-chroot can check the dependencies of RPMs being installed.
define EL10_RUNTIME_INSTALL_IMAGES_CMDS
	rm -rf $(EL10_RUNTIME_PKGROOT)
	mkdir -p $(EL10_RUNTIME_PKGROOT)
	cp -a $(@D)/root/. $(EL10_RUNTIME_PKGROOT)/
	cd $(EL10_RUNTIME_PKGROOT) && rm -rf usr/lib/locale/locale-archive* \
		usr/share/locale usr/share/man usr/share/doc usr/share/info \
		usr/share/i18n usr/share/licenses var/cache
	# EL10 is usrmerged; its 'filesystem' package (not used) makes these links
	cd $(EL10_RUNTIME_PKGROOT) && for l in bin sbin lib lib64; do \
		if [ -d $$l ] && [ ! -L $$l ]; then \
			mkdir -p usr/$$l && cp -a $$l/. usr/$$l/ && rm -rf $$l; \
		fi; \
		ln -sfn usr/$$l $$l; \
	done
	mkdir -p $(EL10_RUNTIME_PKGROOT)/etc/pki/tls/certs $(EL10_RUNTIME_PKGROOT)/etc/pki/ca-trust/extracted/pem \
		$(EL10_RUNTIME_PKGROOT)/.mlpkg $(EL10_RUNTIME_PKGROOT)/dev $(EL10_RUNTIME_PKGROOT)/proc \
		$(EL10_RUNTIME_PKGROOT)/sys $(EL10_RUNTIME_PKGROOT)/tmp $(EL10_RUNTIME_PKGROOT)/home \
		$(EL10_RUNTIME_PKGROOT)/root $(EL10_RUNTIME_PKGROOT)/run $(EL10_RUNTIME_PKGROOT)/etc/ssl \
		$(EL10_RUNTIME_PKGROOT)/var/tmp $(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm
	ln -sf /etc/ssl/certs/ca-certificates.crt $(EL10_RUNTIME_PKGROOT)/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
	ln -sf /etc/ssl/certs/ca-certificates.crt $(EL10_RUNTIME_PKGROOT)/etc/pki/tls/certs/ca-bundle.crt
	ln -sf certs/ca-bundle.crt $(EL10_RUNTIME_PKGROOT)/etc/pki/tls/cert.pem
	printf 'root:x:0:0:root:/root:/bin/bash\n' > $(EL10_RUNTIME_PKGROOT)/etc/passwd
	printf 'root:x:0:\n' > $(EL10_RUNTIME_PKGROOT)/etc/group
	if command -v rpm >/dev/null; then \
		rpm --dbpath $(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm --define '_db_backend sqlite' \
			--justdb --nodeps --noscripts --notriggers --nosignature --nodigest \
			--ignorearch --ignoreos --ignoresize -i \
			$(addprefix $(EL10_RUNTIME_DL_DIR)/,$(notdir $(EL10_RUNTIME_URLS))) && \
		rpm --dbpath $(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm -qa >/dev/null && \
		rm -f $(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm/.rpm.lock \
			$(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm/rpmdb.sqlite-shm \
			$(EL10_RUNTIME_PKGROOT)/usr/lib/sysimage/rpm/rpmdb.sqlite-wal || exit 1; \
	else \
		echo "el10-runtime: rpm not found on the build host: no rpm database (rpm -i needs --nodeps)"; \
	fi
	mkdir -p $(EL10_RUNTIME_PKGROOT)/var/lib
	[ -e $(EL10_RUNTIME_PKGROOT)/var/lib/rpm ] || ln -s ../../usr/lib/sysimage/rpm $(EL10_RUNTIME_PKGROOT)/var/lib/rpm
	( echo "AlmaLinux 10.2 $(ARCH) packages in this module."; \
	  echo "Corresponding sources: https://vault.almalinux.org/10.2/{BaseOS,AppStream}/Source/"; \
	  echo; echo "package license source-rpm"; \
	  awk 'index($$1, "\043") != 1 {print $$1, $$4, $$5}' $(EL10_RUNTIME_LOCK) ) > $(EL10_RUNTIME_PKGROOT)/SOURCES.txt
	printf 'name=el10-runtime\nversion=%s\nmountpoint=/opt/el10\nbin=\ndesktop=\ndescription=RHEL 10 compatible (AlmaLinux 10, glibc 2.39) runtime for el10-run and el10-chroot\nlicense=various (see /opt/el10/SOURCES.txt)\n' \
		$(EL10_RUNTIME_VERSION) > $(EL10_RUNTIME_PKGROOT)/.mlpkg/info
endef

$(eval $(generic-package))

# one hash file per arch (set after generic-package, which defines the default)
EL10_RUNTIME_HASH_FILES = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/el10-runtime/el10-runtime-$(ARCH).hash
