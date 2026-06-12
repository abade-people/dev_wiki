# SoC 교체 가이드

> 새 SoC로 HDS 시스템을 이식할 때의 체크리스트와 절차.
> HAL 상세 사양은 `doc/feature_spec/18_hal_specification.md` 참조.

---

## 1. 교체 범위 요약

```
변경 필요 (SoC 의존)          재사용 가능 (SoC 무관)
─────────────────────         ──────────────────────
✗ machine.conf               ✓ hds-distro.conf
✗ u-boot 레시피               ✓ hds-app 레시피
✗ kernel 레시피               ✓ hds-image 레시피
✗ HAL 라이브러리 레시피        ✓ hds-image-firmware 레시피
✗ MCU 레시피 (보드 의존)       ✓ packagegroup-hds-* 레시피
✗ GPU 드라이버                ✓ MQTT, curl, sqlite, tinyxml2 등
✗ NPU 런타임                  ✓ Qt5 앱 (동일 소스)
                              ✓ IPC 시스템, IMF, TLV
                              ✓ 이벤트/녹화/재생 로직
```

---

## 2. 교체 절차

### Step 1: BSP 레이어 확보

| SoC | BSP 레이어 | 소스 |
|-----|-----------|------|
| RK3588 | meta-rockchip | github.com/pimlie/meta-rockchip |
| Raspberry Pi | meta-raspberrypi | github.com/agherzan/meta-raspberrypi |
| i.MX8 | meta-freescale | github.com/Freescale/meta-freescale |
| Qualcomm | meta-qcom | github.com/pimlie/meta-qcom |
| TI AM62x | meta-ti | git.ti.com/cgit/arago-project/meta-ti |

### Step 2: 새 머신 설정 생성

`02_machine_conf.md`의 `rpi5-hds.conf` 예시를 참고하여:

```python
# meta-hds/conf/machine/NEW-SOC-hds.conf

require include/hds-common.inc  # ← 공통 설정 재사용

# SoC 아키텍처
require conf/machine/include/arm/armv8a/tune-NEW.inc

# HAL 프로바이더 교체
PREFERRED_PROVIDER_virtual/video-codec = "NEW-CODEC"
PREFERRED_PROVIDER_virtual/image-processor = "NEW-IP"
PREFERRED_PROVIDER_virtual/egl = "NEW-GPU"
PREFERRED_PROVIDER_virtual/libgles2 = "NEW-GPU"
PREFERRED_PROVIDER_virtual/npu-runtime = "NEW-NPU"
```

### Step 3: HAL 라이브러리 레시피 작성

각 HAL에 대해 새 SoC의 라이브러리 레시피를 작성:

| HAL | RK3588 | RPi5 | i.MX8 |
|-----|--------|------|-------|
| Video Codec | rockchip-mpp | v4l2-codec (libcamera) | imx-vpu-hantro |
| Image Proc | rockchip-rga | opencv-hal (SW) | imx-gpu-g2d |
| GPU/EGL | mali-gpu | mesa (V3D) | imx-gpu-viv |
| NPU | rknn-runtime | tflite-runtime | imx-nn (eIQ) |
| Display | libdrm-rockchip | libdrm-vc4 | libdrm-imx |

### Step 4: 커널 레시피 작성

```bitbake
# linux-NEW_6.6.bb (예: RPi5)
PREFERRED_PROVIDER_virtual/kernel = "linux-raspberrypi"
KERNEL_DEFCONFIG = "bcm2712_defconfig"
KERNEL_DEVICETREE = "broadcom/bcm2712-rpi-5-b.dtb"
```

필수 커널 옵션 확인 (03_recipes_bsp.md 참조):
- V4L2, DRM, GPIO, CAN, Watchdog, SquashFS 등

### Step 5: DCI 대체 구현

DCI 커널 드라이버(`/dev/dci_menc`)는 RK3588 전용이므로 대체 필요:

| 옵션 | 복잡도 | 성능 |
|------|--------|------|
| **공유 메모리 링 버퍼** (사용자 공간) | 중간 | 좋음 |
| **V4L2 M2M + 파이프** | 낮음 | 보통 |
| **GStreamer 파이프라인** | 낮음 | 보통 |
| **커널 모듈 이식** | 높음 | 최상 |

권장: **공유 메모리 링 버퍼** — `DciMencDevice` 클래스를 사용자 공간 구현으로 교체.

### Step 6: hds-app 수정 (최소한)

HAL 추상화가 완료되면 앱 소스 수정은 최소:

```
config.mk 수정:
  - CROSS_COMPILE 변경 (또는 Yocto SDK 자동)
  - SYSROOT 변경 (또는 Yocto SDK 자동)

hds_config.h 수정 (필요 시):
  - CONFIG_USE_HAILO 토글
  - 디바이스 경로 변경 (CFG_MICOM_DEVICE 등)

HAL 소스 교체:
  - src/rkctrl/EncStream.cc → 새 인코더 API
  - src/rkctrl/DecodeManager.cc → 새 디코더 API
  - src/rkctrl/DisplayManager.cc → 새 DRM 설정
  - src/rkctrl/npu/ObjectDetect.cc → 새 NPU API
  - src/rkctrl/DciDeviceControl.cc → 새 스트림 다중화
```

### Step 7: 빌드 및 테스트

```bash
# 새 머신으로 빌드
MACHINE=new-soc-hds bitbake hds-image-firmware

# 테스트 항목 (doc/feature_spec/ 참조)
- [ ] 카메라 입력 (02_video_pipeline.md)
- [ ] H.264 인코딩/디코딩
- [ ] 녹화/재생 (03_recording_and_storage.md, 04_playback.md)
- [ ] 디스플레이 출력 (05_display_and_view_modes.md)
- [ ] AI 객체탐지 (06_ai_object_detection.md)
- [ ] GPIO/UART/CAN (08_io_and_vehicle_interface.md)
- [ ] 오디오 (09_audio_system.md)
- [ ] HTTP/MQTT (10, 11)
- [ ] Qt UI (12_ui_osd.md)
- [ ] OTA 부팅 (17_ota_and_boot.md)
```

---

## 3. HAL 추상화 전략

### 3.1 현재 구조 (HAL 미분리)

```
hds-app
└── src/rkctrl/
    ├── EncStream.cc        ← MPP API 직접 호출
    ├── DisplayManager.cc   ← DRM + RGA 직접 호출
    └── npu/ObjectDetect.cc ← RKNN API 직접 호출
```

### 3.2 목표 구조 (HAL 분리)

```
hds-app
├── src/rkctrl/
│   ├── EncStream.cc         ← HalVideoEncoder 인터페이스 호출
│   ├── DisplayManager.cc    ← HalDisplay 인터페이스 호출
│   └── npu/ObjectDetect.cc  ← HalNpuInference 인터페이스 호출
│
└── hal/                     ← HAL 구현 (SoC별)
    ├── hal_interface.h      ← 공통 인터페이스 정의
    ├── rk3588/              ← RK3588 구현
    │   ├── hal_encoder_mpp.cc
    │   ├── hal_display_drm_rga.cc
    │   └── hal_npu_rknn.cc
    ├── rpi5/                ← RPi5 구현
    │   ├── hal_encoder_v4l2.cc
    │   ├── hal_display_drm.cc
    │   └── hal_npu_tflite.cc
    └── imx8/                ← i.MX8 구현
        ├── hal_encoder_vpu.cc
        ├── hal_display_drm.cc
        └── hal_npu_eiq.cc
```

### 3.3 Yocto에서 HAL 선택

```bitbake
# hds-app 레시피에서 머신별 HAL 소스 선택
SRC_URI += "${@bb.utils.contains('SOC_FAMILY', 'rk3588', \
    'file://hal/rk3588/', \
    bb.utils.contains('SOC_FAMILY', 'bcm2712', \
        'file://hal/rpi5/', \
        'file://hal/generic/', d), d)}"
```

---

## 4. SoC별 예상 작업량

| SoC | 난이도 | 예상 기간 | 주요 과제 |
|-----|--------|----------|----------|
| **RK3568** | 낮음 | 1~2주 | MPP/RGA/RKNN 동일, 성능 차이만 |
| **RPi5** | 중간 | 4~6주 | V4L2 M2M 인코더, TFLite NPU, DCI 대체 |
| **i.MX8M Plus** | 중간 | 4~6주 | VPU 인코더, eIQ NPU |
| **Qualcomm QCS6490** | 높음 | 6~8주 | SNPE NPU, OMX 인코더, 독자 BSP |
| **x86 (테스트)** | 낮음 | 2~3주 | FFmpeg SW 인코더, CPU 추론 |

---

## 5. 다중 머신 빌드

```bash
# 동시에 여러 머신 빌드
for machine in rk3588-hds rpi5-hds imx8mp-hds; do
    MACHINE=$machine bitbake hds-image-firmware
done

# 출력 확인
ls tmp/deploy/images/*/hds-all.img
```
