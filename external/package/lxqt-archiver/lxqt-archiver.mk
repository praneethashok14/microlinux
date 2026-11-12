################################################################################
#
# lxqt-archiver
#
################################################################################

# 1.4.x goes with LXQt 2.4 (1.5 needs libfm-qt 2.5 and Qt 6.10)
LXQT_ARCHIVER_VERSION = 1.4.0
LXQT_ARCHIVER_SITE = https://github.com/lxqt/lxqt-archiver/releases/download/$(LXQT_ARCHIVER_VERSION)
LXQT_ARCHIVER_SOURCE = lxqt-archiver-$(LXQT_ARCHIVER_VERSION).tar.xz
LXQT_ARCHIVER_LICENSE = GPL-2.0+
LXQT_ARCHIVER_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_ARCHIVER_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_ARCHIVER_DEPENDENCIES = libfm-qt json-glib libglib2 qt6base host-qt6tools lxqt-build-tools
LXQT_ARCHIVER_CONF_OPTS = $(LXQT_CMAKE_OPTS)

$(eval $(cmake-package))
