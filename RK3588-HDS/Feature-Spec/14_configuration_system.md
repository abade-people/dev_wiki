# 설정 시스템

> **참조 소스**: `src/monitor/SystemConfig.cc`, `lib/AppXmlConfig.cc`, `lib/AppJsonConfig.cc`, `lib/BoardConfig.cc`, `include/configs/hds_config.h`, `include/ProjectConfig.hh`

---

## 1. 설정 계층

```
빌드 타임 설정 (hds_config.h)
    └── 컴파일 시 기능 ON/OFF (#define)

보드 설정 (BoardConfig)
    └── 하드웨어별 고정 정보 (시리얼, 보드 버전)
    └── 가변 설정 (부팅 슬롯, 네트워크)

앱 설정 (SystemConfig)
    └── XML/JSON 메뉴 설정
    └── 런타임 변경 가능
    └── 공유 메모리로 프로세스 간 배포

커스텀 모드 (CustomModeBase)
    └── 모델 변형별 특수 설정
```

---

## 2. 빌드 타임 설정 (hds_config.h)

### 2.1 핵심 플래그

| 플래그 | 설명 |
|--------|------|
| CONFIG_HDS | HDS 프로젝트 식별자 |
| CFG_PROJECT_NAME | "hds" |
| CONFIG_SUPPORT_AIMSC | MQTT FMS 활성화 |
| CONFIG_USE_HAILO | Hailo NPU 사용 |
| CONFIG_PARTITION_IN_MMC | eMMC 파티션 |
| CONFIG_HDMI_PARALLEL | HDMI 병렬 출력 |
| CONFIG_USE_MULTI_INITRD | A/B 슬롯 OTA |

### 2.2 녹화/인코딩

| 플래그 | 설명 |
|--------|------|
| CONFIG_SUPPORT_PANIC_RECORD | 패닉 녹화 |
| CONFIG_PARKING_RECORD_MODE | 주차 모드 녹화 |
| CONFIG_SD_ENC_CBR_BASE_KBPS | CBR 기본값 (1500) |
| CONFIG_SD_ENC_CBR_STEP_KBPS | CBR 스텝 (250) |
| CFG_USE_ENC_RC_CBR_BALANCED | 균형 CBR |

### 2.3 파일시스템/저장소

| 플래그 | 설명 |
|--------|------|
| CONFIG_USE_WRITE_BUFFER | 쓰기 버퍼 사용 |
| CONFIG_DEFAULT_FILESYSTEM_EXT4 | 기본 FS: EXT4 |
| CONFIG_USE_RAW_FILE_SYSTEM | RAW FS 사용 |

### 2.4 주변기기

| 플래그 | 설명 |
|--------|------|
| CFG_MCU_PROTOCOL_V2 | MCU 프로토콜 버전 |
| CFG_MICOM_DEVICE | MCU UART 경로 |
| CFG_GPS_DEVICE | GPS UART 경로 |
| CONFIG_USE_NETMANAGER | 네트워크 매니저 |

### 2.5 UI/기능

| 플래그 | 설명 |
|--------|------|
| CONFIG_AUTO_GENERATE_WEB_SETUP | 웹 설정 자동 생성 |
| CONFIG_SUPPORT_MULTIPLE_UI | 다중 UI |
| CONFIG_RC_KEY_INPUT_PATTERN | 리모컨 키 패턴 |
| CONFIG_USE_CHECK_SPEED_CHANGE | 속도 변화 감지 |
| CONFIG_USE_DRM_VCONN | DRM VCONN |

---

## 3. 보드 설정 (BoardConfig)

### 3.1 저장 위치

eMMC GPP3 파티션:
- **f-conf**: Part1 (고정, 읽기 전용) — 시리얼, 보드 버전
- **v-conf**: Part2 (가변, 읽기/쓰기) — 네트워크, 부팅 설정

### 3.2 Part2 (가변) 주요 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| partition | u32 | 부팅 슬롯 (0=A, 1=B) |
| boot_count | u32 | 연속 부팅 실패 횟수 |
| boot_state | u32 | 부팅 상태 (NORMAL/OTA_TRY/FALLBACK/HALT) |
| 네트워크 설정 | - | IP, MAC, DHCP 등 |

### 3.3 접근 방법

```
// 앱에서
BoardConfig bdconf;
bdconf.ReadPartVar();
u32 state = bdconf.GetConfig(BDCONF_BOOT_STATE);

// 쉘에서
bd_conf boot_state      # 읽기
bd_conf boot_state 0    # 쓰기
```

---

## 4. 앱 설정 (SystemConfig)

### 4.1 설정 로드/저장

```
Monitor InitInstance():
    SystemConfig.Load()
        ├── XML 설정 파일 읽기
        ├── JSON 보조 설정 읽기
        └── 공유 메모리에 배포
```

### 4.2 설정 카테고리

| 카테고리 | IPC 항목 | 설명 |
|----------|----------|------|
| 녹화 비디오 | MENU_RECORD_VIDEO | 해상도, FPS, 화질, 코덱 |
| 녹화 오디오 | MENU_RECORD_AUDIO | 오디오 녹화 설정 |
| 녹화 이벤트 | MENU_RECORD_EVENT | Pre/Post, 이벤트 소스 |
| 네트워크 일반 | MENU_NETWORK_GENERAL | IP, DHCP, 포트 |
| 네트워크 DNS | MENU_NETWORK_DNS | DNS 서버 |
| 네트워크 SMTP | MENU_NETWORK_SMTP | 이메일 설정 |
| 네트워크 SNMP | MENU_NETWORK_SNMP | SNMP 설정 |
| 네트워크 ACMS | MENU_NETWORK_ACMS | 관제 서버 |
| 네트워크 AIMS | MENU_NETWORK_AIMS | AIMSC 설정 |
| 시스템 일반 | MENU_SYSTEM_GENERAL | 날짜, 언어, 비밀번호 |
| 시스템 이벤트 라우팅 | MENU_SYSTEM_EVENT_ROUTE | 이벤트→채널 매핑 |
| 시스템 트리거 | MENU_SYSTEM_TRIGGER | 트리거 입력 설정 |
| 시스템 알림 | MENU_SYSTEM_NOTIFY | 알림 설정 |
| 장치 저장소 | MENU_DEVICE_STORAGE | 저장소 설정 |
| 장치 GPIO | MENU_DEVICE_GPIO | GPIO 설정 |
| AI 설정 | MENU_AI_CONFIG | AI 파라미터 |
| AI 마스크 | MENU_AI_MASK | AI 마스킹 |
| AI AVM | MENU_AI_AVM_MOD | AVM 모드 |

### 4.3 설정 변경 흐름

```
UI 메뉴 변경 / HTTP 원격 변경 / MQTT 원격 변경
    │
    ▼
IM_SET_MENU_* (설정 구조체)
    │
    ▼
Monitor: 공유 메모리 갱신
    │
    ▼
IPC_SHM_ITEM_* 변경 이벤트 → 관심 프로세스
    │
    ▼
각 프로세스: 설정 적용
    │
    ▼
IM_SAVE_CONFIG → Monitor: 파일 저장
```

---

## 5. 커스텀 모드

### 5.1 모델 변형

| 모델 | 설명 |
|------|------|
| CustomModeAutoitHds | HDS 표준 모델 |
| CustomModeBase | 기본 클래스 |

### 5.2 커스텀 모드 영향

- 타임존 기본값
- 오디오 매핑
- 암호화 설정
- 기능 활성화/비활성화

---

## 6. 펌웨어 환경변수 (FwEnv)

U-Boot 환경변수 접근:

| 변수 | 설명 |
|------|------|
| 디스플레이 방향 | 화면 회전 각도 |
| 기본 뷰 | 부팅 시 기본 뷰 모드 |
| AVM 지원 | AVM 기능 활성화 |
| DVR 지원 | DVR 기능 활성화 |

---

## 7. IPC 메시지 요약

| 메시지 | 설명 |
|--------|------|
| IM_SAVE_CONFIG | 설정 파일 저장 |
| IM_COMMAND_SYSTEM_CONFIG | 시스템 설정 명령 |
| IM_SET/GET_APP_CONFIG | 앱 설정 |
| IM_SET/GET_BOARD_CONFIG | 보드 설정 |
| IM_GET_MENU_CONTENTS | 메뉴 내용 조회 |
| IM_SET/GET_MENU_* | 카테고리별 메뉴 설정 |
