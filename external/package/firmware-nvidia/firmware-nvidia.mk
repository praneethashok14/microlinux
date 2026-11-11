################################################################################
#
# firmware-nvidia: GPU firmware from linux-firmware, as a repository package
#
################################################################################

# the same tarball as Buildroot's linux-firmware (downloaded once)
FIRMWARE_NVIDIA_VERSION = $(LINUX_FIRMWARE_VERSION)
FIRMWARE_NVIDIA_SOURCE = $(LINUX_FIRMWARE_SOURCE)
FIRMWARE_NVIDIA_SITE = $(LINUX_FIRMWARE_SITE)
FIRMWARE_NVIDIA_DL_SUBDIR = linux-firmware
FIRMWARE_NVIDIA_LICENSE = Redistributable firmware
FIRMWARE_NVIDIA_LICENSE_FILES = LICENCE.nvidia WHENCE
FIRMWARE_NVIDIA_REDISTRIBUTE = YES

FIRMWARE_NVIDIA_DIRS = nvidia
# not installed: matches this extended regex
FIRMWARE_NVIDIA_EXCLUDE = ^nvidia/(tegra|gk20a|gm20b|gp10b)|-535\\.113\\.01\\.bin$$

# unpack only WHENCE, the licences and these directories (not all 1.7 GB)
define FIRMWARE_NVIDIA_EXTRACT_CMDS
	$(call suitable-extractor,$(FIRMWARE_NVIDIA_SOURCE)) $(FIRMWARE_NVIDIA_DL_DIR)/$(FIRMWARE_NVIDIA_SOURCE) | \
		$(TAR) --strip-components=1 -C $(@D) $(TAR_OPTIONS) - --wildcards \
		'*/WHENCE' '*/LICEN[CS]E.*' $(foreach d,$(FIRMWARE_NVIDIA_DIRS),'*/$(d)/*')
endef

# install the files and links that WHENCE lists for these directories
define FIRMWARE_NVIDIA_INSTALL_TARGET_CMDS
	cd $(@D) && awk -v dirs="$(FIRMWARE_NVIDIA_DIRS)" -v excl='$(FIRMWARE_NVIDIA_EXCLUDE)' ' \
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
	$(foreach l,LICENCE.nvidia,$(INSTALL) -D -m 0644 $(@D)/$(l) $(TARGET_DIR)/lib/firmware/$(l)$(sep))
	find -L $(TARGET_DIR)/lib/firmware/nvidia -type l -print | \
		{ if read -r x; then echo "broken firmware link: $$x"; exit 1; fi; }
endef

$(eval $(generic-package))
