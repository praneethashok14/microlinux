################################################################################
#
# lxqt-qtplugin
#
################################################################################

LXQT_QTPLUGIN_VERSION = 2.4.0
LXQT_QTPLUGIN_SITE = https://github.com/lxqt/lxqt-qtplugin/releases/download/$(LXQT_QTPLUGIN_VERSION)
LXQT_QTPLUGIN_SOURCE = lxqt-qtplugin-$(LXQT_QTPLUGIN_VERSION).tar.xz
LXQT_QTPLUGIN_LICENSE = LGPL-2.1+
LXQT_QTPLUGIN_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_QTPLUGIN_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_QTPLUGIN_DEPENDENCIES = lxqt-build-tools libqtxdg libdbusmenu-lxqt libfm-qt qt6base host-qt6tools
LXQT_QTPLUGIN_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DQT_PLUGINS_DIR=/usr/lib/qt6/plugins

$(eval $(cmake-package))
