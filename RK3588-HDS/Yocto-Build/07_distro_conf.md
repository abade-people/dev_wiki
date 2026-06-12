# 배포판 설정 및 빌드 환경

---

## 1. 배포판 설정 (hds-distro.conf)

```python
# meta-hds/conf/distro/hds-distro.conf

DISTRO = "hds-distro"
DISTRO_NAME = "HDS DVR/AI System"
DISTRO_VERSION = "1.0"
DISTRO_CODENAME = "hds"

# ──────────────────────────────────────────────
# 기본 설정
# ──────────────────────────────────────────────
DISTRO_FEATURES = " \
    alsa \
    bluetooth \
    ext2 \
    ipv4 \
    ipv6 \
    usbhost \
    wifi \
    systemd \
    pam \
    opengl \
    wayland \
"

# systemd를 기본 init으로
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
VIRTUAL-RUNTIME_init_manager = "systemd"
VIRTUAL-RUNTIME_initscripts = "systemd-compat-units"

# ──────────────────────────────────────────────
# 툴체인
# ──────────────────────────────────────────────
# Yocto 내부 툴체인 사용 (aarch64-poky-linux)
# 또는 외부 툴체인 지정 가능:
# TCMODE = "external-arm"
# EXTERNAL_TOOLCHAIN = "/opt/toolchain/aarch64-rk3588-linux-gnu"

# C/C++ 표준
GCCVERSION = "12.%"

# ──────────────────────────────────────────────
# 최적화
# ──────────────────────────────────────────────
# 릴리즈 빌드 최적화
FULL_OPTIMIZATION = "-O2 -pipe ${DEBUG_FLAGS}"
DEBUG_BUILD = "0"

# ──────────────────────────────────────────────
# 패키지 관리
# ──────────────────────────────────────────────
# IPK 사용 (용량 절약)
PACKAGE_CLASSES = "package_ipk"

# ──────────────────────────────────────────────
# 이미지 설정
# ──────────────────────────────────────────────
# 읽기 전용 rootfs (squashfs)
IMAGE_FEATURES += "read-only-rootfs"

# 로캘 최소화 (용량 절약)
IMAGE_LINGUAS = ""
GLIBC_GENERATE_LOCALES = ""

# ──────────────────────────────────────────────
# Qt5 설정
# ──────────────────────────────────────────────
# EGLFS 플랫폼 기본
QT_QPA_DEFAULT_PLATFORM = "eglfs"

# Qt5 OpenGL ES2 사용
PACKAGECONFIG:append:pn-qtbase = " gles2 eglfs"
PACKAGECONFIG:remove:pn-qtbase = "tests examples"

# ──────────────────────────────────────────────
# OpenCV 설정
# ──────────────────────────────────────────────
# 필요한 모듈만 빌드 (core, imgproc)
PACKAGECONFIG:pn-opencv = "core imgproc"

# ──────────────────────────────────────────────
# 보안
# ──────────────────────────────────────────────
# SSH 비활성화 (제품)
EXTRA_IMAGE_FEATURES:remove = "ssh-server-openssh"

# ──────────────────────────────────────────────
# 버전 관리
# ──────────────────────────────────────────────
# 이미지 이름에 날짜 포함
IMAGE_VERSION_SUFFIX = "-${DATETIME}"
```

---

## 2. local.conf 설정

```python
# build-hds/conf/local.conf

# 머신 및 배포판
MACHINE = "rk3588-hds"
DISTRO = "hds-distro"

# 빌드 병렬도
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j8"

# 다운로드/캐시 경로
DL_DIR = "${TOPDIR}/../downloads"
SSTATE_DIR = "${TOPDIR}/../sstate-cache"

# TMPDIR (빌드 출력)
TMPDIR = "${TOPDIR}/tmp"

# 라이선스 허용
LICENSE_FLAGS_ACCEPTED = "commercial"

# 개발 빌드 옵션 (릴리즈 시 제거)
EXTRA_IMAGE_FEATURES ?= "debug-tweaks"

# 디스크 모니터
BB_DISKMON_DIRS = "\
    STOPTASKS,${TMPDIR},1G,100K \
    STOPTASKS,${DL_DIR},1G,100K \
    STOPTASKS,${SSTATE_DIR},1G,100K \
"
```

---

## 3. bblayers.conf

```python
# build-hds/conf/bblayers.conf

BBLAYERS ?= " \
    /path/to/poky/meta \
    /path/to/poky/meta-poky \
    /path/to/poky/meta-yocto-bsp \
    /path/to/meta-openembedded/meta-oe \
    /path/to/meta-openembedded/meta-python \
    /path/to/meta-openembedded/meta-networking \
    /path/to/meta-openembedded/meta-filesystems \
    /path/to/meta-openembedded/meta-multimedia \
    /path/to/meta-qt5 \
    /path/to/meta-rockchip \
    /path/to/meta-hds \
"
```

---

## 4. SDK 생성

개발자용 크로스 컴파일 SDK 생성:

```bash
# SDK 생성 (app 개발자 배포용)
bitbake hds-image -c populate_sdk

# 설치
./tmp/deploy/sdk/hds-distro-*-toolchain-*.sh

# 사용
source /opt/hds-distro/*/environment-setup-aarch64-poky-linux
$CC -o myapp myapp.c $(pkg-config --cflags --libs sqlite3 libcurl)
```

---

## 5. 빌드 명령어 요약

```bash
# 전체 펌웨어 빌드 (= make hds)
bitbake hds-image-firmware

# 개별 컴포넌트
bitbake u-boot-hds          # U-Boot만
bitbake linux-hds            # 커널만
bitbake hds-app              # 앱만
bitbake hds-image            # RootFS만
bitbake sys-mcu              # MCU만

# 클린 빌드
bitbake hds-app -c cleansstate
bitbake hds-image-firmware

# SDK 생성
bitbake hds-image -c populate_sdk

# 패키지 검색
bitbake-layers show-recipes "*opencv*"

# 의존성 확인
bitbake -g hds-image-firmware
```

---

## 6. CI/CD 연동

```yaml
# .gitlab-ci.yml 예시

stages:
  - build
  - deploy

build-firmware:
  stage: build
  script:
    - source oe-init-build-env build-hds
    - bitbake hds-image-firmware
  artifacts:
    paths:
      - build-hds/tmp/deploy/images/rk3588-hds/hds-all.img
    expire_in: 7 days

deploy-ota:
  stage: deploy
  script:
    - aws s3 cp build-hds/tmp/deploy/images/rk3588-hds/hds-all.img \
        s3://hds-firmware/releases/${CI_COMMIT_TAG}/
  only:
    - tags
```
