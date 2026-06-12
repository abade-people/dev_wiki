# 디스플레이 및 뷰 모드

> **참조 소스**: `src/rkctrl/DisplayManager.cc`, `lib/DrmResource.cc`, `lib/HdmiEdid.cc`, `src/rkctrl/OverlayOsd*.cc`, `src/rkctrl/VncServer.cc`, `src/rkctrl/avm/`, `src/rkctrl/FeatureExtraction.cpp`

---

## 1. [HAL] 디스플레이 출력

### 1.1 출력 포트

| 포트 | 용도 | 필수 |
|------|------|------|
| HDMI | 메인 모니터 | 필수 |
| eDP/LVDS | 보조 모니터 | 선택 |
| 미러링 | 동일 화면 복제 | 선택 |

### 1.2 해상도 자동 감지

HDMI EDID 정보 기반:
- 연결된 모니터의 지원 해상도 자동 감지
- 최적 해상도 자동 설정
- 핫플러그 감지 (IM_SET_HDMI_STATUS)

### 1.3 레이어 구조

```
┌─────────────────────────────────┐
│ Layer 3: OSD (Qt UI)            │ ← 메뉴, 상태바
├─────────────────────────────────┤
│ Layer 2: AI 오버레이            │ ← 바운딩박스, ROI
├─────────────────────────────────┤
│ Layer 1: 비디오                 │ ← 카메라/재생 영상
├─────────────────────────────────┤
│ Layer 0: 배경                   │ ← 단색 또는 패턴
└─────────────────────────────────┘
```

### 1.4 원자적 업데이트

모든 레이어를 동시에 업데이트하여 티어링 방지 (DRM Atomic Commit 또는 동등 메커니즘).

---

## 2. 뷰 레이아웃

### 2.1 레이아웃 카테고리

| 카테고리 | 설명 | 종류 수 |
|----------|------|---------|
| **AVM 뷰** | 탑뷰 + 방향별 카메라 | 40+ |
| **라이브 뷰** | 단일/분할 카메라 | 10+ |
| **HDS 뷰** | 1~4채널 HDS 조합 | 13 |
| **3D 뷰** | 3D 탑뷰 + 방향 | 10+ |

### 2.2 라이브 뷰 모드

| 모드 | 레이아웃 |
|------|----------|
| 단일 (Single) | 1채널 전체화면 |
| 듀얼 (Dual) | 2채널 좌우/상하 분할 |
| 트리플 (Triple) | 3채널 (1대+2소) |
| 쿼드 (Quad) | 4채널 균등 분할 |
| 헥사 (Hexa) | 6채널 (1대+5소) |
| 나인 (Nine) | 9채널 균등 분할 |

### 2.3 HDS 뷰 모드

| 모드 | 레이아웃 |
|------|----------|
| HDS 1채널 | 단일 HDS 채널 전체화면 |
| HDS 2채널 | 2개 HDS 채널 분할 |
| HDS 3채널 | 3개 HDS 채널 (1대+2소) |
| HDS 4채널 | 4개 HDS 채널 균등 |
| HDS + 라이브 | HDS + 일반 카메라 혼합 |

### 2.4 뷰 모드 제어

```
IM_SET_VIEW_MODE (layout_id)
    → DisplayManager: 레이아웃 변경
    → OSD: UI 레이아웃 동기
```

- 기본 뷰 모드 설정: `IM_SET_DEFAULT_VIEW_MODE`
- 뷰 복원: `IM_RESTORE_VIEW_MODE`

---

## 3. AVM (Around View Monitor)

### 3.1 개요

다중 카메라(전/후/좌/우) 영상을 합성하여 탑뷰(Bird's Eye View) 생성.

### 3.2 LUT 캘리브레이션

```
카메라 파라미터 (렌즈 왜곡, 위치)
    │
    ▼
FeatureExtraction: 다이아몬드 패턴 인식
    │
    ▼
LUT(Look-Up Table) 생성
    │
    ▼
AvmStorage에 저장
```

- LUT 업데이트: `IM_AVM_UPDATE_LUT`
- LUT 추출: `IM_AVM_EXTRACT_LUT`
- USB 프리셋: `IM_EXPORT_AVM_PRESET_FILE`

### 3.3 [HAL] 이미지 합성

LUT를 적용하여 4개 카메라 영상을 하나의 탑뷰로 합성:
- 현재 RGA(2D 가속기) 사용
- 대체: GPU OpenGL ES, 소프트웨어 합성
- 실시간 30fps 필요

### 3.4 뷰포인트

- 뷰포인트 프리셋 (AvmViewPointPreset)
- 동적 조건: 차량 상태에 따라 뷰 자동 변경
- `IM_SET_AVM_VIEW_POINT`, `IM_SET_AVM_MOD_DYNAMIC_CONDITION`

---

## 4. 오버레이 (OSD on Video)

### 4.1 타임스탬프 오버레이

영상 위에 날짜/시간/채널명/속도 텍스트 오버레이:
- 위치: 상단/하단, 좌/중/우
- 포맷: 설정 가능

### 4.2 AI ROI 오버레이

HdsOverlayOsdRoi:
- ROI 영역 시각화 (채우기/윤곽선/그리드)
- 존 타입별 색상 (Red/Yellow)
- 바운딩 박스 그리기
- OpenCV 기반 렌더링

### 4.3 도형 오버레이

OverlayOsdShape:
- 다각형, 선, 원 등
- AVM 보기 모드 지원
- 설정 메뉴: `OsdQtDisplayShapeOsdMenu`

---

## 5. 테스트 패턴

| 패턴 | 용도 |
|------|------|
| 컬러바 | 디스플레이 색상 확인 |
| 그레이스텝 | 밝기/대비 확인 |
| 컬러체커 | 카메라 색 보정 |
| 점검 모드 | 제조 검사 화면 |

---

## 6. VNC 서버

### 6.1 기능

- 원격 화면 공유 (네트워크 경유)
- 마우스/터치 이벤트 원격 입력
- H.264/H.265 기반 화면 인코딩

### 6.2 제어

```
IM_SET_VNC_OUTPUT (enable/disable)
    → VncServer: 시작/중지
```

- 네트워크 부하 모니터링
- 프레임레이트 자동 조절

---

## 7. 화면 방향

| 방향 | 각도 | 용도 |
|------|------|------|
| 기본 | 0° | 가로 모니터 |
| 90° | 90° | 세로 모니터 |
| 180° | 180° | 역방향 설치 |
| 270° | 270° | 세로 역방향 |

`eDisplayDirection`으로 설정. UI 및 영상 모두 회전.

---

## 8. IPC 메시지 요약

| 메시지 | 설명 |
|--------|------|
| IM_SET_VIEW_MODE | 뷰 모드 변경 |
| IM_SET_DEFAULT_VIEW_MODE | 기본 뷰 모드 설정 |
| IM_RESTORE_VIEW_MODE | 뷰 모드 복원 |
| IM_CHANGE_DISPLAY_LAYOUT | 디스플레이 레이아웃 변경 |
| IM_SET_HDMI_MODE | HDMI 출력 모드 |
| IM_SET_VOUT_MODE | 비디오 출력 모드 |
| IM_SET_VNC_OUTPUT | VNC 서버 제어 |
| IM_AVM_UPDATE_LUT | AVM LUT 업데이트 |
| IM_SET_AVM_VIEW_POINT | AVM 뷰포인트 |
