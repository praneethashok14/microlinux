################################################################################
#
# el7-runtime: CentOS 7 runtime (aarch64: AltArch tree, x86_64: main tree)
# as an mlpkg module (/opt/el7)
#
################################################################################

EL7_RUNTIME_VERSION = 7.9.2009
EL7_RUNTIME_LOCK = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/el7-runtime/el7-$(ARCH).lock
EL7_RUNTIME_URLS := $(shell awk 'index($$1, "\043") != 1 {print $$2}' $(EL7_RUNTIME_LOCK))
EL7_RUNTIME_SITE = $(patsubst %/,%,$(dir $(firstword $(EL7_RUNTIME_URLS))))
EL7_RUNTIME_SOURCE = $(notdir $(firstword $(EL7_RUNTIME_URLS)))
EL7_RUNTIME_EXTRA_DOWNLOADS = $(wordlist 2,999,$(EL7_RUNTIME_URLS))
EL7_RUNTIME_LICENSE = GPL-2.0+, GPL-3.0+, LGPL-2.1+, BSD, MIT, OpenSSL (per RPM, see SOURCES.txt)
EL7_RUNTIME_INSTALL_TARGET = NO
EL7_RUNTIME_INSTALL_IMAGES = YES
# per-arch download dir: noarch RPMs have the same file name in both trees
EL7_RUNTIME_DL_SUBDIR = el7-runtime-$(ARCH)

EL7_RUNTIME_PKGROOT = $(BINARIES_DIR)/pkgroot/el7-runtime

define EL7_RUNTIME_EXTRACT_CMDS
	mkdir -p $(@D)/root
	for f in $(notdir $(EL7_RUNTIME_URLS)); do \
		rpm2cpio $(EL7_RUNTIME_DL_DIR)/$$f | \
			(cd $(@D)/root && cpio -idm --quiet --no-absolute-filenames) || exit 1; \
	done
	chmod -R u+w $(@D)/root
endef

# Drop what a runtime does not need: the 100+ MB locale archive, translations,
# documentation and most iconv modules.
define EL7_RUNTIME_INSTALL_IMAGES_CMDS
	rm -rf $(EL7_RUNTIME_PKGROOT)
	mkdir -p $(EL7_RUNTIME_PKGROOT)
	cp -a $(@D)/root/. $(EL7_RUNTIME_PKGROOT)/
	cd $(EL7_RUNTIME_PKGROOT) && rm -rf usr/lib/locale/locale-archive* \
		usr/share/locale usr/share/man usr/share/doc usr/share/info \
		usr/share/i18n usr/share/licenses var/cache
	find $(EL7_RUNTIME_PKGROOT)/usr/lib64/gconv -name '*.so' \
		! -name 'UTF-*' ! -name 'UNICODE.so' ! -name 'ISO8859-1.so' \
		! -name 'ISO8859-15.so' ! -name 'LATIN-GREEK*' -delete
	# usrmerge as done by EL7's 'filesystem' package: several RPMs (glibc, sed,
	# grep, ...) still ship files under /bin, /sbin, /lib, /lib64
	cd $(EL7_RUNTIME_PKGROOT) && for l in bin sbin lib lib64; do \
		if [ -d $$l ] && [ ! -L $$l ]; then \
			mkdir -p usr/$$l && cp -a $$l/. usr/$$l/ && rm -rf $$l; \
		fi; \
		ln -sfn usr/$$l $$l; \
	done
	mkdir -p $(EL7_RUNTIME_PKGROOT)/etc/pki/tls/certs $(EL7_RUNTIME_PKGROOT)/.mlpkg \
		$(EL7_RUNTIME_PKGROOT)/dev $(EL7_RUNTIME_PKGROOT)/proc $(EL7_RUNTIME_PKGROOT)/sys \
		$(EL7_RUNTIME_PKGROOT)/tmp $(EL7_RUNTIME_PKGROOT)/home $(EL7_RUNTIME_PKGROOT)/root \
		$(EL7_RUNTIME_PKGROOT)/run $(EL7_RUNTIME_PKGROOT)/etc/ssl
	ln -sf /etc/ssl/certs/ca-certificates.crt $(EL7_RUNTIME_PKGROOT)/etc/pki/tls/certs/ca-bundle.crt
	ln -sf certs/ca-bundle.crt $(EL7_RUNTIME_PKGROOT)/etc/pki/tls/cert.pem
	printf 'root:x:0:0:root:/root:/bin/bash\n' > $(EL7_RUNTIME_PKGROOT)/etc/passwd
	printf 'root:x:0:\n' > $(EL7_RUNTIME_PKGROOT)/etc/group
	( echo "CentOS 7.9.2009 $(ARCH) packages in this module."; \
	  echo "Corresponding sources: $(EL7_RUNTIME_SRC_URL)"; \
	  echo; echo "package license source-rpm"; \
	  awk 'index($$1, "\043") != 1 {print $$1, $$4, $$5}' $(EL7_RUNTIME_LOCK) ) > $(EL7_RUNTIME_PKGROOT)/SOURCES.txt
	printf 'name=el7-runtime\nversion=%s\nmountpoint=/opt/el7\nbin=\ndesktop=\ndescription=RHEL/CentOS 7 (glibc 2.17) runtime for el7-run and el7-chroot\nlicense=various (see /opt/el7/SOURCES.txt)\n' \
		$(EL7_RUNTIME_VERSION) > $(EL7_RUNTIME_PKGROOT)/.mlpkg/info
endef

ifeq ($(ARCH),aarch64)
EL7_RUNTIME_SRC_URL = https://vault.centos.org/altarch/7.9.2009/{os,updates}/Source/SPackages/
else
EL7_RUNTIME_SRC_URL = https://vault.centos.org/7.9.2009/{os,updates}/Source/SPackages/
endif

$(eval $(generic-package))

# one hash file per arch (set after generic-package, which defines the default)
EL7_RUNTIME_HASH_FILES = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/el7-runtime/el7-runtime-$(ARCH).hash
