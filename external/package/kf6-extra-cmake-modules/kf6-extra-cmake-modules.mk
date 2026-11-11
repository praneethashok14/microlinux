################################################################################
#
# kf6-extra-cmake-modules
#
################################################################################

# KDE Frameworks 6.30: the newest release that still builds with Qt 6.9
KF6_VERSION = 6.30.0
KF6_SITE = https://download.kde.org/stable/frameworks/$(basename $(KF6_VERSION))

KF6_EXTRA_CMAKE_MODULES_VERSION = $(KF6_VERSION)
KF6_EXTRA_CMAKE_MODULES_SITE = $(KF6_SITE)
KF6_EXTRA_CMAKE_MODULES_SOURCE = extra-cmake-modules-$(KF6_EXTRA_CMAKE_MODULES_VERSION).tar.xz
KF6_EXTRA_CMAKE_MODULES_LICENSE = BSD-3-Clause
KF6_EXTRA_CMAKE_MODULES_LICENSE_FILES = LICENSES/BSD-3-Clause.txt
KF6_EXTRA_CMAKE_MODULES_DEPENDENCIES = host-pkgconf
KF6_EXTRA_CMAKE_MODULES_INSTALL_STAGING = YES
KF6_EXTRA_CMAKE_MODULES_INSTALL_TARGET = NO
KF6_EXTRA_CMAKE_MODULES_CONF_OPTS = -DBUILD_DOC=OFF -DBUILD_TESTING=OFF

$(eval $(cmake-package))
