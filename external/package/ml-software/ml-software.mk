################################################################################
#
# ml-software: MicroLinux Software, the package browser (source in src/)
#
################################################################################

ML_SOFTWARE_VERSION = 1.1
ML_SOFTWARE_SITE = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/ml-software/src
ML_SOFTWARE_SITE_METHOD = local
ML_SOFTWARE_LICENSE = MIT
ML_SOFTWARE_DEPENDENCIES = host-pkgconf libgtk3 ml-settings

define ML_SOFTWARE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=gnu11 -Wall \
		-o $(@D)/ml-software $(@D)/ml-software.c \
		$$($(PKG_CONFIG_HOST_BINARY) --cflags --libs gtk+-3.0)
endef

define ML_SOFTWARE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ml-software $(TARGET_DIR)/usr/bin/ml-software
	$(INSTALL) -D -m 0644 $(@D)/ml-software.desktop $(TARGET_DIR)/usr/share/applications/ml-software.desktop
	$(INSTALL) -D -m 0755 $(@D)/ml-deb-install $(TARGET_DIR)/usr/libexec/ml-deb-install
	$(INSTALL) -D -m 0644 $(@D)/ml-deb-install.desktop $(TARGET_DIR)/usr/share/applications/ml-deb-install.desktop
	$(INSTALL) -D -m 0644 $(@D)/mimeapps.list $(TARGET_DIR)/usr/share/applications/mimeapps.list
endef

$(eval $(generic-package))
