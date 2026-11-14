################################################################################
#
# kde-appstream: AppStream metadata library with its Qt bindings (Discover)
#
################################################################################

KDE_APPSTREAM_VERSION = 1.2.3
KDE_APPSTREAM_SITE = https://www.freedesktop.org/software/appstream/releases
KDE_APPSTREAM_SOURCE = AppStream-$(KDE_APPSTREAM_VERSION).tar.xz
KDE_APPSTREAM_LICENSE = LGPL-2.1+, GPL-2.0+ (tools)
KDE_APPSTREAM_LICENSE_FILES = COPYING
KDE_APPSTREAM_INSTALL_STAGING = YES
KDE_APPSTREAM_DEPENDENCIES = libglib2 libxml2 libyaml libcurl libxmlb zstd qt6base host-gperf host-pkgconf
KDE_APPSTREAM_CONF_OPTS = -Dqt=true -Dsystemd=false -Dstemming=false -Dblake3-support=false \
	-Dgir=false -Dvapi=false -Dcompose=false -Ddocs=false -Dapidocs=false -Dinstall-docs=false \
	-Dman=false -Dbash-completion=false -Dapt-support=false -Dzstd-support=true

$(eval $(meson-package))
