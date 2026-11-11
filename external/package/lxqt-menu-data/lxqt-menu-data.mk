################################################################################
#
# lxqt-menu-data
#
################################################################################

LXQT_MENU_DATA_VERSION = 2.4.0
LXQT_MENU_DATA_SITE = https://github.com/lxqt/lxqt-menu-data/releases/download/$(LXQT_MENU_DATA_VERSION)
LXQT_MENU_DATA_SOURCE = lxqt-menu-data-$(LXQT_MENU_DATA_VERSION).tar.xz
LXQT_MENU_DATA_LICENSE = LGPL-2.1+
LXQT_MENU_DATA_LICENSE_FILES = LICENSE
LXQT_MENU_DATA_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LXQT_MENU_DATA_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_MENU_DATA_DEPENDENCIES = lxqt-build-tools qt6base host-qt6tools
LXQT_MENU_DATA_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
