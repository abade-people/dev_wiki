# I/O 및 차량 인터페이스

> **참조 소스**: `src/ioman/IoManagerApp.cc`, `src/ioman/GpsControl.cc`, `src/ioman/CanControl*.cc`, `src/ioman/GsensorReceiver.cc`, `src/ioman/McuControl.cc`, `src/ioman/AlarmControl.cc`, `src/ioman/TriggerInputControl.cc`, `src/ioman/UartControlIoBoard.cc`, `lib/GpioCtrl.cc`, `src/ioman/CarDataStreamManager.cc`

---

## 1. I/O 관리 프로세스 (PT_IOMAN)

IoManager는 모든 외부 하드웨어 인터페이스를 통합 관리하는 프로세스이다.

```
IoManagerApp
├── [HAL] GpioCtrl          — GPIO 입출력
├── [HAL] McuControl        — MCU UART 통신
├── GpsControl              — GPS 수신/파싱
├── GsensorReceiver         — G-sensor 데이터
├── CanControl              — CAN 버스 통신
├── AlarmControl            — 알람 입출력
├── TriggerInputControl     — 트리거 입력
├── UartControlIoBoard      — IO 보드/PLC
├── RemoteControl           — 리모컨
├── TouchEventDevice        — 터치 입력
├── CarDataStreamManager    — 차량 데이터 TLV 패키징
├── HealthCheck             — 시스템 상태 진단
└── WatchDogTimer           — 워치독
```

---

## 2. [HAL] GPIO 제어

### 2.1 입력 핀

| 용도 | 동작 |
|------|------|
| 알람 센서 입력 | 채널별 ON/OFF 감지 |
| 트리거 입력 | 방향지시등, 후진기어, 사이드브레이크 |
| ACC 전원 감지 | 시동 ON/OFF |
| 전압 감지 (ADC) | 배터리 전압 모니터링 |

### 2.2 출력 핀

| 용도 | 동작 |
|------|------|
| 알람 출력 | LED, 부저 제어 |
| DO(Digital Output) | 릴레이, 외부 장치 |
| 전원 제어 | 3.3V/5.0V 레귤레이터 ON/OFF |
| 프론트 출력 | 경고등, LED 바 |

---

## 3. [HAL] MCU 통신

### 3.1 프로토콜

- **인터페이스**: UART (/dev/ttyS1)
- **보드레이트**: 115200
- **프로토콜**: V2 (CFG_MCU_PROTOCOL_V2)
- **기능**: 주변기기 제어, 전원 관리, 상태 보고

### 3.2 주요 기능

| 기능 | 설명 |
|------|------|
| 시스템 시작/종료 | MCU에 앱 상태 통보 |
| 전원 관리 | ACC ON/OFF 감지, 배터리 관리 |
| 버저 제어 | MCU 내장 버저 |
| MCU 펌웨어 업그레이드 | ISP(In-System Programming) |
| 상태 응답 | MCU 요청에 대한 응답 처리 |

---

## 4. GPS

### 4.1 수신 및 파싱

- **인터페이스**: UART (/dev/ttyS4)
- **프로토콜**: NMEA 0183
- **파싱**: GpsUtil에서 NMEA 문장 해석

### 4.2 GPS 데이터

| 필드 | 단위 | 설명 |
|------|------|------|
| latitude | DDmm.mmmm × 10000 | 위도 (정수 변환) |
| longitude | DDDmm.mmmm × 10000 | 경도 (정수 변환) |
| speed | km/h × 10 | 속도 |
| heading | 도 × 10 | 방향 |
| validity | bool | 유효성 플래그 |
| satellite_count | 개 | 가시 위성 수 |
| time | UTC | GPS 시각 |

### 4.3 GPS 기반 이벤트

| 이벤트 | 판정 기준 |
|--------|----------|
| **과속** | 현재 속도 > 설정 임계값 |
| **급가속** | 3초간 속도 증가 > 임계값 |
| **급감속** | 3초간 속도 감소 > 임계값 |

속도 히스토리를 3초간 유지하여 변화량 계산.

### 4.4 GPS 시간 동기화

```
GPS 유효 신호 수신
    │
    ▼
updateGpsTimeShm()      ← 공유 메모리에 GPS 시간 저장
    │
    ▼
IM_GPS_TIME_SYNC → Monitor
    │
    ▼
TimeSyncer: 시스템 시간 업데이트
```

### 4.5 속도 소스 우선순위

| 우선순위 | 소스 | 조건 |
|----------|------|------|
| 1 | CAN 속도 | CAN 데이터 유효 시 |
| 2 | GPS 속도 | CAN 무효 시 |

`IM_CAN_SPEED_OVERRIDE`, `IM_GPS_SPEED_OVERRIDE`로 오버라이드 가능.

---

## 5. G-Sensor (가속도 센서)

### 5.1 데이터

| 필드 | 단위 | 설명 |
|------|------|------|
| x | mg | X축 가속도 |
| y | mg | Y축 가속도 |
| z | mg | Z축 가속도 |

### 5.2 충격 감지

- 3축 합성 가속도 > 설정 임계값 시 이벤트 발생
- 임계값은 메뉴에서 설정 가능
- `IM_SET_RAW_GSENSOR`: 원본 데이터 공유
- `IM_SET_GFORCE_STAT`: G-Force 통계

---

## 6. CAN Bus

### 6.1 인터페이스

```
CanControl (기본 인터페이스)
├── CanReceiver     — CAN 메시지 수신 (소켓 기반)
└── CanTransmitter  — CAN 메시지 송신
```

### 6.2 지원 프로토콜

| 프로토콜 | 차량 | 클래스 |
|----------|------|--------|
| **Emkorea H-Bus** | 현대 시내버스 | CanControlEmkoreaHbus |
| **Emkorea H-Electown** | 현대 전기버스 | CanControlEmkoreaHElectown |
| **Emkorea H-Universe** | 현대 고속버스 | CanControlEmkoreaHUniverse |
| **KoreaWide BitSensing** | 범용 | CanControlKoreaWideBitSensing |
| **KoreaWide Kia Granbird** | 기아 대형버스 | CanControlKoreaWideKiaGranbird |
| **Motrex Vietnam** | 베트남 시장 | CanControlMotrexVietnam |
| **Movon** | Movon 시스템 | CanControlMovon |

### 6.3 CAN 데이터

| 데이터 | 설명 |
|--------|------|
| 차량 속도 | km/h |
| 방향지시등 (좌/우) | ON/OFF |
| 브레이크 | ON/OFF |
| 사이드 브레이크 | ON/OFF |
| 도어 상태 | 열림/닫힘 |
| 후진 기어 | ON/OFF |
| RPM | 엔진 회전수 |
| 휠 앵글 | 조향 각도 |

### 6.4 커스텀 통합

차량 모델별 커스텀 통합 클래스:
- `CustomIntegrateEmKorea`
- `CustomIntegrateKoreaWide`

---

## 7. CarData 스트림

### 7.1 패키징

CarDataStreamManager가 1초마다 모든 센서 데이터를 TLV로 패키징:

```
매 1초:
  GPS → TLV_TYPE_GPS
  G-sensor → TLV_TYPE_GSENSOR
  속도 → TLV_TYPE_SPEED
  OBD → TLV_TYPE_OBD
  각속도 → TLV_TYPE_ANGULAR
      │
      ▼
  TLV_TYPE_CAR_DATA 컨테이너
      │
      ▼
  DCI Extra 스트림 (인덱스 0) → RecordManager → IMF CARDATA 기록
```

---

## 8. 알람 입출력

### 8.1 알람 입력

- 채널별 최대 16개 알람 입력
- GPIO 폴링 또는 인터럽트 감지
- `AlarmControl::ForwardAlarmIn()` → 이벤트 시스템

### 8.2 알람 출력

- 채널별 알람 출력 제어
- OFF 지연: `SetAlarmOffDelay(N초)` — N초 후 자동 OFF
- `IM_ALARM_OUT` 메시지로 제어

---

## 9. 터치/리모컨 입력

### 9.1 터치 디바이스

| 타입 | 인터페이스 | 설명 |
|------|-----------|------|
| HDMI CEC | CEC 프로토콜 | HDMI 터치 모니터 |
| UART 터치 | UART | 시리얼 터치 패널 |
| Tm1k | 이벤트 디바이스 | Tm1k 터치 컨트롤러 |
| IviewAvn | UART | Iview AVN 터치 |

### 9.2 IR 리모컨

- RemoteControl: IR 수신 → 키 코드 변환
- 다수 제조사 키 테이블 지원 (RemoteControlKeyTables)
- 키 패턴 인식 (CONFIG_RC_KEY_INPUT_PATTERN)

---

## 10. [HAL] 워치독

### 10.1 구현 방식

| 타입 | 설명 |
|------|------|
| **DesignWare WDT** | /dev/watchdog 하드웨어 타이머 |
| **MCU WDT** | MCU 기반 소프트웨어 워치독 |

### 10.2 동작

- Monitor 프로세스가 1초마다 킥
- 모든 프로세스 정상 응답 시에만 킥
- 타임아웃 시 시스템 리부팅

---

## 11. 점검 모드 (InspectionControl)

하드웨어 자가진단:

| 항목 | 확인 내용 |
|------|----------|
| 카메라 | 각 채널 영상 입력 |
| 오디오 | 마이크/스피커 |
| GPS | 수신 상태 |
| G-sensor | 데이터 유효성 |
| 디스크 | 읽기/쓰기 |
| 네트워크 | 링크 상태 |
| MCU | 통신 응답 |

HTTP 검사 프로토콜 (`ServiceInspection`)로 원격 진단 가능.
