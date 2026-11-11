################################################################################
#
# kf6-kidletime
#
################################################################################

KF6_KIDLETIME_VERSION = $(KF6_VERSION)
KF6_KIDLETIME_SITE = $(KF6_SITE)
KF6_KIDLETIME_SOURCE = kidletime-$(KF6_KIDLETIME_VERSION).tar.xz
KF6_KIDLETIME_LICENSE = LGPL-2.1+
KF6_KIDLETIME_LICENSE_FILES = LICENSES/LGPL-2.1-or-later.txt LICENSES/GPL-2.0-or-later.txt LICENSES/MIT.txt
KF6_KIDLETIME_INSTALL_STAGING = YES
KF6_KIDLETIME_DEPENDENCIES = kf6-extra-cmake-modules qt6base host-qt6tools xlib_libX11 libxcb
KF6_KIDLETIME_CONF_OPTS = -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_PYTHON_BINDINGS=OFF -DWITH_X11=ON -DWITH_WAYLAND=OFF

$(eval $(cmake-package))
