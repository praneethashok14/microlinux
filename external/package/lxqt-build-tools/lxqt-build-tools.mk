################################################################################
#
# lxqt-build-tools
#
################################################################################

LXQT_BUILD_TOOLS_VERSION = 2.4.0
LXQT_BUILD_TOOLS_SITE = https://github.com/lxqt/lxqt-build-tools/releases/download/$(LXQT_BUILD_TOOLS_VERSION)
LXQT_BUILD_TOOLS_SOURCE = lxqt-build-tools-$(LXQT_BUILD_TOOLS_VERSION).tar.xz
LXQT_BUILD_TOOLS_LICENSE = BSD-3-Clause
LXQT_BUILD_TOOLS_LICENSE_FILES = BSD-3-Clause
LXQT_BUILD_TOOLS_INSTALL_STAGING = YES
LXQT_BUILD_TOOLS_INSTALL_TARGET = NO
# LXQt refuses in-source builds
LXQT_BUILD_TOOLS_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_BUILD_TOOLS_DEPENDENCIES = qt6base
# Options for every LXQt package. Cross build: Qt's tools (qtpaths, lrelease)
# are in the host directory, which CMake doesn't search for packages.
LXQT_CMAKE_OPTS = -DUPDATE_TRANSLATIONS=OFF \
	-DQt6CoreTools_DIR=$(HOST_DIR)/lib/cmake/Qt6CoreTools \
	-DQt6LinguistTools_DIR=$(HOST_DIR)/lib/cmake/Qt6LinguistTools

# without qtpaths the system configuration directory would be asked from the
# host Qt, which answers with a host path: set it
LXQT_BUILD_TOOLS_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DLXQT_ETC_XDG_DIR=/etc/xdg

$(eval $(cmake-package))
