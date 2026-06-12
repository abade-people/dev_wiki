# OTA 및 부트 관리

> **참조 소스**: `bios/board_v1/hds/bd_conf.h`, `bios/board_v1/hds/cmd_update.c`, `src/monitor/MonitorApp.cc`, `lib/SystemImage.cc`, `lib/BoardConfigPartVar.cc`, `app/app_hds/doc/HDS_OTA_BOOT_RECOVERY.md`, `app/app_hds/doc/HDS_PARTITION_MAP.md`

---

## 1. A/B 슬롯 부팅

### 1.1 파티션 구조

```
eMMC 하드웨어 파티션:
┌──────────────────────────────────────────┐
│ User (mmcblk0)    : u-boot_A, u-boot_B  │
│ GPP1 (mmcblk0gp0) : Slot A (kernel, rootfs, extra) │
│ GPP2 (mmcblk0gp1) : Slot B (kernel, rootfs, extra) │
│ GPP3 (mmcblk0gp2) : 설정 (f-conf, v-conf, env)    │
│ GPP4 (mmcblk0gp3) : 로그                           │
└──────────────────────────────────────────┘
```

### 1.2 슬롯 매핑

| 컴포넌트 | Slot A (partition=0) | Slot B (partition=1) |
|----------|---------------------|---------------------|
| u-boot | u-boot_A (User) | u-boot_B (User) |
| kernel | kernel_A (GPP1) | kernel_B (GPP2) |
| rootfs | initrd_A (GPP1) | initrd_B (GPP2) |
| extra | extra_A (GPP1) | extra_B (GPP2) |

### 1.3 슬롯 선택

`bd_conf_p2_t.partition` 값:
- **0**: Slot A (기본)
- **1**: Slot B

---

## 2. 부트 상태 머신

### 2.1 상태 정의

| 상태 | 값 | 의미 |
|------|---|------|
| **NORMAL** | 0 | 정상 운영 |
| **OTA_TRY_NEW** | 1 | OTA 후 새 슬롯 시도 중 |
| **OTA_FALLBACK** | 2 | 새 슬롯 실패, 이전 슬롯으로 롤백 |
| **HALT** | 3 | 양쪽 모두 실패, 부팅 중단 |

### 2.2 상태 전이

```
              OTA 설치 완료
                   │
                   ▼
        ┌─────────────────┐
        │  OTA_TRY_NEW    │
        │  count=0        │
        └────────┬────────┘
                 │
        ┌────────┴────────┐
        │                 │
   App 성공          count > 5
        │                 │
        ▼                 ▼
  ┌──────────┐   ┌──────────────┐
  │ NORMAL   │   │ OTA_FALLBACK │
  │ count=0  │   │ 슬롯 전환     │
  └──────────┘   └──────┬───────┘
        ▲               │
        │      ┌────────┴────────┐
        │      │                 │
        │ App 성공          count > 5
        │      │                 │
        │      ▼                 ▼
        │ ┌──────────┐   ┌──────────┐
        └─│ NORMAL   │   │  HALT    │
          └──────────┘   └──────────┘
```

### 2.3 boot_count 메커니즘

- **BOOT_COUNT_LIMIT**: 5
- OTA_TRY_NEW 또는 OTA_FALLBACK 상태에서만 u-boot가 boot_count 증가
- NORMAL 상태에서는 boot_count 무변경 → 일반 재부팅에 영향 없음

---

## 3. OTA 업데이트 절차

### 3.1 전체 흐름

```
[1] FMS(MQTT) → 펌웨어 다운로드 URL 수신
        │
        ▼
[2] AIMSCFwDownloader: 펌웨어 다운로드
        │
        ▼
[3] 비활성 슬롯에 펌웨어 기록
        (현재 A 사용 중 → B에 기록)
        │
        ▼
[4] 부팅 설정 변경:
        bd_conf boot_count 0
        bd_conf boot_state 1 (OTA_TRY_NEW)
        bd_conf initrd 1 (Slot B로 전환)
        │
        ▼
[5] 시스템 재부팅
        │
        ▼
[6] u-boot: boot_state == OTA_TRY_NEW
        → boot_count++ (0→1)
        → count(1) <= 5 → Slot B 부팅
        │
        ▼
[7] Slot B 커널/rootfs/App 시작
        │
        ▼
[8] Monitor InitInstance():
        boot_state != NORMAL 감지
        → boot_count=0, boot_state=NORMAL 리셋
        → "OTA boot success" 로그
```

### 3.2 부팅 실패 시 롤백

```
Slot B 부팅 실패 (App 미기동, 커널 패닉 등)
        │
        ▼
워치독 → 리부팅 (5회 반복)
        │
        ▼
u-boot: boot_count > 5
        → partition: 1→0 (Slot A로 전환)
        → boot_state: OTA_FALLBACK
        → boot_count: 0
        │
        ▼
Slot A 부팅 (이전 정상 펌웨어)
        │
        ▼
Monitor: boot_state=OTA_FALLBACK 감지
        → boot_count=0, boot_state=NORMAL 리셋
        → 정상 운영 복귀
```

### 3.3 양쪽 실패

Slot A도 실패 시:
- boot_state = HALT
- 부팅 중단
- 수동 복구 필요

---

## 4. AI 모델 업데이트

### 4.1 흐름

```
FMS → AI 모델 URL
    │
    ▼
AiModelDownloader: 다운로드
    │
    ▼
NpuModelStorage에 저장
    │
    ▼
NpuEngine: 모델 재로드
```

### 4.2 USB 경유

```
IM_USB_NPU_MODEL_FILE_LIST → USB에서 모델 파일 목록
    │
    ▼
IM_COPY_USB_NPU_MODEL → 선택한 모델 복사
```

---

## 5. 시스템 이미지 관리

### 5.1 SystemImage

`CONFIG_PARTITION_IN_MMC` 활성 시:
- 파티션명에 _A/_B 접미사 자동 추가
- 현재 활성 슬롯 기반

### 5.2 SystemUpdate

펌웨어 업데이트 진행:
- UpdateStorage에서 펌웨어 파일 읽기
- 파티션별 기록
- 진행률 표시 (UpdateUtil)

---

## 6. 펌웨어 업데이트 방법

| 방법 | 경로 | 설명 |
|------|------|------|
| **OTA (MQTT)** | FMS → 다운로드 → 기록 | 원격 업데이트 |
| **USB** | USB 삽입 감지 → 펌웨어 발견 → 업데이트 | 로컬 업데이트 |
| **HTTP** | /upgrade → 파일 업로드 → 업데이트 | 웹 업데이트 |

---

## 7. 기존 동작 호환성

| 상황 | 영향 |
|------|------|
| 일반 재부팅 | 없음 (NORMAL 상태에서 boot_count 무변경) |
| sysimg 로컬 업그레이드 | 없음 (boot_state 변경 안함) |
| 기존 장비 | boot_state=0(NORMAL) 기본 → 영향 없음 |
