# HDS 애플리케이션 레시피

---

## 1. 메인 애플리케이션 레시피

```bitbake
# meta-hds/recipes-app/hds-app/hds-app_1.0.bb

SUMMARY = "HDS DVR/AI Application"
DESCRIPTION = "Multi-process DVR system with AI object detection, \
fleet management, and vehicle integration"
LICENSE = "CLOSED"

SRC_URI = " \
    git://github.com/AIT/app_hds.git;branch=main;protocol=https \
    file://hds-app.init \
    file://hds-app.service \
"
SRCREV = "${AUTOREV}"
S = "${WORKDIR}/git"

# ──────────────────────────────────────────────
# 의존성
# ──────────────────────────────────────────────
DEPENDS = " \
    zlib openssl sqlite3 libdrm libjpeg-turbo libpng \
    curl libxml2 \
    alsa-lib \
    opencv \
    freetype \
    paho-mqtt-c \
    libvncserver \
    tinyxml2 \
    virtual/video-codec \
    virtual/image-processor \
    virtual/egl \
    virtual/libgles2 \
    virtual/npu-runtime \
    qtbase qtdeclarative qtquickcontrols2 qtsvg \
"

# Hailo 지원 (선택)
DEPENDS += "${@bb.utils.contains('MACHINE_FEATURES', 'hailo', 'hailo-runtime', '', d)}"

# ──────────────────────────────────────────────
# 빌드 설정
# ──────────────────────────────────────────────

inherit qmake5_paths

# 현재 Makefile 시스템 그대로 사용
EXTRA_OEMAKE = " \
    CROSS_COMPILE=${TARGET_PREFIX} \
    SYSROOT=${STAGING_DIR_TARGET} \
    PREFIX_PATH=${STAGING_DIR_TARGET}/usr \
    INSTALL_DIR=${D}${HDS_APP_INSTALL_DIR} \
    LIB_INSTALL_DIR=${D}${HDS_LIB_INSTALL_DIR} \
    ${HDS_FEATURES} \
"

# 릴리즈 빌드
EXTRA_OEMAKE += "${@bb.utils.contains('IMAGE_FEATURES', 'debug-tweaks', '', 'build', d)}"

do_compile() {
    # 서브디렉토리 순서: res ipc flc lib src util
    oe_runmake install -j${BB_NUMBER_THREADS}
}

do_install() {
    # 바이너리
    install -d ${D}${HDS_APP_INSTALL_DIR}
    cp -r ${S}/bin/* ${D}${HDS_APP_INSTALL_DIR}/

    # 라이브러리
    install -d ${D}${HDS_LIB_INSTALL_DIR}
    if [ -d ${S}/bin/lib ]; then
        cp -r ${S}/bin/lib/* ${D}${HDS_LIB_INSTALL_DIR}/
    fi

    # 리소스 (웹, 이미지, 스크립트)
    install -d ${D}${HDS_APP_INSTALL_DIR}/res
    cp -r ${S}/res/* ${D}${HDS_APP_INSTALL_DIR}/res/ 2>/dev/null || true

    # init 스크립트
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/hds-app.init ${D}${sysconfdir}/init.d/hds-app

    # systemd 서비스 (선택)
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -m 0644 ${WORKDIR}/hds-app.service ${D}${systemd_unitdir}/system/
    fi

    # 버전 정보
    install -d ${D}/root
    echo "HDS-APP ${PV} ${DATETIME}" > ${D}/root/.release
}

inherit update-rc.d systemd

INITSCRIPT_NAME = "hds-app"
INITSCRIPT_PARAMS = "defaults 90"

SYSTEMD_SERVICE:${PN} = "hds-app.service"

# ──────────────────────────────────────────────
# 패키징
# ──────────────────────────────────────────────
FILES:${PN} = " \
    ${HDS_APP_INSTALL_DIR}/* \
    ${HDS_LIB_INSTALL_DIR}/* \
    ${sysconfdir}/init.d/* \
    ${systemd_unitdir}/system/* \
    /root/.release \
"

# 내부 라이브러리 RPATH 경고 무시
INSANE_SKIP:${PN} = "dev-so ldflags"

RDEPENDS:${PN} = " \
    packagegroup-hds-base \
    packagegroup-hds-media \
    packagegroup-hds-network \
    packagegroup-hds-filesystem \
"
```

---

## 2. init 스크립트

```bash
#!/bin/sh
# meta-hds/recipes-app/hds-app/files/hds-app.init

### BEGIN INIT INFO
# Provides:          hds-app
# Required-Start:    $local_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       HDS DVR/AI Application
### END INIT INFO

APP_DIR="/opt/app"
export LD_LIBRARY_PATH="/opt/lib:${APP_DIR}/lib:${LD_LIBRARY_PATH}"

case "$1" in
    start)
        echo "Starting HDS Application..."

        # 디바이스 노드 확인
        [ -c /dev/dci_menc ] || mknod /dev/dci_menc c 240 0
        [ -c /dev/ipc ] || mknod /dev/ipc c 241 0

        # 커널 모듈 로드
        modprobe dci_menc 2>/dev/null || true
        modprobe ait_ipc 2>/dev/null || true

        # RKNN 서버 시작
        if [ -x /usr/bin/rknn_server ]; then
            start-stop-daemon -S -b -x /usr/bin/rknn_server
        fi

        # Monitor 프로세스 시작 (나머지 프로세스는 Monitor가 관리)
        start-stop-daemon -S -b -x ${APP_DIR}/monitor
        ;;

    stop)
        echo "Stopping HDS Application..."
        # Monitor에 종료 신호
        start-stop-daemon -K -x ${APP_DIR}/monitor
        sleep 2
        # 잔여 프로세스 정리
        killall -q recorder rkctrl osdQt ioman diskman \
            playback network audioman aimsc 2>/dev/null
        ;;

    restart)
        $0 stop
        sleep 1
        $0 start
        ;;

    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
```

---

## 3. systemd 서비스

```ini
# meta-hds/recipes-app/hds-app/files/hds-app.service

[Unit]
Description=HDS DVR/AI Application
After=network.target local-fs.target
Requires=local-fs.target

[Service]
Type=forking
Environment=LD_LIBRARY_PATH=/opt/lib:/opt/app/lib
ExecStartPre=/sbin/modprobe dci_menc
ExecStartPre=/sbin/modprobe ait_ipc
ExecStart=/opt/app/monitor
ExecStop=/bin/killall monitor
Restart=always
RestartSec=5
WatchdogSec=60

[Install]
WantedBy=multi-user.target
```

---

## 4. 설정 파일 레시피

```bitbake
# meta-hds/recipes-app/hds-app/hds-app-conf_1.0.bb

SUMMARY = "HDS Application default configuration and resources"
LICENSE = "CLOSED"

SRC_URI = " \
    file://default_config.xml \
    file://hds_config.json \
    file://www/ \
    file://image/ \
    file://logo/ \
    file://scripts/ \
    file://qml/ \
"

do_install() {
    # 기본 설정
    install -d ${D}/mnt/doc
    install -m 0644 ${WORKDIR}/default_config.xml ${D}/mnt/doc/

    # 웹 인터페이스
    install -d ${D}/opt/app/www
    cp -r ${WORKDIR}/www/* ${D}/opt/app/www/

    # 부팅 로고
    install -d ${D}/opt/app/logo
    cp -r ${WORKDIR}/logo/* ${D}/opt/app/logo/ 2>/dev/null || true

    # 쉘 스크립트
    install -d ${D}/opt/app/scripts
    cp -r ${WORKDIR}/scripts/* ${D}/opt/app/scripts/ 2>/dev/null || true
    chmod +x ${D}/opt/app/scripts/*.sh 2>/dev/null || true
}

FILES:${PN} = "/mnt/doc/* /opt/app/www/* /opt/app/logo/* /opt/app/scripts/*"
```

---

## 5. 프로세스 목록 (hds-app에 포함)

빌드 시 `src/` 아래의 모든 프로세스가 컴파일되어 `/opt/app/`에 설치됨:

| 바이너리 | 소스 디렉토리 | 주요 LDFLAGS |
|----------|-------------|-------------|
| monitor | src/monitor/ | (기본) |
| recorder | src/recorder/ | (기본) |
| rkctrl | src/rkctrl/ | -lrockchip_mpp -lrga -lopencv_* -lrknnrt -lGLESv2 -ljpeg -lpng -lvncserver |
| osdQt | src/osdQt/ | -lQt5Core -lQt5Gui -lQt5Widgets -lQt5Quick -lQt5Qml -lfreetype |
| ioman | src/ioman/ | (기본) |
| diskman | src/diskman/ | (기본) |
| network | src/network/ | -lcurl |
| playback | src/playback/ | -lasound |
| audioman | src/audioman/ | -lasound |
| aimsc | src/aimsc/ | -lmqtt -lcurl |
| cicsman | src/cicsman/ | -lmqtt -lcurl |
| acmsc | src/acmsc/ | -lcurl -lcrypto -lssl |
| srsradar | src/srsradar/ | (기본) |

**공통 링크**: `-lait -lsqlite3 -lz -lpthread -lrt -ldrm -limf -lfilemanager -ltinyxml2`
