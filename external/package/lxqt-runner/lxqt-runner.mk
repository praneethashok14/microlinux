################################################################################
#
# lxqt-runner
#
################################################################################

LXQT_RUNNER_VERSION = 2.4.0
LXQT_RUNNER_SITE = https://github.com/lxqt/lxqt-runner/releases/download/$(LXQT_RUNNER_VERSION)
LXQT_RUNNER_SOURCE = lxqt-runner-$(LXQT_RUNNER_VERSION).tar.xz
LXQT_RUNNER_LICENSE = LGPL-2.1+
LXQT_RUNNER_LICENSE_FILES = LICENSE
# LXQt refuses in-source builds
LXQT_RUNNER_SUPPORTS_IN_SOURCE_BUILD = NO
LXQT_RUNNER_DEPENDENCIES = liblxqt lxqt-globalkeys kf6-kwindowsystem layer-shell-qt muparser host-pkgconf qt6base host-qt6tools
LXQT_RUNNER_CONF_OPTS = $(LXQT_CMAKE_OPTS) -DRUNNER_VBOX=OFF

$(eval $(cmake-package))
