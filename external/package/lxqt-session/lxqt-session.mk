################################################################################
#
# lxqt-session
#
################################################################################

LXQT_SESSION_VERSION = 2.4.0
LXQT_SESSION_SITE = https://github.com/lxqt/lxqt-session/releases/download/$(LXQT_SESSION_VERSION)
LXQT_SESSION_SOURCE = lxqt-session-$(LXQT_SESSION_VERSION).tar.xz
LXQT_SESSION_LICENSE = LGPL-2.1+
LXQT_SESSION_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_SESSION_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_SESSION_DEPENDENCIES = liblxqt kf6-kwindowsystem layer-shell-qt qtxdg-tools xdg-user-dirs procps-ng udev xlib_libX11 host-pkgconf qt6base host-qt6tools
LXQT_SESSION_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DWITH_LIBUDEV=ON

$(eval $(cmake-package))
