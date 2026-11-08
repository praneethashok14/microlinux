################################################################################
#
# ncurses5-compat: ncurses ABI 5 shared libraries (EL7 binary compatibility)
#
################################################################################

NCURSES5_COMPAT_VERSION = $(NCURSES_VERSION)
NCURSES5_COMPAT_SITE = $(NCURSES_SITE)
NCURSES5_COMPAT_SOURCE = ncurses-$(NCURSES_VERSION).tar.gz
NCURSES5_COMPAT_LICENSE = MIT
NCURSES5_COMPAT_LICENSE_FILES = COPYING

# Same as RHEL 7: narrow and wide libraries both built with a separate tinfo
NCURSES5_COMPAT_COMMON_OPTS = \
	--host=$(GNU_TARGET_NAME) --build=$(GNU_HOST_NAME) \
	--prefix=/usr --with-abi-version=5 --with-shared --with-termlib=tinfo \
	--without-normal --without-debug --without-cxx --without-cxx-binding \
	--without-ada --without-progs --without-tests --without-manpages \
	--without-gpm --without-pkg-config --disable-db-install \
	--with-default-terminfo-dir=/usr/share/terminfo \
	--with-terminfo-dirs=/etc/terminfo:/usr/share/terminfo \
	--disable-stripping

define NCURSES5_COMPAT_BUILD_CMDS
	for v in narrow wide; do \
		mkdir -p $(@D)/build-$$v && cd $(@D)/build-$$v && \
		$(TARGET_CONFIGURE_OPTS) $(@D)/configure $(NCURSES5_COMPAT_COMMON_OPTS) \
			$$( [ $$v = wide ] && echo --enable-widec || echo --disable-widec ) && \
		$(MAKE) -C $(@D)/build-$$v libs || exit 1; \
	done
endef

define NCURSES5_COMPAT_INSTALL_TARGET_CMDS
	cp -a $(@D)/build-narrow/lib/lib*.so.5* $(TARGET_DIR)/usr/lib/
	cp -a $(@D)/build-wide/lib/lib*.so.5* $(TARGET_DIR)/usr/lib/
endef

$(eval $(generic-package))
