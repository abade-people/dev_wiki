# BSP 레시피 (U-Boot, Kernel, MCU)

---

## 1. U-Boot 레시피

```bitbake
# meta-hds/recipes-bsp/u-boot/u-boot-hds_2017.09.bb

SUMMARY = "U-Boot for HDS RK3588 platform"
DESCRIPTION = "U-Boot bootloader with A/B slot support and HDS board configuration"

require recipes-bsp/u-boot/u-boot.inc

PROVIDES += "virtual/bootloader"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://Licenses/README;md5=..."

SRC_URI = " \
    git://github.com/AIT/u-boot.git;branch=hds;protocol=https \
    file://0001-hds-board-support.patch \
    file://hds-defconfig \
    file://package-file \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

DEPENDS += "rockchip-tools-native"

# Rockchip SPL 로더 (pre-built)
SRC_URI += "file://rk3588_spl_loader_v1.18.113.bin"

do_configure:prepend() {
    cp ${WORKDIR}/hds-defconfig ${S}/configs/rk3588_hds_defconfig
}

UBOOT_MACHINE = "rk3588_hds_defconfig"

do_compile:append() {
    # Rockchip 이미지 생성 (make.sh 로직)
    ${S}/scripts/make.sh

    # afptool로 최종 패키징
    afptool -pack ${WORKDIR}/package-file ${B}/u-boot-all.img
    rkImageMaker -RK3588 ${WORKDIR}/${RK_LOADER_BIN} \
        ${B}/u-boot-all.img ${B}/hds_ubt.img -os_type:firmware
}

do_deploy:append() {
    install -m 0644 ${B}/hds_ubt.img ${DEPLOYDIR}/
    install -m 0644 ${WORKDIR}/${RK_LOADER_BIN} ${DEPLOYDIR}/
}
```

### U-Boot 핵심 설정

| 항목 | 값 |
|------|-----|
| 소스 버전 | u-boot-2017.09 |
| defconfig | rk3588_hds_defconfig |
| 보드 파일 | bios/board_v1/hds/ (bd_conf, cmd_update, board) |
| A/B 슬롯 | do_bootr() — partition 필드 기반 슬롯 선택 |
| 부트 복구 | boot_count/boot_state 메커니즘 (BOOT_COUNT_LIMIT=5) |
| 출력 | hds_ubt.img (SPL + U-Boot + Rockchip 헤더) |

---

## 2. 커널 레시피

```bitbake
# meta-hds/recipes-kernel/linux/linux-hds_5.10.bb

SUMMARY = "Linux kernel for HDS RK3588 platform"
DESCRIPTION = "Linux 5.10 with RK3588 SoC support, DCI driver, and HDS board DTS"

require recipes-kernel/linux/linux-yocto.inc

PROVIDES += "virtual/kernel"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=..."

SRC_URI = " \
    git://github.com/AIT/linux-rk3588.git;branch=hds-5.10;protocol=https \
    file://rockchip_linux_defconfig \
    file://rk3588-hds.dts \
    file://0001-dci-menc-driver.patch \
    file://0002-hds-ipc-driver.patch \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

LINUX_VERSION = "5.10"
LINUX_VERSION_EXTENSION = "-hds"

COMPATIBLE_MACHINE = "rk3588-hds"

# 커널 설정
KERNEL_DEFCONFIG = "rockchip_linux_defconfig"

# DTS
KERNEL_DEVICETREE = "rockchip/rk3588-hds.dtb"

# 모듈 스트립 (용량 절약)
KERNEL_MODULE_STRIP = "1"

do_configure:prepend() {
    cp ${WORKDIR}/rockchip_linux_defconfig ${S}/arch/arm64/configs/
    # 커스텀 DTS 복사
    cp ${WORKDIR}/rk3588-hds.dts ${S}/arch/arm64/boot/dts/rockchip/
}

# mkimage 헤더 추가 (U-Boot 호환)
do_deploy:append() {
    mkimage -A arm -O linux -T kernel -C none \
        -a ${UBOOT_MKIMAGE_LOADADDR} -e ${UBOOT_MKIMAGE_LOADADDR} \
        -n "HDS-LNX" \
        -d ${DEPLOYDIR}/Image \
        ${DEPLOYDIR}/hds_lnx.img
}
```

### 커널 핵심 설정

| 항목 | 값 |
|------|-----|
| 커널 버전 | 5.10 |
| 아키텍처 | arm64 (ARCH=arm64) |
| defconfig | rockchip_linux_defconfig |
| DTS | rk3588-hds.dts (arch/arm64/boot/dts/rockchip/) |
| 로드 주소 | 0x00400000 |
| 출력 | Image → mkimage → hds_lnx.img |

### 필수 커널 옵션 (defconfig에 포함)

```
# DCI 드라이버 (커스텀)
CONFIG_DCI_MENC=y

# IPC 드라이버 (커스텀)
CONFIG_AIT_IPC=y

# V4L2 카메라
CONFIG_VIDEO_V4L2=y
CONFIG_VIDEO_ROCKCHIP=y

# DRM 디스플레이
CONFIG_DRM=y
CONFIG_DRM_ROCKCHIP=y

# GPIO
CONFIG_GPIOLIB=y
CONFIG_GPIO_SYSFS=y

# CAN Bus
CONFIG_CAN=y
CONFIG_CAN_RAW=y

# 워치독
CONFIG_WATCHDOG=y
CONFIG_DW_WATCHDOG=y

# 파일시스템
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_LZO=y
CONFIG_EXT4_FS=y
CONFIG_NTFS3_FS=y
CONFIG_FUSE_FS=y

# eMMC
CONFIG_MMC=y
CONFIG_MMC_DW=y
CONFIG_MMC_DW_ROCKCHIP=y
```

---

## 3. 외부 커널 모듈 레시피

```bitbake
# meta-hds/recipes-kernel/kernel-modules/hds-drivers_1.0.bb

SUMMARY = "HDS external kernel drivers (DCI, IPC)"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=..."

inherit module

SRC_URI = " \
    git://github.com/AIT/hds-drivers.git;branch=main;protocol=https \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

RPROVIDES:${PN} += "kernel-module-dci-menc kernel-module-ait-ipc"

# 커널 빌드 디렉토리 자동 참조 (inherit module)
```

---

## 4. MCU 펌웨어 레시피

```bitbake
# meta-hds/recipes-mcu/sys-mcu/sys-mcu_1.0.bb

SUMMARY = "HDS MCU firmware (ARM Cortex-M4)"
DESCRIPTION = "Microcontroller firmware for peripheral control"
LICENSE = "CLOSED"

# arm-none-eabi 툴체인 (native 빌드)
DEPENDS += "gcc-arm-none-eabi-native"

SRC_URI = " \
    git://github.com/AIT/sys-mcu.git;branch=hds;protocol=https \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

# MCU는 타겟 아키텍처가 아닌 별도 아키텍처
INHIBIT_DEFAULT_DEPS = "1"

EXTRA_OEMAKE = " \
    CROSS_COMPILE=arm-none-eabi- \
    BOARD=hds \
"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}/opt/firmware
    install -m 0644 ${B}/sys_mcu.bin ${D}/opt/firmware/
}

do_deploy() {
    install -d ${DEPLOYDIR}
    mkimage -A arm -O linux -T firmware -C none \
        -n "HDS-MCU" \
        -d ${B}/sys_mcu.bin \
        ${DEPLOYDIR}/sys-mcu.img
}

addtask deploy after do_install

FILES:${PN} = "/opt/firmware/*"
```

---

## 5. Rockchip 도구 (네이티브)

```bitbake
# meta-hds/recipes-bsp/rockchip-tools/rockchip-tools-native_1.0.bb

SUMMARY = "Rockchip firmware packaging tools"
LICENSE = "CLOSED"

inherit native

SRC_URI = " \
    file://afptool \
    file://rkImageMaker \
"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/afptool ${D}${bindir}/
    install -m 0755 ${WORKDIR}/rkImageMaker ${D}${bindir}/
}
```
