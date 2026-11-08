################################################################################
#
# jwm
#
################################################################################

JWM_VERSION = 2.4.6
JWM_SOURCE = jwm-$(JWM_VERSION).tar.xz
JWM_SITE = https://github.com/joewing/jwm/releases/download/v$(JWM_VERSION)
JWM_LICENSE = MIT
JWM_LICENSE_FILES = LICENSE
JWM_DEPENDENCIES = host-pkgconf xlib_libX11 xlib_libXext xlib_libXft \
	xlib_libXinerama xlib_libXmu xlib_libXpm xlib_libXrender xlib_libXrandr \
	libpng jpeg cairo
JWM_CONF_OPTS = --disable-nls --enable-xft --enable-xinerama --enable-xrender \
	--enable-png --enable-jpeg --enable-cairo --enable-xpm --disable-fribidi

ifeq ($(BR2_PACKAGE_LIBRSVG),y)
JWM_DEPENDENCIES += librsvg
JWM_CONF_OPTS += --enable-rsvg
else
JWM_CONF_OPTS += --disable-rsvg
endif

$(eval $(autotools-package))
