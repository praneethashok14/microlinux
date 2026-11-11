################################################################################
#
# kf6-solid
#
################################################################################

KF6_SOLID_VERSION = $(KF6_VERSION)
KF6_SOLID_SITE = $(KF6_SITE)
KF6_SOLID_SOURCE = solid-$(KF6_SOLID_VERSION).tar.xz
KF6_SOLID_LICENSE = LGPL-2.1+
KF6_SOLID_LICENSE_FILES = LICENSES/LGPL-2.1-only.txt LICENSES/LGPL-2.1-or-later.txt LICENSES/LGPL-3.0-only.txt LICENSES/LicenseRef-KDE-Accepted-LGPL.txt LICENSES/BSD-3-Clause.txt
KF6_SOLID_INSTALL_STAGING = YES
KF6_SOLID_DEPENDENCIES = kf6-extra-cmake-modules qt6base host-qt6tools host-flex host-bison udev util-linux
KF6_SOLID_CONF_OPTS = -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_PYTHON_BINDINGS=OFF -DUSE_DBUS=ON

$(eval $(cmake-package))
