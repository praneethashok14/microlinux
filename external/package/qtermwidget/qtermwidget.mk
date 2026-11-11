################################################################################
#
# qtermwidget
#
################################################################################

QTERMWIDGET_VERSION = 2.4.0
QTERMWIDGET_SITE = https://github.com/lxqt/qtermwidget/releases/download/$(QTERMWIDGET_VERSION)
QTERMWIDGET_SOURCE = qtermwidget-$(QTERMWIDGET_VERSION).tar.xz
QTERMWIDGET_LICENSE = GPL-2.0+
QTERMWIDGET_LICENSE_FILES = LICENSE
QTERMWIDGET_INSTALL_STAGING = YES
# LXQt refuses in-source builds
QTERMWIDGET_SUPPORTS_IN_SOURCE_BUILD = NO
QTERMWIDGET_DEPENDENCIES = lxqt-build-tools qt6base host-qt6tools
QTERMWIDGET_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DUSE_UTF8PROC=OFF -DBUILD_EXAMPLE=OFF

$(eval $(cmake-package))
