# 이벤트 시스템

> **참조 소스**: `ipc/ipc_struct.h` (ipc_event_source_t), `src/recorder/EventStreamManager.cc`, `lib/EventSender.cc`, `lib/EventDb.cc`, `src/ioman/AlarmControl.cc`, `src/ioman/TriggerInputControl.cc`

---

## 1. 이벤트 소스

### 1.1 이벤트 소스 구조

이벤트는 5개 카테고리의 비트 플래그 조합:

```
ipc_event_source_t:
  alarm_flag (u64)    — 알람 입력 (채널별)
  motion_flag (u64)   — 모션 감지 (채널별)
  vloss_flag (u64)    — 영상 손실 (채널별)
  system_flag (u64)   — 시스템 이벤트
  ai_flag (u64)       — AI 감지 이벤트
```

### 1.2 알람 이벤트 (alarm_flag)

| 비트 | 소스 | 트리거 |
|------|------|--------|
| 0~15 | 채널별 알람 입력 | GPIO 외부 센서 |
| 16~31 | 채널별 G-sensor 충격 | G-sensor 임계값 초과 |
| 기타 | 수동 이벤트, 패닉 | 버튼, IPC |

### 1.3 모션 이벤트 (motion_flag)

| 비트 | 소스 | 트리거 |
|------|------|--------|
| 0~15 | 채널별 모션 감지 | 인코더 모션 배열 분석 |

### 1.4 영상 손실 이벤트 (vloss_flag)

| 비트 | 소스 | 트리거 |
|------|------|--------|
| 0~15 | 채널별 영상 손실 | 카메라 신호 없음 |

- `CFG_IGNORE_CONFIRMED_VLOSS_EVENT`: 확인된 VLOSS 이벤트 무시 옵션

### 1.5 시스템 이벤트 (system_flag)

| 비트 | 소스 | 트리거 |
|------|------|--------|
| 속도 초과 | GPS/CAN 속도 | 설정 임계값 초과 |
| 급가속/급감속 | GPS 속도 변화 | 3초간 속도 변화량 |
| 저전압 | 배터리 ADC | 전압 임계값 미달 |
| 디스크 오류 | DiskManager | 쓰기 실패 |

### 1.6 AI 이벤트 (ai_flag)

| 비트 | 소스 | 트리거 |
|------|------|--------|
| 객체 탐지 | HDS 엔진 | ROI 내 객체 감지 |
| 채널별 | 채널 0~3 | HDS 채널별 독립 |

---

## 2. 이벤트 트리거

### 2.1 알람 입력 (AlarmControl)

```
GPIO 알람 핀 상태 변화
    │
    ▼
AlarmControl::ForwardAlarmIn()
    │
    ▼
IM_SET_ALARM_IN → Monitor
    │
    ▼
EventSender → Recorder (IM_REQ_EVENT_RECORD)
```

### 2.2 G-sensor 충격

```
GsensorReceiver 데이터 수신
    │
    ▼
3축 가속도 > 임계값 판별
    │
    ▼
IM_SET_SYSTEM_EVENT_IN → Monitor
    │
    ▼
EventSender → Recorder
```

### 2.3 과속/급가속/급감속

```
GPS/CAN 속도 데이터 (1초 주기)
    │
    ▼
CheckSpeedEvent()
    ├── 현재 속도 > 과속 임계값 → 과속 이벤트
    ├── 3초간 속도 변화 > 급가속 임계값 → 급가속 이벤트
    └── 3초간 속도 변화 < -급감속 임계값 → 급감속 이벤트
    │
    ▼
IM_SET_SYSTEM_EVENT_IN
```

### 2.4 모션 감지

```
인코더 모션 배열 (60x68) 출력
    │
    ▼
모션 영역 카운트 > 임계값
    │
    ▼
IM_SET_MOTION_STATUS → Monitor
```

### 2.5 AI 객체 탐지

```
NPU 객체탐지 결과
    │
    ▼
HDS ROI 내 객체 존재 판별
    │
    ▼
IM_SET_AI_EVENT_IN → Monitor
    │
    ▼
자동 취소 타이머 (SetAiEventAutoCancle)
```

### 2.6 트리거 입력 (TriggerInputControl)

외부 디지털 입력:
- 해저드 에뮬레이션 (좌/우)
- 후진 기어
- 사이드 브레이크

```
GPIO 트리거 핀 변화
    │
    ▼
IM_DO_NOTIFY_TRIGGER_INPUT
```

---

## 3. 이벤트 녹화

### 3.1 이벤트 녹화 흐름

```
이벤트 감지
    │
    ▼
IM_REQ_EVENT_RECORD (source, channel)
    │
    ▼
Recorder:
    ├── AddEventInDb()              ← DB 기록
    ├── Pre-record 확보              ← DCI 큐 버퍼
    ├── Post-record 타이머 설정      ← 설정 시간
    └── 채널별 이벤트 플래그 설정
    │
    ▼
Post-record 시간 경과
    │
    ▼
IM_END_EVENT_RECORD
    │
    ▼
세그먼트 이벤트 플래그 기록
보존 플래그 설정 (순환 삭제 보호)
```

### 3.2 설정

| 항목 | 범위 | 기본값 |
|------|------|--------|
| Pre-record 시간 | 0~300초 | 10초 |
| Post-record 시간 | 0~300초 | 30초 |
| 이벤트 소스별 활성화 | 비트마스크 | 전체 활성 |
| 이벤트 소스별 포워드 | ACTIVE/INACTIVE | - |

### 3.3 이벤트 소스 라우팅

`CFG_SET_MANUAL_EVENT_SOURCE_ROUTING` 활성 시, 이벤트 소스별로 녹화 채널을 수동 매핑할 수 있다.

---

## 4. 이벤트 알림

이벤트 발생 시 다양한 채널로 알림을 전송:

### 4.1 DO(Digital Output) 알림

```
IM_DO_CONTROL (output_pin, value)
    → GPIO 출력 변경 (LED, 부저, 릴레이)
```

알림 종류:
- `IM_DO_NOTIFY_SYSTEM_CHECK` — 시스템 점검
- `IM_DO_NOTIFY_TRIGGER_INPUT` — 트리거 입력
- `IM_DO_NOTIFY_AI` — AI 감지

### 4.2 오디오 알림

```
IM_PLAY_BEEP → AudioMan → 비프음 재생
IM_PLAY_VOICE → AudioMan → 안내음 재생
```

### 4.3 이메일 알림

```
EventSender → EmailManager → SMTP 전송
```
- 이벤트 타입, 시각, 스냅샷 첨부

### 4.4 FMS 알림

```
EventSender → IM_HDS_OBJECT_DETECT → AIMSC
    → MQTT 이벤트 메시지 전송
    → 결과 이미지 업로드 (Presigned URL)
```

### 4.5 네트워크 알림

- PushManager: 원격 푸시 알림
- IM_SET_NETWORK_EVENT_SENDED: 네트워크 이벤트 전송 확인

---

## 5. 이벤트 기록

### 5.1 EventDb

파일 기반 데이터베이스:

| 필드 | 설명 |
|------|------|
| time | 이벤트 발생 시각 |
| pre_time | 사전 녹화 시간 |
| post_time | 사후 녹화 시간 |
| type | 이벤트 타입 비트마스크 |
| channel | 채널 비트마스크 |
| preserve | 보존 플래그 |

### 5.2 로그 스트림

LogStreamManager가 이벤트를 포함한 시스템 로그를 TLV로 패키징하여 DCI Extra 스트림(인덱스 1)으로 전달 → IMF 파일에 기록.

- **주기**: 500ms
- **포맷**: TLV_TYPE_LOG_LIST → TLV_TYPE_LOG 배열

---

## 6. 이벤트 검색

### 6.1 검색 조건

- **시간 범위**: 시작~종료 시각
- **이벤트 타입**: 비트마스크 필터
- **채널**: 채널 비트마스크
- **운행/주차 모드**: DrivingUnitDb 연동

### 6.2 검색 결과

- 시간 차트 (월/일/시/분 단위)
- 이벤트 목록 (시각, 타입, 채널, 스냅샷)
- IMF 파일 오프셋 매핑

---

## 7. 자동 이벤트 관리

### 7.1 이벤트 자동 취소

AI 이벤트 등 지속적 이벤트는 자동 취소 타이머가 동작:
- 설정 시간 후 자동으로 이벤트 해제
- `SetAiEventAutoCancle()` 함수

### 7.2 알람 출력 지연

알람 출력(DO)은 OFF 지연 설정 가능:
- `SetAlarmOffDelay()`: N초 후 알람 출력 OFF
- `RemoveAlarmOffDelay()`: 즉시 OFF
