# 09. U-Boot 업그레이드 시스템 가이드

> RK3588 HDS 보드에서 U-Boot 콘솔의 `up_ubt`/`up_lnx`/`up_app` 명령으로 eMMC + GPT 영역을 업데이트하는 방법.

## 0. 문서 구조

| 절 | 내용 |
|---|---|
| 1 | 개요 및 설계 결정 |
| 2 | eMMC 파티션 레이아웃 |
| 3 | A/B 슬롯 부팅 원리 |
| 4 | 최초 1회 환경변수 등록 |
| 5 | 업그레이드 명령어 사용법 |
| 6 | TFTP 서버 준비 |
| 7 | 명령어 동작 원리(내부) |
| 8 | 트러블슈팅 |
| 9 | 기존 시스템(u-boot.rv3k)과의 비교 |

---

## 1. 개요

### 1.1 배경
기존 HDS 시스템(u-boot.rv3k)은 AutoIT 커스텀 U-Boot 포크에 `update`(약어 `up`) 명령이 내장되어 있었다:

```
HDS> up ubt          # bootloader 업데이트
HDS> up lnx          # 커널 업데이트
HDS> up app          # 애플리케이션(rootfs) 업데이트
HDS> up all          # 위 3개 전체
HDS> up app mmc image.img   # SD/USB에서 가져와 업데이트
```

이 명령들은 약 5,000줄 규모의 AutoIT 프레임워크 + `cmd_update.c`(2,379줄)로 구현되어 있었으며, eMMC HW 파티션(USER/GPP1~4) + mkimage 레거시 헤더 포맷에 강하게 결합되어 있었다.

### 1.2 설계 결정 (Option A: U-Boot Env Script)
mainline U-Boot로 옮기면서 다음과 같이 결정했다:

| 항목 | 결정 | 이유 |
|---|---|---|
| 명령 구현 방식 | **U-Boot 환경변수 스크립트** | mainline U-Boot의 `tftpboot`/`mmc write`/`gpt`/`ext4write`를 조합하면 동일 기능 구현 가능 |
| 명령 호출 형식 | `run up_lnx` (`run` 접두사) | env 변수는 `run` 으로 실행, 기존 `up lnx` 대비 5글자 추가됨 |
| 슬롯 관리 | eMMC GPT 파티션 + `boot_slot` env | `mmc partconf` 대신 표준 GPT의 `PARTLABEL` 사용 |
| 이미지 헤더 검증 | 미사용 | mainline은 fitImage signature 또는 SHA256(외부 OTA) 사용 |

### 1.3 결과물 위치
| 파일 | 용도 |
|---|---|
| `yocto/sources/meta-hds/recipes-bsp/u-boot/files/hds-uboot-env.txt` | env 변수 정의 (사람이 읽기 좋은 형식) |
| `yocto/sources/meta-hds/recipes-bsp/u-boot/files/hds-uboot-env.cfg` | Kconfig fragment (CMD_TFTPBOOT, CMD_GPT, CMD_EXT4_WRITE 등 활성화) |
| `yocto/sources/meta-hds/recipes-bsp/u-boot/u-boot_%.bbappend` | 위 두 파일을 U-Boot 빌드에 적용 |
| `yocto/build/tmp-glibc/deploy/images/rk3588-hds/hds-uboot-env.txt` | **빌드 산출물 (TFTP 서버에 배치)** |

---

## 2. eMMC 파티션 레이아웃

`hds-emmc.wks` 기준 (mmcblk0):

```
+----------+-------------+----------+----------+--------+
| LBA 0x40 | LBA 0x4000  |          GPT 파티션 영역      |
+----------+-------------+--------------------------------+
|idbloader | u-boot.itb  | p1 boot  | p2 rootfs_a | p3 rootfs_b | p4 config | p5 data |
| (256K)   | (~2M)       | 128MB    | 1024MB      | 1024MB      | 256MB     | 잔여   |
+----------+-------------+----------+-------------+-------------+-----------+--------+
```

| 파티션 | 크기 | 마운트 | 용도 |
|---|---|---|---|
| LBA 0x40 (raw) | 256KB | - | Rockchip first-stage (idbloader.img) |
| LBA 0x4000 (raw) | ~2MB | - | U-Boot + ATF + TEE FIT (u-boot.itb) |
| mmcblk0p1 `boot` | 128MB | `/boot` | fitImage (커널 + DTB FIT) |
| mmcblk0p2 `rootfs_a` | 1024MB | `/` (slot A) | HDS Yocto rootfs (Slot A) |
| mmcblk0p3 `rootfs_b` | 1024MB | `/` (slot B) | HDS Yocto rootfs (Slot B) |
| mmcblk0p4 `config` | 256MB | `/mnt/doc` | 영구 설정 (보드/사용자) |
| mmcblk0p5 `data` | 잔여 | `/mnt/data` | 녹화 데이터 (영구) |

> **주의**: 컨테이너 이미지(`hds-dvr-runtime.tar.gz`)는 rootfs 안에 포함되어 있으므로 `up_app`으로 함께 업데이트된다. OTA 시 컨테이너만 업데이트하려면 별도의 컨테이너 OTA 경로(hds_ota 모듈)를 사용한다.

---

## 3. A/B 슬롯 부팅 원리

### 3.1 슬롯 선택
U-Boot env 변수 `boot_slot` 값에 따라 분기한다:
```
boot_slot=a  →  bootargs root=PARTLABEL=rootfs_a → mmcblk0p2
boot_slot=b  →  bootargs root=PARTLABEL=rootfs_b → mmcblk0p3
```

부팅 명령 흐름:
```
bootcmd → run bootcmd_hds → if boot_slot==b run boot_b else run boot_a
```

### 3.2 슬롯 전환 트리거
| 트리거 | 동작 |
|---|---|
| `run up_app` | 현재 슬롯의 **반대쪽**(비활성)에 새 rootfs 기록 → `boot_slot` 토글 → `saveenv` |
| `run up_swap` | `boot_slot` 만 토글 → `saveenv` → `reset` (디스크 변경 없음) |
| `run up_app_a` / `run up_app_b` | 명시한 슬롯에 강제 기록 |

### 3.3 Roll-back
새 슬롯 부팅 실패 시 콘솔에 진입해 `run up_swap` 으로 이전 슬롯으로 되돌린다.

> **향후 개선**: 자동 watchdog 기반 롤백(boot_count, boot_limit). 현재는 수동.

---

## 4. 최초 1회 환경변수 등록

> 빌드 직후 보드의 U-Boot 환경에는 `up_ubt`/`up_lnx`/`up_app` 변수가 **없다**. 첫 부팅 시 한 번만 아래 절차를 수행하면 saveenv로 영구 저장되어 이후엔 그대로 사용 가능하다.

### 4.1 사전 준비
- TFTP 서버 PC: `192.168.2.10` (또는 환경에 맞게)
- 보드 IP: `192.168.2.20` 권장
- TFTP 루트에 `hds-uboot-env.txt` 복사:
  ```bash
  cp yocto/build/tmp-glibc/deploy/images/rk3588-hds/hds-uboot-env.txt /srv/tftp/
  ```

### 4.2 보드에서 실행 (HDS> 콘솔)
```
HDS> setenv ipaddr   192.168.2.20
HDS> setenv serverip 192.168.2.10
HDS> tftpboot ${loadaddr} hds-uboot-env.txt
HDS> env import -t ${loadaddr} ${filesize}
HDS> saveenv
HDS> reset
```

### 4.3 등록 확인
재부팅 후 콘솔에 진입하여:
```
HDS> printenv up_ubt        # 등록되어 있어야 함
HDS> printenv up_lnx
HDS> printenv up_app
HDS> printenv boot_slot     # 'a' 또는 'b'
```

---

## 5. 업그레이드 명령어 사용법

### 5.1 명령어 매핑 (legacy → 신규)

| Legacy (u-boot.rv3k) | 신규 (mainline + env) | 동작 |
|---|---|---|
| `up ubt` | `run up_ubt` | idbloader.img + u-boot.itb 업데이트 |
| `up lnx` | `run up_lnx` | fitImage 갱신 (boot 파티션의 ext4 안) |
| `up app` | `run up_app` | rootfs를 비활성 슬롯에 기록 + 슬롯 토글 |
| `up app mmc image.img` | (별도 절차) | SD/USB 로딩은 절차 §5.4 참조 |
| `up all` | `run up_all` | up_ubt + up_lnx + up_app 순차 실행 |
| `up safe` | `run up_swap` | 슬롯 전환 (rollback) |

### 5.2 기본 사용 예시

**커널만 업데이트**:
```
HDS> setenv lnx_img fitImage
HDS> run up_lnx
[HDS] up_lnx: fitImage 다운로드...
*** TFTP from 192.168.2.10; our IP 192.168.2.20
Bytes transferred = 13234560 (ca0000 hex)
[HDS] up_lnx: 완료
HDS> reset
```

**rootfs(애플리케이션) 업데이트** (자동으로 비활성 슬롯에):
```
HDS> printenv boot_slot
boot_slot=a
HDS> run up_app
[HDS] up_app_b: rootfs 다운로드...
*** TFTP ...
Bytes transferred = 1063256064 (3f600000 hex)
mmc0(part 0) is current device
[HDS] up_app_b: 완료. 다음 부팅부터 슬롯 B 사용
HDS> reset
```

**전체 업데이트** (부트로더 + 커널 + rootfs):
```
HDS> run up_all
```

**Roll-back** (이전 슬롯으로 복구):
```
HDS> run up_swap
[HDS] 슬롯 전환됨: a. reset 후 적용.
```

### 5.3 이미지 파일 이름 변경
TFTP 서버의 파일 이름이 다르면 setenv로 덮어쓰기:
```
HDS> setenv lnx_img myKernel.bin
HDS> setenv app_img myRootfs.ext4
HDS> setenv ubt_img myIdbloader.img
HDS> setenv ubt2_img myUboot.itb
HDS> saveenv
```

### 5.4 SD/USB 로딩으로 변경 (TFTP 대신)
기본 명령은 TFTP를 가정한다. SD/USB로 바꾸려면:
```
HDS> usb start
HDS> setenv up_lnx 'fatload usb 0:1 ${loadaddr} ${lnx_img}; mmc dev 0 0; ext4write mmc 0:1 ${loadaddr} /fitImage ${filesize}'
HDS> saveenv
```

---

## 6. TFTP 서버 준비

### 6.1 Ubuntu/Debian 예시
```bash
sudo apt install tftpd-hpa
sudo systemctl enable --now tftpd-hpa
# TFTP 루트: /srv/tftp
sudo cp yocto/build/tmp-glibc/deploy/images/rk3588-hds/{idbloader.img,u-boot.itb,fitImage,hds-image-rk3588-hds.rootfs.ext4,hds-uboot-env.txt} /srv/tftp/
sudo chown tftp:tftp /srv/tftp/*
```

### 6.2 PC 측 IP 고정
```bash
sudo ip addr add 192.168.2.10/24 dev eth0
```

### 6.3 보드-PC 연결 확인
보드에서:
```
HDS> ping 192.168.2.10
host 192.168.2.10 is alive
```

---

## 7. 명령어 동작 원리(내부)

각 명령은 mainline U-Boot의 표준 명령들을 조합한 환경변수다. 디버깅을 위해 내부 로직을 정리한다.

### 7.1 up_ubt (부트로더 업데이트)
```
1. tftpboot ${loadaddr} idbloader.img      # PC에서 다운로드 (filesize 자동 설정)
2. mmc dev 0 0                             # eMMC USER 파티션 선택
3. blkcnt = filesize / 0x200 + 1           # 블록 수 계산 (512B 단위)
4. mmc write ${loadaddr} 0x40 ${blkcnt}    # LBA 0x40부터 raw write
5. tftpboot ${loadaddr} u-boot.itb         # u-boot.itb 다운로드
6. blkcnt 재계산
7. mmc write ${loadaddr} 0x4000 ${blkcnt}  # LBA 0x4000부터 raw write
```

### 7.2 up_lnx (커널 업데이트)
```
1. tftpboot ${loadaddr} fitImage
2. mmc dev 0 0
3. ext4write mmc 0:1 ${loadaddr} /fitImage ${filesize}
   # boot 파티션의 ext4 파일시스템 안에 /fitImage 파일을 덮어씀
   # CONFIG_CMD_EXT4_WRITE=y 필요 (hds-uboot-env.cfg 에서 활성화)
```

### 7.3 up_app (애플리케이션 업데이트)
```
1. boot_slot 검사 → 비활성 슬롯 결정 (a → b, b → a)
2. tftpboot ${loadaddr} rootfs.ext4
3. part start mmc 0 rootfs_b slot_start    # GPT PARTLABEL로 시작 LBA 조회
4. part size mmc 0 rootfs_b slot_size      # GPT PARTLABEL로 크기 조회
5. blkcnt 계산 + 슬롯 크기 초과 검사
6. mmc write ${loadaddr} ${slot_start} ${blkcnt}    # 슬롯 raw write
7. setenv boot_slot b                              # 토글
8. saveenv                                          # 영구 저장
```

### 7.4 up_swap (수동 슬롯 전환)
```
1. boot_slot 토글
2. saveenv
3. reset
```

---

## 8. 트러블슈팅

### 8.1 "Unknown command 'up_lnx'"
- env 등록 안 됨 → §4 절차 다시 수행
- `printenv up_lnx`로 확인

### 8.2 "TFTP error: Connection refused"
- TFTP 서버 미실행: `sudo systemctl status tftpd-hpa`
- 방화벽: `sudo ufw allow 69/udp`
- IP 불일치: `printenv serverip`

### 8.3 "Bad Magic Number" / boot 실패
- fitImage 손상 또는 잘못된 파일 → `up_swap` 후 이전 슬롯으로 복구
- 또는 `up_lnx` 재실행

### 8.4 "Wrong image format for "ext4write" command"
- CONFIG_CMD_EXT4_WRITE 비활성화 → `hds-uboot-env.cfg` 확인 후 U-Boot 재빌드:
  ```bash
  bitbake u-boot -c cleansstate && bitbake u-boot
  ```

### 8.5 슬롯 크기 초과
- rootfs.ext4가 1024MB 초과 → `hds-emmc.wks` 의 rootfs_a/rootfs_b 크기 증가
- 또는 IMAGE_OVERHEAD_FACTOR 조정

### 8.6 보드가 부팅 안 됨 (벽돌 위험)
- `up_ubt` 실패 시 idbloader/u-boot.itb 손상 가능
- 복구: `flash-emmc.sh` (rkdeveloptool MaskROM 모드)로 재플래시
- 권장: `up_ubt` 사용 전에 `up_app`만으로 충분히 검증

---

## 9. 기존 시스템(u-boot.rv3k)과의 비교

| 항목 | 기존 (rv3k AutoIT) | 신규 (mainline + env) |
|---|---|---|
| 명령 형식 | `up lnx` | `run up_lnx` |
| 구현 | C 코드 (cmd_update.c, 2379줄) | env 변수 (hds-uboot-env.txt, 100줄) |
| 이미지 포맷 | mkimage v1 (image_header_t) | raw + fitImage |
| 무결성 검증 | mkimage CRC | (없음, OTA 단계에서 SHA256) |
| 슬롯 메타데이터 | bd_conf 구조체 (eMMC GPP3) | env 변수 `boot_slot` |
| 슬롯 위치 | eMMC HW partition (GPP1/GPP2) | GPT PARTLABEL (rootfs_a/rootfs_b) |
| 이미지 로딩 | TFTP / MMC / USB | TFTP (USB는 §5.4로 변경) |
| 자동 복구 | bd_conf.boot_count + boot_limit | 수동 (`up_swap`) |
| 향후 OTA | 별도 절차 | hds_ota 모듈 (HTTP/SHA256/A-B 슬롯 자동) |

### 9.1 사용자 영향
- 명령 입력은 `up lnx` → `run up_lnx` 로 4글자 길어진다
- 그 외 동작 의미는 동일 (TFTP에서 받아 eMMC에 기록)
- 영상 OTA는 hds_ota 모듈이 담당하므로 평상시 U-Boot 진입은 보드 초기화/긴급 복구 용도

### 9.2 향후 개선 항목
- [ ] watchdog + boot_count 자동 롤백 (현재는 수동)
- [ ] 이미지 SHA256 검증 (TFTP 다운로드 후, mmc write 전)
- [ ] `boot.scr`로 첫 부팅 시 env 자동 import (수동 import 절차 제거)
- [ ] HTTP 다운로드 (tftpboot 외에 wget 또는 mainline의 dhcp 옵션)

---

## 10. 빠른 참조 (Cheat Sheet)

```
# === 최초 1회 ===
HDS> setenv ipaddr 192.168.2.20
HDS> setenv serverip 192.168.2.10
HDS> tftpboot ${loadaddr} hds-uboot-env.txt
HDS> env import -t ${loadaddr} ${filesize}
HDS> saveenv
HDS> reset

# === 일상 사용 ===
HDS> run up_lnx       # 커널만 갱신
HDS> run up_app       # rootfs 갱신 (자동 슬롯)
HDS> run up_all       # 전체 갱신
HDS> run up_swap      # rollback
HDS> reset

# === 상태 확인 ===
HDS> printenv boot_slot
HDS> printenv ipaddr serverip
HDS> mmc list
HDS> part list mmc 0
```

---

**관련 문서**:
- `00_yocto_build_guide.md` — Yocto 빌드 환경
- `08_soc_porting_guide.md` — SoC 포팅 가이드
- `app/hds_ota/README.md` — 컨테이너 기반 OTA 시스템
- `scripts/flash-emmc.sh` — MaskROM 모드 초기 플래싱 (긴급 복구)
