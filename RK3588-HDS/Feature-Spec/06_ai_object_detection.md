# AI 객체탐지

> **참조 소스**: `src/rkctrl/npu/NpuEngine.cc`, `src/rkctrl/npu/ObjectDetect.cc`, `src/rkctrl/npu/NpuModel*.cc`, `src/rkctrl/npu/SortTracker.cc`, `src/rkctrl/npu/HdsTracker.cc`

---

## 1. 전체 파이프라인

```
[HAL] 카메라 프레임 (NV12)
    │
    ▼
프레임 선택 (스킵 카운트 기반)
    │
    ▼
전처리 (crop, resize → 모델 입력 크기)
    │
    ▼
[HAL] NPU 추론 (LoadModel → SetInput → Run → GetOutput)
    │
    ▼
후처리 (NMS, 바운딩박스 디코딩)
    │
    ▼
객체 크기/위치 필터링 (min/max 제한)
    │
    ▼
트래킹 (SORT 또는 HDS Tracker)
    │
    ▼
DetectResult 생성
    │
    ├──► HDS 위험감지 (07_hds_hazard_detection.md)
    ├──► OSD 바운딩박스 렌더링
    └──► TLV 기록 (HdsDataStreamManager)
```

---

## 2. [HAL] 추론 엔진

### 2.1 지원 모델

| 모델 | 입력 크기 | 특징 | 용도 |
|------|----------|------|------|
| **YOLOv5s** | 640×640×3 | 범용, 중간 정확도 | 기본 객체탐지 |
| **YOLOv8n** | 640×640×3 | 경량, 빠른 추론 | 실시간 탐지 |
| **SSD** | 300×300×3 | 가장 경량 | 저사양 환경 |

### 2.2 모델 관리

- **저장소**: NpuModelStorage (eMMC doc 파티션 또는 USB)
- **로드**: 시작 시 설정된 모델 파일 로드
- **교체**: FMS(MQTT)를 통해 원격 모델 다운로드/교체
- **USB 업데이트**: `IM_USB_NPU_MODEL_FILE_LIST` → `IM_COPY_USB_NPU_MODEL`

### 2.3 추론 실행

```
NpuEngine:
  ├── 채널별 ObjectDetect 인스턴스 관리
  ├── 프레임 마스크 기반 채널 활성화/비활성화
  ├── 성능 통계 (PerfStat): 추론 시간, FPS
  └── 결과 수집 → DetectResult
```

---

## 3. 객체탐지 (ObjectDetect)

### 3.1 채널별 독립 처리

각 채널은 독립적인 ObjectDetect 인스턴스:
- 입력 프레임 버퍼
- 추론 결과 버퍼  
- 탐지 결과 (바운딩박스 리스트)
- 트래커 인스턴스

### 3.2 탐지 파라미터 (IPC 설정)

| 파라미터 | IPC 필드 | 설명 |
|----------|----------|------|
| 신뢰도 임계값 | dl_threshold | 최소 탐지 신뢰도 (0~100%) |
| 강제 임계값 | dl_threshold_force | 트래커 승격 시 사용 |
| IoU/확인 카운트 | dl_iou_count | 트래커 확정 프레임 수 |
| IoU 점수 | dl_iou_score | 매칭 IoU 임계값 (÷100) |
| 최대 객체 크기 | dl_max_object | 바운딩박스 최대 크기 필터 |
| 최소 객체 크기 | dl_min_object | 바운딩박스 최소 크기 필터 |
| 트래커 카운트 | dl_tracker_count | 미스 허용 프레임 수 |

### 3.3 프레임 마스크

차량 상태에 따라 탐지 채널을 동적으로 활성화/비활성화:

| 조건 | 활성 채널 |
|------|----------|
| 좌회전 방향지시등 | 좌측 카메라 채널 |
| 우회전 방향지시등 | 우측 카메라 채널 |
| 후진 기어 | 후방 카메라 채널 |
| 평상시 | 전체 또는 설정된 채널 |

---

## 4. 객체 추적 (플랫폼 비의존)

### 4.1 런타임 선택

`ipc_menu_ai_config_t::tracker_algo` 필드로 런타임 전환:

| 알고리즘 | 장점 | 단점 |
|----------|------|------|
| **SortTracker** | 최적 할당, 모션 예측 | 높은 CPU, 오탐 |
| **HdsTracker** | 낮은 CPU, 오탐 필터링 | 최적 아닌 매칭 |

### 4.2 SORT Tracker (Kalman + Hungarian)

```
탐지 결과 입력
    │
    ▼
칼만 필터 예측 (8-상태: x, y, w, h + 속도)
    │
    ▼
헝가리안 알고리즘 (최적 할당)
    │
    ▼
매칭된 트랙 업데이트 / 미매칭 트랙 coast / 새 트랙 생성
    │
    ▼
추적 결과 출력 (Track ID + bbox)
```

- **파라미터**: max_age, min_hits, iou_threshold
- **의존성**: Eigen 라이브러리 (행렬 연산)

### 4.3 HDS Tracker (Greedy IoU)

```
탐지 결과 입력
    │
    ▼
Greedy IoU 매칭 (IoU 내림차순 정렬 후 순차 매칭)
    │
    ▼
PendingTracklet 관리:
    ├── 새 탐지 → PendingTracklet 생성
    ├── confirm_k 연속 프레임 확인 → Track으로 승격
    └── 미확인 → 폐기
    │
    ▼
갭 프레임: 선형 보간 (마지막 위치 → 재탐지 위치)
    │
    ▼
저신뢰도 매칭: promote_score 부여
    │
    ▼
추적 결과 출력 (Track ID + bbox)
```

- **파라미터**: confirm_k, confirm_iou, track_iou, max_age, promote_score
- **의존성**: STL만 (외부 라이브러리 불필요)

---

## 5. 탐지 결과 데이터

### 5.1 DetectResult 구조

```
DetectResult:
  channel (int)              — 카메라 채널
  objects[]:
    type (int)               — 객체 타입 (person, vehicle 등)
    confidence (float)       — 신뢰도 (0~1)
    bbox (rect)              — 바운딩 박스
    track_id (int)           — 트래킹 ID
```

### 5.2 IPC 전달

```
ipc_object_item_t:
  nType (int)                — 객체 타입
  nCh (int)                  — 채널
  nProp (int)                — 신뢰도 (0~100)
  nZone (int)                — ROI 존 (비트마스크)
  rect (ipc_rect_t)          — 바운딩 박스
  tDetectTime (timeval32_t)  — 검출 시각
  nPlcIn (u32)               — PLC 입력 상태
```

### 5.3 TLV 기록

탐지 결과는 HdsDataStreamManager를 통해 TLV로 인코딩 → DCI Extra 스트림 → IMF 파일 기록. (상세: `15_data_formats.md` 섹션 2.5)

---

## 6. 결과 시각화

### 6.1 OSD 바운딩박스

탐지된 객체의 바운딩 박스를 디스플레이 화면에 오버레이:
- 객체 타입별 색상 구분
- ROI 존 진입 상태 표시 (Red/Yellow)
- 채널별 독립 렌더링

### 6.2 결과 이미지 생성

HdsDetectResult가 JPEG 파일 생성:
- **경로**: `/tmp/zone{idx}_{count}.jpg`
- **내용**: 바운딩 박스가 그려진 프레임
- **메타데이터**: JPEG Comment에 JSON (채널, 존, 시각, 객체 목록)
- **용도**: FMS 이벤트 이미지 업로드
