# HDS RK3588 전체 이미지 빌드 가이드

## 1. 개요

HDS DVR/AI 시스템의 전체 빌드 파이프라인을 설명한다.
빌드는 크게 **Yocto 빌드** (Host OS 이미지)와 **App 빌드** (컨테이너 애플리케이션)로 나뉜다.

### 빌드 아키텍처

```
┌──────────────────────────────────────────────────────────┐
│  Docker (ubuntu:22.04)                                   │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Yocto 빌드 (docker-compose.yml)                    │ │
│  │                                                     │ │
│  │  bitbake hds-image                                  │ │
│  │    ├── U-Boot   (idbloader.img + u-boot.itb)        │ │
│  │    ├── Kernel   (fitImage + rk3588-hds.dtb)         │ │
│  │    ├── RootFS   (ext4: systemd + containerd + ...)  │ │
│  │    └── WIC      (통합 이미지: GPT + 부트로더 + FS)  │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  App 빌드 (docker-compose.app.yml)                  │ │
│  │                                                     │ │
│  │  Yocto SDK (aarch64 크로스 컴파일러)                │ │
│  │    ├── HAL      (libhds_hal.a)                      │ │
│  │    └── App      (9 ELF + 11 lib)                    │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌───────────────────┐
              │  eMMC / SD 카드    │
              │  (타겟 보드)       │
              └───────────────────┘
```

### 최종 산출물

| 산출물 | 크기 | 설명 |
|---|---|---|
| `hds-image-rk3588-hds.rootfs.wic.gz` | ~184MB | **통합 이미지** (GPT + 부트로더 + 5 파티션) |
| `idbloader.img` | 200KB | Rockchip 1차 부트로더 (TPL+SPL) |
| `u-boot.itb` | 1.3MB | U-Boot + ATF + TEE (FIT 포맷) |
| `fitImage` | 13MB | 커널 + DTB (FIT 포맷) |
| `rk3588-hds.dtb` | 75KB | Device Tree Blob (단독) |
| `hds-image-rk3588-hds.rootfs.ext4` | ~1.1GB | RootFS (단독 ext4) |
| `hds-uboot-env.txt` | 6KB | U-Boot OTA 환경변수 |
| `modules-rk3588-hds.tgz` | 43MB | 커널 모듈 아카이브 |

---

## 2. 사전 준비

### 2.1 호스트 PC 요구 사항

| 항목 | 최소 | 권장 |
|---|---|---|
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |
| RAM | 8GB | 16GB 이상 |
| 디스크 | 100GB 여유 | 200GB 이상 (SSD 권장) |
| CPU | 4코어 | 8코어 이상 |
| Docker | 20.10+ | 최신 안정 버전 |

### 2.2 Docker 설치

```bash
# Docker 설치 (이미 설치된 경우 생략)
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
# 로그아웃/재로그인 필요
```

### 2.3 프로젝트 디렉토리 구조

```
/media/ksw/dev/new_dev/rk3588/
├── docker/
│   ├── Dockerfile              ← Yocto 빌드 컨테이너 정의
│   ├── docker-compose.yml      ← Yocto 빌드 실행
│   ├── Dockerfile.app          ← App 크로스 빌드 컨테이너
│   ├── docker-compose.app.yml  ← App 빌드 실행
│   └── app-build-entry.sh      ← App 빌드 엔트리포인트
├── yocto/
│   ├── sources/                ← Yocto 레이어 소스
│   │   ├── poky/               ← (meta, meta-poky, meta-yocto-bsp)
│   │   ├── meta-openembedded/  ← (meta-oe, meta-python, meta-networking, meta-filesystems)
│   │   ├── meta-arm/           ← (meta-arm, meta-arm-toolchain)
│   │   ├── meta-security/
│   │   ├── meta-virtualization/
│   │   ├── meta-rockchip/
│   │   └── meta-hds/           ← HDS 커스텀 레이어
│   ├── build/conf/
│   │   ├── local.conf          ← 빌드 설정
│   │   └── bblayers.conf       ← 레이어 목록
│   ├── downloads/              ← 소스 다운로드 캐시
│   └── sstate-cache/           ← 빌드 상태 캐시
├── hal/                        ← HAL 소스 (libhds_hal.a)
├── app/                        ← App 소스 (11개 모듈)
└── scripts/
    ├── build-app.sh            ← App 빌드 래퍼
    ├── flash-emmc.sh           ← eMMC 플래싱
    └── flash-sdcard.sh         ← SD 카드 플래싱
```

---

## 3. Yocto 빌드 (Host OS 이미지)

### 3.1 Docker 빌드 컨테이너 생성 (최초 1회)

```bash
cd /media/ksw/dev/new_dev/rk3588/docker
docker compose build
```

컨테이너 환경:
- 베이스: Ubuntu 22.04
- Yocto 필수 패키지 사전 설치
- `builder` 유저 (UID:GID 1000:1000)
- 메모리 제한: 12GB + 스왑 20GB
- 호스트 네트워크 사용 (소스 다운로드)

### 3.2 전체 이미지 빌드 (U-Boot + Kernel + RootFS + WIC)

```bash
cd /media/ksw/dev/new_dev/rk3588/docker

docker compose run --rm yocto-build bash -c \
  "cd /home/builder/yocto && \
   source sources/poky/oe-init-build-env build && \
   bitbake hds-image"
```

- **최초 빌드**: 2~4시간 소요 (인터넷 속도, CPU 성능에 따라 변동)
- **재빌드**: 수 분 (sstate 캐시 활용, 변경분만 재빌드)
- 모든 산출물이 자동 생성됨 (wic.gz, idbloader, u-boot.itb, fitImage 등)

### 3.3 개별 컴포넌트 빌드

특정 컴포넌트만 재빌드할 때 사용한다. 아래 모든 명령은 Docker 컨테이너 안에서 실행한다.

```bash
# ─── 컨테이너 진입 (공통) ──────────────────────────
cd /media/ksw/dev/new_dev/rk3588/docker
docker compose run --rm yocto-build bash
# 컨테이너 내부:
cd /home/builder/yocto && source sources/poky/oe-init-build-env build
```

#### U-Boot만 빌드
```bash
bitbake u-boot
# 산출물: idbloader.img, u-boot.itb
```

#### 커널만 빌드
```bash
bitbake virtual/kernel
# 산출물: fitImage, rk3588-hds.dtb, modules-rk3588-hds.tgz
```

#### RootFS 재생성 (커널/부트로더 변경 후 WIC에 반영)
```bash
bitbake hds-image
# 이미 빌드된 컴포넌트는 sstate 캐시에서 가져오므로 빠름
```

#### 강제 재빌드 (캐시 무시)
```bash
# U-Boot 완전 재빌드
bitbake u-boot -c cleansstate
bitbake u-boot

# 커널 완전 재빌드
bitbake virtual/kernel -c cleansstate
bitbake virtual/kernel

# 이미지 완전 재빌드 (WIC + ext4)
bitbake hds-image -c cleansstate -f
bitbake hds-image

# 전체 클린 재빌드 (U-Boot + Kernel + 이미지)
bitbake u-boot -c cleansstate
bitbake virtual/kernel -c cleansstate
bitbake hds-image -c cleansstate -f
bitbake hds-image
```

### 3.4 유용한 BitBake 명령

```bash
# 드라이런 (실제 빌드 없이 실행 계획 확인)
bitbake hds-image -n

# 레이어/레시피 확인
bitbake-layers show-layers
bitbake-layers show-recipes | grep hds

# 특정 레시피의 태스크 목록
bitbake u-boot -c listtasks

# 빌드 로그 확인
bitbake u-boot -c compile -v    # verbose 출력

# 환경 변수 덤프
bitbake u-boot -e | grep ^UBOOT_MACHINE=

# SDK 빌드 (App 크로스 컴파일용, 최초 1회)
bitbake hds-image -c populate_sdk
```

---

## 4. App 빌드 (컨테이너 애플리케이션)

HAL + App을 Yocto SDK 기반으로 aarch64 타겟용 크로스 컴파일한다.

### 4.1 사전 조건: SDK 설치

SDK가 없으면 먼저 빌드한다 (Yocto 컨테이너에서):
```bash
cd /media/ksw/dev/new_dev/rk3588/docker
docker compose run --rm yocto-build bash -c \
  "cd /home/builder/yocto && \
   source sources/poky/oe-init-build-env build && \
   bitbake hds-image -c populate_sdk"
```

SDK 설치 (호스트에서):
```bash
# SDK 인스톨러 실행 (기본 경로: yocto/sdk-install/)
./yocto/build/tmp-glibc/deploy/sdk/oecore-x86_64-aarch64-toolchain-*.sh \
  -d yocto/sdk-install -y
```

### 4.2 App 전체 빌드

```bash
cd /media/ksw/dev/new_dev/rk3588

# 기본 빌드 (Release)
./scripts/build-app.sh

# 또는 Docker Compose 직접 실행
cd docker
docker compose -f docker-compose.app.yml run --rm app-build build
```

### 4.3 App 빌드 명령어

```bash
# 전체 빌드 (기본)
./scripts/build-app.sh build

# 클린 + 재빌드
./scripts/build-app.sh rebuild

# 빌드 디렉토리 정리
./scripts/build-app.sh clean

# CMake 설정만 (빌드 없이)
./scripts/build-app.sh cmake-only

# 빌드 + 설치 (build-output/install/ 에 출력)
./scripts/build-app.sh install

# SDK 셸 진입 (수동 디버깅)
./scripts/build-app.sh shell
```

### 4.4 App 빌드 옵션

```bash
# Debug 빌드
CMAKE_BUILD_TYPE=Debug ./scripts/build-app.sh rebuild

# 병렬 빌드 수 조절
BUILD_JOBS=4 ./scripts/build-app.sh

# 플랫폼 지정 (기본: rk3588)
HAL_PLATFORM=rk3588 ./scripts/build-app.sh
```

### 4.5 App 빌드 산출물

`build-output/` 디렉토리에 생성:

| 산출물 | 설명 |
|---|---|
| `hds_system` | 메인 엔트리포인트 (24MB ELF) |
| `hds_recorder` | 4~8ch 녹화 |
| `hds_ai` | YOLO NMS AI 감지 |
| `hds_display` | 1/4/9/PIP 레이아웃 |
| `hds_network` | HTTP/스트리밍 서버 |
| `hds_monitor` | 프로세스/리소스 감시 |
| `hds_playback` | IMF 재생 |
| `hds_fms` | MQTT 관제 |
| `hds_ota` | A/B 슬롯 OTA |
| `libhds_hal.a` | HAL 정적 라이브러리 |
| `libhds_*.a` | 각 모듈 정적 라이브러리 (11개) |

---

## 5. 빌드 설정 파일

### 5.1 local.conf (Yocto 빌드 전역 설정)

파일: `yocto/build/conf/local.conf`

```bash
MACHINE = "rk3588-hds"        # 타겟 머신
DISTRO = "hds-distro"         # 배포판

BB_NUMBER_THREADS = "8"       # BitBake 병렬 태스크 수
PARALLEL_MAKE = "-j 8"        # make 병렬 작업 수

INHERIT += "rm_work"          # 빌드 후 작업 디렉토리 삭제 (디스크 절약 ~200GB)
RM_WORK_EXCLUDE += "linux-yocto u-boot"   # 커널/부트로더는 디버깅용 유지

EXTRA_IMAGE_FEATURES = "debug-tweaks tools-debug"   # root 비번 없음 (개발용)
LICENSE_FLAGS_ACCEPTED = "commercial"                # rknn-runtime 등 상업 라이선스 허용
```

### 5.2 bblayers.conf (레이어 구성)

파일: `yocto/build/conf/bblayers.conf`

13개 레이어 사용:

| 레이어 | 출처 | 역할 |
|---|---|---|
| `meta`, `meta-poky`, `meta-yocto-bsp` | poky | Yocto 코어 |
| `meta-oe`, `meta-python`, `meta-networking`, `meta-filesystems` | meta-openembedded | 확장 패키지 |
| `meta-arm-toolchain`, `meta-arm` | meta-arm | ARM 툴체인 |
| `meta-security` | 독립 | 보안 기능 |
| `meta-virtualization` | 독립 | containerd, 가상화 |
| `meta-rockchip` | 독립 | RK3588 BSP |
| **`meta-hds`** | 커스텀 | HDS 전용 레시피 |

### 5.3 머신 설정 (rk3588-hds)

파일: `yocto/sources/meta-hds/conf/machine/rk3588-hds.conf`

```bash
KERNEL_DEVICETREE = "rockchip/rk3588-hds.dtb"     # HDS 전용 DTS
UBOOT_MACHINE = "rock5b-rk3588_defconfig"          # U-Boot defconfig
SERIAL_CONSOLES = "1500000;ttyFIQ0"                # 시리얼 콘솔 (1.5Mbps)
IMAGE_FSTYPES = "ext4 wic.gz"                      # 출력 이미지 포맷
```

### 5.4 배포판 설정 (hds-distro)

파일: `yocto/sources/meta-hds/conf/distro/hds-distro.conf`

```bash
DISTRO_FEATURES = "alsa ext2 ipv4 ipv6 usbhost wifi
                   systemd usrmerge pam opengl virtualization security"

VIRTUAL-RUNTIME_init_manager = "systemd"           # systemd 기반
PACKAGE_CLASSES = "package_ipk"                     # IPK 패키지
```

---

## 6. eMMC 파티션 레이아웃

WIC 이미지(`hds-emmc.wks`)가 생성하는 eMMC 파티션 구조:

```
┌─────────────────────────────────────────────────────────────┐
│ eMMC (mmcblk0)                                              │
│                                                             │
│ LBA 0x00          ┌────────────┐  Protective MBR + GPT      │
│ LBA 0x40 (32KB)   │ idbloader  │  Rockchip TPL+SPL (raw)   │
│ LBA 0x4000 (8MB)  │ u-boot.itb │  U-Boot+ATF+TEE (raw)    │
│                   └────────────┘                            │
│ mmcblk0p1         ┌────────────┐  boot     (128MB, ext4)   │
│                   │  fitImage   │  커널 FIT 이미지           │
│                   └────────────┘                            │
│ mmcblk0p2         ┌────────────┐  rootfs_a (1024MB, ext4)  │
│                   │  Slot A     │  활성 루트 파일시스템      │
│                   └────────────┘                            │
│ mmcblk0p3         ┌────────────┐  rootfs_b (1024MB, ext4)  │
│                   │  Slot B     │  OTA 대상 슬롯            │
│                   └────────────┘                            │
│ mmcblk0p4         ┌────────────┐  config   (256MB, ext4)   │
│                   │  영구 설정   │  /mnt/doc                │
│                   └────────────┘                            │
│ mmcblk0p5         ┌────────────┐  data     (나머지, ext4)  │
│                   │  녹화 데이터 │  /mnt/data               │
│                   └────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. eMMC 플래싱 (rkdeveloptool)

### 7.1 rkdeveloptool 설치 (소스 빌드)

```bash
sudo apt install -y git build-essential libudev-dev libusb-1.0-0-dev \
    pkg-config autoconf libtool

cd /tmp
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
autoreconf -i && ./configure
make -j$(nproc) CXXFLAGS="-Wno-error"
sudo install -m 0755 rkdeveloptool /usr/local/bin/
```

### 7.2 udev 규칙 (sudo 없이 사용)

```bash
sudo tee /etc/udev/rules.d/99-rockchip.rules > /dev/null <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="2207", MODE="0666", GROUP="plugdev"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG plugdev $USER
# 로그아웃/재로그인 필요
```

### 7.3 MaskROM 모드 진입

```
1. 보드 전원 OFF
2. RECOVERY 버튼 누른 상태 유지
3. USB-C OTG 케이블로 PC에 연결
4. 전원 ON (RECOVERY 버튼 누른 채로)
5. 3초 후 RECOVERY 버튼 release
```

확인:
```bash
sudo rkdeveloptool ld
# 출력: DevNo=1 ... Maskrom
```

### 7.4 자동 플래싱 (스크립트)

```bash
cd /media/ksw/dev/new_dev/rk3588
./scripts/flash-emmc.sh
```

스크립트 동작 순서:
1. `rkdeveloptool db u-boot.itb` — MaskROM → Loader 모드 전환
2. `rkdeveloptool wl 0x40 idbloader.img` — idbloader 기록
3. `rkdeveloptool wl 0x4000 u-boot.itb` — U-Boot 기록
4. `gunzip -c wic.gz > /tmp/xxx.wic` — wic 압축 해제
5. `rkdeveloptool wl 0 /tmp/xxx.wic` — **통합 이미지 LBA 0부터 전체 기록**
6. `rkdeveloptool rd` — 보드 재부팅

> **참고**: wic.gz 안에 idbloader.img과 u-boot.itb가 이미 포함되어 있다.
> 2~3번 단계는 안전을 위한 중복 기록이며, 5번이 통합 이미지를 덮어쓴다.

### 7.5 수동 플래싱 (개별 명령)

```bash
IMAGES=/media/ksw/dev/new_dev/rk3588/yocto/build/tmp-glibc/deploy/images/rk3588-hds

# 1. 장치 확인
sudo rkdeveloptool ld

# 2. MaskROM에서 Loader로 전환 (MaskROM 모드일 때만)
sudo rkdeveloptool db ${IMAGES}/u-boot.itb
sleep 2

# 3. wic 압축 해제 + 전체 기록
gunzip -c ${IMAGES}/hds-image-rk3588-hds.rootfs.wic.gz > /tmp/hds.wic
sudo rkdeveloptool wl 0 /tmp/hds.wic

# 4. 재부팅
sudo rkdeveloptool rd
rm /tmp/hds.wic
```

### 7.6 Rockchip 부트 모드

| 모드 | `rkdeveloptool ld` 출력 | 조건 | `db` 필요 여부 |
|---|---|---|---|
| **MaskROM** | `Found One MASKROM Device` | eMMC 공백 / RECOVERY 버튼 | O (필수) |
| **Loader** | `Found One LOADER Device` | 부트로더가 이미 존재 | X (불필요) |

### 7.7 주요 rkdeveloptool 명령어

| 명령 | 용도 |
|---|---|
| `rkdeveloptool ld` | 장치 인식 확인 |
| `rkdeveloptool db <file>` | RAM에 부트로더 다운로드 (MaskROM→Loader) |
| `rkdeveloptool wl <LBA> <file>` | eMMC 특정 LBA에 파일 기록 |
| `rkdeveloptool rl <LBA> <count> <file>` | eMMC에서 읽기 |
| `rkdeveloptool ef` | eMMC 전체 삭제 |
| `rkdeveloptool rd` | 보드 재부팅 |

---

## 8. SD 카드 플래싱

eMMC 대신 SD 카드로 부팅할 때 사용한다.

```bash
# 디바이스 목록 확인
./scripts/flash-sdcard.sh --list

# 플래싱 (주의: 대상 디바이스 확인 필수!)
./scripts/flash-sdcard.sh /dev/sdX
```

내부 동작:
```bash
# bmaptool 있으면 (빠름):
sudo bmaptool copy --bmap <bmap> <wic.gz> /dev/sdX

# 없으면 (dd):
gunzip -c <wic.gz> | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## 9. U-Boot OTA 환경변수 등록

플래싱 후 U-Boot OTA 명령(`run up_ubt/up_lnx/up_app`)을 사용하려면 한 번만 등록한다.
자세한 내용은 `09_uboot_update_guide.md` 참조.

### 9.1 PC 측 TFTP 서버 준비

```bash
sudo apt install -y tftpd-hpa

# 환경변수 파일을 TFTP 디렉토리에 복사
IMAGES=/media/ksw/dev/new_dev/rk3588/yocto/build/tmp-glibc/deploy/images/rk3588-hds
sudo cp ${IMAGES}/hds-uboot-env.txt /srv/tftp/

sudo systemctl restart tftpd-hpa
```

### 9.2 보드 측 (U-Boot 콘솔)

시리얼 콘솔(1.5Mbps, ttyFIQ0)로 접속 후, 자동 부팅 카운트다운에서 Enter:
```
=> setenv ipaddr 192.168.2.20
=> setenv serverip 192.168.2.10
=> tftpboot ${loadaddr} hds-uboot-env.txt
=> env import -t ${loadaddr} ${filesize}
=> saveenv
=> reset
```

등록 후 사용 가능한 OTA 명령:
```
=> run up_ubt     # 부트로더 업데이트
=> run up_lnx     # 커널 업데이트
=> run up_app     # rootfs 업데이트 (자동 비활성 슬롯)
=> run up_all     # 전체 업데이트
=> run up_swap    # A↔B 슬롯 전환
```

---

## 10. 빌드 후 부팅 검증

### 10.1 시리얼 콘솔 연결

```bash
# minicom 사용
sudo minicom -D /dev/ttyUSB0 -b 1500000

# 또는 picocom
sudo picocom -b 1500000 /dev/ttyUSB0
```

### 10.2 부팅 로그 확인 순서

```
[1] DDR 초기화
    DDR Version V...
    Boot (InternalMem) ...

[2] U-Boot SPL
    U-Boot SPL 2024.01 (...)
    Trying to boot from MMC1

[3] U-Boot 본체
    U-Boot 2024.01 (...)
    Model: Radxa ROCK 5B
    Hit any key to stop autoboot: 2    ← Enter로 콘솔 진입 가능

[4] 커널 부팅
    Starting kernel ...
    [    0.000000] Linux version 6.6.123 ...

[5] systemd 서비스 시작
    [  OK  ] Started containerd ...
    [  OK  ] Started hds-container.service ...

[6] 로그인 프롬프트
    hds-rk3588 login: root             ← 비밀번호 없음 (debug-tweaks)
```

### 10.3 시스템 상태 확인

```bash
# 파티션 구조 확인
lsblk

# OS 정보
cat /etc/os-release

# containerd 상태
systemctl status containerd
systemctl status hds-container.service

# 커널 모듈
lsmod

# 네트워크
ip addr
```

---

## 11. 빌드 문제 해결

### 빌드 실패 시

```bash
# 에러 로그 위치
cat yocto/build/tmp-glibc/work/<ARCH>/<RECIPE>/<VER>/temp/log.do_compile

# 의존성 확인
bitbake -g hds-image
cat task-depends.dot | grep <recipe>

# 단일 태스크 재실행 (verbose)
bitbake <recipe> -c compile -v
```

### 디스크 부족

```bash
# sstate 캐시 정리 (오래된 캐시 삭제)
# 컨테이너 안에서:
sstate-cache-management.sh --remove-duplicated --cache-dir=/home/builder/yocto/sstate-cache

# 또는 전체 정리 후 재빌드
rm -rf yocto/build/tmp-glibc/
```

### fetch 실패 (소스 다운로드)

```bash
# 미러 설정 확인
bitbake <recipe> -c fetch -v

# 수동 다운로드 후 재시도
# downloads/ 디렉토리에 소스 파일을 직접 배치
```

### Docker 컨테이너 문제

```bash
# 컨테이너 재빌드
cd docker && docker compose build --no-cache

# 볼륨 확인
docker volume ls | grep yocto
docker volume inspect yocto-sources
```

---

## 12. 빌드 명령어 요약 (Cheat Sheet)

```bash
PROJECT=/media/ksw/dev/new_dev/rk3588
DOCKER="cd ${PROJECT}/docker && docker compose run --rm yocto-build bash -c"
YOCTO_INIT="cd /home/builder/yocto && source sources/poky/oe-init-build-env build"

# ─── Yocto 빌드 ──────────────────────────────────────
# 전체 이미지 (U-Boot + Kernel + RootFS + WIC)
${DOCKER} "${YOCTO_INIT} && bitbake hds-image"

# U-Boot만
${DOCKER} "${YOCTO_INIT} && bitbake u-boot"

# 커널만
${DOCKER} "${YOCTO_INIT} && bitbake virtual/kernel"

# U-Boot 강제 재빌드 후 이미지 재생성
${DOCKER} "${YOCTO_INIT} && \
  bitbake u-boot -c cleansstate && \
  bitbake hds-image -c cleansstate -f && \
  bitbake hds-image"

# SDK 빌드
${DOCKER} "${YOCTO_INIT} && bitbake hds-image -c populate_sdk"

# ─── App 빌드 ────────────────────────────────────────
cd ${PROJECT}
./scripts/build-app.sh                # 기본 빌드
./scripts/build-app.sh rebuild        # 클린 + 빌드
CMAKE_BUILD_TYPE=Debug ./scripts/build-app.sh rebuild   # Debug 빌드

# ─── 플래싱 ──────────────────────────────────────────
cd ${PROJECT}
./scripts/flash-emmc.sh               # eMMC (rkdeveloptool)
./scripts/flash-sdcard.sh /dev/sdX    # SD 카드

# ─── 산출물 확인 ──────────────────────────────────────
ls -la ${PROJECT}/yocto/build/tmp-glibc/deploy/images/rk3588-hds/
```
