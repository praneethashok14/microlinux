################################################################################
#
# qt5-base: Qt 5.15 base libraries (libQt5Core, libQt5Gui, libQt5Widgets,
# Network, DBus, Xml, Concurrent, PrintSupport, OpenGL) and the X11 platform
# plugin, next to Qt 6, for programs made for Qt 5. A repository package.
#
# Buildroot's own qt5base can't be used: its Qt 6 depends on !Qt5. This
# follows its recipe (the "device" mkspec of package/qt5/qt5base), with paths
# apart from Qt 6: plugins in /usr/lib/qt5/plugins, headers in
# /usr/include/qt5, host tools (qmake, moc) in $(HOST_DIR)/qt5.
#
################################################################################

QT5_BASE_VERSION = 5.15.19
QT5_BASE_SITE = https://download.qt.io/archive/qt/5.15/$(QT5_BASE_VERSION)/submodules
QT5_BASE_SOURCE = qtbase-everywhere-opensource-src-$(QT5_BASE_VERSION).tar.xz
QT5_BASE_LICENSE = GPL-2.0+ or LGPL-3.0, GPL-3.0 with exception(tools)
QT5_BASE_LICENSE_FILES = LICENSE.GPL2 LICENSE.GPL3 LICENSE.GPL3-EXCEPT LICENSE.LGPLv3
QT5_BASE_INSTALL_STAGING = YES
QT5_BASE_DEPENDENCIES = host-pkgconf pcre2 zlib freetype harfbuzz fontconfig libpng jpeg dbus \
	libglib2 openssl zstd libxkbcommon libxcb xcb-util-wm xcb-util-image xcb-util-keysyms \
	xcb-util-renderutil xlib_libX11 xlib_libXext libgl udev

QT5_BASE_CFLAGS = $(TARGET_CFLAGS)
QT5_BASE_CXXFLAGS = $(TARGET_CXXFLAGS)

QT5_BASE_CONFIGURE_OPTS = \
	-opensource -confirm-license -release -optimized-qmake -no-optimize-debug \
	-shared -no-pch -no-rpath -no-feature-relocatable -nomake tests -nomake examples \
	-no-iconv -system-zlib -system-pcre -zstd -no-icu -glib -dbus -openssl \
	-gui -widgets -system-freetype -system-harfbuzz -fontconfig -system-libjpeg -system-libpng \
	-xcb -xkbcommon -qpa xcb -opengl desktop -no-feature-vulkan \
	-no-eglfs -no-kms -no-gbm -no-linuxfb -no-directfb -no-libinput -no-tslib \
	-no-gtk -no-cups -no-journald -no-syslog \
	-no-sql-mysql -no-sql-psql -no-sql-sqlite -no-sql-odbc -no-sql-db2 -no-sql-ibase -no-sql-oci -no-sql-tds

# x86: the CPU features the target has (as package/qt5/qt5base)
ifeq ($(BR2_X86_CPU_HAS_SSE2),)
QT5_BASE_CONFIGURE_OPTS += -no-sse2
else ifeq ($(BR2_X86_CPU_HAS_SSE3),)
QT5_BASE_CONFIGURE_OPTS += -no-sse3
else ifeq ($(BR2_X86_CPU_HAS_SSSE3),)
QT5_BASE_CONFIGURE_OPTS += -no-ssse3
else ifeq ($(BR2_X86_CPU_HAS_SSE4),)
QT5_BASE_CONFIGURE_OPTS += -no-sse4.1
else ifeq ($(BR2_X86_CPU_HAS_SSE42),)
QT5_BASE_CONFIGURE_OPTS += -no-sse4.2
else ifeq ($(BR2_X86_CPU_HAS_AVX),)
QT5_BASE_CONFIGURE_OPTS += -no-avx
else ifeq ($(BR2_X86_CPU_HAS_AVX2),)
QT5_BASE_CONFIGURE_OPTS += -no-avx2
endif
ifeq ($(BR2_CCACHE),y)
QT5_BASE_CONFIGURE_OPTS += -ccache
endif

QT5_BASE_DEVICE = $(@D)/mkspecs/devices/linux-buildroot-g++
QT5_BASE_BR_QT5 = $(TOPDIR)/package/qt5/qt5base

define QT5_BASE_CONFIGURE_CMDS
	mkdir -p $(QT5_BASE_DEVICE)
	sed 's/@EGLFS_DEVICE@//g' $(QT5_BASE_BR_QT5)/qmake.conf.in > $(QT5_BASE_DEVICE)/qmake.conf
	$(INSTALL) -m 0644 -D $(QT5_BASE_BR_QT5)/qplatformdefs.h $(QT5_BASE_DEVICE)/qplatformdefs.h
	: > $(QT5_BASE_DEVICE)/arch.conf
	$(if $(BR2_TOOLCHAIN_HAS_LIBATOMIC),printf '!host_build { \n LIBS += -latomic\n }' > $(QT5_BASE_DEVICE)/arch.conf)
	$(SED) 's,^QMAKE_CC\s*=.*,QMAKE_CC = $(HOSTCC_NOCCACHE),' $(@D)/mkspecs/common/g++-base.conf
	$(SED) 's,^QMAKE_CXX\s*=.*,QMAKE_CXX = $(HOSTCXX_NOCCACHE),' $(@D)/mkspecs/common/g++-base.conf
	(cd $(@D); \
		$(TARGET_MAKE_ENV) \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		MAKEFLAGS="-j$(PARALLEL_JOBS) $(MAKEFLAGS)" \
		./configure -v \
		-prefix /usr \
		-hostprefix $(HOST_DIR)/qt5 \
		-headerdir /usr/include/qt5 \
		-archdatadir /usr/lib/qt5 \
		-plugindir /usr/lib/qt5/plugins \
		-libexecdir /usr/lib/qt5/libexec \
		-datadir /usr/share/qt5 \
		-translationdir /usr/share/qt5/translations \
		-examplesdir /usr/lib/qt5/examples \
		-sysroot $(STAGING_DIR) \
		-device buildroot \
		-device-option CROSS_COMPILE="$(TARGET_CROSS)" \
		-device-option BR_COMPILER_CFLAGS="$(QT5_BASE_CFLAGS)" \
		-device-option BR_COMPILER_CXXFLAGS="$(QT5_BASE_CXXFLAGS)" \
		$(QT5_BASE_CONFIGURE_OPTS))
endef

define QT5_BASE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

# (with -sysroot, "make install" puts the files into $(STAGING_DIR))
define QT5_BASE_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) install
endef

# the libraries and plugins; not the headers, tools and build files
define QT5_BASE_INSTALL_TARGET_CMDS
	cp -a $(STAGING_DIR)/usr/lib/libQt5*.so.* $(TARGET_DIR)/usr/lib/
	mkdir -p $(TARGET_DIR)/usr/lib/qt5
	cp -a $(STAGING_DIR)/usr/lib/qt5/plugins $(TARGET_DIR)/usr/lib/qt5/
	rm -f $(TARGET_DIR)/usr/lib/libQt5*.so.*.debug
endef

$(eval $(generic-package))
