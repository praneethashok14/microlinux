################################################################################
#
# kde-common: CMake options of every KDE package (scripts/kde-gen.py)
#
################################################################################

# no tests, API docs, Python bindings or translations (MicroLinux is in
# English); host tools that cross builds need (kconfig_compiler, ...) come from
# the host packages in $(HOST_DIR) (KF6_HOST_TOOLING)
KDE_CONF_OPTS = \
	-DBUILD_TESTING=OFF \
	-DBUILD_QCH=OFF \
	-DBUILD_DOC=OFF \
	-DBUILD_PYTHON_BINDINGS=OFF \
	-DKF_SKIP_PO_PROCESSING=ON \
	-DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
	-DKF6_HOST_TOOLING=$(HOST_DIR)/lib/cmake
