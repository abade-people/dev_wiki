# 영상 파이프라인

> **참조 소스**: `src/rkctrl/VideoInput.cc`, `src/rkctrl/EncStream.cc`, `src/rkctrl/DciDeviceControl.cc`, `src/rkctrl/MppBufferManager.cc`, `src/rkctrl/SnapshotManager.cc`

---

## 1. 전체 흐름

```
[HAL] 카메라 (V4L2)           [HAL] DMA 버퍼 관리
    │                              │
    ▼                              ▼
[HAL] VideoInput ──────► [HAL] MppBufferManager
    (epoll 비동기)              (프레임 버퍼 풀)
                                   │
                                   ▼
                          [HAL] EncStream
                          (H.264/H.265 인코딩)
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
               REC 스트림     NET 스트림     Snapshot
               (녹화용)       (네트워크)     (JPEG)
                    │              │              │
                    ▼              ▼              ▼
              [HAL] Stream Multiplexer (DCI)
                    │
         ┌─────────┼─────────────┐
         ▼         ▼             ▼
     REC 큐    NET 큐        LIVE 큐
         │         │             │
         ▼         ▼             ▼
    Recorder   HTTP Live    Display
```

---

## 2. [HAL] 영상 입력

### 2.1 카메라 캡처

- **인터페이스**: V4L2 호환 (/dev/video0~7)
- **캡처 방식**: epoll 기반 비동기 프레임 수신
- **최대 카메라 수**: 8개 (MAX_VIDEO_INPUT_CNT)
- **프레임 버퍼**: DMA 버퍼, Export FD로 제로카피 전달

### 2.2 카메라 설정

| 항목 | 값 |
|------|-----|
| 입력 포맷 | NV12 (YUV420SP) |
| 최대 해상도 | 1920x1080 |
| 프레임 버퍼 수 | 채널당 최대 10개 |
| Flip/Mirror | 카메라별 독립 설정 |

### 2.3 프레임 수집 흐름

```
1. V4L2 디바이스 open
2. 버퍼 요청 (VIDIOC_REQBUFS)
3. 버퍼 큐잉 (VIDIOC_QBUF)
4. 스트림 시작 (VIDIOC_STREAMON)
5. epoll 대기
6. 프레임 도착 → VIDIOC_DQBUF
7. Export FD → 인코더/디스플레이로 전달
8. 처리 완료 → VIDIOC_QBUF (재사용)
```

---

## 3. [HAL] 영상 인코딩

### 3.1 인코딩 그룹

채널을 4개씩 그룹으로 묶어 병렬 인코딩:
- **Group 0**: 채널 0~3
- **Group 1**: 채널 4~7
- 그룹당 독립적인 인코딩 컨텍스트

### 3.2 채널당 다중 스트림

| 스트림 타입 | 용도 | 코덱 |
|------------|------|------|
| **REC** | 녹화 저장 | H.264/H.265 |
| **NET** | 네트워크 스트리밍 | H.264/H.265 |
| **PB_SNAPSHOT** | 재생 스냅샷 | JPEG |
| **LIVE_SNAPSHOT** | 라이브 스냅샷 | JPEG |

### 3.3 인코딩 파라미터

| 파라미터 | 범위 | 기본값 |
|----------|------|--------|
| **해상도** | 1080P, 720P, 960H, HD1, CIF, VGA | 1080P |
| **FPS** | 30, 25, 15, 10, 5, 1 | 30 (NTSC) / 25 (PAL) |
| **비트레이트** | 250~4000 kbps | 1500 kbps (CBR) |
| **비트레이트 스텝** | 250 kbps | - |
| **코덱** | H.264, H.265 | H.264 |
| **레이트 제어** | CBR (balanced) | CBR |
| **GOP 길이** | FPS 기반 자동 | FPS 값 |

### 3.4 모션 감지

인코더가 프레임 간 움직임 정보를 배열로 출력:
- **배열 크기**: 60 x 68
- **용도**: 소프트웨어 모션 감지 보조 데이터
- IPC 메시지 `IM_SET_MOTION_STATUS`로 모션 상태 전파

### 3.5 실시간 변경

다음 파라미터는 인코딩 중 실시간 변경 가능:
- 비트레이트 (CBR 값)
- FPS
- QP (Quantization Parameter)
- I프레임 강제 삽입

---

## 4. [HAL] DMA 버퍼 관리

### 4.1 버퍼 풀

MppBufferManager가 채널별 버퍼 풀을 관리:
- **할당**: 시작 시 고정 크기 버퍼 풀 생성
- **공유**: Export FD를 통해 프로세스 간 제로카피
- **해제**: 참조 카운트 기반

### 4.2 캐시 관리

| 동작 | 시점 | 이유 |
|------|------|------|
| **CacheWriteback** | 인코딩 전 | CPU 캐시 → 하드웨어 인코더 |
| **CacheInvalidate** | 인코딩 후 | 하드웨어 → CPU 캐시 |

---

## 5. 스트림 다중화

인코딩된 프레임은 스트림 다중화 버퍼(DCI)를 통해 다수 컨슈머에게 배포된다.

### 5.1 프로듀서 패턴

```
인코딩 완료
    │
    ▼
LockHandle()                    ← 스레드 안전
    │
    ▼
ReqNullStream(stream_info)      ← 빈 슬롯 요청
    │
    ▼
GetMemoryWriteHandle(buf)       ← mmap
    │
    ▼
memcpy(buf, encoded_data)       ← 데이터 복사
    │
    ▼
FreeMemoryHandle(buf)           ← munmap
    │
    ▼
AckNullStream(index)            ← 큐 삽입
    │
    ▼
UnlockHandle()
```

### 5.2 스트림 메타데이터 설정

```
stream_info.channel = ch;           // 채널 번호
stream_info.type = I_FRAME/P_FRAME; // 프레임 타입
stream_info.codec = H264/H265;      // 코덱
stream_info.size = encoded_size;     // 데이터 크기
stream_info.time = capture_time;     // 캡처 시각
stream_info.gopid = gop_id;          // GOP ID
stream_info.gopos = gop_offset;      // 0이면 I프레임
```

---

## 6. 스냅샷

### 6.1 스냅샷 모드

| 모드 | 설명 |
|------|------|
| **단일 채널** | 특정 채널 JPEG 캡처 |
| **다중 채널** | 모든 활성 채널 동시 캡처 |
| **AVM 카메라** | AVM 합성 화면 캡처 |
| **화면 스냅샷** | 현재 디스플레이 출력 캡처 |

### 6.2 스냅샷 흐름

```
스냅샷 요청 (IPC: IM_SNAPSHOT_CONTROL)
    │
    ▼
인코더에 JPEG 스냅샷 요청
    │
    ▼
DCI CAP 큐에서 JPEG 데이터 수신
    │
    ▼
파일 저장 (/tmp/capture/ 또는 SnapStorage)
    │
    ▼
완료 통보 (IM_NOTIFY_CAM_CAPTURE_DONE)
```

### 6.3 스냅샷 저장

- **경로**: `/tmp/capture/ch{N}_{timestamp}.jpg`
- **메타데이터**: JPEG Comment 세그먼트에 JSON 삽입 (15_data_formats.md 섹션 4 참조)
- **FMS 업로드**: Presigned URL 통해 S3 업로드

---

## 7. Extra 스트림 (TLV 데이터)

비디오/오디오 외에 센서/AI 데이터도 동일한 다중화 버퍼를 통해 전달된다.

### 7.1 Extra 스트림 종류

| 인덱스 | 프로듀서 | 프로세스 | 데이터 | 주기 |
|--------|----------|----------|--------|------|
| 0 | CarDataStreamManager | ioman | GPS, G-sensor, 속도 | 1초 |
| 1 | LogStreamManager | monitor | 시스템 로그 | 500ms |
| 2 | HdsDataStreamManager | rkctrl | 객체탐지, PLC | 1초 |

### 7.2 Extra 스트림 메타데이터

```
stream_info.type = E_FRAME;      // Extra 타입
stream_info.codec = TLV2;        // TLV 인코딩
stream_info.channel = extra_idx; // Extra 인덱스 (0/1/2)
```

---

## 8. 성능 특성

| 항목 | 값 |
|------|-----|
| 카메라 캡처 | epoll 비동기, <1ms 지연 |
| 인코딩 지연 | <10ms (하드웨어 가속) |
| DCI 큐 딜레이 | 300~1800ms (프리레코딩) |
| 최대 동시 인코딩 | 16채널 × 2스트림 |
| 최대 총 비트레이트 | 약 60 Mbps (16ch × 4Mbps) |
