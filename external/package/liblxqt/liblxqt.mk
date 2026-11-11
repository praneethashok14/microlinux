################################################################################
#
# liblxqt
#
################################################################################

LIBLXQT_VERSION = 2.4.0
LIBLXQT_SITE = https://github.com/lxqt/liblxqt/releases/download/$(LIBLXQT_VERSION)
LIBLXQT_SOURCE = liblxqt-$(LIBLXQT_VERSION).tar.xz
LIBLXQT_LICENSE = LGPL-2.1+
LIBLXQT_LICENSE_FILES = COPYING
LIBLXQT_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LIBLXQT_SUPPORTS_IN_SOURCE_BUILD = NO
LIBLXQT_DEPENDENCIES = lxqt-build-tools libqtxdg kf6-kwindowsystem polkit-qt6 xlib_libX11 xlib_libXScrnSaver qt6base host-qt6tools
LIBLXQT_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
