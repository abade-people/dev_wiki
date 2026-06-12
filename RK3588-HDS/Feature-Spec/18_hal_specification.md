# HAL (Hardware Abstraction Layer) 명세

> 새 플랫폼 이식 시 **반드시 구현해야 할 하드웨어 추상화 계층**의 전체 목록이다.
> 각 HAL의 기능 요구사항, 입출력, 성능 조건을 기술한다.

---

## 1. HAL 개요

### 구현 우선순위

| 우선순위 | HAL | 이유 |
|----------|-----|------|
| **P0 (필수)** | Video Input, Video Encoder, Stream Mux, Display | 없으면 DVR 기본 기능 불가 |
| **P1 (핵심)** | Video Decoder, Image Processing, Audio, DMA Buffer | 재생/오버레이/오디오 필요 |
| **P2 (AI)** | NPU/AI Inference | AI 기능 필요 시 |
| **P3 (I/O)** | GPIO, UART, Watchdog | 차량 연동 필요 시 |

### 현재 RK3588 구현 참조

| HAL | RK3588 구현 | 소스 파일 |
|-----|-------------|----------|
| Video Input | V4L2 + DMA | src/rkctrl/VideoInput.cc, camera_source.c |
| Video Encoder | Rockchip MPP | src/rkctrl/EncStream.cc |
| Video Decoder | Rockchip MPP | src/rkctrl/DecodeManager.cc |
| Display | DRM + RGA | src/rkctrl/DisplayManager.cc, DrmResource |
| Image Processing | RGA | lib/DrmResource.cc |
| AI Inference | RKNN Runtime | src/rkctrl/npu/NpuEngine.cc, ObjectDetect.cc |
| Stream Mux | /dev/dci_menc | lib/DciMencDevice.cc, src/rkctrl/DciDeviceControl.cc |
| Audio | ALSA | src/audioman/ |
| GPIO | sysfs/devmem | lib/GpioCtrl.cc |
| UART | termios | src/ioman/McuControl.cc |
| Watchdog | /dev/watchdog | src/ioman/WatchDogTimer*.cc |

---

## 2. Video Input HAL

### 기능 요구사항
- 다중 카메라 동시 캡처 (최대 8채널)
- 비동기 프레임 수신 (콜백 또는 이벤트 기반)
- DMA 버퍼 기반 제로카피

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Open** | 채널 번호, 해상도, 포맷 | 핸들 |
| **Start** | 핸들 | - |
| **Stop** | 핸들 | - |
| **Close** | 핸들 | - |
| **GetFrame** | 핸들 | 프레임 버퍼 (fd 또는 포인터), 타임스탬프 |
| **ReleaseFrame** | 프레임 버퍼 | - |
| **SetFlipMirror** | 채널, flip, mirror | - |

### 사양

| 항목 | 값 |
|------|-----|
| 최대 채널 수 | 8 (MAX_VIDEO_INPUT_CNT) |
| 입력 포맷 | NV12 (YUV420SP) |
| 최대 해상도 | 1920x1080 |
| 프레임 버퍼 수 | 채널당 최소 4개 |
| 캡처 방식 | 비동기 (epoll/poll/callback) |

---

## 3. Video Encoder HAL

### 기능 요구사항
- H.264/H.265 하드웨어 인코딩
- 채널당 다중 스트림 동시 인코딩 (녹화용 + 네트워크용)
- 실시간 파라미터 변경 (비트레이트, FPS)

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Create** | 코덱, 해상도, FPS, 비트레이트 | 인코더 핸들 |
| **Destroy** | 핸들 | - |
| **Encode** | 핸들, 프레임 버퍼 | 인코딩 패킷 (데이터, 크기, 프레임타입) |
| **SetBitrate** | 핸들, kbps | - |
| **SetFPS** | 핸들, fps | - |
| **SetResolution** | 핸들, width, height | - |
| **ForceKeyFrame** | 핸들 | - |
| **GetMotionData** | 핸들 | 모션 감지 배열 (60x68) |

### 사양

| 항목 | 값 |
|------|-----|
| 코덱 | H.264 (필수), H.265 (선택) |
| 최대 채널 | 16 |
| 인코딩 그룹 | 4채널 단위 |
| 해상도 | 1080P, 720P, 960H, HD1, CIF, VGA |
| FPS | 30, 25, 15, 10, 5, 1 |
| 레이트 제어 | CBR (기본 1500kbps, 스텝 250kbps) |
| 스트림 타입 | REC(녹화), NET(네트워크), Snapshot(JPEG) |
| 모션 배열 크기 | 60 x 68 |

---

## 4. Video Decoder HAL

### 기능 요구사항
- H.264/H.265 하드웨어 디코딩
- IMF 파일에서 추출한 스트림 디코딩
- 암호화된 스트림 복호화 후 디코딩 지원

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Create** | 코덱 | 디코더 핸들 |
| **Destroy** | 핸들 | - |
| **Decode** | 핸들, 패킷 데이터 | 디코딩 프레임 버퍼 |
| **Flush** | 핸들 | - |
| **Reset** | 핸들 | - |

### 사양

| 항목 | 값 |
|------|-----|
| 코덱 | H.264 (필수), H.265 (선택) |
| 최대 동시 디코딩 | 채널 수만큼 |
| 출력 포맷 | NV12 |

---

## 5. Display HAL

### 기능 요구사항
- HDMI/LVDS 출력 (1개 이상)
- 다중 레이어(Plane) 합성
- HDMI 핫플러그 감지
- EDID 기반 해상도 자동 설정

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Init** | 출력 포트 | 핸들 |
| **Deinit** | 핸들 | - |
| **SetMode** | 핸들, 해상도, 주사율 | - |
| **SetPlane** | 핸들, 레이어, 프레임버퍼, 위치, 크기 | - |
| **Commit** | 핸들 | - (원자적 업데이트) |
| **CheckHotplug** | 핸들 | 연결 상태 |
| **GetEDID** | 핸들 | 지원 해상도 목록 |

### 사양

| 항목 | 값 |
|------|-----|
| 출력 포트 | 최소 1개 (HDMI), 선택: LVDS/eDP |
| 레이어 수 | 최소 4개 (배경, 영상, OSD, 커서) |
| 최대 출력 해상도 | 3840x2160 (4K) |
| 컬러 포맷 | NV12, ARGB8888 |

---

## 6. Image Processing HAL

### 기능 요구사항
- 이미지 리사이즈 (스케일링)
- 이미지 크롭
- 컬러 포맷 변환 (NV12 ↔ RGB ↔ ARGB)
- 이미지 합성 (블렌딩)
- AVM LUT 기반 왜곡 보정 (선택)

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Resize** | 소스 버퍼, 타겟 크기 | 결과 버퍼 |
| **Crop** | 소스 버퍼, 크롭 영역 | 결과 버퍼 |
| **Convert** | 소스 버퍼, 타겟 포맷 | 결과 버퍼 |
| **Blend** | 전경, 배경, 알파 | 결과 버퍼 |
| **LutTransform** | 소스, LUT 테이블 | 결과 버퍼 |

### 성능 조건
- 30fps 실시간 처리 (1080P 기준)
- 제로카피 가능 시 선호

---

## 7. NPU/AI Inference HAL

### 기능 요구사항
- 딥러닝 모델 파일 로드/해제
- 텐서 메모리 할당/해제
- 추론 실행 (동기 또는 비동기)
- 다중 모델 동시 지원

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **LoadModel** | 모델 파일 경로 | 모델 핸들 |
| **UnloadModel** | 모델 핸들 | - |
| **AllocTensor** | 크기, 타입 | 텐서 메모리 |
| **FreeTensor** | 텐서 메모리 | - |
| **SetInput** | 모델, 텐서 인덱스, 데이터 | - |
| **Run** | 모델 | - |
| **GetOutput** | 모델, 텐서 인덱스 | 출력 데이터, 크기 |
| **GetModelInfo** | 모델 | 입출력 텐서 정보 (수, 크기, 타입) |

### 지원 모델

| 모델 | 입력 크기 | 출력 | 용도 |
|------|----------|------|------|
| YOLOv5s | 640x640x3 | 바운딩박스, 클래스, 신뢰도 | 범용 객체탐지 |
| YOLOv8n | 640x640x3 | 바운딩박스, 클래스, 신뢰도 | 범용 객체탐지 |
| SSD | 300x300x3 | 바운딩박스, 클래스, 신뢰도 | 경량 객체탐지 |

### 성능 조건
- 추론 시간: 100ms 이하 (프레임 스킵 가능)
- 메모리: 모델당 128MB 이하

---

## 8. Stream Multiplexer HAL

### 기능 요구사항

> 상세 사양은 `01_system_architecture.md` 섹션 5 참조

- 다수 프로듀서가 동시에 스트림을 쓰고, 다수 컨슈머가 독립적으로 읽는 링 버퍼
- 4개 독립 큐 모드 (REC, NET, LIVE, CAP)
- 채널별 큐 포함/제외 마스크
- 프리레코딩 지연 버퍼 (최대 1800ms)

### 대체 구현 옵션
- **사용자 공간 링 버퍼**: 공유 메모리 + 뮤텍스
- **파이프/소켓 기반**: 프로듀서→컨슈머 파이프라인
- **GStreamer appsrc/appsink**: 기존 프레임워크 활용

---

## 9. Audio HAL

### 기능 요구사항
- PCM 오디오 캡처 (녹음)
- PCM 오디오 재생
- 볼륨 제어
- 디바이스 열거 및 선택

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **OpenCapture** | 디바이스, 샘플레이트, 채널, 포맷 | 핸들 |
| **OpenPlayback** | 디바이스, 샘플레이트, 채널, 포맷 | 핸들 |
| **Read** | 핸들, 버퍼, 크기 | 읽은 바이트 수 |
| **Write** | 핸들, 데이터, 크기 | 쓴 바이트 수 |
| **Close** | 핸들 | - |
| **SetVolume** | 핸들 또는 글로벌, 볼륨(0~100) | - |
| **ListDevices** | - | 디바이스 목록 |

### 사양

| 항목 | 값 |
|------|-----|
| 샘플레이트 | 8000Hz (녹음), 44100/48000Hz (재생) |
| 채널 | 모노/스테레오 |
| 비트깊이 | 16bit |
| 출력 | 스피커, HDMI, USB |

---

## 10. GPIO HAL

### 기능 요구사항
- 디지털 입력 읽기
- 디지털 출력 쓰기
- 인터럽트 또는 폴링 기반 입력 감지

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Export** | 핀 번호, 방향(IN/OUT) | - |
| **Read** | 핀 번호 | 값 (0/1) |
| **Write** | 핀 번호, 값 | - |
| **WaitForEdge** | 핀 번호, 엣지(RISING/FALLING/BOTH) | 이벤트 |
| **Unexport** | 핀 번호 | - |

### 용도

| 핀 | 방향 | 용도 |
|----|------|------|
| 알람 입력 | IN | 외부 알람 센서 |
| 알람 출력 | OUT | 경고 LED, 부저 |
| 트리거 입력 | IN | 방향지시등, 후진 기어 |
| 전원 감지 | IN | ACC 상태, 전압 |
| DO 제어 | OUT | 릴레이, PLC |

---

## 11. UART HAL

### 기능 요구사항
- 시리얼 포트 열기/닫기
- 바이트 송수신
- 보드레이트/패리티/스톱비트 설정

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Open** | 디바이스 경로, 보드레이트, 설정 | 핸들 |
| **Close** | 핸들 | - |
| **Read** | 핸들, 버퍼, 크기, 타임아웃 | 읽은 바이트 |
| **Write** | 핸들, 데이터, 크기 | 쓴 바이트 |
| **Flush** | 핸들 | - |

### 포트 할당

| 포트 | 보드레이트 | 용도 |
|------|-----------|------|
| /dev/ttyS1 | 115200 | MCU 통신 |
| /dev/ttyS4 | 9600/115200 | GPS 수신 |
| 가변 | 가변 | IO 보드 (PLC) |
| 가변 | 가변 | 터치 패널 |

---

## 12. Watchdog HAL

### 기능 요구사항
- 워치독 타이머 설정
- 주기적 킥 (리셋 방지)
- 타임아웃 시 시스템 리부팅

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Open** | 타임아웃(초) | 핸들 |
| **Kick** | 핸들 | - |
| **Close** | 핸들 | - |
| **SetTimeout** | 핸들, 타임아웃(초) | - |

### 사양

| 항목 | 값 |
|------|-----|
| 기본 타임아웃 | 30초 |
| 킥 주기 | Monitor 프로세스에서 1초마다 |

---

## 13. DMA Buffer HAL

### 기능 요구사항
- 연속 물리 메모리 할당
- FD(File Descriptor) export (프로세스간 공유)
- CPU 캐시 관리 (Writeback/Invalidate)

### 인터페이스

| 동작 | 입력 | 출력 |
|------|------|------|
| **Alloc** | 크기, 플래그 | 버퍼 핸들, fd |
| **Free** | 핸들 | - |
| **Map** | 핸들 | 가상 주소 |
| **Unmap** | 핸들, 주소 | - |
| **ExportFd** | 핸들 | fd |
| **ImportFd** | fd | 핸들 |
| **CacheWriteback** | 핸들 | - (CPU→디바이스) |
| **CacheInvalidate** | 핸들 | - (디바이스→CPU) |

### 성능 조건
- 제로카피 파이프라인 지원 (카메라→인코더→디스플레이)
- 최대 버퍼 크기: 1MB

---

## 14. 플랫폼별 구현 가이드

### Raspberry Pi

| HAL | 권장 구현 |
|-----|----------|
| Video Input | V4L2 (libcamera) |
| Video Encoder | V4L2 M2M (H.264 only) 또는 FFmpeg |
| Video Decoder | V4L2 M2M 또는 FFmpeg |
| Display | DRM/KMS (vc4) |
| Image Processing | OpenCV 또는 GPU (OpenGL ES) |
| AI Inference | TensorFlow Lite, ONNX Runtime, 또는 Hailo-8 |
| Stream Mux | 사용자 공간 공유 메모리 링 버퍼 |
| Audio | ALSA (호환) |
| GPIO | sysfs 또는 libgpiod |

### Qualcomm

| HAL | 권장 구현 |
|-----|----------|
| Video Input | V4L2 (CAMX) |
| Video Encoder | OMX / V4L2 M2M |
| Video Decoder | OMX / V4L2 M2M |
| Display | DRM/KMS (MSM) |
| Image Processing | Adreno GPU 또는 C2D |
| AI Inference | SNPE / QNN |
| Stream Mux | ION 버퍼 기반 링 버퍼 |

### NXP i.MX

| HAL | 권장 구현 |
|-----|----------|
| Video Input | V4L2 (ISI) |
| Video Encoder | VPU (hantro) |
| Video Decoder | VPU (hantro) |
| Display | DRM/KMS (LCDIF) |
| Image Processing | GPU (Vivante) 또는 2D BLT |
| AI Inference | eIQ (TFLite, ONNX) |
