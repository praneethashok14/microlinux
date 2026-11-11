################################################################################
#
# lightdm
#
################################################################################

LIGHTDM_VERSION = 1.32.0
LIGHTDM_SITE = https://github.com/canonical/lightdm/releases/download/$(LIGHTDM_VERSION)
LIGHTDM_SOURCE = lightdm-$(LIGHTDM_VERSION).tar.xz
LIGHTDM_LICENSE = GPL-3.0, LGPL-2.0 or LGPL-3.0 (liblightdm-gobject)
LIGHTDM_LICENSE_FILES = COPYING.GPL3 COPYING.LGPL2 COPYING.LGPL3
LIGHTDM_INSTALL_STAGING = YES
LIGHTDM_DEPENDENCIES = host-pkgconf host-intltool libglib2 libgcrypt linux-pam \
	libxcb xlib_libX11 xlib_libXdmcp libxklavier $(TARGET_NLS_DEPENDENCIES)
# itstool/xmllint only build the help pages, which are not installed (patch)
LIGHTDM_CONF_ENV = ITSTOOL=/bin/true XMLLINT=/bin/true
LIGHTDM_CONF_OPTS = --disable-tests --disable-introspection --disable-vala \
	--disable-liblightdm-qt5 --disable-gtk-doc --disable-libaudit \
	--with-greeter-user=lightdm --with-greeter-session=lightdm-gtk-greeter \
	--with-user-session=lxqt

define LIGHTDM_USERS
	lightdm -1 lightdm -1 * /var/lib/lightdm - - LightDM greeter
endef

# configuration and PAM files come from the MicroLinux rootfs overlay
define LIGHTDM_REMOVE_EXTRAS
	rm -rf $(TARGET_DIR)/etc/apparmor.d $(TARGET_DIR)/etc/init \
		$(TARGET_DIR)/usr/share/bash-completion/completions/*lightdm* \
		$(TARGET_DIR)/usr/share/bash-completion/completions/dm-tool
endef
LIGHTDM_POST_INSTALL_TARGET_HOOKS += LIGHTDM_REMOVE_EXTRAS

$(eval $(autotools-package))
