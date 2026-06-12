# 차량관제 시스템 (Fleet Management)

> **참조 소스**: `src/aimsc/AIMSCApp.cc`, `src/aimsc/AIMSCSession.cc`, `src/aimsc/AIMSCManager.cc`, `src/aimsc/AIMSCDataSender.cc`, `src/aimsc/AIMSCConnect.cc`, `src/aimsc/AIMSCLiveStream.cc`, `lib/mqtt/`

---

## 1. AIMSC 프로토콜

### 1.1 MQTT 기반 통신

| 항목 | 값 |
|------|-----|
| 프로토콜 | MQTT (Paho C 라이브러리) |
| 프로젝트명 | "HDS" |
| 프로토콜 버전 | "V1" |
| 최대 패킷 크기 | 256KB (비디오 스트리밍용) |
| QoS | 메시지별 0/1/2 |
| yield 주기 | 1초 (50ms timeout) |

### 1.2 세션 관리

```
AIMSCSession:
├── MQTTClient 관리
├── 세션 초기화 (서버 주소, 인증)
├── yield() — 1초마다 호출, 수신 메시지 처리
├── 연결 끊김 시 자동 재접속
└── 하트비트 관리
```

---

## 2. 디바이스 → 서버

### 2.1 하트비트

- **주기**: TIMER_ID_AIMSC_HEARTBEAT (1초)
- **내용**: 디바이스 ID, 상태, 타임스탬프

### 2.2 부팅 알림

```
BootingNotify():
  → 디바이스 정보 (모델, 버전, 채널 수) 전송
```

### 2.3 상태 보고

| 메시지 | 내용 |
|--------|------|
| SendDevInfoResp | 디바이스 정보 (모델, 시리얼) |
| SendStatusInfoResp | GPS, 속도, 녹화 상태 |
| SendVlossEvent | 영상 손실 이벤트 |
| SendObjectEvent | 객체 탐지 이벤트 (이미지 포함) |

### 2.4 이미지 업로드

```
객체 탐지 이벤트
    │
    ▼
CollectAndSelectFiles()     ← /tmp/zone*.jpg 수집
    │
    ▼
SetPresignedFilePath()      ← 대기 맵 등록
    │
    ▼
RequestPresignedUrl()       ← REQ_PRESIGN_URL (MQTT QOS2)
    │
    ▼
서버 응답: RES_PRESIGN_URL (imgUrl)
    │
    ▼
RecvPresignUrlResp()        ← Presigned URL 수신
    │
    ▼
UploadServer(imgUrl, filepath) ← curl PUT 업로드 (detached thread)
    │
    ▼
업로드 완료 → 파일 삭제
```

### 2.5 비디오 업로드

```
서버: REQ_UPLOAD_VIDEO
    │
    ▼
SendUploadVideoResp()       ← 요청 검증
    │
    ▼
ReqSendVideoData()          ← DB 확인
    │
    ▼
StartVideoConversion()      ← IMF → AVI 변환 (백그라운드 스레드)
    │
    ▼
CheckVideoFileMakeStatus()  ← 1초 타이머로 완료 감지
    │
    ▼
RequestPresignedUrl()       ← Presigned URL 요청
    │
    ▼
UploadServer(url, avi_file) ← PUT 업로드
    │
    ▼
EVENT_UPLOAD_VIDEO_DONE     ← 완료 통보
```

### 2.6 라이브 스트리밍

AIMSCLiveStream:
- 멀티채널 비디오/오디오 수집
- 임시 파일 기반 (`/tmp/hds_live_stream.bin`)
- 최대 5분 (300초)
- 스트림 헤더 + 데이터 프레임 구조

---

## 3. 서버 → 디바이스

### 3.1 환경 설정 수신

| 메시지 | 동작 |
|--------|------|
| SetUploadImageConfResp | 이미지 업로드 설정 변경 |
| 원격 설정 변경 | JSON 기반 메뉴 설정 변경 |

### 3.2 펌웨어 다운로드

```
서버: 펌웨어 URL 전달
    │
    ▼
AIMSCFwDownloader:
    ├── URL에서 다운로드 (curl)
    ├── 진행률 추적
    ├── SendFwProgressNotify() → 서버에 진행률 보고
    └── 완료 → OTA 시퀀스 시작 (17_ota_and_boot.md 참조)
```

### 3.3 AI 모델 다운로드

```
서버: AI 모델 URL 전달
    │
    ▼
AiModelDownloader:
    ├── URL에서 다운로드
    ├── SendAiProgressNotify() → 진행률 보고
    └── 완료 → NpuModelStorage에 저장
```

---

## 4. Presigned URL 관리

### 4.1 대기 맵

```cpp
// 키: "camNum_timeStamp"
std::map<std::string, PresignedPendingEntry> mPresignedPendingMap;

PresignedPendingEntry:
  filepath (string)      — 업로드 파일 경로
  registeredAt (long long) — 등록 시각
  imgType (int)          — STILL, AVI, RAW, LIVE
```

### 4.2 타임아웃

- 등록 후 30초 이내 URL 응답 없으면 자동 삭제
- `CleanupExpiredPresignedEntries()`: yield 타이머에서 호출

---

## 5. MQTT 메시지 형식

### 5.1 요청 (디바이스 → 서버)

```json
{
  "projectId": 1234,
  "cpuId": "DEVICE_NAME",
  "msgType": "REQ_PRESIGN_URL",
  "data": { "camNum": 0 },
  "timeStamp": 1709545200000
}
```

### 5.2 응답 (서버 → 디바이스)

```json
{
  "statusCode": 200,
  "reqId": 1709545200000,
  "data": {
    "camNum": 0,
    "imgUrl": "https://s3.amazonaws.com/..."
  }
}
```

---

## 6. 에러 처리

| 상황 | 처리 |
|------|------|
| 요청 파라미터 오류 | retCode=400 응답 |
| 녹화 데이터 없음 | retCode=204 응답 |
| 업로드 진행 중 재요청 | retCode=503 응답 |
| AVI 변환 실패 | EVENT_UPLOAD_VIDEO_FAIL |
| Presigned URL 타임아웃 | 30초 후 자동 정리 |
| MQTT 연결 끊김 | 자동 재접속 |

---

## 7. 타이머

| 타이머 | 주기 | 기능 |
|--------|------|------|
| AIMSC_HEARTBEAT | 1초 | MQTT yield + 하트비트 |
| CHECK_IMAGE_UPLOAD | 1초 | 이미지 업로드 상태 |
| CHECK_VIDEO_UPLOAD | 1초 | 비디오 업로드 상태 |
| CREATE_VIDEO_FILE | 1초 | AVI 변환 완료 감지 |
| CHECK_FW_DOWNLOAD | 가변 | 펌웨어 다운로드 진행 |
| CHECK_AI_DOWNLOAD | 가변 | AI 모델 다운로드 진행 |

---

## 8. 운행 기록

DrivingUnitDb 연동:
- 운행 시작/종료 서버 보고
- 주행/주차 세션별 데이터 집계
