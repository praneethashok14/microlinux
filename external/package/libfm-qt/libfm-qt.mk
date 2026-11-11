################################################################################
#
# libfm-qt
#
################################################################################

LIBFM_QT_VERSION = 2.4.0
LIBFM_QT_SITE = https://github.com/lxqt/libfm-qt/releases/download/$(LIBFM_QT_VERSION)
LIBFM_QT_SOURCE = libfm-qt-$(LIBFM_QT_VERSION).tar.xz
LIBFM_QT_LICENSE = LGPL-2.1+
LIBFM_QT_LICENSE_FILES = LICENSE
LIBFM_QT_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LIBFM_QT_SUPPORTS_IN_SOURCE_BUILD = NO
LIBFM_QT_DEPENDENCIES = lxqt-build-tools lxqt-menu-data menu-cache libglib2 libexif libxcb qt6base host-qt6tools
LIBFM_QT_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DBUILD_DOCUMENTATION=OFF

$(eval $(cmake-package))
