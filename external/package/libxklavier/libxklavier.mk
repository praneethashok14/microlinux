################################################################################
#
# libxklavier
#
################################################################################

LIBXKLAVIER_VERSION = 5.4
LIBXKLAVIER_SITE = https://people.freedesktop.org/~svu
LIBXKLAVIER_SOURCE = libxklavier-$(LIBXKLAVIER_VERSION).tar.bz2
LIBXKLAVIER_LICENSE = LGPL-2.0+
LIBXKLAVIER_LICENSE_FILES = COPYING.LIB
LIBXKLAVIER_INSTALL_STAGING = YES
LIBXKLAVIER_DEPENDENCIES = host-pkgconf libglib2 libxml2 xlib_libX11 \
	xlib_libxkbfile xlib_libXi
LIBXKLAVIER_CONF_OPTS = --disable-introspection --disable-vala \
	--disable-gtk-doc --disable-xmodmap-support \
	--with-xkb-base=/usr/share/X11/xkb --with-xkb-bin-base=/usr/bin

# configure insists on iso-codes, which is only used at run time to translate
# country and language names (and is ~20 MB): give it a stub .pc file
define LIBXKLAVIER_ISO_CODES_STUB
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	printf 'prefix=/usr\nName: iso-codes\nDescription: stub\nVersion: 4.0\n' \
		> $(STAGING_DIR)/usr/lib/pkgconfig/iso-codes.pc
endef
LIBXKLAVIER_PRE_CONFIGURE_HOOKS += LIBXKLAVIER_ISO_CODES_STUB

$(eval $(autotools-package))
