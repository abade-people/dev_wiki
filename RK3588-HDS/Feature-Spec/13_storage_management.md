# 저장소 관리

> **참조 소스**: `src/diskman/DiskManagerApp.cc`, `lib/DiskDevice.cc`, `lib/PhysicalDisk.cc`, `lib/MainStorage.cc`, `lib/ManualBackupManager.cc`, `res/main_storage.sh`, `res/part_cleanup.sh`

---

## 1. 디스크 관리 프로세스 (PT_DISKMAN)

```
DiskManagerApp
├── MainStorage          — 메인 녹화 저장소 (eMMC/SSD)
├── BackupManager        — 수동 백업
├── UpdateUtil           — 펌웨어 업데이트
├── OverallLogBackupUtil — 전체 로그 백업
├── AvmStorage           — AVM LUT 데이터
├── NpuModelStorage      — NPU 모델
├── CustomLogoStorage    — 사용자 로고
└── 외부 저장소 관리      — SD카드, USB
```

---

## 2. 저장소 유형

| 저장소 | 클래스 | 매체 | 용도 |
|--------|--------|------|------|
| **MainStorage** | MainStorage | eMMC/SSD | 주 녹화 |
| **RecordStorage** | RecordStorage | eMMC/SSD | 녹화 파일 관리 |
| **BackupStorage** | ManualBackupManager | USB/ODD | 백업 |
| **ConfigStorage** | ConfigStorage | eMMC | 설정 저장 |
| **DataStorage** | DataStorage | eMMC | 데이터 저장 |
| **SnapStorage** | SnapStorage | eMMC/SD | 스냅샷 |
| **LogStorage** | LogStorage | eMMC | 시스템 로그 |
| **AvmStorage** | AvmStorage | eMMC | AVM LUT |
| **NpuModelStorage** | NpuModelStorage | eMMC | AI 모델 |
| **CustomLogoStorage** | CustomLogoStorage | eMMC | 부팅 로고 |
| **FreeStorage** | FreeStorage | - | 여유 공간 관리 |

---

## 3. 디스크 감지 및 관리

### 3.1 디스크 감지

```
MainStorage: mmcblk[0-9] 패턴으로 eMMC 탐색
DiskGroup: 물리 디스크 그룹 관리
    │
    ▼
PhysicalDisk → LogicalDisk → BlockDevice
```

### 3.2 핫플러그

| 이벤트 | IPC 메시지 |
|--------|-----------|
| 메인 디스크 추가 | IM_MAIN_DISK_ADD |
| 메인 디스크 제거 | IM_MAIN_DISK_REMOVE |
| 외부 디스크 연결 | IM_EXT_DISK_DEVICE_ATTACH |
| 외부 디스크 분리 | IM_EXT_DISK_DEVICE_DETACH |
| 외부 디스크 마운트 | IM_EXT_DISK_DEVICE_MOUNT |
| 외부 디스크 언마운트 | IM_EXT_DISK_DEVICE_UMOUNT |

### 3.3 디스크 정합성 검사

`IM_MAIN_DISK_FIXUP`: 비정상 종료 후 파일시스템/녹화 데이터 검사 및 복구.

---

## 4. 파티션 관리

### 4.1 GPT 파티션 (sgdisk)

SetPartitionTable()에서 sgdisk로 파티션 생성:

| 파티션 | 라벨 | 타입 | 용도 |
|--------|------|------|------|
| 1 | mbfsdata | 0700 | SWAP 영역 |
| 2 | mbfsraw | 0700 | RAW/녹화 영역 |
| 3 | private | 8300 | Private 데이터 (선택) |

### 4.2 MBR 파티션 (sfdisk)

2TB 미만 또는 레거시 호환:
- `/sbin/sfdisk -uS -f`

### 4.3 파티션 정리

`part_cleanup.sh`:
- Protective MBR 클리어
- Primary/Secondary GPT 클리어
- `/sbin/sgdisk -Z` + dd 제로클리어
- 파티션 테이블 재읽기

---

## 5. 파일시스템

### 5.1 지원 파일시스템

| FS | 명령 | 용도 |
|----|------|------|
| **EXT4** | mkfs.ext3 -t ext4 | 기본 (CONFIG_DEFAULT_FILESYSTEM_EXT4) |
| **JFS** | mkfs.jfs -q | RAID 구성 시 |
| **XFS** | mkfs.xfs -f -q | 대용량 |
| **exFAT** | mkfs.exfat | USB 호환 |
| **FAT32** | mkfs.vfat -I -F32 | SD 호환 |
| **NTFS** | mkfs.ntfs -f | Windows 호환 |
| **RAW** | 자체 초기화 | CONFIG_USE_RAW_FILE_SYSTEM |
| **SWAP** | mkswap | 스왑 영역 |

### 5.2 RAW 파일시스템

`CONFIG_USE_RAW_FILE_SYSTEM` 활성 시:
- 파일시스템 없이 직접 블록 디바이스에 기록
- Mass Block 기반 관리 (MassBlockDb)
- 순환 덮어쓰기에 최적화

---

## 6. 백업

### 6.1 수동 백업

ManualBackupManager:
- **대상**: USB, ODD (광학 드라이브)
- **범위**: 시간 범위, 채널 선택
- **포맷**: IMF 파일 복사 또는 AVI 변환

```
IM_MANUAL_BACKUP_CMD (target, time_range, channels)
    │
    ▼
ManualBackupManager:
    ├── ManualBackupToHdd — HDD/USB 백업
    └── ManualBackupToOdd — ODD 백업
```

### 6.2 전체 로그 백업

OverallLogBackupManager:
- 시스템 로그 + 이벤트 로그 통합 백업
- 스냅샷 포함 가능

### 6.3 설정 백업

USB 프리셋 파일:
- `IM_COPY_USB_PRESET` — USB → 디바이스
- `IM_USB_PRESET_FILE_LIST` — USB 파일 목록

---

## 7. RAID 구성 (선택)

`main_storage.sh`:
- mdadm RAID1 구성 지원
- sgdisk 파티션 → mdadm 배열 → mkfs.jfs

---

## 8. 디스크 건강

- HealthCheck: 디스크 읽기/쓰기 테스트
- `CFG_ALLOW_DISK_REPLACEMENT`: 디스크 교체 허용
- 다른 호스트 저장소 감지: `IM_OTHER_HOST_STORAGE_DETECTED`

---

## 9. 미디어 포맷

```
IM_MEDIA_FORMAT (target_disk)
    │
    ▼
녹화 중지
    │
    ▼
파일시스템 포맷 (mkfs)
    │
    ▼
녹화 재시작
    │
    ▼
IM_UPDATE_MEDIA_FORMAT_STATUS
```

---

## 10. USB 파일 관리

| 기능 | IPC |
|------|-----|
| USB 프리셋 파일 목록 | IM_USB_PRESET_FILE_LIST |
| USB 프리셋 복사 | IM_COPY_USB_PRESET |
| USB 차량 디자인 목록 | IM_USB_VEHICLE_DESIGN_FILE_LIST |
| USB 차량 디자인 복사 | IM_COPY_USB_VEHICLE_DESIGN |
| USB 커스텀 로고 복사 | IM_COPY_USB_CUSTOM_LOGO |
| USB NPU 모델 목록 | IM_USB_NPU_MODEL_FILE_LIST |
| USB NPU 모델 복사 | IM_COPY_USB_NPU_MODEL |
