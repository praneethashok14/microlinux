################################################################################
#
# kf6-kwindowsystem
#
################################################################################

KF6_KWINDOWSYSTEM_VERSION = $(KF6_VERSION)
KF6_KWINDOWSYSTEM_SITE = $(KF6_SITE)
KF6_KWINDOWSYSTEM_SOURCE = kwindowsystem-$(KF6_KWINDOWSYSTEM_VERSION).tar.xz
KF6_KWINDOWSYSTEM_LICENSE = LGPL-2.1+
KF6_KWINDOWSYSTEM_LICENSE_FILES = LICENSES/LGPL-2.1-only.txt LICENSES/LGPL-2.1-or-later.txt LICENSES/LGPL-3.0-only.txt LICENSES/LicenseRef-KDE-Accepted-LGPL.txt LICENSES/MIT.txt
KF6_KWINDOWSYSTEM_INSTALL_STAGING = YES
KF6_KWINDOWSYSTEM_DEPENDENCIES = kf6-extra-cmake-modules qt6base host-qt6tools xlib_libX11 libxcb xcb-util-keysyms xcb-util-wm
KF6_KWINDOWSYSTEM_CONF_OPTS = -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_PYTHON_BINDINGS=OFF -DKWINDOWSYSTEM_QML=OFF -DKWINDOWSYSTEM_WAYLAND=OFF

$(eval $(cmake-package))
