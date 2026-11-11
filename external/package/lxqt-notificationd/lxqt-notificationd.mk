################################################################################
#
# lxqt-notificationd
#
################################################################################

LXQT_NOTIFICATIOND_VERSION = 2.4.0
LXQT_NOTIFICATIOND_SITE = https://github.com/lxqt/lxqt-notificationd/releases/download/$(LXQT_NOTIFICATIOND_VERSION)
LXQT_NOTIFICATIOND_SOURCE = lxqt-notificationd-$(LXQT_NOTIFICATIOND_VERSION).tar.xz
LXQT_NOTIFICATIOND_LICENSE = LGPL-2.1+
LXQT_NOTIFICATIOND_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_NOTIFICATIOND_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_NOTIFICATIOND_DEPENDENCIES = liblxqt kf6-kwindowsystem layer-shell-qt qt6base host-qt6tools
LXQT_NOTIFICATIOND_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
