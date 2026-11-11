################################################################################
#
# lightdm-gtk-greeter
#
################################################################################

LIGHTDM_GTK_GREETER_VERSION = 2.0.9
LIGHTDM_GTK_GREETER_SITE = https://github.com/Xubuntu/lightdm-gtk-greeter/releases/download/lightdm-gtk-greeter-$(LIGHTDM_GTK_GREETER_VERSION)
LIGHTDM_GTK_GREETER_SOURCE = lightdm-gtk-greeter-$(LIGHTDM_GTK_GREETER_VERSION).tar.gz
LIGHTDM_GTK_GREETER_LICENSE = GPL-3.0+
LIGHTDM_GTK_GREETER_LICENSE_FILES = COPYING
LIGHTDM_GTK_GREETER_DEPENDENCIES = host-pkgconf host-intltool lightdm libgtk3 \
	xlib_libX11 $(TARGET_NLS_DEPENDENCIES)
LIGHTDM_GTK_GREETER_CONF_OPTS = --disable-libindicator --disable-libido \
	--disable-at-spi-command --disable-indicator-services-command \
	--enable-kill-on-sigterm

# the release tarball ships the headers generated from the .ui and .css files;
# make must not regenerate them (that needs xdt-csource, from xfce4-dev-tools)
define LIGHTDM_GTK_GREETER_KEEP_GENERATED_HEADERS
	touch $(@D)/src/lightdm-gtk-greeter-ui.h \
		$(@D)/src/lightdm-gtk-greeter-css-fallback.h \
		$(@D)/src/lightdm-gtk-greeter-css-application.h
endef
LIGHTDM_GTK_GREETER_PRE_BUILD_HOOKS += LIGHTDM_GTK_GREETER_KEEP_GENERATED_HEADERS

# the greeter configuration comes from the MicroLinux rootfs overlay
define LIGHTDM_GTK_GREETER_REMOVE_CONF
	rm -f $(TARGET_DIR)/etc/lightdm/lightdm-gtk-greeter.conf.dist
endef
LIGHTDM_GTK_GREETER_POST_INSTALL_TARGET_HOOKS += LIGHTDM_GTK_GREETER_REMOVE_CONF

$(eval $(autotools-package))
