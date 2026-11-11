################################################################################
#
# qterminal
#
################################################################################

QTERMINAL_VERSION = 2.4.0
QTERMINAL_SITE = https://github.com/lxqt/qterminal/releases/download/$(QTERMINAL_VERSION)
QTERMINAL_SOURCE = qterminal-$(QTERMINAL_VERSION).tar.xz
QTERMINAL_LICENSE = GPL-2.0+
QTERMINAL_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
QTERMINAL_SUPPORTS_IN_SOURCE_BUILD = NO
QTERMINAL_DEPENDENCIES = qtermwidget layer-shell-qt lxqt-build-tools xlib_libX11 qt6base host-qt6tools
QTERMINAL_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DBUILD_TESTS=OFF

$(eval $(cmake-package))
