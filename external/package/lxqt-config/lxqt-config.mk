################################################################################
#
# lxqt-config
#
################################################################################

LXQT_CONFIG_VERSION = 2.4.0
LXQT_CONFIG_SITE = https://github.com/lxqt/lxqt-config/releases/download/$(LXQT_CONFIG_VERSION)
LXQT_CONFIG_SOURCE = lxqt-config-$(LXQT_CONFIG_VERSION).tar.xz
LXQT_CONFIG_LICENSE = LGPL-2.1+
LXQT_CONFIG_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_CONFIG_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_CONFIG_DEPENDENCIES = liblxqt lxqt-menu-data qt6svg libxcb xlib_libXcursor xlib_libXi xlib_libXfixes xdriver_xf86-input-libinput udev zlib host-pkgconf qt6base host-qt6tools
LXQT_CONFIG_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DWITH_MONITOR=OFF

# Touchpad settings need the X libinput driver's property names, but the
# driver package only installs its header and .pc file to the target
define LXQT_CONFIG_XORG_LIBINPUT_HEADER
	$(INSTALL) -D -m 0644 $(TARGET_DIR)/usr/include/xorg/libinput-properties.h \
		$(STAGING_DIR)/usr/include/xorg/libinput-properties.h
	$(INSTALL) -D -m 0644 $(TARGET_DIR)/usr/lib/pkgconfig/xorg-libinput.pc \
		$(STAGING_DIR)/usr/lib/pkgconfig/xorg-libinput.pc
endef
LXQT_CONFIG_PRE_CONFIGURE_HOOKS += LXQT_CONFIG_XORG_LIBINPUT_HEADER

$(eval $(cmake-package))
