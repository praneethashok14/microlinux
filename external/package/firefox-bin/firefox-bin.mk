################################################################################
#
# firefox-bin: official Firefox ESR build (aarch64 or x86_64), packaged as an
# mlpkg module
#
################################################################################

FIREFOX_BIN_VERSION = 153.6.0esr
# MicroLinux package revision: bump it when the package changes but Firefox
# doesn't, so that "mlpkg upgrade" picks it up
FIREFOX_BIN_PKGREV = 2
FIREFOX_BIN_SOURCE = firefox-$(FIREFOX_BIN_VERSION).tar.xz
FIREFOX_BIN_SITE = https://download-installer.cdn.mozilla.net/pub/firefox/releases/$(FIREFOX_BIN_VERSION)/linux-$(ARCH)/en-US
FIREFOX_BIN_LICENSE = MPL-2.0
FIREFOX_BIN_INSTALL_TARGET = NO
FIREFOX_BIN_INSTALL_IMAGES = YES
# Mozilla uses the same tarball name for every arch: keep the downloads apart
FIREFOX_BIN_DL_SUBDIR = firefox-bin-$(ARCH)
# runtime libraries it needs must exist in the rootfs (checked by post-image.sh)
FIREFOX_BIN_DEPENDENCIES = libgtk3 dbus xlib_libXcomposite xlib_libXdamage \
	xlib_libXrandr xlib_libXtst alsa-lib

FIREFOX_BIN_PKGROOT = $(BINARIES_DIR)/pkgroot/firefox

define FIREFOX_BIN_EXTRACT_CMDS
	$(call suitable-extractor,$(FIREFOX_BIN_SOURCE)) $(FIREFOX_BIN_DL_DIR)/$(FIREFOX_BIN_SOURCE) | \
		$(TAR) --strip-components=1 -C $(@D) $(TAR_OPTIONS) -
endef

define FIREFOX_BIN_INSTALL_IMAGES_CMDS
	rm -rf $(FIREFOX_BIN_PKGROOT)
	mkdir -p $(FIREFOX_BIN_PKGROOT)/.mlpkg $(FIREFOX_BIN_PKGROOT)/distribution
	cp -a $(@D)/. $(FIREFOX_BIN_PKGROOT)/
	rm -f $(FIREFOX_BIN_PKGROOT)/.stamp_* $(FIREFOX_BIN_PKGROOT)/.files-list* \
		$(FIREFOX_BIN_PKGROOT)/.applied_patches_list
	# no in-app updates (mlpkg updates Firefox), no crash reports sent home
	rm -f $(FIREFOX_BIN_PKGROOT)/updater $(FIREFOX_BIN_PKGROOT)/updater.ini \
		$(FIREFOX_BIN_PKGROOT)/update-settings.ini $(FIREFOX_BIN_PKGROOT)/pingsender
	$(INSTALL) -m 0755 $(FIREFOX_BIN_PKGDIR)/firefox.sh $(FIREFOX_BIN_PKGROOT)/firefox
	$(INSTALL) -m 0644 $(FIREFOX_BIN_PKGDIR)/policies.json $(FIREFOX_BIN_PKGROOT)/distribution/policies.json
	$(INSTALL) -m 0644 $(FIREFOX_BIN_PKGDIR)/firefox.desktop $(FIREFOX_BIN_PKGROOT)/.mlpkg/firefox.desktop
	# compress=zstd: libxul.so (180 MB) decompresses ~8x faster than with xz
	printf 'name=firefox\nversion=%s-%s\nmountpoint=/opt/firefox\nbin=firefox\ndesktop=firefox.desktop\ndescription=Mozilla Firefox ESR web browser (official build)\nlicense=MPL-2.0\ncompress=zstd\n' \
		$(FIREFOX_BIN_VERSION) $(FIREFOX_BIN_PKGREV) > $(FIREFOX_BIN_PKGROOT)/.mlpkg/info
endef

$(eval $(generic-package))

# one hash file per arch (set after generic-package, which defines the default)
FIREFOX_BIN_HASH_FILES = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/firefox-bin/firefox-bin-$(ARCH).hash
