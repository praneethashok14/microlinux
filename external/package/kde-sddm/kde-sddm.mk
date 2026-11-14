################################################################################
#
# kde-sddm: SDDM, the login screen of the KDE edition (Qt 6, elogind, PAM)
#
################################################################################

KDE_SDDM_VERSION = 0.21.0
KDE_SDDM_SITE = https://github.com/sddm/sddm/archive/refs/tags
KDE_SDDM_SOURCE = v$(KDE_SDDM_VERSION).tar.gz
KDE_SDDM_LICENSE = GPL-2.0+, CC-BY-3.0 (themes)
KDE_SDDM_LICENSE_FILES = LICENSE LICENSE.CC-BY-3.0
KDE_SDDM_DEPENDENCIES = qt6base qt6declarative host-qt6tools linux-pam libxcb libxkbcommon kde-elogind \
	kf6-extra-cmake-modules host-pkgconf
KDE_SDDM_CONF_OPTS = -DBUILD_WITH_QT6=ON -DNO_SYSTEMD=ON -DUSE_ELOGIND=ON -DENABLE_JOURNALD=OFF \
	-DBUILD_MAN_PAGES=OFF -DRUNTIME_DIR=/run/sddm -DUID_MIN=1000

define KDE_SDDM_USERS
	sddm -1 sddm -1 * /var/lib/sddm - video SDDM login screen
endef

define KDE_SDDM_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(KDE_SDDM_PKGDIR)/S95sddm $(TARGET_DIR)/etc/init.d/S95sddm
endef

$(eval $(cmake-package))
