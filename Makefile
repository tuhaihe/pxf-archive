include common.mk

PXF_MODULES = external-table fdw cli server
export PXF_MODULES

PXF_VERSION ?= $(shell cat version)
export PXF_VERSION

FDW_SUPPORT = $(shell $(PG_CONFIG) --version | egrep "PostgreSQL 1[2-5]")
FDW_SUPPORT =

# variables that control whether the FDW extension will be built and packaged,
# if left empty there is no skipping, otherwise a value should contain a reason for skipping
ifeq ($(shell test $(GP_MAJORVERSION) -lt 6; echo $$?),0)
	SKIP_FDW_BUILD_REASON := "GPDB version $(GP_MAJORVERSION) is less than 6."
endif
ifeq ($(shell test $(GP_MAJORVERSION) -lt 7; echo $$?),0)
	SKIP_FDW_PACKAGE_REASON := "GPDB version $(GP_MAJORVERSION) is less than 7."
endif

ifeq ($(BLD_ARCH),)
	GP_BUILD_ARCH := $(PORTNAME)-$(subst _,-,$(host_cpu))
else
	GP_BUILD_ARCH := $(subst _,-,$(BLD_ARCH))
endif

export SKIP_FDW_BUILD_REASON
export SKIP_FDW_PACKAGE_REASON
export GP_MAJORVERSION
export GP_BUILD_ARCH

PXF_PACKAGE_NAME := pxf-gpdb$(GP_MAJORVERSION)-$(PXF_VERSION)-$(GP_BUILD_ARCH)
export PXF_PACKAGE_NAME

LICENSE ?= ASL 2.0
VENDOR ?= Open Source

default: all

.PHONY: all extensions external-table fdw cli server install install-server stage tar rpm rpm-tar deb deb-tar clean test it help

all: extensions cli server
	@echo "===> PXF compilation is complete <==="

extensions: external-table fdw

external-table cli server:
	@echo "===> Compiling [$@] module <==="
	make -C $@

fdw:
ifeq ($(SKIP_FDW_BUILD_REASON),)
	@echo "===> Compiling [$@] module <==="
	make -C fdw
else
	@echo "Skipping building FDW extension because $(SKIP_FDW_BUILD_REASON)"
endif

clean:
	rm -rf build
	set -e ;\
	for module in $${PXF_MODULES[@]}; do \
		echo "===> Cleaning [$${module}] module <===" ;\
		make -C $${module} clean-all ;\
	done ;\
	echo "===> PXF cleaning is complete <==="

test:
ifeq ($(SKIP_FDW_BUILD_REASON),)
	make -C fdw installcheck
else
	@echo "Skipping testing FDW extension because $(SKIP_FDW_BUILD_REASON)"
endif
	make -C cli test
	make -C server test

it:
	make -C automation TEST=$(TEST)

install:
ifneq ($(SKIP_FDW_BUILD_REASON),)
	@echo "Skipping installing FDW extension because $(SKIP_FDW_BUILD_REASON)"
	$(eval PXF_MODULES := $(filter-out fdw,$(PXF_MODULES)))
endif
	set -e ;\
	for module in $${PXF_MODULES[@]}; do \
		echo "===> Installing [$${module}] module <===" ;\
		make -C $${module} install ;\
	done ;\
	echo "===> PXF installation is complete <==="

install-server:
	make -C server install-server

stage:
	rm -rf build/stage
ifneq ($(SKIP_FDW_PACKAGE_REASON),)
	@echo "Skipping staging FDW extension because $(SKIP_FDW_PACKAGE_REASON)"
	$(eval PXF_MODULES := $(filter-out fdw,$(PXF_MODULES)))
endif
	set -e ;\
	GP_MAJOR_VERSION=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/gp_major_version) ;\
	GP_BUILD_ARCH=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/build_arch) ;\
	PXF_PACKAGE_NAME=pxf-cbdb$${GP_MAJOR_VERSION}-$${PXF_VERSION}-$${GP_BUILD_ARCH} ;\
	mkdir -p build/stage/$${PXF_PACKAGE_NAME} ;\
	cp -a $(SOURCE_EXTENSION_DIR)/build/stage/* build/stage/$${PXF_PACKAGE_NAME} ;\
	cp -a cli/build/stage/* build/stage/$${PXF_PACKAGE_NAME} ;\
	cp -a server/build/stage/* build/stage/$${PXF_PACKAGE_NAME} ;\
	echo $$(git rev-parse --verify HEAD) > build/stage/$${PXF_PACKAGE_NAME}/pxf/commit.sha ;\
	cp package/install_binary build/stage/$${PXF_PACKAGE_NAME}/install_component ;\
	echo "===> PXF staging is complete <==="

tar: stage
	rm -rf build/dist
	mkdir -p build/dist
	tar -czf build/dist/$(PXF_PACKAGE_NAME).tar.gz -C build/stage $(PXF_PACKAGE_NAME)
	echo "===> PXF TAR file with binaries creation is complete <==="

gppkg-rpm: rpm
	rm -rf gppkg
	mkdir -p gppkg/deps
	GP_MAJOR_VERSION=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/gp_major_version)
	cat package/gppkg_spec.yml.in | sed "s,#arch,`arch`," | sed "s,#os,$(TEST_OS)," | sed "s,#gppkgver,1.0," | sed "s,#gpver,1," > gppkg/gppkg_spec.yml
	find build/rpmbuild/RPMS -name pxf-cbdb$(GP_MAJOR_VERSION)-*.rpm -exec cp {} gppkg/ \;
	source $(GPHOME)/greenplum_path.sh && gppkg --build gppkg

gppkg-rpm: rpm
	rm -rf gppkg
	mkdir -p gppkg/deps
	GP_MAJOR_VERSION=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/gp_major_version)
	cat package/gppkg_spec.yml.in | sed "s,#arch,`arch`," | sed "s,#os,$(TEST_OS)," | sed "s,#gppkgver,1.0," | sed "s,#gpver,1," > gppkg/gppkg_spec.yml
	find build/rpmbuild/RPMS -name pxf-cbdb$(GP_MAJOR_VERSION)-*.rpm -exec cp {} gppkg/ \;
	source $(GPHOME)/greenplum_path.sh && gppkg --build gppkg

rpm:
	make -C $(SOURCE_EXTENSION_DIR) stage
	make -C cli/go/src/pxf-cli stage
	make -C server stage
	set -e ;\
	PXF_MAIN_VERSION=$${PXF_VERSION//-SNAPSHOT/} ;\
	if [[ $${PXF_VERSION} == *"-SNAPSHOT" ]]; then PXF_RELEASE=SNAPSHOT; else PXF_RELEASE=1; fi ;\
	mkdir -p build/rpmbuild/{BUILD,RPMS,SOURCES,SPECS} ;\
	cp -a build/stage/$${PXF_PACKAGE_NAME}/pxf/* build/rpmbuild/SOURCES ;\
	cp package/*.spec build/rpmbuild/SPECS/ ;\
	rpmbuild \
	--define "_topdir $${PWD}/build/rpmbuild" \
	--define "pxf_version $${PXF_MAIN_VERSION}" \
	--define "pxf_release $${PXF_RELEASE}" \
	--define "license ${LICENSE}" \
	--define "vendor ${VENDOR}" \
	-bb $${PWD}/build/rpmbuild/SPECS/pxf-cbdb$${GP_MAJOR_VERSION}.spec

rpm-tar: rpm
	rm -rf build/{stagerpm,distrpm}
	mkdir -p build/{stagerpm,distrpm}
	set -e ;\
	GP_MAJOR_VERSION=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/gp_major_version) ;\
	PXF_RPM_FILE=$$(find build/rpmbuild/RPMS -name pxf-cbdb$${GP_MAJOR_VERSION}-*.rpm) ;\
	PXF_RPM_BASE_NAME=$$(basename $${PXF_RPM_FILE%*.rpm}) ;\
	PXF_PACKAGE_NAME=$${PXF_RPM_BASE_NAME%.*} ;\
	mkdir -p build/stagerpm/$${PXF_PACKAGE_NAME} ;\
	cp $${PXF_RPM_FILE} build/stagerpm/$${PXF_PACKAGE_NAME} ;\
	cp package/install_rpm build/stagerpm/$${PXF_PACKAGE_NAME}/install_component ;\
	tar -czf build/distrpm/$${PXF_PACKAGE_NAME}.tar.gz -C build/stagerpm $${PXF_PACKAGE_NAME} ;\
	echo "===> PXF TAR file with RPM package creation is complete <==="

deb: stage
	rm -rf build/debbuild
	set -e ;\
	PXF_MAIN_VERSION=$${PXF_VERSION//-SNAPSHOT/} ;\
	if [[ $${PXF_VERSION} == *"-SNAPSHOT" ]]; then PXF_RELEASE=SNAPSHOT; else PXF_RELEASE=1; fi ;\
	rm -rf build/debbuild ;\
	mkdir -p build/debbuild/usr/local/pxf-cbdb$${GP_MAJOR_VERSION}/$(TARGET_EXTENSION_DIR) ;\
	cp -a $(SOURCE_EXTENSION_DIR)/build/stage/* build/debbuild/usr/local/pxf-cbdb$${GP_MAJOR_VERSION}/$(TARGET_EXTENSION_DIR) ;\
	cp -a cli/build/stage/pxf/* build/debbuild/usr/local/pxf-cbdb$${GP_MAJOR_VERSION} ;\
	cp -a server/build/stage/pxf/* build/debbuild/usr/local/pxf-cbdb$${GP_MAJOR_VERSION} ;\
	echo $$(git rev-parse --verify HEAD) > build/debbuild/usr/local/pxf-cbdb$${GP_MAJOR_VERSION}/commit.sha ;\
	mkdir build/debbuild/DEBIAN ;\
	cp -a package/DEBIAN/* build/debbuild/DEBIAN/ ;\
	sed -i -e "s/%VERSION%/$${PXF_MAIN_VERSION}-$${PXF_RELEASE}/" -e "s/%MAINTAINER%/${VENDOR}/" build/debbuild/DEBIAN/control ;\
	dpkg-deb --build build/debbuild ;\
	mv build/debbuild.deb build/pxf-cbdb$${GP_MAJOR_VERSION}-$${PXF_MAIN_VERSION}-$${PXF_RELEASE}-ubuntu18.04-amd64.deb

deb-tar: deb
	rm -rf build/{stagedeb,distdeb}
	mkdir -p build/{stagedeb,distdeb}
	set -e ;\
	GP_MAJOR_VERSION=$$(cat $(SOURCE_EXTENSION_DIR)/build/metadata/gp_major_version) ;\
	PXF_DEB_FILE=$$(find build/ -name pxf-cbdb$${GP_MAJOR_VERSION}*.deb) ;\
	PXF_PACKAGE_NAME=$$(dpkg-deb --field $${PXF_DEB_FILE} Package)-$$(dpkg-deb --field $${PXF_DEB_FILE} Version)-ubuntu18.04 ;\
	mkdir -p build/stagedeb/$${PXF_PACKAGE_NAME} ;\
	cp $${PXF_DEB_FILE} build/stagedeb/$${PXF_PACKAGE_NAME} ;\
	cp package/install_deb build/stagedeb/$${PXF_PACKAGE_NAME}/install_component ;\
	tar -czf build/distdeb/$${PXF_PACKAGE_NAME}.tar.gz -C build/stagedeb $${PXF_PACKAGE_NAME} ;\
	echo "===> PXF TAR file with DEB package creation is complete <==="


help:
	@echo
	@echo 'Possible targets'
	@echo	'  - all - build extensions, cli, and server modules'
	@echo	'  - extensions - build Greenplum external table and foreign data wrapper extensions'
	@echo	'  - external-table - build Greenplum external table extension'
	@echo	'  - fdw - build Greenplum foreign data wrapper extension'
	@echo	'  - cli - install Go CLI dependencies and build Go CLI'
	@echo	'  - server - install server dependencies and build server module'
	@echo	'  - clean - clean up external-table, fdw, CLI and server binaries'
	@echo	'  - test - runs tests for Go CLI and server'
	@echo	'  - install - install external table and foreign data wrapper extensions, CLI and server binaries'
	@echo	'  - install-server - install server binaries only without running tests'
	@echo	'  - stage - install external table and foreign data wrapper extensions, CLI, and server binaries into build/stage/pxf directory'
	@echo	'  - tar - bundle external table and foreign data wrapper extensions, CLI, and server into a single tarball'
	@echo	'  - rpm - create PXF RPM package'
	@echo	'  - rpm-tar - bundle PXF RPM package along with helper scripts into a single tarball'
	@echo	'  - deb - create PXF DEB package'
	@echo	'  - deb-tar - bundle PXF DEB package along with helper scripts into a single tarball'
