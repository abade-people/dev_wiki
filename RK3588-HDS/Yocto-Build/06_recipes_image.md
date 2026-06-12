# 이미지 레시피

> 현재 `make hds`의 최종 출력인 `hds_all.img`와 동일한 구조의 이미지를 생성한다.

---

## 1. RootFS 이미지 (hds-image.bb)

```bitbake
# meta-hds/recipes-image/hds-image.bb

SUMMARY = "HDS DVR/AI System Root Filesystem Image"
DESCRIPTION = "Complete rootfs with HDS application, drivers, and utilities"

LICENSE = "MIT"

inherit core-image

# ──────────────────────────────────────────────
# 이미지 포맷
# ──────────────────────────────────────────────
IMAGE_FSTYPES = "squashfs-lzo"

# squashfs 블록 크기 (현재 시스템과 동일)
EXTRA_IMAGECMD:squashfs-lzo = "-b 131072"

# ──────────────────────────────────────────────
# 패키지 구성
# ──────────────────────────────────────────────
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    packagegroup-hds-base \
    packagegroup-hds-media \
    packagegroup-hds-network \
    packagegroup-hds-filesystem \
    hds-app \
    hds-app-conf \
    hds-drivers \
    kernel-modules \
"

# RKNN 서버
IMAGE_INSTALL += "rknn-runtime"

# 디버그 (개발 빌드 시에만)
IMAGE_INSTALL += "${@bb.utils.contains('IMAGE_FEATURES', 'debug-tweaks', \
    'gdb strace ltrace', '', d)}"

# ──────────────────────────────────────────────
# 이미지 크기
# ──────────────────────────────────────────────
# squashfs는 압축이므로 크기 제한 불필요
# 예상 크기: 200~300MB (압축 전), 80~120MB (압축 후)

# ──────────────────────────────────────────────
# 이미지 후처리
# ──────────────────────────────────────────────
IMAGE_POSTPROCESS_COMMAND += "hds_rootfs_fixup;"

hds_rootfs_fixup() {
    # /opt/app 심링크 확인
    if [ ! -d ${IMAGE_ROOTFS}/opt/app ]; then
        bberror "HDS application not found in rootfs"
    fi

    # 디바이스 노드
    mknod -m 666 ${IMAGE_ROOTFS}/dev/dci_menc c 240 0 2>/dev/null || true
    mknod -m 666 ${IMAGE_ROOTFS}/dev/ipc c 241 0 2>/dev/null || true

    # tmp 디렉토리
    mkdir -p ${IMAGE_ROOTFS}/tmp
    mkdir -p ${IMAGE_ROOTFS}/mnt/doc
    mkdir -p ${IMAGE_ROOTFS}/mnt/main_storage

    # 버전 정보
    echo "HDS-ALL ${DISTRO_VERSION} ${DATETIME}" > ${IMAGE_ROOTFS}/root/.release
}
```

---

## 2. 최종 펌웨어 이미지 (hds-image-firmware.bb)

```bitbake
# meta-hds/recipes-image/hds-image-firmware.bb

SUMMARY = "HDS Complete Firmware Image (all-in-one)"
DESCRIPTION = "Combines U-Boot, Kernel, RootFS, and MCU into a single deployable image"

LICENSE = "MIT"

# 이 레시피는 다른 이미지/레시피에 의존
DEPENDS = "u-boot-hds linux-hds hds-image sys-mcu"

# do_rootfs를 실행하지 않음 (이미지 결합만)
inherit nopackages

do_compile[depends] = " \
    u-boot-hds:do_deploy \
    linux-hds:do_deploy \
    hds-image:do_image_complete \
    sys-mcu:do_deploy \
"

DEPLOY_DIR = "${DEPLOY_DIR_IMAGE}"

# ──────────────────────────────────────────────
# 서브 이미지 경로
# ──────────────────────────────────────────────
UBT_IMG = "${DEPLOY_DIR}/hds_ubt.img"
LNX_IMG = "${DEPLOY_DIR}/hds_lnx.img"
APP_IMG = "${DEPLOY_DIR}/hds-image-${MACHINE}.squashfs-lzo"
MCU_IMG = "${DEPLOY_DIR}/sys-mcu.img"

# ──────────────────────────────────────────────
# APP 이미지에 mkimage 헤더 추가
# ──────────────────────────────────────────────
do_create_app_img() {
    mkimage -A arm -O linux -T filesystem -C none \
        -n "HDS-APP-${DISTRO_VERSION}" \
        -d ${APP_IMG} \
        ${DEPLOY_DIR}/hds_app.img
}

# ──────────────────────────────────────────────
# 최종 multi 이미지 생성
# ──────────────────────────────────────────────
do_create_all_img() {
    # 서브 이미지 존재 확인
    for img in ${UBT_IMG} ${LNX_IMG} ${MCU_IMG}; do
        if [ ! -f "$img" ]; then
            bbfatal "Missing sub-image: $img"
        fi
    done

    if [ ! -f "${DEPLOY_DIR}/hds_app.img" ]; then
        bbfatal "Missing app image: ${DEPLOY_DIR}/hds_app.img"
    fi

    # mkimage -T multi: 4개 이미지를 하나로 결합
    # 형식: UBT:LNX:APP:MCU (콜론으로 구분)
    mkimage -A arm -O linux -T multi -C none \
        -a 0 -e 0 \
        -n "HDS-ALL-${DISTRO_VERSION}-${DATETIME}" \
        -d "${UBT_IMG}:${LNX_IMG}:${DEPLOY_DIR}/hds_app.img:${MCU_IMG}" \
        ${DEPLOY_DIR}/hds-all.img

    bbplain "========================================="
    bbplain "HDS Firmware Image: ${DEPLOY_DIR}/hds-all.img"
    bbplain "========================================="

    # 개별 이미지 크기 로그
    for img in ${UBT_IMG} ${LNX_IMG} ${DEPLOY_DIR}/hds_app.img ${MCU_IMG} ${DEPLOY_DIR}/hds-all.img; do
        if [ -f "$img" ]; then
            size=$(du -h "$img" | cut -f1)
            bbplain "  $(basename $img): $size"
        fi
    done
}

addtask create_app_img after do_compile before do_create_all_img
addtask create_all_img after do_create_app_img before do_build

# ──────────────────────────────────────────────
# OTA 업데이트용 개별 이미지도 배포
# ──────────────────────────────────────────────
do_deploy() {
    install -d ${DEPLOYDIR}
    # all 이미지 (전체 업데이트)
    install -m 0644 ${DEPLOY_DIR}/hds-all.img ${DEPLOYDIR}/
    # 개별 이미지 (부분 업데이트)
    install -m 0644 ${DEPLOY_DIR}/hds_app.img ${DEPLOYDIR}/
    install -m 0644 ${LNX_IMG} ${DEPLOYDIR}/
}
addtask deploy after do_create_all_img
```

---

## 3. eMMC 파티션 레이아웃 (WIC)

```
# meta-hds/wic/hds-emmc.wks
# Yocto WIC (Kickstart) 파일 — eMMC 직접 쓰기 이미지용
# 참고: 실제 HDS는 mkimage multi + u-boot 기반 파티셔닝 사용
#       이 파일은 개발/테스트용 SD 카드 이미지 생성 시 사용

# SPL + U-Boot (raw write)
part --source rawcopy --sourceparams="file=rk3588_spl_loader.bin" \
     --no-table --align 32 --size 4M

part u-boot --source rawcopy --sourceparams="file=u-boot.img" \
     --no-table --offset 4M --size 4M

# Kernel
part /boot --source bootimg-partition --fstype=ext4 \
     --label kernel --align 1024 --size 64M

# RootFS (SquashFS, 읽기 전용)
part / --source rootfs --fstype=squashfs-lzo \
     --label rootfs --align 1024

# Data 파티션 (설정, 로그)
part /mnt/doc --fstype=ext4 \
     --label data --align 1024 --size 64M

# 녹화 파티션 (나머지 전체)
part /mnt/main_storage --fstype=ext4 \
     --label storage --align 1024 --size 0 --grow
```

---

## 4. 빌드 출력 구조

```
tmp/deploy/images/rk3588-hds/
│
├── 최종 이미지
│   └── hds-all.img                  ← make hds의 hds_all_ksw.img과 동일
│
├── 서브 이미지
│   ├── hds_ubt.img                  ← U-Boot (SPL + U-Boot + RK 헤더)
│   ├── hds_lnx.img                  ← 커널 (Image + mkimage 헤더)
│   ├── hds_app.img                  ← RootFS (squashfs-lzo + mkimage 헤더)
│   └── sys-mcu.img                  ← MCU 펌웨어
│
├── 원본 파일
│   ├── Image                        ← 커널 바이너리
│   ├── rk3588-hds.dtb               ← Device Tree
│   ├── u-boot.img                   ← U-Boot 바이너리
│   ├── rk3588_spl_loader.bin        ← SPL 로더
│   └── hds-image-rk3588-hds.squashfs-lzo  ← RootFS
│
└── 개발용
    ├── hds-image-rk3588-hds.manifest  ← 패키지 목록
    └── modules-rk3588-hds.tgz        ← 커널 모듈
```

---

## 5. 현재 시스템과의 대응

| make hds 단계 | Yocto 레시피 | 출력 |
|--------------|-------------|------|
| `make -C micom/sys_mcu.hds img` | `bitbake sys-mcu` | sys-mcu.img |
| `make -C bios/u-boot.hds image` | `bitbake u-boot-hds` | hds_ubt.img |
| `make -C kernel/linux.hds image` | `bitbake linux-hds` | hds_lnx.img |
| `make -C app/app.hds image` | `bitbake hds-image` | squashfs-lzo |
| `mkimage -T multi` | `bitbake hds-image-firmware` | hds-all.img |
| **`make hds` (전체)** | **`bitbake hds-image-firmware`** | **hds-all.img** |
