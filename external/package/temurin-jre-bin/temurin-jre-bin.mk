################################################################################
#
# temurin-jre-bin: Eclipse Temurin Java runtimes (OpenJDK), as repository
# packages openjdk-25-jre, openjdk-21-jre, openjdk-17-jre and openjdk-8-jre
#
################################################################################

# Minecraft: 26.1+ Java 25, 1.20.5-1.21.x Java 21, 1.17-1.20.4 Java 17,
# older Java 8. Mounted at /opt/openjdk-<N>-jre, where Prism Launcher finds them.
TEMURIN_JRE_BIN_RELEASES = 25:25.0.5+8 21:21.0.13+9 17:17.0.21+9 8:8u512-b09
TEMURIN_JRE_BIN_ARCH = $(if $(BR2_aarch64),aarch64,x64)

# 25.0.5+8 -> jdk-25.0.5+8 / 25.0.5_8; 8u512-b09 -> jdk8u512-b09 / 8u512b09
temurin-tag = $(if $(filter 8,$(1)),jdk$(2),jdk-$(2))
temurin-file = OpenJDK$(1)U-jre_$(TEMURIN_JRE_BIN_ARCH)_linux_hotspot_$(if $(filter 8,$(1)),$(subst -,,$(2)),$(subst +,_,$(2))).tar.gz
temurin-url = https://github.com/adoptium/temurin$(1)-binaries/releases/download/$(subst +,%2B,$(call temurin-tag,$(1),$(2)))/$(call temurin-file,$(1),$(2))
temurin-major = $(firstword $(subst :, ,$(1)))
temurin-ver = $(lastword $(subst :, ,$(1)))

TEMURIN_JRE_BIN_VERSION = 25.0.5
TEMURIN_JRE_BIN_SOURCE =
TEMURIN_JRE_BIN_EXTRA_DOWNLOADS = $(foreach r,$(TEMURIN_JRE_BIN_RELEASES),\
	$(call temurin-url,$(call temurin-major,$(r)),$(call temurin-ver,$(r))))
TEMURIN_JRE_BIN_LICENSE = GPL-2.0 with Classpath exception
TEMURIN_JRE_BIN_INSTALL_TARGET = NO
TEMURIN_JRE_BIN_INSTALL_IMAGES = YES

define TEMURIN_JRE_BIN_EXTRACT_ONE
	mkdir -p $(@D)/$(1)
	$(TAR) -xzf $(TEMURIN_JRE_BIN_DL_DIR)/$(call temurin-file,$(1),$(2)) --strip-components=1 -C $(@D)/$(1)
endef

define TEMURIN_JRE_BIN_EXTRACT_CMDS
	$(foreach r,$(TEMURIN_JRE_BIN_RELEASES),$(call TEMURIN_JRE_BIN_EXTRACT_ONE,$(call temurin-major,$(r)),$(call temurin-ver,$(r)))$(sep))
endef

# one image package per Java version; "java<N>" in the PATH, and "java" for
# the newest
define TEMURIN_JRE_BIN_INSTALL_IMAGES_CMDS
	$(foreach r,$(TEMURIN_JRE_BIN_RELEASES),$(call TEMURIN_JRE_BIN_PKG,$(call temurin-major,$(r)),$(call temurin-ver,$(r)))$(sep))
endef

define TEMURIN_JRE_BIN_PKG
	rm -rf $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre
	mkdir -p $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre/.mlpkg
	cp -a $(@D)/$(1)/. $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre/
	printf '#!/bin/sh\nexec /opt/openjdk-$(1)-jre/bin/java "$$@"\n' > $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre/java$(1)
	chmod 0755 $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre/java$(1)
	printf 'name=openjdk-$(1)-jre\nversion=%s\nmountpoint=/opt/openjdk-$(1)-jre\nbin=java$(1)$(if $(filter 25,$(1)), bin/java)\ndescription=Java $(1) runtime (Eclipse Temurin OpenJDK $(2))\nlicense=GPL-2.0 with Classpath exception\ncategory=Development\nbuilddeps=alsa-lib xlib_libxtst xlib_libxi xlib_libxrender xlib_libxext freetype fontconfig\n' \
		'$(subst +,.,$(subst -,.,$(2)))' > $(BINARIES_DIR)/pkgroot-repo/openjdk-$(1)-jre/.mlpkg/info
endef

$(eval $(generic-package))
