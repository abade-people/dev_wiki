# 머신 설정

## rk3588-hds.conf

```python
# meta-hds/conf/machine/rk3588-hds.conf
#
# RK3588 HDS DVR/AI 시스템 머신 설정
# SoC 교체 시 이 파일을 새 머신 설정으로 교체한다.

#@TYPE: Machine
#@NAME: RK3588 HDS
#@DESCRIPTION: RK3588-based HDS DVR/AI System

require include/hds-common.inc

# ──────────────────────────────────────────────
# SoC / 아키텍처
# ──────────────────────────────────────────────
SOC_FAMILY = "rk3588"
require conf/machine/include/arm/armv8a/tune-cortexa76-cortexa55.inc

DEFAULTTUNE = "cortexa76-cortexa55"

# ──────────────────────────────────────────────
# 부트로더
# ──────────────────────────────────────────────
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-hds"
PREFERRED_VERSION_virtual/bootloader = "2017.09"

UBOOT_MACHINE = "rk3588_hds_defconfig"
UBOOT_BINARY = "u-boot.img"
SPL_BINARY = "rk3588_spl_loader.bin"

# Rockchip SPL/TPL
RK_LOADER_BIN = "rk3588_spl_loader_v1.18.113.bin"

# ──────────────────────────────────────────────
# 커널
# ──────────────────────────────────────────────
PREFERRED_PROVIDER_virtual/kernel = "linux-hds"
PREFERRED_VERSION_virtual/kernel = "5.10%"

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = "rockchip/rk3588-hds.dtb"
KERNEL_DEFCONFIG = "rockchip_linux_defconfig"

# 커널 모듈 자동 설치
MACHINE_EXTRA_RRECOMMENDS += "kernel-modules"
MACHINE_EXTRA_RRECOMMENDS += "hds-drivers"

# ──────────────────────────────────────────────
# 미디어 하드웨어 (HAL)
# ──────────────────────────────────────────────
# 비디오 인코딩/디코딩: Rockchip MPP
PREFERRED_PROVIDER_virtual/video-codec = "rockchip-mpp"
# 2D 가속: Rockchip RGA
PREFERRED_PROVIDER_virtual/image-processor = "rockchip-rga"
# GPU: Mali G610
PREFERRED_PROVIDER_virtual/egl = "mali-gpu"
PREFERRED_PROVIDER_virtual/libgles2 = "mali-gpu"
# AI/NPU: RKNN
PREFERRED_PROVIDER_virtual/npu-runtime = "rknn-runtime"

# ──────────────────────────────────────────────
# 디스플레이
# ──────────────────────────────────────────────
# DRM/KMS 기반
MACHINE_FEATURES += "screen gpu"

# Qt5 EGLFS 플랫폼
QT_QPA_DEFAULT_PLATFORM = "eglfs"
QT_QPA_EGLFS_INTEGRATION = "eglfs_kms"

# ──────────────────────────────────────────────
# 시리얼 콘솔
# ──────────────────────────────────────────────
SERIAL_CONSOLES = "1500000;ttyFIQ0"

# ──────────────────────────────────────────────
# 이미지 포맷
# ──────────────────────────────────────────────
IMAGE_FSTYPES = "squashfs-lzo"

# mkimage 로드 주소
UBOOT_MKIMAGE_LOADADDR = "0x00400000"

# ──────────────────────────────────────────────
# MCU
# ──────────────────────────────────────────────
MCU_FIRMWARE = "sys-mcu"
MCU_CROSS_COMPILE = "arm-none-eabi-"

# ──────────────────────────────────────────────
# 머신 기능
# ──────────────────────────────────────────────
MACHINE_FEATURES += " \
    can \
    gps \
    gsensor \
    gpio \
    uart \
    watchdog \
    npu \
    hdmi \
    emmc \
    wifi \
    alsa \
"

# eMMC 파티션 (A/B 슬롯)
HDS_EMMC_PARTITIONS = "yes"
HDS_AB_BOOT = "yes"
```

---

## hds-common.inc (머신 공통)

```python
# meta-hds/conf/machine/include/hds-common.inc
#
# SoC 무관한 HDS 공통 머신 설정

# ──────────────────────────────────────────────
# HDS 프로젝트 설정
# ──────────────────────────────────────────────
HDS_PROJECT_NAME = "hds"
HDS_MAX_CHANNELS = "16"
HDS_HDS_CHANNELS = "4"

# ──────────────────────────────────────────────
# 앱 설정
# ──────────────────────────────────────────────
HDS_APP_INSTALL_DIR = "/opt/app"
HDS_LIB_INSTALL_DIR = "/opt/lib"
HDS_CONFIG_DIR = "/mnt/doc"
HDS_TMP_DIR = "/tmp"

# ──────────────────────────────────────────────
# UART 장치 매핑
# ──────────────────────────────────────────────
HDS_MCU_DEVICE = "/dev/ttyS1"
HDS_GPS_DEVICE = "/dev/ttyS4"

# ──────────────────────────────────────────────
# 기능 토글 (CONFIG_* → Yocto DISTRO_FEATURES)
# ──────────────────────────────────────────────
# 이 값들은 hds-app 레시피의 EXTRA_OEMAKE로 전달됨
HDS_FEATURES = " \
    CONFIG_HDS=y \
    CONFIG_SUPPORT_AIMSC=y \
    CONFIG_PARTITION_IN_MMC=y \
    CONFIG_HDMI_PARALLEL=y \
    CONFIG_USE_MULTI_INITRD=y \
    CONFIG_SUPPORT_PANIC_RECORD=y \
    CONFIG_PARKING_RECORD_MODE=y \
    CONFIG_USE_RAW_FILE_SYSTEM=y \
    CONFIG_DEFAULT_FILESYSTEM_EXT4=y \
    CONFIG_USE_WRITE_BUFFER=y \
"
```

---

## SoC 교체 시 새 머신 설정 예시

### Raspberry Pi 5 (`rpi5-hds.conf`)

```python
# meta-hds/conf/machine/rpi5-hds.conf

require include/hds-common.inc
require conf/machine/include/arm/armv8a/tune-cortexa76.inc

SOC_FAMILY = "bcm2712"
DEFAULTTUNE = "cortexa76"

PREFERRED_PROVIDER_virtual/bootloader = "u-boot-rpi"
PREFERRED_PROVIDER_virtual/kernel = "linux-raspberrypi"
PREFERRED_VERSION_virtual/kernel = "6.6%"

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = "broadcom/bcm2712-rpi-5-b.dtb"

# HAL 대체
PREFERRED_PROVIDER_virtual/video-codec = "v4l2-codec"     # V4L2 M2M
PREFERRED_PROVIDER_virtual/image-processor = "opencv-hal"  # 소프트웨어
PREFERRED_PROVIDER_virtual/egl = "mesa"
PREFERRED_PROVIDER_virtual/libgles2 = "mesa"
PREFERRED_PROVIDER_virtual/npu-runtime = "tflite-runtime"  # TensorFlow Lite

SERIAL_CONSOLES = "115200;ttyAMA0"
IMAGE_FSTYPES = "squashfs-lzo"

MACHINE_FEATURES += "screen gpu wifi bluetooth can"

# RPi 고유: GPU 메모리, 카메라 인터페이스
GPU_MEM = "256"
ENABLE_UART = "1"
```

### Qualcomm QCS6490 (`qcs6490-hds.conf`)

```python
# meta-hds/conf/machine/qcs6490-hds.conf

require include/hds-common.inc
require conf/machine/include/arm/armv8-2a/tune-cortexa55.inc

SOC_FAMILY = "qcs6490"

PREFERRED_PROVIDER_virtual/video-codec = "qcom-mm-video"
PREFERRED_PROVIDER_virtual/image-processor = "adreno-gpu"
PREFERRED_PROVIDER_virtual/npu-runtime = "snpe-runtime"

# Qualcomm BSP
PREFERRED_PROVIDER_virtual/kernel = "linux-qcom"
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-qcom"
```
