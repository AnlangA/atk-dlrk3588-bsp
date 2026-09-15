# SPDX-License-Identifier: GPL-2.0-only
# Entry points for the ATK-DLRK3588 out-of-tree BSP. Every target is a thin
# wrapper around a script in scripts/; run the scripts directly for options.

.PHONY: all fetch prepare linux uboot app check qemu package deploy deploy-app \
        display display-sysroot display-detect check-display deploy-display test-display \
        flash-uboot export-patches clean distclean help

all: linux uboot app

fetch:
	scripts/fetch.sh $(FETCH_TARGETS)

prepare:
	scripts/prepare.sh linux
	scripts/prepare.sh u-boot

linux:
	scripts/build-linux.sh $(LINUX_TARGETS)

uboot:
	scripts/build-uboot.sh $(UBOOT_TARGETS)

app:
	scripts/build-app.sh

display:
	scripts/build-display.sh

display-sysroot:
	scripts/display-sysroot.sh

display-detect:
	scripts/detect-display.sh

check-display:
	scripts/check-display.sh

deploy-display:
	scripts/deploy-display.sh $(DISPLAY_DEPLOY_ARGS)

test-display:
	scripts/test-display.sh $(DISPLAY_TEST_ARGS)

check:
	scripts/check.sh

qemu:
	scripts/test-qemu.sh

package:
	scripts/package.sh

deploy:
	scripts/deploy-board.sh $(DEPLOY_ARGS)

deploy-app:
	scripts/deploy-app.sh $(DEPLOY_ARGS)

flash-uboot:
	scripts/flash-uboot.sh $(FLASH_ARGS)

export-patches:
	scripts/export-patches.sh linux
	scripts/export-patches.sh u-boot

clean:
	rm -rf build

distclean: clean
	rm -rf external

help:
	@echo 'make fetch          fetch Linux $(LINUX_TAG), U-Boot $(UBOOT_TAG), rkbin and Ubuntu Base $(UBUNTU_BASE_VERSION) into external/'
	@echo '                    FETCH_TARGETS="ubuntu-base" selects only Ubuntu Base'
	@echo 'make linux          patch + configure + build kernel, out-of-tree modules and DTB'
	@echo 'make uboot          patch + build U-Boot with the derived DDR blob and BL31'
	@echo 'make app            cross-build rs485-test and driver-test-init (no kernel needed)'
	@echo 'make display        cross-build the Slint DRM/KMS dashboard'
	@echo 'make display-sysroot copy target development libraries from BOARD_HOST'
	@echo 'make display-detect read the MIPI panel ID resistor via board IIO'
	@echo 'make check-display  native Slint formatting, Clippy and tests'
	@echo 'make deploy-display install/start the non-root Slint service over SSH'
	@echo 'make test-display   verify Mali execution, AFBC scanout and GPU capture (DISPLAY_TEST_ARGS=--touch to inject input)'
	@echo 'make check          shell/python syntax, rustfmt, clippy and host tests'
	@echo 'make qemu           run the module lifecycle tests in QEMU'
	@echo 'make package        assemble build/deploy/ payload and tarball'
	@echo 'make deploy         install the payload on the board over SSH (BOARD_HOST)'
	@echo 'make deploy-app     install only rs485-test on the board (DEPLOY_ARGS=--check to test it)'
	@echo 'make flash-uboot    FLASH_ARGS="--board|--sd /dev/sdX|--maskrom"'
	@echo 'make export-patches regenerate */patches from the prepared source trees'

include manifest.env
