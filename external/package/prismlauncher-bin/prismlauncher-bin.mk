################################################################################
#
# prismlauncher-bin: Prism Launcher (Minecraft) portable build, as a
# repository package
#
################################################################################

PRISMLAUNCHER_BIN_VERSION = 11.1.1
PRISMLAUNCHER_BIN_SOURCE = PrismLauncher-Linux-$(if $(BR2_aarch64),aarch64-)Qt6-Portable-$(PRISMLAUNCHER_BIN_VERSION).tar.gz
PRISMLAUNCHER_BIN_SITE = https://github.com/PrismLauncher/PrismLauncher/releases/download/$(PRISMLAUNCHER_BIN_VERSION)
PRISMLAUNCHER_BIN_LICENSE = GPL-3.0, various (bundled Qt and libraries)
PRISMLAUNCHER_BIN_INSTALL_TARGET = NO
PRISMLAUNCHER_BIN_INSTALL_IMAGES = YES

# repository only: post-image.sh packs pkgroot-repo/* into the repository, not the ISO
PRISMLAUNCHER_BIN_PKGROOT = $(BINARIES_DIR)/pkgroot-repo/prismlauncher

define PRISMLAUNCHER_BIN_EXTRACT_CMDS
	$(TAR) -xzf $(PRISMLAUNCHER_BIN_DL_DIR)/$(PRISMLAUNCHER_BIN_SOURCE) -C $(@D)
endef

# The build is self-contained (sharun: its own loader, glibc, Qt). Not
# portable mode: the package is read-only, data goes to ~/.local/share. No
# self-updater: mlpkg updates it. Prism picks the Java each Minecraft version
# needs (openjdk-<N>-jre packages in /opt, or downloads it).
define PRISMLAUNCHER_BIN_INSTALL_IMAGES_CMDS
	rm -rf $(PRISMLAUNCHER_BIN_PKGROOT)
	mkdir -p $(PRISMLAUNCHER_BIN_PKGROOT)/.mlpkg
	cp -a $(@D)/. $(PRISMLAUNCHER_BIN_PKGROOT)/
	rm -f $(PRISMLAUNCHER_BIN_PKGROOT)/portable.txt $(PRISMLAUNCHER_BIN_PKGROOT)/PrismLauncher \
		$(PRISMLAUNCHER_BIN_PKGROOT)/bin/prismlauncher_updater \
		$(PRISMLAUNCHER_BIN_PKGROOT)/shared/bin/prismlauncher_updater \
		$(PRISMLAUNCHER_BIN_PKGROOT)/.stamp_*
	# plugins for libraries the bundle doesn't include: TIFF images, and
	# Ubuntu's Mesa GBM backend (the launcher window doesn't use the GPU)
	rm -rf $(PRISMLAUNCHER_BIN_PKGROOT)/shared/lib/gbm $(PRISMLAUNCHER_BIN_PKGROOT)/lib/gbm
	find $(PRISMLAUNCHER_BIN_PKGROOT) -name libqtiff.so -delete
	$(INSTALL) -m 0755 $(PRISMLAUNCHER_BIN_PKGDIR)/prismlauncher $(PRISMLAUNCHER_BIN_PKGROOT)/prismlauncher
	$(INSTALL) -m 0644 $(PRISMLAUNCHER_BIN_PKGDIR)/prismlauncher.desktop $(PRISMLAUNCHER_BIN_PKGROOT)/.mlpkg/prismlauncher.desktop
	printf 'name=prismlauncher\nversion=%s\nmountpoint=/opt/prismlauncher\nbin=prismlauncher\ndesktop=prismlauncher.desktop\ndescription=Prism Launcher: Minecraft launcher (instances, mods, modpacks)\nlicense=GPL-3.0 and others\ncategory=Games\npkgdeps=openjdk-25-jre\nbuilddeps=xlib_libxxf86vm\n' \
		$(PRISMLAUNCHER_BIN_VERSION) > $(PRISMLAUNCHER_BIN_PKGROOT)/.mlpkg/info
endef

$(eval $(generic-package))
