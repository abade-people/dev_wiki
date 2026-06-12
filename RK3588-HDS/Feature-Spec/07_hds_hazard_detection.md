# HDS 위험감지 시스템

> **참조 소스**: `src/rkctrl/HdsEngine.cc`, `src/rkctrl/HdsOverlayOsdRoi.cc`, `src/rkctrl/HdsDetectResult.cc`, `src/rkctrl/HdsDataStreamManager.cc`, `src/ioman/UartControlIoBoard.cc`

---

## 1. 시스템 개요

HDS(Hazard Detection System)는 AI 객체탐지 결과를 ROI 영역과 비교하여 위험 상황을 판별하고, PLC 출력을 통해 외부 경고 장치를 제어하는 시스템이다.

```
AI 객체탐지 결과
    │
    ▼
HdsEngine: ROI 내 객체 존재 판별
    │
    ├──► PLC 출력 (IO 보드 → 경고등/부저)
    ├──► 이벤트 알림 (비프, 안내음)
    ├──► TLV 데이터 기록 (IMF)
    └──► FMS 이벤트 업로드 (MQTT)
```

---

## 2. ROI 영역 설정

### 2.1 ROI 구조

채널별 독립 ROI 영역 정의:

```
ipc_hds_roi_t:
  채널별 ROI 비트맵 (64비트)
  zone_map: ROI 인덱스 → 존 타입 매핑
```

### 2.2 존 타입

| 존 | 값 | 의미 | 색상 |
|----|---|------|------|
| **Red** | 0x01 | 고위험 영역 | 빨강 |
| **Yellow** | 0x02 | 주의 영역 | 노랑 |
| **없음** | 0x00 | ROI 밖 | - |

### 2.3 ROI 설정 UI

- `OsdQtAIHdsRoiMenu`: ROI 영역 그리기 메뉴
- 그리드 기반 ROI 편집
- 채널별 독립 설정
- IPC 공유 메모리: `ipc_menu_hds_roi_t`

### 2.4 ROI 렌더링

HdsOverlayOsdRoi가 설정된 ROI를 디스플레이에 오버레이:
- 채우기/빈 상자/그리드 패턴
- 존 타입별 색상
- OpenCV 기반 렌더링

---

## 3. 위험 판정 로직

### 3.1 ObjectDetectProc 흐름

```
ObjectDetectProc() — Display Thread (~30fps)
    │
    ├── [1] PLC 입력 읽기 (IpcGetHdsPlcInput)
    │       └── shared memory에서 현재 PLC 입력 상태
    │
    ├── [2] 탐지 결과 순회
    │       └── 각 객체에 대해:
    │           ├── RoiContainsObject(객체 bbox, ROI 비트맵)
    │           ├── 존 타입 결정 (Red/Yellow)
    │           └── objInfo 구조체 설정 (타입, 채널, 신뢰도, 존, bbox, PLC입력)
    │
    ├── [3] AddObjectData(objInfo)
    │       └── HdsDataStreamManager: 1초 구간 TLV 컨테이너에 추가
    │
    └── [4] IpcHdsSetObjDetect(ch, zone)
            └── ioman 프로세스에 검출 통보 → PLC 출력 결정
```

### 3.2 RoiContainsObject

객체 바운딩 박스의 중심점 또는 하단 중심이 ROI 영역 내에 있는지 판별:
- ROI 비트맵의 해당 좌표 비트 확인
- Red/Yellow 존 우선순위: Red > Yellow

---

## 4. PLC 출력 연동

### 4.1 PLC 출력 흐름

```
ioman: OnHdsSetObjDetect(ch, zone) 수신
    │
    ├── SetAiEventAutoCancle()      ← 자동 취소 타이머
    │
    ├── PlcOutProcessEvent()        ← PLC 출력 결정
    │       └── IO 보드로 PLC 패킷 전송
    │       └── shared memory PLC 출력 갱신
    │
    ├── IpcGetHdsPlcOutput()        ← 확정된 PLC 출력 읽기
    │
    └── IpcHdsMetadataPlcOut(plcOut)← rkctrl에 PLC 출력 전달
            │
            ▼
        rkctrl: OnHdsMetadataPlcOut()
            │
            └── AddPlcOutData(plcOut)
                └── 같은 1초 구간 TLV 컨테이너에 PLC_OUT 추가
```

### 4.2 PLC I/O 데이터

```
PLC 입력 (ipc_plcin_info_t):
  input (u32)    — 비트 플래그, 각 비트 = 개별 입력 채널 ON/OFF

PLC 출력 (ipc_plcout_info_t):
  output (u32)   — 비트 플래그, 각 비트 = 개별 출력 채널 ON/OFF
```

### 4.3 IO 보드 UART 통신

UartControlIoBoard가 IO 보드와 UART 통신:

| 명령 | 설명 |
|------|------|
| START | 통신 시작 |
| HEARTBEAT | 생존 신호 |
| PLC_OUT_ALL | PLC 전체 출력 설정 |
| PLC_OUT_BIT | PLC 개별 비트 설정 |
| TRIG_OUT_SET | 트리거 출력 설정 |
| PLC_IN_ACK | PLC 입력 확인 |
| PLC_BYPASS | PLC 바이패스 모드 |

고정 핀:
- 입력: 로봇, 바이패스, 리셋
- 출력: PLC 전체, 장치 실패, 생존신호

### 4.4 PLC 모니터

`OsdQtPlcMonitor`: 실시간 PLC 입출력 상태 UI 표시

---

## 5. HDS 데이터 스트림

### 5.1 1초 단위 패키징

HdsDataStreamManager가 1초 구간의 TLV 컨테이너를 관리:

```
매 200ms (CheckStream 타이머):
    현재 시각 - 1.5초 이전 구간 확인
        │
        └── 해당 구간 완료 → SendStream()
                ├── TLV 바이너리 → DCI Extra 스트림(인덱스 2)
                └── IpcHdsObjectEvent() → AIMSC(MQTT)에 통보
```

### 5.2 TLV 컨테이너 구조

```
TLV_TYPE_OBJECT_LIST (컨테이너)
├── TLV_TYPE_OBJECT      ← 객체 #1 (nPlcIn 포함)
├── TLV_TYPE_OBJECT      ← 객체 #2
├── TLV_TYPE_OBJ_SPEC    ← 추가 정보
├── ...
└── TLV_TYPE_PLC_OUT     ← PLC 출력 값
```

### 5.3 동기화 요구사항

- Object와 PlcOut은 **같은 1초 구간** 컨테이너에 저장
- CheckStream은 구간 완료 후 **1회만** DCI에 전달
- Display Thread와 Main Thread 간 **mutex** 동기화 필요 (mStreamLock)

---

## 6. FMS 이벤트 업로드

### 6.1 MQTT 이벤트 전송

```
SendStream() → IpcHdsObjectEvent()
    │
    ▼
AIMSC: SendObjectEvent()
    ├── 결과 이미지 선택 (/tmp/zone*.jpg)
    ├── JPEG 메타데이터 읽기 (Comment 세그먼트)
    └── MQTT 메시지 전송 (이미지 포함)
```

### 6.2 전송 주기

- **최소 간격**: 1초 (HDS_DATA_STREAM_INTERVAL_SEC)
- AddObjectData() 호출마다 전송하지 않음
- CheckStream이 구간 완료 시에만 트리거

---

## 7. 설정 (ipc_menu_ai_config_t)

| 항목 | 설명 |
|------|------|
| tracker_algo | 트래커 알고리즘 (SORT/HDS) |
| dl_threshold | 탐지 신뢰도 임계값 |
| dl_iou_count | IoU 확인 카운트 |
| dl_iou_score | IoU 매칭 점수 |
| dl_max_object | 최대 객체 크기 |
| dl_min_object | 최소 객체 크기 |
| dl_tracker_count | 트래커 허용 미스 수 |

설정 변경: AI Config 메뉴 → IPC 공유 메모리 갱신 → NpuEngine 재설정
