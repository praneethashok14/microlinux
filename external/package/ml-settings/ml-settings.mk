################################################################################
#
# ml-settings: the MicroLinux settings application (source in src/)
#
################################################################################

ML_SETTINGS_VERSION = 1.0
ML_SETTINGS_SITE = $(BR2_EXTERNAL_MICROLINUX_PATH)/package/ml-settings/src
ML_SETTINGS_SITE_METHOD = local
ML_SETTINGS_LICENSE = MIT
ML_SETTINGS_DEPENDENCIES = host-pkgconf libgtk3 alsa-lib

define ML_SETTINGS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=gnu11 -Wall \
		-o $(@D)/ml-settings $(@D)/ml-settings.c \
		$$($(PKG_CONFIG_HOST_BINARY) --cflags --libs gtk+-3.0 alsa)
endef

define ML_SETTINGS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ml-settings $(TARGET_DIR)/usr/bin/ml-settings
	$(INSTALL) -D -m 0755 $(@D)/ml-askpass $(TARGET_DIR)/usr/libexec/ml-askpass
	$(INSTALL) -D -m 0644 $(@D)/ml-settings.desktop $(TARGET_DIR)/usr/share/applications/ml-settings.desktop
endef

$(eval $(generic-package))
