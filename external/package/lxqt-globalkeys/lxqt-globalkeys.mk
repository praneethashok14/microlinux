################################################################################
#
# lxqt-globalkeys
#
################################################################################

LXQT_GLOBALKEYS_VERSION = 2.4.0
LXQT_GLOBALKEYS_SITE = https://github.com/lxqt/lxqt-globalkeys/releases/download/$(LXQT_GLOBALKEYS_VERSION)
LXQT_GLOBALKEYS_SOURCE = lxqt-globalkeys-$(LXQT_GLOBALKEYS_VERSION).tar.xz
LXQT_GLOBALKEYS_LICENSE = LGPL-2.1+
LXQT_GLOBALKEYS_LICENSE_FILES = LICENSE
LXQT_GLOBALKEYS_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LXQT_GLOBALKEYS_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_GLOBALKEYS_DEPENDENCIES = liblxqt qt6base host-qt6tools
LXQT_GLOBALKEYS_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
