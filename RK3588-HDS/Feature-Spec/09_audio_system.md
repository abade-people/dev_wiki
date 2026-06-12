# 오디오 시스템

> **참조 소스**: `src/audioman/AudioManagerApp.cc`, `src/audioman/AudioRecorder.cc`, `src/audioman/AudioPlayer.cc`, `src/audioman/BeepPlayer.cc`, `src/audioman/GuidancePlayer.cc`, `src/audioman/SoundPlayer.cc`, `src/audioman/AudioCtrl.cc`

---

## 1. 오디오 프로세스 (PT_AUDIOMAN)

```
AudioManagerApp
├── [HAL] AudioRecorder     — 오디오 녹음 (DCI 프로듀서)
├── [HAL] AudioPlayer       — 오디오 재생 (DCI 컨슈머)
├── BeepPlayer              — 비프음 생성
├── GuidancePlayer          — 안내음 재생
├── SoundPlayer             — WAV 파일 재생
└── [HAL] AudioCtrl         — ALSA 디바이스 제어
```

---

## 2. [HAL] 오디오 녹음

### 2.1 녹음 사양

| 항목 | 값 |
|------|-----|
| 샘플레이트 | 8000Hz |
| 비트깊이 | 16bit |
| 채널 | 모노 |
| 포맷 | PCM |

### 2.2 녹음 흐름

```
ALSA PCM 캡처
    │
    ▼
AudioRecorder (DciMencDevice)
    │
    ▼
DCI Extra 스트림 (Audio 타입)
    │
    ▼
RecordManager → IMF AUDIO 스트림
```

- VLOSS(영상 손실) 플래그 추적
- 비디오 I-프레임 대기 후 녹음 시작
- 오디오 활성 시 DCI 큐 딜레이 최소 150ms 보장

---

## 3. [HAL] 오디오 재생

### 3.1 재생 사양

| 항목 | 값 |
|------|-----|
| 샘플레이트 | 44100Hz / 48000Hz |
| 비트깊이 | 16bit |
| 채널 | 스테레오 |

### 3.2 재생 소스

| 소스 | 설명 |
|------|------|
| IMF 파일 | 녹화 재생 시 오디오 스트림 |
| WAV 파일 | 안내음, 시스템 사운드 |
| 생성 톤 | 비프음 (사인파) |

### 3.3 출력 라우팅

| 출력 | 설명 |
|------|------|
| 스피커 | 내장 스피커 |
| HDMI | HDMI 오디오 출력 |
| USB | USB 오디오 장치 |
| EXT1/EXT2 | 외부 오디오 출력 |

`IM_CHANGE_AUDIO_OUTPUT`으로 출력 변경.

---

## 4. 비프 재생 (BeepPlayer)

### 4.1 기능

- 사인파 기반 비프음 생성
- 주파수/음량 설정 가능
- 비프 시퀀스 지원 (반복 패턴)

### 4.2 사용 시점

| 상황 | 비프 |
|------|------|
| 키 입력 | 짧은 비프 |
| 이벤트 발생 | 연속 비프 |
| 후진 경고 | 반복 비프 |
| 에러 | 장음 비프 |

### 4.3 제어

```
IM_PLAY_BEEP (beep_type, count)
    → BeepPlayer: 사인파 생성 → ALSA 출력
```

---

## 5. 안내음 재생 (GuidancePlayer)

### 5.1 기능

- 다국어 음성 안내 (WAV 파일)
- 안내 큐 (최대 16개)
- 우선순위 기반 재생
- 저장/복원 (재생 중 인터럽트 후 복귀)

### 5.2 사용 시점

| 상황 | 안내 |
|------|------|
| 시동 ON | "녹화를 시작합니다" |
| 시동 OFF | "녹화를 종료합니다" |
| AI 감지 | "위험이 감지되었습니다" |
| 저전압 | "배터리 전압이 낮습니다" |
| 안전벨트 미착용 | "안전벨트를 착용해주세요" |

### 5.3 타이머

- `TIMER_ID_GUIDE_SYSTEM`: 5초 주기로 큐 처리
- 다국어 설정: `IPC_SHM_ITEM_LANGUAGE`

### 5.4 제어

```
IM_PLAY_VOICE (voice_id)
    → GuidancePlayer: WAV 파일 로드 → 큐에 추가 → aplay 실행
```

---

## 6. 사운드 재생 (SoundPlayer)

### 6.1 기능

- WAV/PCM 파일 재생
- 반복 재생 지원
- 중단(Abort) 가능

### 6.2 제어

```
IM_PLAY_SOUND (sound_id)
    → SoundPlayer: aplay 통합 실행
```

---

## 7. [HAL] 오디오 제어 (AudioCtrl)

### 7.1 ALSA 통합

- 오디오 디바이스 열거
- PCM 캡처/재생 설정
- 믹서 제어

### 7.2 볼륨 제어

```
IM_SET_SPEAKER_VOLUME (volume: 0~100)
    → AudioCtrl: ALSA 믹서 볼륨 설정
```

- `TIMER_ID_VOLUME_CTRL`: 500ms 주기 볼륨 스케줄
- ACC 모드, HDMI 상태에 따른 자동 볼륨 조절

### 7.3 HDMI 상태

```
IM_CHANGE_HDMI_STATUS (connected/disconnected)
    → 오디오 출력 라우팅 자동 변경
```

---

## 8. 차량 연동 오디오

### 8.1 차량 상태 기반 안내

| 타이머 | 주기 | 기능 |
|--------|------|------|
| SIDE_BRAKE_CHECK | 가변 | 사이드 브레이크 미해제 경고 |
| SEAT_BELT_CHECK | 가변 | 안전벨트 미착용 경고 |
| BACK_DOOR_CHECK | 가변 | 후미 도어 열림 경고 |
| LOW_BATTERY_CHECK | 가변 | 저전압 경고 |

### 8.2 기본 사운드 변경

```
IM_CHANGE_BASE_SOUND (sound_set)
    → 시스템 사운드 세트 변경 (기본/커스텀)
```

---

## 9. IPC 메시지 요약

| 메시지 | 설명 |
|--------|------|
| IM_SET_AUDIO_PLAYER | 오디오 플레이어 설정 |
| IM_SET_AUDIO_RECORDER | 오디오 녹음기 설정 |
| IM_SET_AUDIO_OUTPUT | 출력 장치 변경 |
| IM_PLAY_SOUND | 사운드 재생 |
| IM_PLAY_VOICE | 안내음 재생 |
| IM_PLAY_BEEP | 비프음 재생 |
| IM_SET_SPEAKER_VOLUME | 볼륨 설정 |
| IM_CHANGE_BASE_SOUND | 기본 사운드 변경 |
| IM_CHANGE_HDMI_STATUS | HDMI 연결 상태 |
