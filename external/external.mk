include $(sort $(wildcard $(BR2_EXTERNAL_MICROLINUX_PATH)/package/*/*.mk))

# libfm (Vala-generated code) mixes related GObject pointer types;
# GCC 14 turned -Wincompatible-pointer-types into an error.
LIBFM_CONF_ENV += CFLAGS="$(TARGET_CFLAGS) -Wno-error=incompatible-pointer-types"

# x86_64 has GPU drivers (Mesa iris/crocus/radeonsi/r600/nouveau + GBM), so
# Xorg gets glamor (loaded first by xorg.conf.d/05-glamor.conf, see post-build.sh):
# the modesetting driver then offers DRI3 and OpenGL
# programs (games) render on the GPU. aarch64 has no GPU drivers in the
# image: build Xorg without glamor there. Otherwise the modesetting driver
# references GBM symbols that only glamor provides, and with Buildroot's
# -z now (full RELRO) it fails to load ("no screens found").
ifneq ($(BR2_x86_64),y)
XSERVER_XORG_SERVER_CONF_OPTS += --disable-glamor
endif

# glibc 2.42's x86_64 modf/modff ifunc variants call __trunc/__truncf, which
# only exist when the library is built with -O2: -Os fails to link libc.so.
ifeq ($(BR2_x86_64),y)
GLIBC_CFLAGS += -O2
endif

# Package repository: optional features that would drag repository packages
# (Python, LVM, Lua, Valgrind) into the base system. repo-split.py ignores the
# matching dependency edges; post-image.sh verifies that no base binary needs them.
UTIL_LINUX_CONF_OPTS := $(filter-out --with-python --enable-pylibmount,$(UTIL_LINUX_CONF_OPTS)) --without-python --disable-pylibmount
# lastlog2 is built whenever configure happens to find SQLite (a repository package)
UTIL_LINUX_CONF_OPTS += --disable-liblastlog2
PARTED_CONF_OPTS := $(filter-out --enable-device-mapper,$(PARTED_CONF_OPTS)) --disable-device-mapper
LIBINPUT_CONF_OPTS := $(filter-out -Dlua-plugins=enabled,$(LIBINPUT_CONF_OPTS)) -Dlua-plugins=disabled
LIBDRM_CONF_OPTS := $(filter-out -Dvalgrind=enabled,$(LIBDRM_CONF_OPTS)) -Dvalgrind=disabled
MESA3D_CONF_OPTS := $(filter-out -Dvalgrind=enabled,$(MESA3D_CONF_OPTS)) -Dvalgrind=disabled
# CUPS is enabled only for Chromium (libcups, a repository package): GTK's
# base-system print dialog keeps its file/lpr backends
LIBGTK3_CONF_OPTS := $(filter-out -Dprint_backends=file$(comma)cups,$(LIBGTK3_CONF_OPTS)) -Dprint_backends=file,lpr

# SVG support for GTK (symbolic icons, theme assets, SVG pictures): build
# librsvg's gdk-pixbuf loader; post-build.sh registers it in loaders.cache
LIBRSVG_CONF_OPTS := $(filter-out --disable-pixbuf-loader,$(LIBRSVG_CONF_OPTS)) --enable-pixbuf-loader
# (pkg-config hands configure the build-tree paths; install to the target's
# loader directory, and let its own cache file go to a side name)
ML_RSVG_LOADER_PATHS = gdk_pixbuf_moduledir=/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders \
	gdk_pixbuf_cache_file=/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache.librsvg
LIBRSVG_MAKE_OPTS += $(ML_RSVG_LOADER_PATHS)
LIBRSVG_INSTALL_STAGING_OPTS += $(ML_RSVG_LOADER_PATHS)
LIBRSVG_INSTALL_TARGET_OPTS += $(ML_RSVG_LOADER_PATHS)
