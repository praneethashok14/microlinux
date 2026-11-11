################################################################################
#
# libdbusmenu-lxqt
#
################################################################################

LIBDBUSMENU_LXQT_VERSION = 0.4.0
LIBDBUSMENU_LXQT_SITE = https://github.com/lxqt/libdbusmenu-lxqt/releases/download/$(LIBDBUSMENU_LXQT_VERSION)
LIBDBUSMENU_LXQT_SOURCE = libdbusmenu-lxqt-$(LIBDBUSMENU_LXQT_VERSION).tar.xz
LIBDBUSMENU_LXQT_LICENSE = LGPL-2.0+
LIBDBUSMENU_LXQT_LICENSE_FILES = COPYING
LIBDBUSMENU_LXQT_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LIBDBUSMENU_LXQT_SUPPORTS_IN_SOURCE_BUILD = NO
LIBDBUSMENU_LXQT_DEPENDENCIES = qt6base host-qt6tools
LIBDBUSMENU_LXQT_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DWITH_DOC=OFF -DBUILD_TESTS=OFF

$(eval $(cmake-package))
