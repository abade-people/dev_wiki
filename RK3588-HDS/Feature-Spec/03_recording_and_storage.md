# 녹화 및 저장

> **참조 소스**: `src/recorder/RecorderApp.cc`, `src/recorder/RecordManager.cc`, `src/recorder/RecordChannel.cc`, `src/recorder/RecordStreamFile.cc`, `src/recorder/EventStreamManager.cc`, `lib/imf/`

---

## 1. 녹화 엔진 개요

RecordManager는 스트림 다중화 버퍼(DCI)에서 인코딩된 데이터를 읽어 IMF 파일로 기록하는 핵심 엔진이다.

### 1.1 메인 루프

```
RecordManager 루프 (50ms 주기):
    │
    ├── select(DCI fd, 50ms timeout)     ← 데이터 대기
    │
    ├── ReqRecStream(info, index)         ← 스트림 팝
    │
    ├── IsRecordStream() 필터링           ← 채널/이벤트 조건
    │
    ├── GetMemoryReadHandle()             ← 데이터 접근
    │
    ├── DCI → IMF 변환:
    │   ├── Video → ImfVideoStream
    │   ├── Audio → ImfAudioStream
    │   └── TLV Extra:
    │       ├── TLV_TYPE_CAR_DATA → ImfCarDataStream
    │       ├── TLV_TYPE_OBJECT_LIST → ImfHdsDataStream
    │       └── TLV_TYPE_LOG_LIST → ImfLogStream
    │
    ├── RecordStreamFile::RecordStream()  ← IMF 기록
    │
    ├── FreeMemoryHandle()                ← 버퍼 해제
    │
    └── AckRecStream()                    ← 읽기 완료
```

### 1.2 TLV 처리 주의사항

`TLV_TYPE_OBJECT_LIST` 처리 시, 모든 child TLV를 추가한 후 **1회만** RecordStream을 호출해야 한다. child마다 호출하면 동일 시간에 SID가 분할되는 버그가 발생한다.

```
올바른 처리:
  for (each child in OBJECT_LIST):
      if OBJECT → AddObjectData()
      if PLC_OUT → AddPlcOutData()
      if OBJ_SPEC → AddSpecData()
  RecordStream() ← 모든 child 추가 후 1회 호출
```

---

## 2. 녹화 모드

### 2.1 일반 녹화 (ACC 모드)

- **트리거**: 시동 ON (ACC 전원)
- **동작**: 연속 녹화
- **채널**: 활성 채널 전체
- 시동 OFF 시 녹화 중지

### 2.2 이벤트 녹화

- **트리거**: 외부 이벤트 (알람, 충격, AI 감지 등)
- **사전 녹화 (Pre-record)**: 이벤트 발생 전 N초 (DCI 큐 딜레이 활용)
- **사후 녹화 (Post-record)**: 이벤트 발생 후 N초
- **보존**: 이벤트 녹화 파일은 순환 삭제에서 보호

```
이벤트 발생
    │
    ▼
AddEventInDb()          ← EventDb에 기록
    │
    ▼
Pre-record 확보          ← DCI 큐 버퍼에서 과거 데이터
    │
    ▼
Post-record 녹화          ← 설정 시간만큼 추가 녹화
    │
    ▼
SegmentCloseNotify()     ← 세그먼트에 이벤트 플래그 설정
```

### 2.3 주차 모드 녹화

- **트리거**: 시동 OFF 상태에서 이벤트 발생
- **프리레코딩 활성**: DCI 큐에 0~300초 버퍼 유지
- **이벤트 시에만 녹화 시작**
- CONFIG_PARKING_RECORD_MODE로 활성화

### 2.4 패닉 녹화

- **트리거**: 긴급 이벤트
- **동작**: 즉시 녹화 시작, 보존 플래그 자동 설정
- CONFIG_SUPPORT_PANIC_RECORD로 활성화

---

## 3. 채널 관리

### 3.1 RecordChannel

채널별 독립 녹화 관리:

| 속성 | 설명 |
|------|------|
| 채널 번호 | 0~15 |
| 이벤트 플래그 | 활성 이벤트 비트마스크 |
| Pre/Post 시간 | 채널별 설정 |
| 활성 상태 | 녹화 중/정지 |

### 3.2 채널 마스크

- 비트마스크로 녹화 대상 채널 선택
- 채널별 독립 해상도/FPS/화질 설정
- 최대 16채널이 하나의 IMF 파일에 인터리브 기록

---

## 4. 이중 저장소

### 4.1 Main / Sub 저장소

| 저장소 | 매체 | 용도 |
|--------|------|------|
| **Main** | eMMC / SSD | 주 녹화 저장 |
| **Sub** | SD카드 | 보조 녹화 또는 백업 |

- 각 저장소는 독립적인 RecordManager 인스턴스
- 동시 녹화 가능

### 4.2 순환 덮어쓰기

저장소가 가득 차면 가장 오래된 파일부터 삭제:

```
녹화 파일 생성
    │
    ▼
디스크 공간 확인
    │
    ├── 충분 → 계속 녹화
    │
    └── 부족 → 가장 오래된 파일 삭제
               (보존 플래그 파일은 제외)
```

### 4.3 보관 기간

- **체크 주기**: 10초
- **정책**: 설정된 기간(일) 초과 파일 자동 삭제
- **이벤트 보존**: preserve 플래그 설정된 파일은 기간 무관 보존

---

## 5. IMF 파일 기록

### 5.1 파일 생성

```
녹화 시작
    │
    ▼
RecordStreamFile 생성
    ├── IMF 파일 생성 (imf_temp_0_NNNNNN.tmp)
    ├── FileHeader 기록
    └── 세그먼트 시작
```

### 5.2 세그먼트 관리

- **세그먼트 시간**: 기본 60초 (설정 가능)
- **세그먼트 닫기**: 시간 경과 또는 크기 한계 도달
- **Footer 기록**: SegmentIndex + SegmentSummary

### 5.3 파일 종료

```
녹화 중지 / 세그먼트 닫기
    │
    ▼
FileFooter 기록
    │
    ▼
임시 파일명 → 정식 파일명 변경
    (imf_temp_*.tmp → {timestamp}_NNNNNN.imf)
    │
    ▼
IM_NOTIFY_RECORD_FILE_CLOSE 전송
```

---

## 6. 녹화 제어 인터페이스

### 6.1 IPC 메시지

| 메시지 | 파라미터 | 설명 |
|--------|----------|------|
| **IM_RECORD_CONTROL** | control_type | 녹화 시작/중지/인코더 제어 |
| **IM_REQ_EVENT_RECORD** | event_source | 이벤트 녹화 요청 |
| **IM_END_EVENT_RECORD** | - | 이벤트 녹화 종료 |
| **IM_CHECK_BOOTUP_RECORD** | - | 부팅 시 자동 녹화 확인 |
| **IM_SET_RECORD_PRESERVE** | - | 보존 설정 |

### 6.2 녹화 제어 타입

| 타입 | 설명 |
|------|------|
| STREAM_START | 녹화 스트림 시작 |
| STREAM_STOP | 녹화 스트림 중지 |
| ENCODER_START | 인코더 시작 |
| ENCODER_STOP | 인코더 중지 |

---

## 7. 데이터베이스

### 7.1 EventDb

이벤트 녹화 정보 기록:
- 이벤트 시각, 타입, 채널, Pre/Post 시간, 보존 플래그

### 7.2 DrivingUnitDb

주행/주차 세션 추적:
- 세션 시작/종료, ACC 모드, 저장소 ID

### 7.3 SearchDb

비디오 검색 인덱스:
- 시간 범위별 파일 매핑
- 이벤트 타입 필터링

---

## 8. 성능 특성

| 항목 | 값 |
|------|-----|
| RecordManager 폴링 | 50ms |
| 세그먼트 시간 | 60초 |
| 쓰기 버퍼 | 512KB |
| 보관 기간 체크 | 10초 |
| 최대 채널 | 16 |
| 최대 파일 크기 | 디스크 여유 공간 기반 |
