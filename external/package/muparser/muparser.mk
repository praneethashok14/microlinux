################################################################################
#
# muparser
#
################################################################################

MUPARSER_VERSION = 2.3.5
MUPARSER_SITE = $(call github,beltoforion,muparser,v$(MUPARSER_VERSION))
MUPARSER_LICENSE = BSD-2-Clause
MUPARSER_LICENSE_FILES = LICENSE
MUPARSER_INSTALL_STAGING = YES
MUPARSER_CONF_OPTS = -DENABLE_SAMPLES=OFF -DENABLE_OPENMP=OFF -DBUILD_TESTING=OFF

$(eval $(cmake-package))
