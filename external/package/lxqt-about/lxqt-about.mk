################################################################################
#
# lxqt-about
#
################################################################################

LXQT_ABOUT_VERSION = 2.4.0
LXQT_ABOUT_SITE = https://github.com/lxqt/lxqt-about/releases/download/$(LXQT_ABOUT_VERSION)
LXQT_ABOUT_SOURCE = lxqt-about-$(LXQT_ABOUT_VERSION).tar.xz
LXQT_ABOUT_LICENSE = LGPL-2.1+
LXQT_ABOUT_LICENSE_FILES = COPYING
# LXQt refuses in-source builds
LXQT_ABOUT_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_ABOUT_DEPENDENCIES = liblxqt qt6base host-qt6tools
LXQT_ABOUT_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
