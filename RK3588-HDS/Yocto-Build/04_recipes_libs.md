# 라이브러리 레시피

> 현재 시스템에서 사용하는 외부 라이브러리의 Yocto 레시피.
> OE 코어/meta-oe에서 제공하는 것은 DEPENDS에 명시만 하면 되고,
> Rockchip 전용 또는 커스텀 라이브러리만 별도 레시피가 필요하다.

---

## 1. OE 제공 라이브러리 (레시피 불필요, DEPENDS만 추가)

```
# 시스템
zlib  openssl  sqlite3  curl  libxml2  expat  readline  ncurses  eudev

# 미디어
libjpeg-turbo  libpng  libdrm  alsa-lib  v4l-utils

# 네트워크
wpa-supplicant  chrony  libnl

# 파일시스템
e2fsprogs  ntfs-3g  dosfstools  fuse3  gptfdisk  squashfs-tools  mdadm

# 그래픽
freetype

# Qt5 (meta-qt5)
qtbase  qtdeclarative  qtquickcontrols2  qtsvg  qtgraphicaleffects

# OpenCV (meta-oe)
opencv
```

---

## 2. Rockchip MPP (미디어 처리)

```bitbake
# meta-hds/recipes-support/rockchip-mpp/rockchip-mpp_1.0.bb

SUMMARY = "Rockchip Media Process Platform (MPP)"
DESCRIPTION = "Hardware video encoder/decoder library for RK3588"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=..."

PROVIDES += "virtual/video-codec"

SRC_URI = "git://github.com/rockchip-linux/mpp.git;branch=develop;protocol=https"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

inherit cmake

EXTRA_OECMAKE = " \
    -DRKPLATFORM=ON \
    -DHAVE_DRM=ON \
"

DEPENDS = "libdrm"

FILES:${PN} = " \
    ${libdir}/librockchip_mpp.so.* \
    ${libdir}/librockchip_vpu.so.* \
"
FILES:${PN}-dev = " \
    ${includedir}/rockchip/ \
    ${libdir}/librockchip_mpp.so \
    ${libdir}/librockchip_vpu.so \
    ${libdir}/pkgconfig/ \
"
```

---

## 3. Rockchip RGA (2D 가속)

```bitbake
# meta-hds/recipes-support/rockchip-rga/rockchip-rga_2.0.bb

SUMMARY = "Rockchip RGA (Raster Graphic Acceleration)"
DESCRIPTION = "2D image processing: resize, crop, rotate, color convert"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=..."

PROVIDES += "virtual/image-processor"

SRC_URI = "git://github.com/AIT/linux-rga.git;branch=main;protocol=https"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

inherit cmake

DEPENDS = "libdrm"

FILES:${PN} = "${libdir}/librga.so.*"
FILES:${PN}-dev = "${includedir}/rga/ ${libdir}/librga.so"
```

---

## 4. Mali GPU

```bitbake
# meta-hds/recipes-support/mali-gpu/mali-gpu_1.0.bb

SUMMARY = "ARM Mali G610 GPU user-space driver"
DESCRIPTION = "OpenGL ES, EGL, Vulkan for RK3588 Mali G610 MP4"
LICENSE = "CLOSED"

PROVIDES += "virtual/egl virtual/libgles2 virtual/libgbm"

# Pre-built 바이너리 (ARM에서 제공)
SRC_URI = "file://mali-valhall-g610-${PV}-${TARGET_ARCH}.tar.gz"

do_install() {
    install -d ${D}${libdir}
    install -m 0644 ${S}/libmali.so.1 ${D}${libdir}/
    ln -sf libmali.so.1 ${D}${libdir}/libEGL.so.1
    ln -sf libmali.so.1 ${D}${libdir}/libGLESv2.so.2
    ln -sf libmali.so.1 ${D}${libdir}/libgbm.so.1

    install -d ${D}${includedir}
    cp -r ${S}/include/* ${D}${includedir}/
}

INSANE_SKIP:${PN} = "already-stripped ldflags"
FILES:${PN} = "${libdir}/*.so.*"
```

---

## 5. RKNN Runtime (NPU)

```bitbake
# meta-hds/recipes-support/rknn-runtime/rknn-runtime_1.0.bb

SUMMARY = "Rockchip NPU Runtime (RKNN)"
DESCRIPTION = "Neural network inference runtime for RK3588 NPU"
LICENSE = "CLOSED"

PROVIDES += "virtual/npu-runtime"

SRC_URI = "git://github.com/AIT/rknn-toolkit2.git;branch=master;protocol=https"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git/rknpu2/runtime/Linux/librknn_api"

do_install() {
    install -d ${D}${libdir}
    install -m 0644 ${S}/aarch64/librknnrt.so ${D}${libdir}/

    install -d ${D}${includedir}
    install -m 0644 ${S}/include/rknn_api.h ${D}${includedir}/

    # rknn_server 설치
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/git/rknpu2/runtime/Linux/rknn_server/aarch64/rknn_server ${D}${bindir}/
}

FILES:${PN} = "${libdir}/librknnrt.so ${bindir}/rknn_server"
FILES:${PN}-dev = "${includedir}/rknn_api.h"
INSANE_SKIP:${PN} = "already-stripped ldflags"
```

---

## 6. Hailo Runtime (선택, CONFIG_USE_HAILO)

```bitbake
# meta-hds/recipes-support/hailo-runtime/hailo-runtime_4.20.bb

SUMMARY = "Hailo-8 AI Accelerator Runtime"
LICENSE = "CLOSED"

PROVIDES += "virtual/npu-runtime-hailo"

SRC_URI = "https://hailo.ai/download/hailort-${PV}-aarch64.tar.gz"

do_install() {
    install -d ${D}${libdir}
    install -m 0644 ${S}/lib/libhailort.so.${PV} ${D}${libdir}/
    ln -sf libhailort.so.${PV} ${D}${libdir}/libhailort.so

    install -d ${D}${includedir}/hailo
    cp -r ${S}/include/* ${D}${includedir}/hailo/
}

FILES:${PN} = "${libdir}/libhailort.so.*"
INSANE_SKIP:${PN} = "already-stripped ldflags"
```

---

## 7. Paho MQTT 클라이언트

```bitbake
# meta-hds/recipes-support/paho-mqtt/paho-mqtt-c_1.3.bb

SUMMARY = "Eclipse Paho MQTT C Client Library"
LICENSE = "EPL-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=..."

SRC_URI = "git://github.com/eclipse/paho.mqtt.c.git;branch=master;protocol=https"
SRCREV = "v1.3.13"
S = "${WORKDIR}/git"

inherit cmake

EXTRA_OECMAKE = " \
    -DPAHO_WITH_SSL=ON \
    -DPAHO_BUILD_SHARED=ON \
    -DPAHO_BUILD_STATIC=OFF \
"

DEPENDS = "openssl"

FILES:${PN} = "${libdir}/libpaho-mqtt*.so.*"
```

---

## 8. libvncserver

```bitbake
# meta-hds/recipes-support/libvncserver/libvncserver_0.9.bb

SUMMARY = "VNC server library"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=..."

SRC_URI = "git://github.com/LibVNC/libvncserver.git;branch=master;protocol=https"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

inherit cmake

DEPENDS = "zlib libjpeg-turbo libpng openssl"

FILES:${PN} = "${libdir}/libvncserver.so.*"
```

---

## 9. 라이브러리 의존성 맵 (hds-app 기준)

```
hds-app
├── 공통: zlib  sqlite3  pthread  rt  libdrm  tinyxml2
├── recorder: (공통만)
├── rkctrl: rockchip-mpp  rockchip-rga  opencv  openssl  libjpeg-turbo
│           libpng  mali-gpu  rknn-runtime  libvncserver  gomp
├── osdQt: qtbase  qtdeclarative  freetype  libpng
├── network: curl
├── aimsc: paho-mqtt-c  curl
├── cicsman: paho-mqtt-c  curl
├── acmsc: curl  openssl
├── playback: alsa-lib
├── audioman: alsa-lib
├── ioman: (공통만)
├── diskman: (공통만)
└── monitor: (공통만)
```
