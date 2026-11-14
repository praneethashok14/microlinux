################################################################################
#
# kde-qcoro: C++ coroutines for Qt (used by Plasma and KDE apps)
#
################################################################################

KDE_QCORO_VERSION = 0.13.0
KDE_QCORO_SITE = https://github.com/qcoro/qcoro/archive/refs/tags
KDE_QCORO_SOURCE = v$(KDE_QCORO_VERSION).tar.gz
KDE_QCORO_LICENSE = MIT
KDE_QCORO_LICENSE_FILES = LICENSES/MIT.txt
KDE_QCORO_INSTALL_STAGING = YES
KDE_QCORO_DEPENDENCIES = qt6base qt6declarative
KDE_QCORO_CONF_OPTS = -DUSE_QT_VERSION=6 -DBUILD_TESTING=OFF -DQCORO_BUILD_EXAMPLES=OFF \
	-DQCORO_WITH_QTDBUS=ON -DQCORO_WITH_QTNETWORK=ON -DQCORO_WITH_QML=ON -DQCORO_WITH_QTQUICK=ON \
	-DQCORO_WITH_QTWEBSOCKETS=OFF -DQCORO_WITH_QTTEST=OFF

$(eval $(cmake-package))
