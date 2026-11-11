################################################################################
#
# firmware-amdgpu: GPU firmware from linux-firmware, as a repository package
#
################################################################################

# the same tarball as Buildroot's linux-firmware (downloaded once)
FIRMWARE_AMDGPU_VERSION = $(LINUX_FIRMWARE_VERSION)
FIRMWARE_AMDGPU_SOURCE = $(LINUX_FIRMWARE_SOURCE)
FIRMWARE_AMDGPU_SITE = $(LINUX_FIRMWARE_SITE)
FIRMWARE_AMDGPU_DL_SUBDIR = linux-firmware
FIRMWARE_AMDGPU_LICENSE = Redistributable firmware
FIRMWARE_AMDGPU_LICENSE_FILES = LICENSE.amdgpu LICENSE.radeon WHENCE
FIRMWARE_AMDGPU_REDISTRIBUTE = YES

FIRMWARE_AMDGPU_DIRS = amdgpu radeon
# not installed: matches this extended regex
FIRMWARE_AMDGPU_EXCLUDE = ^$$

# unpack only WHENCE, the licences and these directories (not all 1.7 GB)
define FIRMWARE_AMDGPU_EXTRACT_CMDS
	$(call suitable-extractor,$(FIRMWARE_AMDGPU_SOURCE)) $(FIRMWARE_AMDGPU_DL_DIR)/$(FIRMWARE_AMDGPU_SOURCE) | \
		$(TAR) --strip-components=1 -C $(@D) $(TAR_OPTIONS) - --wildcards \
		'*/WHENCE' '*/LICEN[CS]E.*' $(foreach d,$(FIRMWARE_AMDGPU_DIRS),'*/$(d)/*')
endef

# install the files and links that WHENCE lists for these directories
define FIRMWARE_AMDGPU_INSTALL_TARGET_CMDS
	cd $(@D) && awk -v dirs="$(FIRMWARE_AMDGPU_DIRS)" -v excl='$(FIRMWARE_AMDGPU_EXCLUDE)' ' \
		BEGIN { n = split(dirs, d, " ") } \
		/^(File|RawFile|Link): / { \
			p = $$2; ok = 0; \
			for (i = 1; i <= n; i++) if (index(p, d[i] "/") == 1) ok = 1; \
			if (!ok || p ~ excl) next; \
			if ($$1 == "Link:") print "L", p, $$4; else print "F", p }' WHENCE | \
	while read -r t f l; do \
		f=$$(echo "$$f" | tr -d '"'); \
		mkdir -p "$(TARGET_DIR)/lib/firmware/$$(dirname "$$f")"; \
		if [ "$$t" = F ]; then \
			cp "$$f" "$(TARGET_DIR)/lib/firmware/$$f" || exit 1; \
		else \
			ln -sfn "$$l" "$(TARGET_DIR)/lib/firmware/$$f"; \
		fi; \
	done
	$(foreach l,LICENSE.amdgpu LICENSE.radeon,$(INSTALL) -D -m 0644 $(@D)/$(l) $(TARGET_DIR)/lib/firmware/$(l)$(sep))
	find -L $(TARGET_DIR)/lib/firmware/amdgpu -type l -print | \
		{ if read -r x; then echo "broken firmware link: $$x"; exit 1; fi; }
endef

$(eval $(generic-package))
