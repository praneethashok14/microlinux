################################################################################
#
# kde-elogind: logind without systemd (seats and sessions for KWin, polkit,
# SDDM and Plasma on BusyBox init)
#
################################################################################

KDE_ELOGIND_VERSION = 257.16
KDE_ELOGIND_SITE = https://github.com/elogind/elogind/archive/refs/tags
KDE_ELOGIND_SOURCE = v$(KDE_ELOGIND_VERSION).tar.gz
KDE_ELOGIND_LICENSE = LGPL-2.1+, GPL-2.0+
KDE_ELOGIND_LICENSE_FILES = LICENSE.LGPL2.1 LICENSE.GPL2
KDE_ELOGIND_INSTALL_STAGING = YES
KDE_ELOGIND_DEPENDENCIES = host-gperf host-python3 host-python-jinja2 libcap udev dbus linux-pam util-linux
KDE_ELOGIND_CONF_OPTS = \
	-Dmode=release -Dman=disabled -Dhtml=disabled -Dtests=false -Dtranslations=false \
	-Dpam=enabled -Dpamlibdir=/lib/security -Dpolkit=enabled -Dacl=disabled \
	-Dselinux=disabled -Dsmack=false -Daudit=disabled -Dxenctrl=disabled \
	-Dutmp=false -Defi=false -Ddefault-hierarchy=unified -Dcgroup-controller=elogind \
	-Dhalt-path=/sbin/halt -Dpoweroff-path=/sbin/poweroff -Dreboot-path=/sbin/reboot \
	-Dnologin-path=/sbin/nologin -Dbashcompletiondir=no -Dzshcompletiondir=no

define KDE_ELOGIND_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(KDE_ELOGIND_PKGDIR)/S45elogind $(TARGET_DIR)/etc/init.d/S45elogind
endef

$(eval $(meson-package))
