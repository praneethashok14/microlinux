################################################################################
#
# libxcrypt-compat: libcrypt.so.1 for binaries linked against glibc's libcrypt
#
################################################################################

LIBXCRYPT_COMPAT_VERSION = $(LIBXCRYPT_VERSION)
LIBXCRYPT_COMPAT_SITE = $(LIBXCRYPT_SITE)
LIBXCRYPT_COMPAT_SOURCE = $(LIBXCRYPT_SOURCE)
LIBXCRYPT_COMPAT_LICENSE = LGPL-2.1+
LIBXCRYPT_COMPAT_LICENSE_FILES = LICENSING COPYING.LIB
LIBXCRYPT_COMPAT_INSTALL_STAGING = NO
LIBXCRYPT_COMPAT_CONF_OPTS = --disable-werror --enable-obsolete-api=glibc \
	--enable-hashes=all --disable-static --disable-xcrypt-compat-files

define LIBXCRYPT_COMPAT_INSTALL_TARGET_CMDS
	cp -a $(@D)/.libs/libcrypt.so.1* $(TARGET_DIR)/usr/lib/
endef

$(eval $(autotools-package))
