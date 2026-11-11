################################################################################
#
# qtxdg-tools
#
################################################################################

QTXDG_TOOLS_VERSION = 4.4.0
QTXDG_TOOLS_SITE = https://github.com/lxqt/qtxdg-tools/releases/download/$(QTXDG_TOOLS_VERSION)
QTXDG_TOOLS_SOURCE = qtxdg-tools-$(QTXDG_TOOLS_VERSION).tar.xz
QTXDG_TOOLS_LICENSE = LGPL-2.1+
QTXDG_TOOLS_LICENSE_FILES = LICENSE
QTXDG_TOOLS_INSTALL_STAGING = YES
# LXQt refuses in-source builds
QTXDG_TOOLS_SUPPORTS_IN_SOURCE_BUILD = NO
QTXDG_TOOLS_DEPENDENCIES = lxqt-build-tools libqtxdg qt6base host-qt6tools
QTXDG_TOOLS_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
