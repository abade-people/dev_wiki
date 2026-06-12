# eMMC Partition & Capacity Info

RK3588 HDS 디바이스의 eMMC 칩 사양, HW partition 구성, A/B OTA 슬롯 구조, pSLC 운영 모드 및 용량 정보를 정리한 문서입니다. ext_csd dump 분석 + 프로젝트 OTA/Partition 설계 정보를 기반으로 작성되었습니다.

본 문서는 **두 가지 모델 (64GB / 128GB)** 을 모두 다룹니다. 두 모델은 **동일한 pSLC 정책** 으로 운영되며, **OS/시스템 데이터 영역은 완전 동일**, **USER 영역 (녹화 영상 저장) 크기만 비례 차이** 가 있습니다.

> 128GB 의 ext_csd 값은 실측 dump 기반. 64GB 값은 모델 구성상 추정치 (raw NAND × 1/3 pSLC 변환) — 실측 확보 시 갱신 권장.

---

## 0. 64GB 보드 실측 (2026-05-29, 첫 실기 부팅)

64GB 테스트 보드(첫 플래싱+부팅)에서 `parted print` / `lsblk` 로 확인한 값:

**설계 기준**: 64GB 모델도 128GB 와 **동일하게 pSLC 를 적용**한다 (제품 사양 — 2026-05-29 확인).
따라서 §3 이하의 64GB pSLC 가정(USER ≈ 20 GB)이 설계상 정상이다.

64GB 테스트 보드(첫 플래싱+부팅)에서 `parted print` 로 확인한 값:

| 항목 | 실측값 | 비고 |
|---|---|---|
| parted Model | `MMC DV4064 (sd/mmc)` | 본 문서가 추정한 `MMC064` 와 표기 다름 — PNM 확인 필요 |
| **USER 가시 용량** | **57.2 GiB** | ⚠️ pSLC 적용 시 예상(~20 GiB)과 불일치 — 아래 참조 |
| data 파티션(p6) 확장 후 | **56.6 GiB** | first-boot resize 는 USER 전체 기준으로 정상 동작 |
| GPP4 (`/dev/mmcblk0gp3`) | 존재, ext4 | HW general-purpose 영역 존재 확인 (journal 영속 대상) |
| 파티션 레이아웃 | GPT **6파티션** (BSP) | uboot/boot/rootfs_a/rootfs_b/config/data — §3 끝 BSP 노트 참조 |

> ⚠️ **측정값과 설계의 불일치 — 확인 필요**:
> 설계상 64GB 도 pSLC 적용(→ USER ≈ 20 GiB 예상)이지만, 이 테스트 보드는 **57.2 GiB**
> (raw 64GB 거의 전체)로 측정되었다. 가능한 원인:
> - 이 **테스트 유닛에 pSLC(Enhanced Area)가 아직 활성화되지 않은** 상태일 가능성
>   (factory enhanced-area 설정 미적용 — 양산 유닛과 다를 수 있음).
> - 또는 pSLC 가 **일부 영역(OS/부트)에만** 적용되고 USER 녹화 영역은 TLC 일 가능성.
>
> 아래 `mmc extcsd read` 의 ENH_SIZE_MULT / ENH_START_ADDR / MAX_ENH_SIZE_MULT 값으로
> **이 보드의 pSLC 활성 여부와 영역을 확정**해 본 표를 갱신할 것.

확정 명령 (실기 — 결과를 본 문서에 반영):
```sh
cat /sys/block/mmcblk0/device/name        # PNM (MMC064 vs DV4064 확인)
cat /sys/block/mmcblk0/size                # sector 수 (×512 = bytes)
parted -s /dev/mmcblk0 unit GiB print
# pSLC(Enhanced Area) 활성 여부 — 핵심:
mmc extcsd read /dev/mmcblk0 | grep -iE 'ENH_SIZE_MULT|ENH_START|MAX_ENH|PARTITIONING_SETTING|PARTITIONS_ATTRIBUTE|SEC_COUNT'
```

---

## 1. eMMC 칩 정보 (CID)

`/sys/block/mmcblk0/device/` 조회 결과:

| 필드 | 64GB 모델 (예상) | 128GB 모델 (실측) | 비고 |
|---|---|---|---|
| **CID** | (dump 필요) | `3201014d4d4331323851dab8c0dc4b00` | 16-byte raw |
| **manfid** | `0x32` (동일 가정) | `0x32` | 마이너 제조사 (Foresee/Phison 추정) |
| **oemid** | `0x0101` (동일 가정) | `0x0101` | |
| **name (PNM)** | `MMC064` (추정) | `MMC128` | raw NAND 용량 표기 |
| **PRV** | (모델별) | `0x51` | 제품 리비전 |
| **MDT** | (모델별) | `0x4b` | 제조일자 (2024년 4월) |

→ 모델 구분 명령:
```sh
cat /sys/block/mmcblk0/device/name        # MMC064 vs MMC128
cat /sys/block/mmcblk0/size                # sector 수로 확정
```

---

## 2. eMMC Spec

ext_csd 디코딩 결과 — **두 모델 동일** (spec 차원에서는 차이 없음):

| 항목 | 64GB | 128GB | 의미 |
|---|---|---|---|
| **EXT_CSD_REV** (byte 192) | `0x08` | `0x08` | **eMMC v5.1 (Rev 1.8)** spec |
| **DEVICE_TYPE** (byte 196) | `0x57` | `0x57` | HS400 / HS200 / HS DDR 1.8V 지원 |
| **PARTITIONS_SUPPORT** (byte 160) | `0x07` | `0x07` | Partitioning / Enhanced / Extended Attribute |
| **BOOT_INFO** (byte 228) | `0x07` | `0x07` | ALT/DDR/HS Boot mode 모두 지원 |
| **BOOT_SIZE_MULT** (byte 226) | 32 → **4 MB** | 32 → **4 MB** | Boot 파티션 크기 |

---

## 3. HW Partition + GPT Sub-partition 구조

eMMC 는 4 종류의 HW partition 으로 나뉘고, 각각 다른 용도로 사용됨.

### 두 모델 비교 표

| HW Partition | 디바이스 | 64GB 모델 | 128GB 모델 | 동일 여부 |
|---|---|---|---|---|
| **USER (HW#0)** | `/dev/mmcblk0` | ≈ **20 GB** | ≈ **40.5 GB** | **다름 (raw 비례)** |
|   └ u-boot_A | (offset 4 MB) | 4 MB | 4 MB | 동일 |
|   └ u-boot_B | (offset 8 MB) | 4 MB | 4 MB | 동일 |
|   └ **mbfsraw** | (나머지) | ≈ **20 GB** | ≈ **40 GB** | **다름 (raw 비례)** |
| **BOOT1 (HW#1)** | `/dev/mmcblk0boot0` | 4 MB | 4 MB | 동일 |
| **BOOT2 (HW#2)** | `/dev/mmcblk0boot1` | 4 MB | 4 MB | 동일 |
| **RPMB (HW#3)** | `/dev/mmcblk0rpmb` | 보안 영역 | 보안 영역 | 동일 |
| **GPP1 (HW#4)** | `/dev/mmcblk0gp0` | 256 MB | 256 MB | 동일 |
|   └ kernel_A | | 48 MB | 48 MB | 동일 |
|   └ extra_A | | 16 MB | 16 MB | 동일 |
|   └ **initrd_A (SquashFS)** | | 191 MB | 191 MB | 동일 |
| **GPP2 (HW#5)** | `/dev/mmcblk0gp1` | 256 MB | 256 MB | 동일 |
|   └ kernel_B | | 48 MB | 48 MB | 동일 |
|   └ extra_B | | 16 MB | 16 MB | 동일 |
|   └ initrd_B (SquashFS) | | 191 MB | 191 MB | 동일 |
| **GPP3 (HW#6)** | `/dev/mmcblk0gp2` | 128 MB | 128 MB | 동일 |
|   └ f-conf / v-conf / env / resource / doc | | 동일 분할 | 동일 분할 | 동일 |
| **GPP4 (HW#7)** | `/dev/mmcblk0gp3` | 384 MB | 384 MB | 동일 |
|   └ log (`/mnt/log`) | | 384 MB | 384 MB | 동일 |
| **GPP 합계** | | **1024 MB** | **1024 MB** | 동일 |

### 64GB 모델 레이아웃 (요약)
```
┌────────────────────────────────────────────┐
│ USER (≈20 GB)                              │
│   ├─ u-boot_A (4MB) / u-boot_B (4MB)        │
│   └─ mbfsraw (≈ 20 GB)  = Internal Storage │
├────────────────────────────────────────────┤
│ BOOT1 (4MB) / BOOT2 (4MB) / RPMB           │
├────────────────────────────────────────────┤
│ GPP1 (256MB) — Slot A (kernel/squashfs)    │
│ GPP2 (256MB) — Slot B (kernel/squashfs)    │
│ GPP3 (128MB) — config/env/resource/doc     │
│ GPP4 (384MB) — log                         │
└────────────────────────────────────────────┘
```

### 128GB 모델 레이아웃 (요약)
```
┌────────────────────────────────────────────┐
│ USER (≈40.5 GB)                            │
│   ├─ u-boot_A (4MB) / u-boot_B (4MB)        │
│   └─ mbfsraw (≈ 40 GB)  = Internal Storage │
├────────────────────────────────────────────┤
│ BOOT1 (4MB) / BOOT2 (4MB) / RPMB           │
├────────────────────────────────────────────┤
│ GPP1 (256MB) — Slot A (kernel/squashfs)    │
│ GPP2 (256MB) — Slot B (kernel/squashfs)    │
│ GPP3 (128MB) — config/env/resource/doc     │
│ GPP4 (384MB) — log                         │
└────────────────────────────────────────────┘
```

→ **OS firmware (kernel + rootfs) 와 시스템 데이터 (config/env/log) 는 모델 무관 동일**.
→ 차이는 **mbfsraw (녹화 영상 저장 영역) 크기만 raw NAND 에 비례**.

### ⚠️ 실제 Yocto/BSP 플래싱 레이아웃은 위와 다름 (2026-05-29 실측)

위 표는 **레거시 HDS 디바이스의 네이티브 설계**(A/B 슬롯을 GPP1/GPP2 에 두고, USER 는
u-boot + mbfsraw 녹화 영역)다. 그러나 현재 **Yocto wic 이미지로 플래싱한 보드의 실제
레이아웃은 USER(HW#0) 안에 GPT 6 파티션**으로 구성되어 있다 (BSP 전환 후):

| # | PARTLABEL | FS | 용도 |
|---|---|---|---|
| (raw) | idblock | raw @LBA 0x40 | SPL/TPL (GPT 엔트리 없음) |
| p1 | uboot | raw | U-Boot + TF-A |
| p2 | boot | ext4 | 커널(boot.img) |
| p3 | rootfs_a | squashfs ro | A 슬롯 (루트) |
| p4 | rootfs_b | squashfs ro | B 슬롯 |
| p5 | config | ext4 | /mnt/doc |
| p6 | data | ext4 | 녹화 (first-boot 확장: 64GB→56.6GiB) |

- A/B 슬롯이 **GPP 가 아니라 USER 의 GPT p3/p4** 에 있음 (레거시 설계와 핵심 차이).
- **GPP4(`/dev/mmcblk0gp3`) 는 systemd journal 영속화(`/var/log/journal`)** 에 재활용 — 레거시의 `log` 용도와 유사하나 마운트 지점이 다름.
- 상세 절차/검증: `MarkDown/testing/02_flash_verification_guide.md` (갱신본).

향후 두 문서(레거시 HW 설계 vs Yocto 실제 레이아웃)를 명확히 분리·정합화 필요.

---

## 4. rootfs = **SquashFS** (read-only) + A/B OTA 이중화

두 모델 모두 동일:

- `initrd_A` / `initrd_B` (각 191 MB) 에 **SquashFS** 포맷의 rootfs 가 저장됨
- 부팅 시 `boot_state` 값으로 Slot A 또는 Slot B 의 squashfs 가 mount
- SquashFS 특성:
  - **read-only** → OS 변조 방지 / OTA 무결성 보장
  - **압축** → 191 MB 안에 OS 전체 패킹 가능
  - **block 단위 lazy decompress** → 빠른 부팅, 메모리 효율
  - **CRC 검증** → block 단위 무결성

### A/B OTA Boot Recovery 흐름

| 단계 | 동작 |
|---|---|
| OTA 설치 | 비활성 슬롯에 새 kernel + initrd squashfs 기록 후 `boot_state=OTA_TRY_NEW`, partition 전환 |
| U-Boot | OTA_TRY_NEW / FALLBACK 상태에서 `boot_count++`, 5 회 초과 시 다른 슬롯으로 롤백 |
| Monitor `InitInstance()` | `boot_state != NORMAL` 이면 부팅 성공으로 간주 → NORMAL 리셋 |
| 양쪽 모두 실패 | HALT |

관련 파일:
- `bios/board_v1/hds/cmd_update.c`
- `app_hds/src/monitor/MonitorApp.cc`
- `app_hds/lib/BoardConfigPartVar.cc`

---

## 5. pSLC (Enhanced Area) 운영 상태

**두 모델 모두 동일한 pSLC 정책** 적용. PARTITIONS_ATTRIBUTE / PARTITION_SETTING_COMPLETED 등 정책 필드는 동일하고, 절대 크기 (ENH_SIZE_MULT, SEC_COUNT) 만 raw NAND 비례 차이.

### 정책 필드 (두 모델 동일)

| ext_csd byte | 필드 | 64GB | 128GB | 의미 |
|---|---|---|---|---|
| 155 | `PARTITION_SETTING_COMPLETED` | `0x01` | `0x01` | 설정 완료 ✓ |
| 156 | `PARTITIONS_ATTRIBUTE` | **`0x1F`** | **`0x1F`** | USER + GPP1~4 모두 Enhanced |
| 160 | `PARTITIONS_SUPPORT` | `0x07` | `0x07` | Partition / Enh / Ext attr 지원 |
| 221 | `HC_WP_GRP_SIZE` | 16 | 16 | WP group = 8 MB |
| 224 | `HC_ERASE_GRP_SIZE` | 1 | 1 | Erase group = 512 KB |

### 절대 크기 (raw NAND 비례)

| ext_csd byte | 필드 | 64GB (예상) | 128GB (실측) | 의미 |
|---|---|---|---|---|
| 140-142 | `ENH_SIZE_MULT` | ≈ 2400 | `0x0012EA` (4842) | USER Enhanced 크기 (× 8 MB) |
| 157-159 | `MAX_ENH_SIZE_MULT` | ≈ 2480 | `0x00136A` (4970) | 디바이스 지원 최대 Enhanced |
| 212-215 | `SEC_COUNT` (4-byte LE) | ≈ 40 M sectors | `0x04BA8000` (79,167,488) | USER 영역 sector 수 |

### PARTITIONS_ATTRIBUTE = `0x1F` 비트 해석 (두 모델 동일)

| bit | 의미 | 상태 |
|---|---|---|
| 0 (0x01) | `ENH_USR` (USER 영역) | ✓ pSLC |
| 1 (0x02) | `ENH_1` (GP1) | ✓ pSLC |
| 2 (0x04) | `ENH_2` (GP2) | ✓ pSLC |
| 3 (0x08) | `ENH_3` (GP3) | ✓ pSLC |
| 4 (0x10) | `ENH_4` (GP4) | ✓ pSLC |

**→ 두 모델 모두 USER + GPP1~4 전 영역 pSLC (Enhanced) 모드 운영**

Enhanced 영역 활용률 = `ENH_SIZE_MULT / MAX_ENH_SIZE_MULT` ≈ **97.4%** (128GB 기준, 거의 max 사용)

---

## 6. 용량 계산 (Raw NAND → User-Visible)

### 변환 단계 — 두 모델 공통 로직

```
[Raw NAND, TLC, 3 bit/cell]
        ↓ pSLC 변환 (1 bit/cell, 1/3 비율)
[pSLC 이론치]
        ↓ factory over-provisioning · spare · FTL metadata 차감
[USER 영역]  (ext_csd SEC_COUNT)
        ↓ u-boot_A/B (8 MB) 차감
[mbfsraw]  (Internal Storage = 녹화 영상)
        ↓ UI 단위 변환 (GB decimal → GiB binary)
[UI 표시]
```

### 모델별 단계별 용량 비교

| 단계 | 64GB 모델 | 128GB 모델 | 비율 |
|---|---|---|---|
| **Raw NAND (TLC)** | 64 GB | 128 GB | 1 : 2 |
| pSLC 이론치 (×1/3) | ≈ 21.3 GB | ≈ 42.67 GB | 1 : 2 |
| **USER 영역 (ext_csd)** | ≈ **20 GB** | **40.5 GB** | 1 : 2 |
| u-boot_A/B 차감 | -8 MB | -8 MB | 동일 |
| **mbfsraw** | ≈ **20 GB** | ≈ **40 GB** | 1 : 2 |
| **UI 표시 (Internal Storage, GiB)** | ≈ **18 ~ 19 GB** | ≈ **38 GB** | 1 : 2 |

### 128GB SEC_COUNT 정확값 (실측)

| 필드 | 값 |
|---|---|
| `SEC_COUNT` (byte 212-215) | `0x04BA8000` = 79,167,488 sectors |
| Bytes | 79,167,488 × 512 = **40,533,753,856 bytes** |
| Decimal GB | 40.53 GB |
| Binary GiB | 37.75 GiB |

### Raw 대비 사용자 가용 비율 (두 모델 동일)

| 단계 | Raw 대비 비율 |
|---|---|
| Raw NAND | 100% |
| pSLC 이론치 | 33.3% |
| USER 영역 | 31.6% |
| mbfsraw | 31.3% |
| UI 표시 | ~29.7% |

→ **pSLC 비율 자체는 두 모델 동일**. 사용자 가용 용량은 raw 의 약 30% 수준.

---

## 7. GPP1~4 세부 크기 (두 모델 동일)

WP group 단위 환산 (1 group = HC_WP_GRP_SIZE × HC_ERASE_GRP_SIZE × 512KB = 16 × 1 × 512KB = **8 MB**):

| Partition | GP_SIZE_MULT | 크기 | 용도 |
|---|---|---|---|
| GPP1 | 32 | **256 MB** | Slot A (kernel + squashfs) |
| GPP2 | 32 | **256 MB** | Slot B (kernel + squashfs) |
| GPP3 | 16 | **128 MB** | f-conf/v-conf/env/resource/doc |
| GPP4 | 48 | **384 MB** | log (`/mnt/log`) |
| **합계** | | **1024 MB** | |

→ 모델 무관 GPP 합 = **1 GB 고정**. 그래서 64GB 모델은 USER 영역이 더 작은 만큼 GPP 비율은 상대적으로 큼.

---

## 8. pSLC 운영의 Trade-off (두 모델 동일)

| 항목 | TLC (raw) | pSLC (현재) | 배율 |
|---|---|---|---|
| Cell 당 bit | 3 | 1 | 1/3 capacity |
| P/E cycles (수명) | ~1,000 | ~30,000 | **30×** |
| Write 속도 | ~50 MB/s | ~150+ MB/s | 3×+ |
| Read latency | 보통 | 빠름 | ↑ |
| Power-loss 신뢰성 | 보통 | 매우 높음 | ↑ |

**DVR/Industrial 환경의 의도된 선택**: 용량 (64 → 20GB / 128 → 40GB) 을 희생하고 신뢰성·수명·속도 확보.

### 모델별 녹화 가능 시간 영향

| 항목 | 64GB | 128GB |
|---|---|---|
| 녹화 가능 시간 | 기준 × 1 | 기준 × 2 |
| 녹화 영상 endurance | 동일 (~30k P/E) | 동일 (~30k P/E) |
| OS/시스템 동작 | 완전 동일 | 완전 동일 |

→ 두 모델의 차이는 **"얼마나 오래된 영상까지 보관 가능한가"** 의 측면만 차이.

---

## 9. 디바이스에서 직접 확인 명령

### 모델 구분 (64GB / 128GB 확정)
```sh
# 1) PNM (Product Name) 으로 1차 확인
cat /sys/block/mmcblk0/device/name
# "MMC064" → 64GB, "MMC128" → 128GB

# 2) USER 영역 sector 수로 확정 (가장 신뢰)
cat /sys/block/mmcblk0/size
# 약 41,943,040 (40M sectors) → 20 GB → 64GB 모델
# 79,167,488 sectors → 40.5 GB → 128GB 모델
```

### CID / 모델 정보
```sh
cat /sys/block/mmcblk0/device/cid
cat /sys/block/mmcblk0/device/manfid
cat /sys/block/mmcblk0/device/oemid
```

### ext_csd 전체 dump (pSLC 운영 검증)
```sh
hexdump -C /sys/kernel/debug/mmc0/mmc0:0001/ext_csd
# 또는 (mmc-utils 설치된 경우)
mmc extcsd read /dev/mmcblk0 | grep -iE "enh|reliab|partition|sec_count"

# 주요 확인 필드 (64GB / 128GB 비교 시 차이나는 부분)
# - ENH_SIZE_MULT (140-142)
# - MAX_ENH_SIZE_MULT (157-159)
# - SEC_COUNT (212-215)
# 정책 필드 PARTITIONS_ATTRIBUTE (156) / PARTITION_SETTING_COMPLETED (155) 는 동일해야
```

### HW partition 별 크기
```sh
# USER (모델별 차이)
cat /sys/block/mmcblk0/size
# BOOT1/BOOT2 (동일)
cat /sys/block/mmcblk0boot0/size
cat /sys/block/mmcblk0boot1/size
# GPP1~4 (동일)
for i in 0 1 2 3; do
    echo -n "GPP$((i+1)): "
    cat /sys/block/mmcblk0gp${i}/size
done
```

### Slot A/B rootfs 확인 (SquashFS 시그니처)
```sh
mount | grep squash
cat /proc/filesystems | grep squashfs
```

### 현재 활성 Slot (boot_state) 확인
```sh
# v-conf (GPP3 의 일부) 에서 boot_state / boot_count / partition 조회
# bd_conf_p2_t 구조 → setconfig 유틸 또는 mbinfo 등
```

### GPT 파티션
```sh
parted /dev/mmcblk0 unit MiB print
parted /dev/mmcblk0gp0 unit MiB print   # Slot A 내부 (kernel/extra/initrd)
```

---

## 10. 참고 ext_csd 필드 매핑 (디코딩)

JEDEC eMMC 5.1 (JESD84-B51) 기준. 128GB 는 실측, 64GB 는 추정.

| Byte | 필드 | 64GB (예상) | 128GB (실측) |
|---|---|---|---|
| 134 | `BOOT_PARTITION_NO_WP` | `0x00` | `0x00` |
| 140-142 | `ENH_SIZE_MULT` (3-byte LE) | ≈ 2400 (0x000960) | `0x0012EA` = 4842 |
| 143-145 | `GP_SIZE_MULT_1` | `0x000020` = 32 → 256 MB | `0x000020` = 32 → 256 MB |
| 146-148 | `GP_SIZE_MULT_2` | `0x000020` = 32 → 256 MB | `0x000020` = 32 → 256 MB |
| 149-151 | `GP_SIZE_MULT_3` | `0x000010` = 16 → 128 MB | `0x000010` = 16 → 128 MB |
| 152-154 | `GP_SIZE_MULT_4` | `0x000030` = 48 → 384 MB | `0x000030` = 48 → 384 MB |
| 155 | `PARTITION_SETTING_COMPLETED` | `0x01` | `0x01` |
| 156 | `PARTITIONS_ATTRIBUTE` | `0x1F` | `0x1F` |
| 157-159 | `MAX_ENH_SIZE_MULT` | ≈ 2480 | `0x00136A` = 4970 |
| 160 | `PARTITIONS_SUPPORT` | `0x07` | `0x07` |
| 192 | `EXT_CSD_REV` | `0x08` (v5.1) | `0x08` (v5.1) |
| 196 | `DEVICE_TYPE` | `0x57` | `0x57` |
| 212-215 | `SEC_COUNT` (4-byte LE) | ≈ 40 M sectors (20 GB) | `0x04BA8000` = 79,167,488 sectors (40.5 GB) |
| 221 | `HC_WP_GRP_SIZE` | 16 | 16 |
| 224 | `HC_ERASE_GRP_SIZE` | 1 | 1 |
| 226 | `BOOT_SIZE_MULT` | 32 → 4 MB | 32 → 4 MB |
| 228 | `BOOT_INFO` | `0x07` | `0x07` |
| 231 | `SEC_FEATURE_SUPPORT` | `0x55` | `0x55` |

> 64GB 모델의 실측 dump 가 확보되면 위 표의 "(예상)" 항목을 정확값으로 갱신할 것.

---

## 결론

| 항목 | 64GB 모델 | 128GB 모델 |
|---|---|---|
| **물리 NAND** | 64 GB TLC eMMC v5.1 | 128 GB TLC eMMC v5.1 |
| **운영 모드** | **전체 pSLC** (USER + GPP1~4) | **전체 pSLC** (USER + GPP1~4) |
| **rootfs 형식** | SquashFS (read-only, A/B OTA) | SquashFS (read-only, A/B OTA) |
| **OS 영역 (kernel/rootfs)** | GPP1/GPP2 (256MB × 2) | GPP1/GPP2 (256MB × 2) |
| **시스템 데이터 (GPP3+GPP4)** | 128 + 384 MB | 128 + 384 MB |
| **녹화 영역 (mbfsraw)** | ≈ 20 GB | ≈ 40 GB |
| **UI Internal Storage** | ≈ 18~19 GB | ≈ 38 GB |
| **수명** | ~30 배 TLC (~10년+) | ~30 배 TLC (~10년+) |

### 핵심 차이 한 줄

> **두 모델은 동일한 pSLC 정책 / 동일한 OS 및 시스템 데이터 영역을 가지며, 녹화 영상 저장 영역 (mbfsraw) 만 raw NAND 에 비례하여 2배 차이가 납니다.**
>
> 펌웨어 / OTA / 부팅 동작 / 로그 시스템 / 신뢰성 / 수명은 두 모델 모두 동일합니다.
