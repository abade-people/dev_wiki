# UI/OSD 시스템

> **참조 소스**: `src/osdQt/OsdQtMainApp.cc`, `src/osdQt/OsdQt*Menu.cc`, `src/osdQt/OsdQtViewModeControl*.cc`, `src/osdQt/resource/qml/`

---

## 1. Qt 기반 UI 프레임워크

### 1.1 개요

- **프레임워크**: Qt5 (QML + C++)
- **프로세스**: PT_OSD
- **진입점**: OsdQtMainApp

### 1.2 화면 구성

```
┌──────────────────────────────────┐
│ TitleBar (제목, 모델 정보)        │
├──────────────────────────────────┤
│                                  │
│   Main Screen                    │
│   (라이브 영상 / 재생 / 메뉴)     │
│                                  │
├──────────────────────────────────┤
│ StatusBar (녹화, GPS, 디스크 등)  │
└──────────────────────────────────┘
```

### 1.3 다국어 지원

- `lang/` 디렉토리에 번역 파일
- `IPC_SHM_ITEM_LANGUAGE`로 언어 변경
- 런타임 언어 전환

---

## 2. 메뉴 구조

### 2.1 메인 메뉴 트리

```
MainMenu
├── 녹화 설정 (RecordMenu)
│   ├── 비디오 (해상도, FPS, 화질, 코덱)
│   ├── 이벤트 (Pre/Post 시간, 이벤트 소스)
│   └── 기타 (보관 기간, 순환 덮어쓰기)
│
├── 시스템 설정 (SystemBasicMenu)
│   ├── 일반 (날짜/시간, 언어, 비밀번호)
│   ├── 카메라 (이름, Flip/Mirror, 밝기)
│   ├── 네트워크 (IP, DHCP, DNS, WiFi)
│   ├── 저장소 (포맷, 파티션, 디스크 정보)
│   ├── 버전 (펌웨어, 모델, 시리얼)
│   ├── 트리거 (입력 설정, 이벤트 매핑)
│   └── 진단 (하드웨어 점검)
│
├── AI 설정 (AIConfigMenu)
│   ├── 일반 (트래커 알고리즘, 임계값)
│   ├── 모델 선택 (AIModelConfigMenu)
│   └── ROI 설정 (AIHdsRoiMenu)
│
├── HDS 디스플레이 (HdsDisplayMenu)
│   ├── 기본 뷰 (HdsDisplayDefaultViewMenu)
│   ├── 일반 설정 (HdsDisplayGeneralMenu)
│   ├── OSD 도형 (DisplayShapeOsdMenu)
│   └── PLC 모니터 (SystemPlcMenu)
│
├── 서비스 (ServiceConfigMenu)
│   └── 로그 (ServiceLogMenu)
│
└── 빠른 설정 (QuickSetupMenu)
```

### 2.2 메뉴 항목 유형

| 유형 | 설명 |
|------|------|
| 선택 (Combo) | 드롭다운 목록 |
| 숫자 입력 | 정수/실수 값 |
| 텍스트 입력 | 문자열 |
| 토글 (Switch) | ON/OFF |
| 버튼 | 동작 실행 |
| 슬라이더 | 범위 값 |

---

## 3. 뷰 모드 제어

### 3.1 컨트롤러

| 클래스 | 용도 |
|--------|------|
| OsdQtViewModeControl | 기본 뷰 모드 (멀티 윈도우) |
| OsdQtViewModeControlUx2 | UX2 버전 |
| OsdQtHdsViewModeControl | HDS 특화 뷰 모드 |

### 3.2 뷰 전환

- 터치/마우스 클릭으로 채널 선택
- 더블클릭으로 전체화면 전환
- 뷰 모드 버튼으로 레이아웃 변경

---

## 4. 상태 표시

### 4.1 StatusBar 항목

| 항목 | 표시 |
|------|------|
| 녹화 상태 | 녹화 중/정지/이벤트 |
| GPS 상태 | 수신/미수신/위성 수 |
| 네트워크 | 연결/미연결/IP |
| MQTT | 관제 연결 상태 |
| 디스크 용량 | 사용량/전체 |
| 시스템 시간 | 현재 시각 |
| PLC 상태 | PLC 연결/데이터 |

### 4.2 시스템 정보 (OsdQtSystemInfo)

| 항목 | 설명 |
|------|------|
| CPU 사용률 | % |
| 메모리 사용률 | 사용/전체 MB |
| 디스크 사용률 | 사용/전체 GB |
| CPU 온도 | °C |

---

## 5. 팝업/대화상자

### 5.1 메시지 박스

| 메시지 | 상황 |
|--------|------|
| 저장소 없음 | 디스크 미감지 |
| 알 수 없는 저장소 | 다른 호스트의 저장소 |
| 영상 손실 | 카메라 신호 없음 |
| 포맷 확인 | 디스크 포맷 전 확인 |
| 비밀번호 | 메뉴 접근 시 인증 |

### 5.2 IPC 팝업

```
IM_REQ_OSD_MSGBOX (message_type, text)
    → OSD: 메시지 박스 표시
    → 사용자 응답
IM_OSD_MSGBOX_CLOSE
    → 메시지 박스 닫기
```

- CICS/AIMS 메시지 팝업 지원

---

## 6. 재생 UI

### 6.1 OsdQtPlayBack

- 재생 컨트롤 바 (재생, 정지, 빨리감기 등)
- 시간 차트 (녹화 존재 표시)
- 채널 선택 드롭다운
- 이벤트 필터

---

## 7. PLC 모니터 (OsdQtPlcMonitor)

실시간 PLC 입출력 상태 표시:
- PLC 입력 비트별 ON/OFF 표시
- PLC 출력 비트별 ON/OFF 표시
- 상태 변화 시 즉시 갱신

---

## 8. 백업 대화상자 (OsdQtBackupDialog)

- USB/ODD 대상 선택
- 시간 범위 설정
- 채널 선택
- 진행률 표시

---

## 9. 화면 방향

| 설정 | 효과 |
|------|------|
| 0° | 가로 (기본) |
| 90° | 시계방향 90° 회전 |
| 180° | 180° 회전 |
| 270° | 반시계방향 90° 회전 |

UI 전체와 영상 출력 모두 회전.

---

## 10. 모델 정보

OsdQtModelInfo: 모델명, 시리얼, 펌웨어 버전, 채널 수 등 표시.
