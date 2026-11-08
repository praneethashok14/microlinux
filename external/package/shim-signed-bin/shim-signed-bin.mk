################################################################################
#
# shim-signed-bin: Microsoft-signed shim and signed MOK Manager from Debian 13
#
################################################################################

SHIM_SIGNED_BIN_VERSION = 16.1
SHIM_SIGNED_BIN_SITE = https://deb.debian.org/debian/pool/main/s/shim-signed
SHIM_SIGNED_BIN_SOURCE = shim-signed_1.51~1+deb13u1+16.1-2~deb13u1_amd64.deb
SHIM_SIGNED_BIN_HELPERS = shim-helpers-amd64-signed_1+16.1+2~deb13u1_amd64.deb
SHIM_SIGNED_BIN_EXTRA_DOWNLOADS = \
	https://deb.debian.org/debian/pool/main/s/shim-helpers-amd64-signed/$(SHIM_SIGNED_BIN_HELPERS)
SHIM_SIGNED_BIN_LICENSE = BSD-2-Clause
SHIM_SIGNED_BIN_INSTALL_TARGET = NO
SHIM_SIGNED_BIN_INSTALL_IMAGES = YES

# .deb = ar archive with data.tar.*; take the signed EFI binaries
define SHIM_SIGNED_BIN_EXTRACT_CMDS
	for d in $(SHIM_SIGNED_BIN_SOURCE) $(SHIM_SIGNED_BIN_HELPERS); do \
		mkdir -p $(@D)/x && cd $(@D)/x && rm -f data.tar.* && \
		ar x $(SHIM_SIGNED_BIN_DL_DIR)/$$d && tar xf data.tar.* -C $(@D) ./usr/lib/shim || exit 1; \
	done
endef

define SHIM_SIGNED_BIN_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/usr/lib/shim/shimx64.efi.signed $(BINARIES_DIR)/shim/shimx64.efi
	$(INSTALL) -D -m 0644 $(@D)/usr/lib/shim/mmx64.efi.signed $(BINARIES_DIR)/shim/mmx64.efi
endef

$(eval $(generic-package))
