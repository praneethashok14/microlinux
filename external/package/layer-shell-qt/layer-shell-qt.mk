################################################################################
#
# layer-shell-qt
#
################################################################################

# Plasma 6.5: the newest series that still builds with Qt 6.9
LAYER_SHELL_QT_VERSION = 6.5.5
LAYER_SHELL_QT_SITE = https://download.kde.org/stable/plasma/$(LAYER_SHELL_QT_VERSION)
LAYER_SHELL_QT_SOURCE = layer-shell-qt-$(LAYER_SHELL_QT_VERSION).tar.xz
LAYER_SHELL_QT_LICENSE = LGPL-3.0+
LAYER_SHELL_QT_LICENSE_FILES = LICENSES/LGPL-3.0-or-later.txt LICENSES/LGPL-3.0-only.txt \
	LICENSES/LGPL-2.1-only.txt LICENSES/LicenseRef-KDE-Accepted-LGPL.txt
LAYER_SHELL_QT_INSTALL_STAGING = YES
LAYER_SHELL_QT_DEPENDENCIES = kf6-extra-cmake-modules qt6base qt6wayland \
	wayland wayland-protocols host-wayland libxkbcommon
LAYER_SHELL_QT_CONF_OPTS = -DBUILD_TESTING=OFF

$(eval $(cmake-package))
