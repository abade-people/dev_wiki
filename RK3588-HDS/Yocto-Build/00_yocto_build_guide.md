# HDS DVR/AI 시스템 — Yocto 빌드 가이드

## 1. 목적

RK3588 기반 HDS DVR/AI 시스템의 전체 펌웨어를 Yocto Project로 빌드한다.
현재 커스텀 Makefile 빌드 시스템(`make hds`)과 **동일한 출력 이미지**를 생성하되,
Yocto의 레이어 구조를 활용하여 **SoC 교체 시 BSP 레이어만 변경**하면 되도록 설계한다.

---

## 2. 현재 빌드 시스템 요약

```
make hds → 4개 서브 이미지 빌드 → mkimage -T multi로 통합

[1] MCU:    micom/sys_mcu.hds  → hds_mcu.img    (arm-none-eabi-)
[2] U-Boot: bios/u-boot.hds   → hds_ubt.img    (aarch64-rk3588-linux-gnu-)
[3] Kernel: kernel/linux.hds   → hds_lnx.img    (aarch64-rk3588-linux-gnu-)
[4] App+RootFS: app/app.hds   → hds_app.img    (aarch64-rk3588-linux-gnu-)
                                    └── mksquashfs -comp lzo

최종: hds_all.img = UBT:LNX:APP:MCU (mkimage -T multi)
```

---

## 3. Yocto 구성 개요

### 3.1 레이어 구조

```
poky/                            ← Yocto 기본
meta-openembedded/               ← OE 공통 레이어
meta-qt5/                        ← Qt5 지원
meta-rockchip/                   ← RK3588 BSP (SoC 교체 시 이 레이어만 변경)
meta-hds/                        ← HDS 프로젝트 레이어 (이 문서에서 정의)
```

### 3.2 문서 목록

| 파일 | 내용 |
|------|------|
| `00_yocto_build_guide.md` | 이 문서 (전체 가이드) |
| `01_layer_structure.md` | meta-hds 레이어 디렉토리/파일 전체 구조 |
| `02_machine_conf.md` | 머신 설정 (rk3588-hds.conf) |
| `03_recipes_bsp.md` | BSP 레시피 (u-boot, kernel, MCU) |
| `04_recipes_libs.md` | 라이브러리 레시피 (MPP, RGA, RKNN, MQTT 등) |
| `05_recipes_app.md` | HDS 애플리케이션 레시피 |
| `06_recipes_image.md` | 이미지 레시피 (rootfs + all 이미지) |
| `07_distro_conf.md` | 배포판 설정 및 빌드 환경 |
| `08_soc_porting_guide.md` | SoC 교체 시 변경 가이드 |

---

## 4. 빠른 시작

### 4.1 환경 구축

```bash
# 1. Yocto 소스 가져오기
git clone git://git.yoctoproject.org/poky -b kirkstone
cd poky
git clone git://git.openembedded.org/meta-openembedded -b kirkstone
git clone https://github.com/pimlie/meta-qt5.git -b kirkstone
git clone https://github.com/pimlie/meta-rockchip.git -b kirkstone

# 2. meta-hds 레이어 추가
# (01_layer_structure.md 참조하여 생성)

# 3. 빌드 환경 초기화
source oe-init-build-env build-hds

# 4. bblayers.conf에 레이어 추가
bitbake-layers add-layer ../meta-openembedded/meta-oe
bitbake-layers add-layer ../meta-openembedded/meta-python
bitbake-layers add-layer ../meta-openembedded/meta-networking
bitbake-layers add-layer ../meta-openembedded/meta-filesystems
bitbake-layers add-layer ../meta-openembedded/meta-multimedia
bitbake-layers add-layer ../meta-qt5
bitbake-layers add-layer ../meta-rockchip
bitbake-layers add-layer ../meta-hds

# 5. local.conf 설정
echo 'MACHINE = "rk3588-hds"' >> conf/local.conf
echo 'DISTRO = "hds-distro"' >> conf/local.conf

# 6. 빌드 실행
bitbake hds-image-firmware
```

### 4.2 빌드 출력

```
tmp/deploy/images/rk3588-hds/
├── hds-image-firmware-rk3588-hds.rootfs.squashfs-lzo  ← RootFS
├── Image                                               ← 커널
├── rk3588-hds.dtb                                      ← DTB
├── u-boot.img                                          ← U-Boot
├── sys-mcu.img                                         ← MCU
└── hds-all.img                                         ← 최종 통합 이미지
```

---

## 5. 현재 시스템 → Yocto 매핑

| 현재 (make hds) | Yocto 레시피 | 비고 |
|-----------------|-------------|------|
| `micom/sys_mcu.hds` | `recipes-mcu/sys-mcu` | external toolchain (arm-none-eabi) |
| `bios/u-boot-2017.09` | `recipes-bsp/u-boot/u-boot-hds` | SPL + U-Boot + afptool |
| `kernel/linux-5.10` | `recipes-kernel/linux/linux-hds` | rockchip_linux_defconfig |
| `kernel/driver_v1` | `recipes-kernel/kernel-modules/hds-drivers` | 외부 커널 모듈 |
| `app/app_hds` | `recipes-app/hds-app` | 13+ 프로세스 |
| `initrd/rootfs.hds` | `recipes-image/hds-image` | Yocto가 자동 생성 |
| `config/Makefile.rv3k` | `hds-image-firmware.bb` | mkimage -T multi |
| 크로스 컴파일러 | Yocto SDK 자동 생성 | aarch64 |

---

## 6. 의존성 패키지 전체 목록

### 6.1 시스템 라이브러리 (meta-oe에서 제공)

```
zlib  openssl  sqlite3  curl  libxml2  expat  readline  ncurses
libudev  kmod  util-linux(blkid, mount, uuid)
libnl  libinput  libevdev  libv4l  libiio
```

### 6.2 미디어/그래픽 (meta-multimedia, meta-rockchip)

```
libjpeg-turbo  libpng  opencv(core, imgproc)
libdrm  mali-gpu(libmali)  mesa(GLESv2)
alsa-lib  alsa-utils(amixer, aplay)
libvncserver
```

### 6.3 Rockchip 전용 (meta-rockchip 또는 meta-hds)

```
rockchip-mpp(librockchip_mpp, librockchip_vpu)
rockchip-rga(librga)
rknn-runtime(librknnrt)  rknn-server
```

### 6.4 AI 가속기 (선택)

```
hailo-runtime(libhailort)    ← CONFIG_USE_HAILO 시
```

### 6.5 Qt5 (meta-qt5)

```
qtbase  qtdeclarative(qml, quick)  qtgraphicaleffects
qtquickcontrols2  qtsvg
- EGLFS 플랫폼 플러그인 필수
```

### 6.6 네트워크/파일시스템 도구

```
wpa-supplicant  curl  ntpd(chrony)
ntfs-3g  e2fsprogs  dosfstools  exfat-utils  fuse3
sgdisk(gptfdisk)  smartmontools  mdadm
```

### 6.7 내부 라이브러리 (app_hds 내 빌드)

```
libait(AitApp)  libtinyxml2  libimf  libmqtt  libfilemanager
```
