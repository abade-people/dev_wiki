# HDS DVR/AI 시스템 - 기능 사양서

## 1. 문서 목적

이 문서 세트는 RK3588 SoC 기반으로 구현된 HDS(Hazard Detection System) DVR/AI 디바이스의 **모든 기능을 하드웨어 비의존적으로 기술**한다. 새로운 SoC 플랫폼(예: Raspberry Pi, Qualcomm, NXP 등)에서 동일한 기능의 디바이스를 구현할 때 이 문서를 기준으로 삼는다.

### 읽는 순서

1. **이 문서 (00)** → 시스템 전체 파악
2. **01_system_architecture** → 프로세스 구조, IPC 이해
3. **18_hal_specification** → 플랫폼별 구현 필요 항목 파악
4. **15_data_formats** → 데이터 포맷 (TLV, IMF) 이해
5. 나머지 문서는 기능 영역별로 필요에 따라 참조

### [HAL] 표기 규약

문서 전체에서 `[HAL]` 태그가 붙은 항목은 **플랫폼별 하드웨어 추상화 계층(Hardware Abstraction Layer) 구현이 필요**한 부분이다. 이 항목들의 전체 목록과 인터페이스 명세는 `18_hal_specification.md`에 정리되어 있다.

---

## 2. 시스템 요약

| 항목 | 사양 |
|------|------|
| **용도** | 차량용 DVR + AI 위험감지 시스템 (차량 관제) |
| **최대 영상 채널** | 16채널 (HDS 모델: 4채널 + AVM) |
| **인코딩** | H.264 / H.265 |
| **녹화 저장** | eMMC / SSD / SD카드, 순환 덮어쓰기 |
| **AI 기능** | 객체탐지 (YOLO/SSD), 트래킹, ROI 위험감지 |
| **차량 연동** | CAN bus, GPS, G-sensor, PLC I/O |
| **관제 연동** | MQTT 기반 FMS (이미지/영상 업로드, OTA) |
| **UI** | Qt5 기반 OSD + 웹 인터페이스 |
| **네트워크** | HTTP 서버, 라이브 스트리밍, DHCP, WiFi |
| **오디오** | 녹음, 재생, 안내음, 비프 |

---

## 3. 프로세스 목록

| 프로세스 | 역할 |
|----------|------|
| **PT_MONITOR** | 시스템 모니터링, 프로세스 관리, 설정, 시간 동기화 |
| **PT_RECORDER** | 멀티채널 영상 녹화 (DCI→IMF) |
| **PT_PLAYBACK** | 녹화 영상 재생/검색 |
| **PT_DISKMAN** | 디스크/저장소 관리, 백업, 펌웨어 업데이트 |
| **PT_IOMAN** | I/O 관리 (GPIO, MCU, GPS, G-sensor, CAN, PLC, 알람) |
| **PT_OSD** | Qt 기반 UI (메뉴, 상태바, 뷰 모드) |
| **PT_SUBCTRL** | 영상 입력, 인코딩, 디스플레이, DCI, AI/NPU 제어 |
| **PT_FMS** | MQTT 관제 (AIMSC), 이미지/영상 업로드, OTA |
| **PT_NETWORK** | HTTP 서버, 라이브 스트리밍, 원격 설정 |
| **PT_AUDIOMAN** | 오디오 녹음/재생, 비프, 안내음 |
| **PT_NETMAN** | 네트워크 인터페이스 관리 |
| **PT_HTTP** | HTTP 요청 처리 워커 |

---

## 4. 하드웨어 의존/비의존 분류

### [HAL] 하드웨어 의존 (플랫폼별 구현 필요)

| 영역 | 설명 |
|------|------|
| **영상 입력** | V4L2 카메라 캡처, DMA 버퍼 |
| **영상 인코딩** | H.264/H.265 하드웨어 인코더 |
| **영상 디코딩** | H.264/H.265 하드웨어 디코더 |
| **디스플레이** | DRM/KMS 프레임 출력, 다중 모니터 |
| **이미지 처리** | 리사이즈, 크롭, 컬러변환, 합성 (RGA 대체) |
| **AI 추론** | 딥러닝 모델 로드/추론 (NPU/GPU) |
| **스트림 다중화** | 프로듀서→컨슈머 링 버퍼 (DCI 대체) |
| **오디오** | PCM 캡처/재생 (ALSA) |
| **GPIO** | 디지털 입출력 |
| **워치독** | 하드웨어 타이머 |
| **DMA 버퍼** | 제로카피 메모리 관리 |

### 하드웨어 비의존 (재사용 가능)

| 영역 | 설명 |
|------|------|
| **IPC 시스템** | 프로세스간 메시지 통신, 공유 메모리 |
| **IMF 파일 포맷** | 커스텀 멀티채널 비디오 컨테이너 |
| **TLV 인코딩** | 센서/AI 데이터 구조화 저장 |
| **MQTT 프로토콜** | 관제 서버 통신 |
| **HTTP 서버** | 웹 인터페이스, 원격 제어 |
| **Qt UI** | OSD 메뉴, 상태 표시 |
| **녹화 로직** | 이벤트/연속/주차 녹화 관리 |
| **저장소 관리** | 파일시스템, 순환 덮어쓰기, 백업 |
| **GPS 파싱** | NMEA 프로토콜 |
| **CAN 프로토콜** | 차량 데이터 수신 |
| **설정 시스템** | XML/JSON 기반 설정 관리 |
| **이벤트 시스템** | 이벤트 감지, 기록, 알림 |
| **객체 추적** | SORT/HDS 트래커 알고리즘 |
| **데이터베이스** | 이벤트DB, 검색DB, 주행DB |

---

## 5. 데이터 흐름 개요

```
카메라 (V4L2)                    GPS/G-sensor/CAN
    │                                │
    ▼                                ▼
[HAL] 영상 입력              CarDataStreamManager
    │                                │
    ▼                                │
[HAL] 인코딩 (H.264)                │
    │                                │
    ▼                                ▼
[HAL] 스트림 다중화 버퍼 ◄─── TLV Extra 스트림
    │
    ├──► RecordManager ──► IMF 파일 ──► 스토리지
    │
    ├──► HTTP 라이브 스트리밍
    │
    └──► MQTT FMS 업로드

[HAL] AI 추론 (NPU)
    │
    ▼
객체탐지 결과 ──► HDS 위험감지 ──► PLC 출력
                      │
                      ▼
               HdsDataStream ──► TLV ──► IMF 기록
                      │
                      └──► MQTT 이벤트 업로드
```

---

## 6. 용어 정의

| 용어 | 설명 |
|------|------|
| **DCI** | Data Channel Interface. 커널 레벨 공유 메모리 링 버퍼. 인코딩된 스트림을 녹화/네트워크/라이브 큐로 다중화 |
| **IMF** | Interleaved Media Format. 커스텀 멀티채널 비디오 컨테이너 포맷 |
| **TLV** | Type-Length-Value. 확장 가능한 바이너리 데이터 인코딩 |
| **AVM** | Around View Monitor. 다중 카메라 이미지를 합성한 탑뷰 화면 |
| **HDS** | Hazard Detection System. ROI 기반 객체 위험감지 |
| **PLC** | Programmable Logic Controller. 산업용 디지털 I/O |
| **FMS** | Fleet Management System. MQTT 기반 차량 관제 |
| **AIMSC** | AI Mobile Surveillance Cloud. FMS 구현 모듈 |
| **ROI** | Region of Interest. 객체탐지 관심 영역 |
| **MPP** | Media Process Platform. Rockchip 미디어 처리 프레임워크 (RK3588 전용) |
| **DRM** | Direct Rendering Manager. Linux 디스플레이 출력 프레임워크 |
| **RGA** | Raster Graphics Accelerator. Rockchip 2D 이미지 처리 (RK3588 전용) |
| **RKNN** | Rockchip Neural Network. RK3588 NPU 런타임 (RK3588 전용) |
| **ACC** | Accessory. 차량 시동 전원 상태 |

---

## 7. 문서 목록

| 번호 | 파일명 | 내용 |
|------|--------|------|
| 00 | overview.md | 시스템 전체 개요 (이 문서) |
| 01 | system_architecture.md | 멀티프로세스 구조, IPC, 공유메모리 |
| 02 | video_pipeline.md | 영상 입력, 인코딩, 스트림 다중화 |
| 03 | recording_and_storage.md | 녹화 모드, IMF 포맷, 순환 저장 |
| 04 | playback.md | 재생, 디코딩, 검색 |
| 05 | display_and_view_modes.md | 디스플레이, 뷰 레이아웃, AVM |
| 06 | ai_object_detection.md | AI 추론, 객체탐지, 트래킹 |
| 07 | hds_hazard_detection.md | 위험감지, ROI, PLC 연동 |
| 08 | io_and_vehicle_interface.md | GPIO, MCU, CAN, GPS, G-sensor |
| 09 | audio_system.md | 오디오 녹음/재생, 비프, 안내음 |
| 10 | network_and_streaming.md | HTTP 서버, 라이브 스트리밍 |
| 11 | fleet_management.md | MQTT FMS, 업로드, OTA |
| 12 | ui_osd.md | Qt UI, 메뉴, 상태 표시 |
| 13 | storage_management.md | 디스크 관리, 백업, 파티션 |
| 14 | configuration_system.md | 설정 시스템 |
| 15 | data_formats.md | TLV, IMF, CarData 포맷 상세 |
| 16 | event_system.md | 이벤트 정의, 트리거, 알림 |
| 17 | ota_and_boot.md | A/B 슬롯, OTA, 부트 복구 |
| 18 | hal_specification.md | HAL 인터페이스 명세 |

---

## 8. 현재 구현 참조 (RK3588)

현재 구현의 소스 코드는 다음 경로에 있다. 새 플랫폼 구현 시 참고용으로만 사용한다.

```
app/app_hds/
├── src/              # 프로세스별 구현
│   ├── rkctrl/       # [HAL 집중] 영상 입력/인코딩/디스플레이/AI
│   ├── recorder/     # 녹화 엔진
│   ├── playback/     # 재생 엔진
│   ├── aimsc/        # MQTT FMS
│   ├── osdQt/        # Qt UI
│   ├── ioman/        # I/O 관리
│   ├── diskman/      # 디스크 관리
│   ├── monitor/      # 시스템 모니터
│   ├── network/      # 네트워크/HTTP
│   └── audioman/     # 오디오
├── lib/              # 공유 라이브러리
├── ipc/              # IPC 정의
├── include/          # 공용 헤더
└── res/              # 리소스 (스크립트, 이미지, 웹)
```
