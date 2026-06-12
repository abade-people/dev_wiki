# 시스템 아키텍처

> **참조 소스**: `ipc/ipc_message.h`, `ipc/ipc_struct.h`, `lib/AitApp.cc`, `ipc/sharedmem.h`, `ipc/psm.h`

---

## 1. 멀티프로세스 구조

시스템은 독립 프로세스들이 IPC로 통신하는 아키텍처이다. 각 프로세스는 `AitApp` 기본 클래스를 상속하며, 메시지 맵 기반으로 IPC 메시지를 처리한다.

### 1.1 프로세스 목록

| ID | 프로세스 | 비트마스크 | 역할 | 스케줄링 |
|----|----------|-----------|------|----------|
| 0 | PT_MONITOR | 1 << 0 | 시스템 모니터링, 설정, 프로세스 관리 | 일반 |
| 1 | PT_RECORDER | 1 << 1 | 멀티채널 녹화 엔진 | SCHED_FIFO(15) |
| 2 | PT_NETWORK | 1 << 2 | HTTP 서버 관리 | 일반 |
| 3 | PT_DISKMAN | 1 << 3 | 디스크/저장소 관리 | 일반 |
| 4 | PT_PLAYBACK | 1 << 4 | 영상 재생 | 일반 |
| 5 | PT_IOMAN | 1 << 5 | I/O 관리 (GPIO, MCU, 센서) | 일반 |
| 6 | PT_OSD | 1 << 6 | Qt 기반 UI | 일반 |
| 8 | PT_HTTP | 1 << 8 | HTTP 요청 워커 | 일반 |
| 12 | PT_SUBCTRL | 1 << 12 | 영상/인코딩/디스플레이/AI 제어 | 일반 |
| 13 | PT_AUDIOMAN | 1 << 13 | 오디오 관리 | 일반 |
| 17 | PT_FMS | 1 << 17 | MQTT 관제 (AIMSC/CICS) | 일반 |
| 27 | PT_NETMAN | 1 << 27 | 네트워크 인터페이스 관리 | 일반 |

### 1.2 프로세스 생명주기

```
ProcessManager::WakeUpAllProcess()
    │
    ▼
각 프로세스 fork() + exec()
    │
    ▼
AitApp::InitInstance()
    ├── IPC 등록 (IM_REGISTER)
    ├── 의존 프로세스 대기 (WaitProcess)
    ├── 타이머 등록 (AddTimer)
    └── 초기화 완료
    │
    ▼
AitApp::Run() — 메인 루프
    ├── IPC 메시지 수신/디스패치
    ├── 타이머 콜백 실행
    └── OnIdle() 호출
    │
    ▼
AitApp::ExitInstance()
    ├── 리소스 해제
    └── IPC 등록 해제 (IM_UNREGISTER)
```

### 1.3 프로세스 감시

Monitor 프로세스가 1초 주기로 모든 프로세스의 생존을 확인한다.

- **IM_PING_PONG**: Monitor → 각 프로세스, 응답 확인
- **IM_PROCESS_ALIVE**: 각 프로세스 → Monitor, 생존 보고
- **IM_DEAD_PROCESS / IM_STOPPED_PROCESS**: 프로세스 사망 감지 시 브로드캐스트
- **워치독 연동**: 모든 프로세스 정상 시 워치독 타이머 리셋

---

## 2. IPC 메시지 시스템

### 2.1 메시지 구조

메시지는 32비트 정수로 인코딩된다:

```
┌────────────┬──────────┬──────────┬──────────┐
│ TYPE (3bit)│ NR (13bit)│ SIZE1    │ SIZE2    │
└────────────┴──────────┴──────────┴──────────┘
```

- **TYPE**: 메시지 카테고리 (7종)
- **NR**: 카테고리 내 메시지 번호
- **SIZE1/SIZE2**: 파라미터 크기 인코딩

### 2.2 메시지 카테고리

| 카테고리 | ID | 용도 | 예시 |
|----------|---|------|------|
| **PROCESS** | 0 | 프로세스 관리 | PING_PONG, REGISTER, TERMINATE |
| **MENU** | 1 | 메뉴 설정 읽기/쓰기 | SET/GET_MENU_RECORD_VIDEO |
| **INOUT** | 2 | 입출력 이벤트 | KEY_IN, KEY_EMULATE |
| **CONTROL** | 3 | 제어 명령 | RECORD_CONTROL, CAMERA_CONTROL |
| **STATUS** | 4 | 상태 조회/갱신 | SET/GET_VIDEO_LOSS, PLAYBACK_CMD |
| **INFO** | 5 | 정보 교환 | MODEL_INFO, VERSION_INFO |
| **CONFIG** | 6 | 설정 관리 | APP_CONFIG, BOARD_CONFIG |

### 2.3 메시지 송수신

```
// 동기 전송 (응답 대기)
int result = IpcSendMessage(PT_RECORDER, IM_RECORD_CONTROL, arg1, arg2);

// 비동기 전송 (응답 불필요)
IpcPostMessage(PT_ALL, IM_SYSTEM_TIME_CHANGED, 0, 0);
```

### 2.4 메시지 핸들러 등록

```
BEGIN_MESSAGE_MAP(MyApp, AitApp)
    ON_MESSAGE(IM_RECORD_CONTROL, OnRecordControl)
    ON_MESSAGE(IM_TIMER, OnTimer)
END_MESSAGE_MAP()

int MyApp::OnRecordControl(int arg1, int arg2) {
    // arg1, arg2: 메시지 파라미터
    return 0; // 반환값은 송신자에게 전달
}
```

---

## 3. 공유 메모리

프로세스 간 상태 공유를 위해 공유 메모리를 사용한다. 각 데이터 항목은 `ipc_base_t` 구조를 기반으로 한다.

### 3.1 기본 구조

```c
typedef struct {
    int size;       // 구조체 크기
    u32 mask;       // 변경된 필드 비트마스크
} ipc_base_t;
```

### 3.2 주요 공유 메모리 항목

| 항목 | 구조체 | 설명 |
|------|--------|------|
| **IPC_SHM_ITEM_RECORD_VIDEO** | ipc_menu_record_video_t | 녹화 설정 (해상도, FPS, 화질) |
| **IPC_SHM_ITEM_RECORD_AUDIO** | ipc_menu_record_audio_t | 오디오 녹화 설정 |
| **IPC_SHM_ITEM_RECORD_EVENT** | ipc_menu_record_event_t | 이벤트 녹화 설정 |
| **IPC_SHM_ITEM_NETWORK** | ipc_menu_network_t | 네트워크 설정 |
| **IPC_SHM_ITEM_SYSTEM_GENERAL** | ipc_menu_system_t | 시스템 일반 설정 |
| **IPC_SHM_ITEM_AI_CONFIG** | ipc_menu_ai_config_t | AI 설정 |
| **IPC_SHM_ITEM_TIME_ZONE** | - | 타임존 |
| **IPC_SHM_ITEM_CAR_ACC_MODE** | - | ACC(시동) 상태 |
| **IPC_SHM_ITEM_CAMERA_INFO** | ipc_camera_info_t | 카메라 정보 |
| **IPC_SHM_ITEM_VEHICLE_ALIAS** | - | 차량 이름 |
| **IPC_SHM_ITEM_HDS_PLC_INPUT** | ipc_plcin_info_t | PLC 입력 상태 |
| **IPC_SHM_ITEM_HDS_PLC_OUTPUT** | ipc_plcout_info_t | PLC 출력 상태 |

### 3.3 접근 패턴

```c
// 읽기
DECLARE_IPC_STRUCT(ipc_menu_network_t, network);
IpcGetMenuNetwork(&network);

// 쓰기 (변경 후 다른 프로세스에 통보)
network.dhcp = true;
IpcSetMenuNetwork(&network);
```

공유 메모리 항목이 변경되면, 관심 프로세스에 `IPC_SHM_ITEM_*` 갱신 이벤트가 자동 전달된다.

---

## 4. 타이머 시스템

각 프로세스는 독립적인 타이머를 등록할 수 있다.

```c
// 등록
AddTimer(TIMER_ID_HEARTBEAT, 1000);  // 1초 주기

// 핸들러
int OnTimer(TimerIdType timer_id, void* param) {
    switch(timer_id) {
        case TIMER_ID_HEARTBEAT:
            DoHeartbeat();
            break;
    }
    return 0;
}
```

### 주요 타이머 목록

| 프로세스 | 타이머 | 주기 | 용도 |
|----------|--------|------|------|
| Monitor | 프로세스 상태 확인 | 1초 | 전체 프로세스 생존 확인 |
| Monitor | 로그 스트림 | 500ms | 로그 → DCI |
| Recorder | 보관 기간 체크 | 10초 | 만료 파일 삭제 |
| SUBCTRL | HDS 데이터 체크 | 200ms | TLV 컨테이너 전송 |
| FMS | MQTT 하트비트 | 1초 | 세션 유지, yield() |
| FMS | 이미지 업로드 체크 | 1초 | 업로드 상태 확인 |
| AudioMan | 볼륨 제어 | 500ms | 볼륨 스케줄 |
| AudioMan | 안내 시스템 | 5초 | 안내음 큐 처리 |

---

## 5. [HAL] 스트림 다중화 버퍼

현재 구현에서는 `/dev/dci_menc` 커널 드라이버를 사용하지만, 새 플랫폼에서는 동등한 기능을 제공하는 스트림 다중화 시스템을 구현해야 한다.

### 5.1 기능 요구사항

```
┌─ 프로듀서들 (다수) ──────────────┐
│  Video 인코더 (채널 0~15)        │
│  Audio 레코더 (채널 0~15)        │
│  Extra 스트림 (CarData, HDS, Log)│
└──────────┬───────────────────────┘
           │ 쓰기 (비동기)
           ▼
    ┌──────────────────┐
    │  링 버퍼 시스템   │
    │  (다중 큐 모드)   │
    └──────┬───────────┘
           │ 읽기 (폴링)
           ▼
┌─ 컨슈머들 ──────────────────────┐
│  REC 큐: RecordManager (녹화)   │
│  NET 큐: NetworkManager (스트림) │
│  LIVE 큐: Display (프리뷰)       │
│  CAP 큐: Snapshot (캡처)         │
└─────────────────────────────────┘
```

### 5.2 프로듀서 API

| 동작 | 설명 |
|------|------|
| **ReqNullStream(info, index)** | 빈 버퍼 슬롯 요청 |
| **GetMemoryWriteHandle(buf, index, size)** | 쓰기용 메모리 접근 |
| **FreeMemoryHandle(buf, size)** | 메모리 접근 해제 |
| **AckNullStream(index)** | 쓰기 완료 → 큐에 삽입 |

### 5.3 컨슈머 API

| 동작 | 설명 |
|------|------|
| **ReqRecStream(info, index)** | 채워진 버퍼 요청 (팝) |
| **GetMemoryReadHandle(buf, index, size)** | 읽기용 메모리 접근 |
| **FreeMemoryHandle(buf, size)** | 메모리 접근 해제 |
| **AckRecStream(index)** | 읽기 완료 → 버퍼 해제 |

### 5.4 스트림 메타데이터

각 스트림 버퍼에는 다음 메타데이터가 포함된다:

| 필드 | 타입 | 설명 |
|------|------|------|
| channel | u16 | 채널 번호 (0~15) |
| type | u4 | 프레임 타입 (I/P/Audio/Extra) |
| codec | u4 | 코덱 (H264, H265, TLV2) |
| source | u4 | 소스 (REC/NET/LIVE/CAP) |
| size | int | 데이터 크기 |
| time | timeval | 캡처 타임스탬프 |
| gopid | u32 | GOP ID |
| gopos | u32 | GOP 내 오프셋 (0=I프레임) |

### 5.5 Extra 스트림 채널

| 인덱스 | 이름 | 프로듀서 | 데이터 |
|--------|------|----------|--------|
| 0 | CAR_DATA | CarDataStreamManager (ioman) | GPS, G-sensor, 속도, OBD |
| 1 | LOG | LogStreamManager (monitor) | 시스템 로그 |
| 2 | OBJECT_DATA | HdsDataStreamManager (rkctrl) | 객체탐지, PLC 출력 |

### 5.6 큐 관리

| 기능 | 설명 |
|------|------|
| **큐 열기/닫기** | 모드별 독립 관리 (REC/NET/LIVE/CAP) |
| **채널 마스크** | 채널별 큐 포함 여부 비트마스크 |
| **프리레코딩** | N밀리초 분량의 과거 데이터 유지 (300~1800ms) |
| **드롭 통계** | 큐 오버플로 시 드롭 카운트 |

---

## 6. 프로세스 간 의존 관계

시스템 부팅 시 프로세스 시작 순서:

```
Monitor (1번째)
    └── 모든 프로세스 WakeUp
        │
        ├── DiskMan
        │     └── 디스크 초기화 완료
        │
        ├── IoMan
        │     └── WaitProcess(DiskMan)
        │     └── 센서 초기화 완료
        │
        ├── SubCtrl (rkctrl)
        │     └── WaitProcess(DiskMan, IoMan)
        │     └── 카메라/인코더/DCI 초기화
        │     └── → Recorder에 녹화 시작 통보
        │
        ├── Recorder
        │     └── WaitProcess(SubCtrl, OSD, IoMan, DiskMan)
        │     └── DCI 컨슈머 시작
        │
        ├── OSD (Qt)
        ├── AudioMan
        ├── Network/HTTP
        ├── FMS (AIMSC)
        └── NetMan
```

---

## 7. 디버그 시스템

### 7.1 로그 매크로

| 매크로 | 용도 |
|--------|------|
| `ait_error()` | 에러 메시지 (항상 출력) |
| `ait_info()` | 정보 메시지 (항상 출력) |
| `ait_debug()` | 디버그 메시지 (릴리즈에서 제거) |
| `ait_trace()` | 함수 추적 |

### 7.2 런타임 디버그 플래그

각 프로세스에 32비트 디버그 플래그를 런타임에 설정/해제할 수 있다:

- `IM_SET_PROCESS_DEBUG_FLAG_BIT` — 특정 비트 설정
- `IM_CLEAR_PROCESS_DEBUG_FLAG_BIT` — 특정 비트 해제
- `IM_TOGGLE_PROCESS_DEBUG_FLAG_BIT` — 특정 비트 토글

### 7.3 PSM (Performance State Machine)

프로세스별 성능/상태 데이터를 공유 메모리에 게시하여 모니터링 도구에서 조회 가능:

- `IM_PSM_REGISTER` — PSM 등록
- `IM_PSM_UPDATE_DATA` — PSM 데이터 갱신
