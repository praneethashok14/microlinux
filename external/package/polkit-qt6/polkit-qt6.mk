################################################################################
#
# polkit-qt6
#
################################################################################

POLKIT_QT6_VERSION = 0.201.1
POLKIT_QT6_SITE = https://download.kde.org/stable/polkit-qt-1
POLKIT_QT6_SOURCE = polkit-qt-1-$(POLKIT_QT6_VERSION).tar.xz
POLKIT_QT6_LICENSE = LGPL-2.0+
POLKIT_QT6_LICENSE_FILES = LICENSES/LGPL-2.0-or-later.txt
POLKIT_QT6_INSTALL_STAGING = YES
POLKIT_QT6_DEPENDENCIES = qt6base polkit libglib2 host-pkgconf
POLKIT_QT6_CONF_OPTS = -DQT_MAJOR_VERSION=6 -DBUILD_EXAMPLES=OFF -DBUILD_TEST=OFF

$(eval $(cmake-package))
