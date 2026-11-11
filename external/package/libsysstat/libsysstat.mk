################################################################################
#
# libsysstat
#
################################################################################

LIBSYSSTAT_VERSION = 1.1.0
LIBSYSSTAT_SITE = https://github.com/lxqt/libsysstat/releases/download/$(LIBSYSSTAT_VERSION)
LIBSYSSTAT_SOURCE = libsysstat-$(LIBSYSSTAT_VERSION).tar.xz
LIBSYSSTAT_LICENSE = LGPL-2.1+
LIBSYSSTAT_LICENSE_FILES = COPYING
LIBSYSSTAT_INSTALL_STAGING = YES
# LXQt refuses in-source builds
LIBSYSSTAT_SUPPORTS_IN_SOURCE_BUILD = NO
LIBSYSSTAT_DEPENDENCIES = lxqt-build-tools qt6base host-qt6tools
LIBSYSSTAT_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
