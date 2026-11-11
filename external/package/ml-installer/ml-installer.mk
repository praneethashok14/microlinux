################################################################################
#
# ml-installer: the MicroLinux graphical installer (Rust + egui, source in src/)
#
################################################################################

ML_INSTALLER_VERSION = 1.0
ML_INSTALLER_SITE = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/ml-installer/src
ML_INSTALLER_SITE_METHOD = local
ML_INSTALLER_LICENSE = MIT
# egui finds libX11, libxkbcommon-x11 and libEGL at run time (dlopen)
ML_INSTALLER_DEPENDENCIES = xlib_libX11 xlib_libXcursor xlib_libXi \
	xlib_libXrandr libxkbcommon libegl

# Buildroot vendors the crates of downloaded cargo packages only: vendor the
# crates of this local one the same way, before building (the versions are
# pinned by Cargo.lock; this needs the network, like any download). Not right
# after copying the source: with per-package directories, host-rustc's cargo
# is only in this package's host directory from the configure step on.
define ML_INSTALLER_VENDOR_CRATES
	mkdir -p $(@D)/.cargo $(HOST_DIR)/share/cargo
	cd $(@D) && CARGO_HOME=$(HOST_DIR)/share/cargo \
		flock $(HOST_DIR)/share/cargo/.br-lock \
		$(HOST_DIR)/bin/cargo vendor --locked VENDOR > $(@D)/.cargo/config.toml
endef
ML_INSTALLER_PRE_CONFIGURE_HOOKS += ML_INSTALLER_VENDOR_CRATES

define ML_INSTALLER_INSTALL_DESKTOP_FILE
	$(INSTALL) -D -m 0644 $(@D)/ml-installer.desktop \
		$(TARGET_DIR)/usr/share/applications/ml-installer.desktop
endef
ML_INSTALLER_POST_INSTALL_TARGET_HOOKS += ML_INSTALLER_INSTALL_DESKTOP_FILE

$(eval $(cargo-package))
