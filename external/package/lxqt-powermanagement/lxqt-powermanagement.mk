################################################################################
#
# lxqt-powermanagement
#
################################################################################

LXQT_POWERMANAGEMENT_VERSION = 2.4.0
LXQT_POWERMANAGEMENT_SITE = https://github.com/lxqt/lxqt-powermanagement/releases/download/$(LXQT_POWERMANAGEMENT_VERSION)
LXQT_POWERMANAGEMENT_SOURCE = lxqt-powermanagement-$(LXQT_POWERMANAGEMENT_VERSION).tar.xz
LXQT_POWERMANAGEMENT_LICENSE = LGPL-2.1+
LXQT_POWERMANAGEMENT_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_POWERMANAGEMENT_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_POWERMANAGEMENT_DEPENDENCIES = liblxqt lxqt-globalkeys kf6-kidletime kf6-solid qt6svg libxcb qt6base host-qt6tools
LXQT_POWERMANAGEMENT_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
