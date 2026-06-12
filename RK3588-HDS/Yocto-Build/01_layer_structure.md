# meta-hds 레이어 구조

## 전체 디렉토리 트리

```
meta-hds/
├── COPYING.MIT
├── README.md
│
├── conf/
│   ├── layer.conf                          ← 레이어 설정
│   ├── distro/
│   │   └── hds-distro.conf                 ← 배포판 설정
│   └── machine/
│       ├── rk3588-hds.conf                 ← RK3588 머신 설정
│       └── include/
│           └── hds-common.inc              ← 머신 공통 설정
│
├── recipes-bsp/
│   ├── u-boot/
│   │   ├── u-boot-hds_2017.09.bb          ← U-Boot 레시피
│   │   └── files/
│   │       ├── 0001-hds-board-support.patch
│   │       ├── hds-defconfig
│   │       └── package-file
│   │
│   └── rockchip-tools/
│       └── rockchip-tools_1.0.bb           ← afptool, rkImageMaker
│
├── recipes-kernel/
│   ├── linux/
│   │   ├── linux-hds_5.10.bb              ← 커널 레시피
│   │   └── files/
│   │       ├── rockchip_linux_defconfig
│   │       ├── rk3588-hds.dts
│   │       └── *.patch
│   │
│   └── kernel-modules/
│       └── hds-drivers_1.0.bb              ← 외부 커널 모듈 (DCI 등)
│
├── recipes-mcu/
│   └── sys-mcu/
│       ├── sys-mcu_1.0.bb                  ← MCU 펌웨어 레시피
│       └── files/
│           └── (MCU 소스 또는 pre-built)
│
├── recipes-support/
│   ├── rockchip-mpp/
│   │   └── rockchip-mpp_1.0.bb            ← MPP 라이브러리
│   ├── rockchip-rga/
│   │   └── rockchip-rga_2.0.bb            ← RGA 라이브러리
│   ├── rknn-runtime/
│   │   └── rknn-runtime_1.0.bb            ← RKNN AI 런타임
│   ├── hailo-runtime/
│   │   └── hailo-runtime_4.20.bb           ← Hailo NPU (선택)
│   ├── paho-mqtt/
│   │   └── paho-mqtt-c_1.3.bb             ← MQTT 클라이언트
│   ├── libvncserver/
│   │   └── libvncserver_0.9.bb
│   └── mali-gpu/
│       └── mali-gpu_1.0.bb                 ← Mali GPU 라이브러리
│
├── recipes-app/
│   └── hds-app/
│       ├── hds-app_1.0.bb                  ← HDS 메인 애플리케이션
│       ├── hds-app-conf_1.0.bb             ← 설정 파일, 리소스
│       └── files/
│           ├── hds-app.init                ← init 스크립트
│           └── hds-app.service             ← systemd 서비스 (선택)
│
├── recipes-image/
│   ├── hds-image.bb                        ← RootFS 이미지 (squashfs)
│   └── hds-image-firmware.bb               ← 최종 all 이미지 (mkimage multi)
│
├── recipes-core/
│   ├── packagegroups/
│   │   ├── packagegroup-hds-base.bb        ← 기본 시스템 패키지
│   │   ├── packagegroup-hds-media.bb       ← 미디어/그래픽 패키지
│   │   ├── packagegroup-hds-network.bb     ← 네트워크 패키지
│   │   └── packagegroup-hds-filesystem.bb  ← 파일시스템 도구
│   │
│   └── init-files/
│       └── hds-init-files_1.0.bb           ← /etc 초기 설정
│
├── recipes-qt/
│   └── qt5-hds/
│       └── qt5-hds-plugins_1.0.bb          ← Qt5 EGLFS 플러그인 설정
│
└── wic/
    └── hds-emmc.wks                        ← eMMC 파티션 레이아웃 (wic)
```

---

## layer.conf

```python
# meta-hds/conf/layer.conf

BBPATH .= ":${LAYERDIR}"
BBFILES += " \
    ${LAYERDIR}/recipes-*/*/*.bb \
    ${LAYERDIR}/recipes-*/*/*.bbappend \
"
BBFILE_COLLECTIONS += "hds"
BBFILE_PATTERN_hds = "^${LAYERDIR}/"
BBFILE_PRIORITY_hds = "10"

LAYERDEPENDS_hds = " \
    core \
    openembedded-layer \
    networking-layer \
    filesystems-layer \
    multimedia-layer \
    qt5-layer \
    rockchip \
"

LAYERSERIES_COMPAT_hds = "kirkstone scarthgap"
```

---

## 패키지 그룹 상세

### packagegroup-hds-base.bb

```bitbake
PACKAGES = "${PN}"
RDEPENDS:${PN} = " \
    base-files base-passwd busybox \
    glibc libstdc++ libgcc \
    zlib openssl libcrypto libssl \
    sqlite3 libcurl libxml2 expat \
    readline ncurses \
    udev eudev \
    util-linux-blkid util-linux-mount util-linux-sfdisk \
    gptfdisk \
"
```

### packagegroup-hds-media.bb

```bitbake
RDEPENDS:${PN} = " \
    libjpeg-turbo libpng \
    opencv-core opencv-imgproc \
    libdrm \
    alsa-lib alsa-utils \
    v4l-utils media-ctl \
    rockchip-mpp rockchip-rga \
    rknn-runtime \
    mali-gpu \
    libvncserver \
    qtbase qtdeclarative qtquickcontrols2 qtsvg \
    qtbase-plugins qtgraphicaleffects \
"
```

### packagegroup-hds-network.bb

```bitbake
RDEPENDS:${PN} = " \
    wpa-supplicant \
    curl \
    chrony \
    paho-mqtt-c \
    libnl libnl-genl \
    iptables \
"
```

### packagegroup-hds-filesystem.bb

```bitbake
RDEPENDS:${PN} = " \
    e2fsprogs e2fsprogs-mke2fs e2fsprogs-e2fsck \
    ntfs-3g ntfs-3g-ntfsprogs \
    dosfstools \
    exfat-utils fuse-exfat \
    fuse3 \
    squashfs-tools \
    mdadm \
    smartmontools \
"
```
