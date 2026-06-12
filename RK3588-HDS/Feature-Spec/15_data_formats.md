# 데이터 포맷

> **참조 소스**: `include/imf/ImfTypes.hh`, `include/Tlv.hh`, `include/TlvTypes.hh`, `ipc/ipc_struct.h`, `lib/imf/`

---

## 1. IMF (Interleaved Media Format)

커스텀 멀티채널 비디오 컨테이너 포맷. 최대 16채널의 영상/오디오/메타데이터를 하나의 파일에 인터리브 저장한다.

### 1.1 파일 구조

```
┌──────────────────────────────┐
│ File Header                  │
│  ├── FileInfo (magic, ver)   │
│  ├── SystemInfo              │
│  │    ├── 채널명, 해상도     │
│  │    ├── SVA (비디오 속성)   │
│  │    └── 암호화 정보        │
│  └── SecureInfo (AES 키)     │
├──────────────────────────────┤
│ Segment 0                    │
│  ├── Video Stream (ch0, I)   │
│  ├── Video Stream (ch0, P)   │
│  ├── Video Stream (ch1, I)   │
│  ├── Audio Stream (ch0)      │
│  ├── CarData Stream (TLV)    │
│  ├── HdsData Stream (TLV)    │
│  ├── Event Stream            │
│  ├── Log Stream              │
│  └── Segment Footer          │
│       ├── SegmentIndex       │
│       └── SegmentSummary     │
├──────────────────────────────┤
│ Segment 1                    │
│  └── ...                     │
├──────────────────────────────┤
│ ...                          │
├──────────────────────────────┤
│ File Footer                  │
│  ├── FileIndex               │
│  └── FileSummary             │
└──────────────────────────────┘
```

### 1.2 스트림 타입

| 타입 | ID | 블록 접두사 | 설명 |
|------|---|------------|------|
| VIDEO | 2 | 'v' | H.264/H.265 비디오 프레임 |
| AUDIO | 1 | 'a' | 오디오 프레임 (PCM/AAC) |
| EVENT | 3 | 'e' | 이벤트 마커 |
| LOG | 4 | - | 시스템 로그 (TLV) |
| MARKER | 5 | - | 주행 단위 마커 |
| CAPTION | 6 | 'p' | 텍스트 캡션 |
| CARDATA | 7 | 'r' | GPS, G-sensor, 속도, OBD (TLV) |
| HDSDATA | 8 | 'h' | 객체탐지, PLC (TLV) |
| EXT_STREAM | 9 | 'x' | 확장 스트림 |

### 1.3 블록 타입

| 타입 | 접두사 | 설명 |
|------|--------|------|
| Simple 블록 | 'v', 'a', 'p', 'e', 'r', 'h', 'n', 'x' | 단일 스트림 데이터 |
| Complex 블록 | 'V', 'A', 'X', 'P', 'M' | 다중 데이터 포함 |

### 1.4 세그먼트

- **세그먼트 시간**: 기본 60초 (설정 가능)
- **자동 분할**: 크기 또는 시간 기준
- 세그먼트 닫힐 때 **Footer**에 인덱스/요약 기록
- Footer 구성:
  - **SegmentIndex**: 프레임별 타이밍, 오프셋 매핑
  - **SegmentSummary**: 채널 마스크, 프레임 수, 통계

### 1.5 비디오 설정

| 항목 | 값 |
|------|-----|
| 멀티스트림 수 (비디오) | 2 (primary + secondary) |
| 멀티스트림 수 (오디오) | 1 |
| 쓰기 버퍼 | 512KB |
| 최대 채널 | 16 |

### 1.6 암호화

- **타입**: AES-128 ECB (IMF_CRYPT_TYPE_AES128_1)
- 비디오/오디오 스트림 데이터만 암호화
- 헤더/인덱스는 평문

### 1.7 마커 타입

| 마커 | 용도 |
|------|------|
| DRIVING_UNIT_START | 주행 시작 |
| DRIVING_UNIT_END | 주행 종료 |
| EVENT_PRESERVE_SET | 이벤트 보존 설정 |
| EVENT_PRESERVE_UNSET | 이벤트 보존 해제 |

---

## 2. TLV (Type-Length-Value)

확장 가능한 바이너리 데이터 인코딩. 센서 데이터, AI 결과, 시스템 로그를 구조화하여 저장한다.

### 2.1 바이너리 구조

```
┌──────────────┬──────────────┬──────────────────┐
│ Type (u32)   │ Length (u32) │ Value (N bytes)  │
└──────────────┴──────────────┴──────────────────┘
```

- **Type**: 데이터 종류 식별자
- **Length**: Value 영역의 바이트 수
- **Value**: 실제 데이터 (중첩 TLV 가능)

### 2.2 타입 목록

| 타입 | ID | 데이터 | 설명 |
|------|---|--------|------|
| **CAR_DATA** | 1 | 중첩 TLV | CarData 컨테이너 |
| **GPS** | 2 | ipc_gps_data_t | GPS 좌표/속도/방향 |
| **GSENSOR** | 3 | ipc_gsensor_data_t | 3축 가속도 |
| **OBD** | 4 | ipc_obd_data_t | OBD 차량 진단 데이터 |
| **ANGULAR** | 5 | ipc_angular_data_t | 각속도 |
| **LOG_LIST** | 6 | 중첩 TLV | 로그 컨테이너 |
| **LOG** | 7 | log_entry_t | 단일 로그 엔트리 |
| **SPEED** | 8 | ipc_speed_data_t | 차량 속도 |
| **OBJECT_LIST** | 9 | 중첩 TLV | HDS 객체 컨테이너 |
| **OBJECT** | 10 | ipc_object_item_t | 단일 탐지 객체 |
| **PLC_OUT** | 11 | ipc_plcout_item_t | PLC 출력 값 |
| **OBJ_SPEC** | 12 | ipc_obj_spec_t | 객체 추가 정보 |

### 2.3 중첩 구조

TLV는 중첩 가능하다. 컨테이너 TLV의 Value가 다시 TLV 목록이 된다.

```
TLV_TYPE_CAR_DATA (컨테이너)
├── TLV_TYPE_GPS      (GPS 데이터)
├── TLV_TYPE_GSENSOR  (가속도 데이터)
├── TLV_TYPE_SPEED    (속도 데이터)
└── TLV_TYPE_ANGULAR  (각속도 데이터)
```

```
TLV_TYPE_OBJECT_LIST (컨테이너)
├── TLV_TYPE_OBJECT   (객체 #1)
├── TLV_TYPE_OBJECT   (객체 #2)
├── TLV_TYPE_OBJ_SPEC (추가 정보)
└── TLV_TYPE_PLC_OUT  (PLC 출력)
```

### 2.4 CarData TLV 패키징

ioman 프로세스의 CarDataStreamManager가 1초마다 수집하여 DCI Extra 스트림(인덱스 0)으로 전달:

```
매 1초:
  GPS 데이터 수집 → AddGpsData()
  G-sensor 데이터 수집 → AddGsensorData()
  속도 데이터 수집 → AddSpeedData()
  OBD 데이터 수집 → AddObdData()
  각속도 데이터 수집 → AddAngularData()
  → TLV_TYPE_CAR_DATA 패키징
  → DCI Extra 스트림으로 전송
```

### 2.5 HdsData TLV 패키징

rkctrl 프로세스의 HdsDataStreamManager가 1초 단위로 패키징:

```
ObjectDetectProc() 호출 시 (Display Thread, ~30fps):
  AddObjectData(objInfo) → TLV_TYPE_OBJECT child 추가

ioman PLC 출력 확정 시:
  AddPlcOutData(plcOut) → TLV_TYPE_PLC_OUT child 추가

매 1초 (CheckStream, Main Thread, 200ms 타이머):
  1초 경과 TLV 컨테이너 → DCI Extra 스트림(인덱스 2)으로 전송
```

---

## 3. IPC 데이터 구조

### 3.1 기본 패턴

모든 IPC 구조체는 `ipc_base_t`를 포함:

```c
#pragma pack(push, 4)  // 4바이트 정렬

typedef struct {
    int size;       // 구조체 전체 크기
    u32 mask;       // 변경 필드 비트마스크
} ipc_base_t;

// 공유 메모리 선언 매크로
#define DECLARE_IPC_STRUCT(type, var) \
    type var; memset(&var, 0, sizeof(type)); var.size = sizeof(type);
```

### 3.2 주요 구조체

#### 객체 탐지 관련

```
ipc_object_item_t:
  nType (int)           — 객체 타입 (person, vehicle 등)
  nCh (int)             — 카메라 채널
  nProp (int)           — 검출 신뢰도 (0~100%)
  nZone (int)           — ROI 존 (비트마스크, 0x01=Red, 0x02=Yellow)
  rect (ipc_rect_t)     — 바운딩 박스 (left, top, width, height)
  tDetectTime (timeval32_t) — 검출 시각
  nPlcIn (u32)          — 검출 시점 PLC 입력 상태

ipc_plcout_item_t:
  nPlcOut (u32)         — PLC 출력 값 (비트 플래그)
  tTime (timeval32_t)   — PLC 출력 확정 시각
```

#### GPS 관련

```
ipc_gps_data_t:
  latitude (s32)        — 위도 (DDmm.mmmm * 10000)
  longitude (s32)       — 경도 (DDDmm.mmmm * 10000)
  speed (u16)           — 속도 (km/h * 10)
  heading (u16)         — 방향 (도 * 10)
  validity (u8)         — 유효성 플래그
  satellite_count (u8)  — 위성 수
  time (timeval32_t)    — GPS 시각
```

#### PLC 관련

```
ipc_plcin_info_t:
  input (u32)           — PLC 입력 비트 플래그

ipc_plcout_info_t:
  output (u32)          — PLC 출력 비트 플래그

ipc_plcstatus_info_t:
  status (u32)          — PLC 상태
```

### 3.3 기하 구조체

```
ipc_rect_t:
  left (int), top (int), width (int), height (int)

ipc_size_t:
  width (int), height (int)
```

---

## 4. JPEG 메타데이터 포맷

객체탐지 결과 이미지에 JSON 메타데이터를 JPEG Comment 세그먼트(마커 0xFFFE)에 삽입:

```json
{
  "channel": 0,
  "zone": 1,
  "snap_count": 5,
  "timestamp": 1709545200,
  "object_count": 2,
  "objects": [
    {
      "type": 1,
      "prop": 92,
      "x": 100,
      "y": 200,
      "width": 50,
      "height": 80
    }
  ]
}
```

---

## 5. 이벤트 DB 포맷

파일 기반 데이터베이스 (FileDb/EventDb):

| 필드 | 타입 | 설명 |
|------|------|------|
| time | timeval | 이벤트 발생 시각 |
| pre_time | int | 사전 녹화 시간(초) |
| post_time | int | 사후 녹화 시간(초) |
| type | u32 | 이벤트 타입 비트마스크 |
| channel | u32 | 채널 비트마스크 |
| preserve | u8 | 보존 플래그 |

---

## 6. 주행 단위 DB

DrivingUnitDb: 주행/주차 세션 추적

| 필드 | 타입 | 설명 |
|------|------|------|
| start_time | timeval | 세션 시작 시각 |
| end_time | timeval | 세션 종료 시각 |
| mode | int | ACC/주차 모드 |
| disk_id | int | 저장소 ID |
