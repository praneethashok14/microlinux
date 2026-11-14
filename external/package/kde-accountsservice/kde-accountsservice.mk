################################################################################
#
# kde-accountsservice: user accounts over D-Bus (SDDM's user list, Plasma's
# Users settings)
#
################################################################################

KDE_ACCOUNTSSERVICE_VERSION = 26.27.3
KDE_ACCOUNTSSERVICE_SITE = https://gitlab.freedesktop.org/accountsservice/accountsservice/-/archive/$(KDE_ACCOUNTSSERVICE_VERSION)
KDE_ACCOUNTSSERVICE_SOURCE = accountsservice-$(KDE_ACCOUNTSSERVICE_VERSION).tar.gz
KDE_ACCOUNTSSERVICE_LICENSE = GPL-3.0+
KDE_ACCOUNTSSERVICE_LICENSE_FILES = COPYING
KDE_ACCOUNTSSERVICE_INSTALL_STAGING = YES
KDE_ACCOUNTSSERVICE_DEPENDENCIES = libglib2 polkit dbus kde-elogind libxcrypt host-pkgconf
# administrators: the wheel group (sudo, /etc/sudoers.d/10-wheel)
KDE_ACCOUNTSSERVICE_CONF_OPTS = -Delogind=true -Dlibxcrypt=true -Dadmin_group=wheel \
	-Dintrospection=false -Dvapi=false -Ddocbook=false -Dgtk_doc=false -Dtests=false \
	-Dsystemdsystemunitdir=no -Dlightdmconffile=/etc/lightdm/lightdm.conf

$(eval $(meson-package))
