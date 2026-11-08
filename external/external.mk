include $(sort $(wildcard $(BR2_EXTERNAL_MICROLINUX_PATH)/package/*/*.mk))

# libfm (Vala-generated code) and pcmanfm mix related GObject pointer types;
# GCC 14 turned -Wincompatible-pointer-types into an error.
LIBFM_CONF_ENV += CFLAGS="$(TARGET_CFLAGS) -Wno-error=incompatible-pointer-types"
PCMANFM_CONF_ENV += CFLAGS="$(TARGET_CFLAGS) -Wno-error=incompatible-pointer-types"

# No GPU drivers in the image: build Xorg without glamor. Otherwise the
# modesetting driver references GBM symbols that only glamor provides, and
# with Buildroot's -z now (full RELRO) it fails to load ("no screens found").
XSERVER_XORG_SERVER_CONF_OPTS += --disable-glamor

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
