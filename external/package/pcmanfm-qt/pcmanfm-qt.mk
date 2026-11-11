################################################################################
#
# pcmanfm-qt
#
################################################################################

PCMANFM_QT_VERSION = 2.4.0
PCMANFM_QT_SITE = https://github.com/lxqt/pcmanfm-qt/releases/download/$(PCMANFM_QT_VERSION)
PCMANFM_QT_SOURCE = pcmanfm-qt-$(PCMANFM_QT_VERSION).tar.xz
PCMANFM_QT_LICENSE = GPL-2.0+
PCMANFM_QT_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
PCMANFM_QT_SUPPORTS_IN_SOURCE_BUILD = NO
PCMANFM_QT_DEPENDENCIES = libfm-qt layer-shell-qt lxqt-build-tools qt6base host-qt6tools
PCMANFM_QT_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DBUILD_DOCUMENTATION=OFF

$(eval $(cmake-package))
