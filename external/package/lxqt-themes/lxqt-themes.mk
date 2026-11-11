################################################################################
#
# lxqt-themes
#
################################################################################

LXQT_THEMES_VERSION = 2.4.0
LXQT_THEMES_SITE = https://github.com/lxqt/lxqt-themes/releases/download/$(LXQT_THEMES_VERSION)
LXQT_THEMES_SOURCE = lxqt-themes-$(LXQT_THEMES_VERSION).tar.xz
LXQT_THEMES_LICENSE = LGPL-2.1+
LXQT_THEMES_LICENSE_FILES = COPYING
# LXQt refuses in-source builds
LXQT_THEMES_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_THEMES_DEPENDENCIES = lxqt-build-tools qt6base host-qt6tools
LXQT_THEMES_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
