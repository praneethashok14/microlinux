################################################################################
#
# chromium-bin: ungoogled-chromium portable build, as a repository package
#
################################################################################

CHROMIUM_BIN_VERSION = 156.0.8078.79-1
CHROMIUM_BIN_ARCH = $(if $(BR2_aarch64),arm64,x86_64)
CHROMIUM_BIN_SOURCE = ungoogled-chromium-$(CHROMIUM_BIN_VERSION)-$(CHROMIUM_BIN_ARCH)_linux.tar.xz
CHROMIUM_BIN_SITE = https://github.com/ungoogled-software/ungoogled-chromium-portablelinux/releases/download/$(CHROMIUM_BIN_VERSION)
CHROMIUM_BIN_LICENSE = BSD-3-Clause (Chromium), various (third-party components)
CHROMIUM_BIN_INSTALL_TARGET = NO
CHROMIUM_BIN_INSTALL_IMAGES = YES
# libraries it needs that the base system doesn't have (repository packages)
CHROMIUM_BIN_DEPENDENCIES = libnss libnspr cups libgtk3

# repository only: post-image.sh packs pkgroot-repo/* into the repository, not the ISO
CHROMIUM_BIN_PKGROOT = $(BINARIES_DIR)/pkgroot-repo/chromium

define CHROMIUM_BIN_EXTRACT_CMDS
	$(call suitable-extractor,$(CHROMIUM_BIN_SOURCE)) $(CHROMIUM_BIN_DL_DIR)/$(CHROMIUM_BIN_SOURCE) | \
		$(TAR) --strip-components=1 -C $(@D) $(TAR_OPTIONS) -
endef

# Trimmed like the Firefox package: no debug symbols, no chromedriver, no Qt
# integration (MicroLinux uses GTK), English user-interface translations only.
define CHROMIUM_BIN_INSTALL_IMAGES_CMDS
	rm -rf $(CHROMIUM_BIN_PKGROOT)
	mkdir -p $(CHROMIUM_BIN_PKGROOT)/.mlpkg
	cp -a $(@D)/. $(CHROMIUM_BIN_PKGROOT)/
	rm -f $(CHROMIUM_BIN_PKGROOT)/chromedriver $(CHROMIUM_BIN_PKGROOT)/libqt5_shim.so \
		$(CHROMIUM_BIN_PKGROOT)/libqt6_shim.so $(CHROMIUM_BIN_PKGROOT)/.stamp_*
	find $(CHROMIUM_BIN_PKGROOT)/locales -type f ! -name 'en-US.pak*' ! -name 'en-GB.pak*' -delete
	$(TARGET_STRIP) --strip-debug $(CHROMIUM_BIN_PKGROOT)/chrome
	$(INSTALL) -m 0755 $(CHROMIUM_BIN_PKGDIR)/chromium $(CHROMIUM_BIN_PKGROOT)/chromium
	$(INSTALL) -m 0644 $(CHROMIUM_BIN_PKGDIR)/chromium.desktop $(CHROMIUM_BIN_PKGROOT)/.mlpkg/chromium.desktop
	printf 'name=chromium\nversion=%s\nmountpoint=/opt/chromium\nbin=chromium\ndesktop=chromium.desktop\ndescription=Chromium web browser (ungoogled-chromium: without Google services)\nlicense=BSD-3-Clause and others\ncategory=Internet & network\nbuilddeps=libnss libnspr cups\n' \
		$(firstword $(subst -, ,$(CHROMIUM_BIN_VERSION))) > $(CHROMIUM_BIN_PKGROOT)/.mlpkg/info
endef

$(eval $(generic-package))
