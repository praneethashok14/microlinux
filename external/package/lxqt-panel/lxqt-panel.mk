################################################################################
#
# lxqt-panel
#
################################################################################

LXQT_PANEL_VERSION = 2.4.1
LXQT_PANEL_SITE = https://github.com/lxqt/lxqt-panel/releases/download/$(LXQT_PANEL_VERSION)
LXQT_PANEL_SOURCE = lxqt-panel-$(LXQT_PANEL_VERSION).tar.xz
LXQT_PANEL_LICENSE = LGPL-2.1+
LXQT_PANEL_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_PANEL_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_PANEL_DEPENDENCIES = liblxqt lxqt-globalkeys lxqt-menu-data libdbusmenu-lxqt libsysstat kf6-kwindowsystem kf6-solid layer-shell-qt qt6wayland libxkbcommon xlib_libXtst libxcb alsa-lib host-pkgconf qt6base host-qt6tools
LXQT_PANEL_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DCPULOAD_PLUGIN=OFF -DNETWORKMONITOR_PLUGIN=OFF -DSENSORS_PLUGIN=OFF -DVOLUME_USE_PULSEAUDIO=OFF -DVOLUME_USE_ALSA=ON

$(eval $(cmake-package))
