################################################################################
#
# libqtxdg
#
################################################################################

LIBQTXDG_VERSION = 4.4.0
LIBQTXDG_SITE = https://github.com/lxqt/libqtxdg/releases/download/$(LIBQTXDG_VERSION)
LIBQTXDG_SOURCE = libqtxdg-$(LIBQTXDG_VERSION).tar.xz
LIBQTXDG_LICENSE = LGPL-2.1+
LIBQTXDG_LICENSE_FILES = COPYING
LIBQTXDG_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LIBQTXDG_SUPPORTS_IN_SOURCE_BUILD = NO
LIBQTXDG_DEPENDENCIES = lxqt-build-tools qt6base host-qt6tools qt6svg libglib2
LIBQTXDG_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DBUILD_TESTS=OFF -DBUILD_DEV_UTILS=OFF \
	-DQTXDGX_ICONENGINEPLUGIN_INSTALL_PATH=/usr/lib/qt6/plugins/iconengines

$(eval $(cmake-package))
