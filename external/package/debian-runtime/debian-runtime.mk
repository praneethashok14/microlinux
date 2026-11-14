################################################################################
#
# debian-runtime: Debian 13 (trixie) runtime as an mlpkg module (/opt/debian)
#
################################################################################

DEBIAN_RUNTIME_VERSION = 13.7
DEBIAN_RUNTIME_LOCK = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/debian-runtime/debian-$(ARCH).lock
DEBIAN_RUNTIME_URLS := $(shell awk 'index($$1, "\043") != 1 {print $$2}' $(DEBIAN_RUNTIME_LOCK))
DEBIAN_RUNTIME_SITE = $(patsubst %/,%,$(dir $(firstword $(DEBIAN_RUNTIME_URLS))))
DEBIAN_RUNTIME_SOURCE = $(notdir $(firstword $(DEBIAN_RUNTIME_URLS)))
DEBIAN_RUNTIME_EXTRA_DOWNLOADS = $(wordlist 2,999,$(DEBIAN_RUNTIME_URLS))
DEBIAN_RUNTIME_LICENSE = GPL-2.0+, GPL-3.0+, LGPL-2.1+, BSD, MIT (per package, see usr/share/doc/*/copyright)
DEBIAN_RUNTIME_INSTALL_TARGET = NO
DEBIAN_RUNTIME_INSTALL_IMAGES = YES
# per-arch download dir: "all" packages have the same file name for both
DEBIAN_RUNTIME_DL_SUBDIR = debian-runtime-$(ARCH)
DEBIAN_RUNTIME_DEBS = $(addprefix $(DEBIAN_RUNTIME_DL_DIR)/,$(notdir $(DEBIAN_RUNTIME_URLS)))

DEBIAN_RUNTIME_PKGROOT = $(BINARIES_DIR)/pkgroot/debian-runtime

# Unpack every package and write the dpkg database (status, file lists,
# conffiles, md5sums) as if dpkg had installed them, so dpkg inside
# deb-chroot can check the dependencies of .deb packages being installed.
# Maintainer scripts are not run.
define DEBIAN_RUNTIME_EXTRACT_CMDS
	rm -rf $(@D)/root $(@D)/ctl
	mkdir -p $(@D)/root/var/lib/dpkg/info $(@D)/root/var/lib/dpkg/updates \
		$(@D)/root/var/lib/dpkg/triggers $(@D)/root/var/lib/dpkg/alternatives
	: > $(@D)/root/var/lib/dpkg/status
	for d in $(DEBIAN_RUNTIME_DEBS); do \
		dpkg-deb -x $$d $(@D)/root || exit 1; \
		rm -rf $(@D)/ctl && dpkg-deb -e $$d $(@D)/ctl || exit 1; \
		p=$$(dpkg-deb -f $$d Package); \
		[ "$$(dpkg-deb -f $$d Multi-Arch)" = same ] && p=$$p:$$(dpkg-deb -f $$d Architecture); \
		dpkg-deb --fsys-tarfile $$d | tar -t | sed -e 's|^\./|/|' -e 's|/$$||' -e 's|^$$|/.|' \
			> $(@D)/root/var/lib/dpkg/info/$$p.list; \
		for c in conffiles md5sums triggers shlibs symbols; do \
			[ -f $(@D)/ctl/$$c ] && cp $(@D)/ctl/$$c $(@D)/root/var/lib/dpkg/info/$$p.$$c; \
		done; \
		sed -e '/^Package:/a Status: install ok installed' $(@D)/ctl/control \
			>> $(@D)/root/var/lib/dpkg/status; \
		echo >> $(@D)/root/var/lib/dpkg/status; \
	done
	rm -rf $(@D)/ctl
	: > $(@D)/root/var/lib/dpkg/available
	chmod -R u+w $(@D)/root
endef

# Drop what a runtime does not need (translations, documentation except the
# copyright files); C.UTF-8 stays.
define DEBIAN_RUNTIME_INSTALL_IMAGES_CMDS
	rm -rf $(DEBIAN_RUNTIME_PKGROOT)
	mkdir -p $(DEBIAN_RUNTIME_PKGROOT)
	cp -a $(@D)/root/. $(DEBIAN_RUNTIME_PKGROOT)/
	cd $(DEBIAN_RUNTIME_PKGROOT) && rm -rf usr/share/locale usr/share/man usr/share/info \
		usr/share/i18n usr/share/lintian var/cache
	find $(DEBIAN_RUNTIME_PKGROOT)/usr/share/doc -type f ! -name copyright -delete
	# Debian 13 is usrmerged: /bin, /lib, ... are links into /usr
	cd $(DEBIAN_RUNTIME_PKGROOT) && for l in bin sbin lib lib64; do \
		if [ -d $$l ] && [ ! -L $$l ]; then \
			mkdir -p usr/$$l && cp -a $$l/. usr/$$l/ && rm -rf $$l; \
		fi; \
		[ -e usr/$$l ] && ln -sfn usr/$$l $$l; true; \
	done
	# the links update-alternatives would make (maintainer scripts are not run)
	ln -sf gawk $(DEBIAN_RUNTIME_PKGROOT)/usr/bin/awk
	ln -sf less $(DEBIAN_RUNTIME_PKGROOT)/usr/bin/pager
	ln -sf which.debianutils $(DEBIAN_RUNTIME_PKGROOT)/usr/bin/which
	[ -e $(DEBIAN_RUNTIME_PKGROOT)/usr/bin/sh ] || ln -s dash $(DEBIAN_RUNTIME_PKGROOT)/usr/bin/sh
	mkdir -p $(DEBIAN_RUNTIME_PKGROOT)/.mlpkg $(DEBIAN_RUNTIME_PKGROOT)/dev $(DEBIAN_RUNTIME_PKGROOT)/proc \
		$(DEBIAN_RUNTIME_PKGROOT)/sys $(DEBIAN_RUNTIME_PKGROOT)/tmp $(DEBIAN_RUNTIME_PKGROOT)/home \
		$(DEBIAN_RUNTIME_PKGROOT)/root $(DEBIAN_RUNTIME_PKGROOT)/run $(DEBIAN_RUNTIME_PKGROOT)/etc/ssl \
		$(DEBIAN_RUNTIME_PKGROOT)/var/tmp
	printf 'root:x:0:0:root:/root:/bin/bash\n' > $(DEBIAN_RUNTIME_PKGROOT)/etc/passwd
	printf 'root:x:0:\n' > $(DEBIAN_RUNTIME_PKGROOT)/etc/group
	( echo "Debian 13.7 (trixie) $(ARCH) packages in this module (snapshot 20260913T000000Z)."; \
	  echo "Corresponding sources: https://snapshot.debian.org/package/<source>/<version>/"; \
	  echo "Licenses: usr/share/doc/<package>/copyright"; \
	  echo; echo "package source_version"; \
	  awk 'index($$1, "\043") != 1 {print $$1, $$5}' $(DEBIAN_RUNTIME_LOCK) ) > $(DEBIAN_RUNTIME_PKGROOT)/SOURCES.txt
	printf 'name=debian-runtime\nversion=%s\nmountpoint=/opt/debian\nbin=\ndesktop=\ndescription=Debian 13 (glibc 2.41) runtime for deb-run and deb-chroot\nlicense=various (see /opt/debian/SOURCES.txt)\n' \
		$(DEBIAN_RUNTIME_VERSION) > $(DEBIAN_RUNTIME_PKGROOT)/.mlpkg/info
endef

$(eval $(generic-package))

# one hash file per arch (set after generic-package, which defines the default)
DEBIAN_RUNTIME_HASH_FILES = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/debian-runtime/debian-runtime-$(ARCH).hash
