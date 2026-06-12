# HDS RK3588 실기 플래싱 + 부팅 검증 가이드

P0~P3 적용 후 실기 보드에서 검증해야 할 4단계 절차. 각 단계의 명령, 기대 출력, 통과 기준, 트러블슈팅을 포함한다.

전제: 호스트 사전 점검 통과 — rkdeveloptool v1.32+, wic.gz 무결성, 산출물 존재.

---

## ⚠️ 갱신 노트 (2026-05-29 실기 검증 반영)

이 가이드는 초기 mainline U-Boot 가정(2024.01 / idbloader.img / u-boot.itb / fitImage / 7파티션)으로
작성되었으나, 이후 **Rockchip BSP 2017.09 로 전환**되었고 실기 부팅으로 다음이 확정되었다.
아래 절차의 "기대 출력"은 이 사실에 맞춰 읽을 것.

**부트로더 산출물 (BSP 전환 후):**
| 옛 기대(mainline) | 실제(BSP 2017.09) |
|---|---|
| idbloader.img | `idblock.img` (SPL/TPL, raw @LBA 0x40, GPT 엔트리 없음) |
| u-boot.itb (FIT) | `uboot.img` (U-Boot + TF-A) |
| fitImage | `boot.img` (rkboot 형식 kernel+dtb) |

**실제 파티션 = 6개 (GPT, 7개 아님):**
| # | PARTLABEL | FS | 용도 |
|---|---|---|---|
| p1 | uboot | raw | U-Boot + TF-A |
| p2 | boot | ext4 | 커널(boot.img) |
| **p3** | **rootfs_a** | **squashfs ro** | **A 슬롯 (루트 = `/dev/mmcblk0p3`)** |
| p4 | rootfs_b | squashfs ro | B 슬롯 |
| p5 | config | ext4 | /mnt/doc |
| **p6** | **data** | **ext4** | **녹화 (first-boot 확장)** |

→ 루트는 **p3**(옛 p4 아님), 데이터는 **p6**(옛 p7 아님). idblock은 raw 영역이라 파티션 번호 없음.

**보드 2종 — eMMC 용량별 data 확장 목표가 다름:**
| 보드 | eMMC | 가시 용량 | data 확장 목표 |
|---|---|---|---|
| 64GB 변형 (현재 테스트기, DV4064) | 64GB TLC | 57.2 GiB | ~56.6 GiB |
| 128GB 변형 | 128GB TLC (pSLC) | 40.5 GiB | ~38.7 GiB |

---

## Task 18 — MaskROM 진입 + 플래싱

### A. MaskROM 모드 진입

1. 보드 **전원 OFF**
2. USB Type-C OTG 케이블을 PC와 연결 (데이터선 포함 케이블, 전원 전용 케이블 불가)
3. **RECOVERY 버튼을 누른 상태**에서 보드 전원 ON
4. 약 3초 후 RECOVERY 버튼 release

### B. PC에서 인식 확인

```bash
lsusb | grep -i rockchip
# 기대: ID 2207:350b Fuzhou Rockchip Electronics Company

sudo rkdeveloptool ld
# 기대: DevNo=1 Vid=0x2207, Pid=0x350b, ... Maskrom
```

### C. 플래싱 실행

```bash
cd /media/ksw/dev/new_dev/rk3588
sudo ./scripts/flash-emmc.sh
```

기대 출력 흐름:
```
==== HDS RK3588 eMMC 플래싱 ====
  wic.gz:      .../hds-image-rk3588-hds.rootfs.wic.gz (375M)
  legacy raw:  no
  erase first: no
타겟 보드가 MaskROM 모드인지 확인합니다...
장치 감지됨: DevNo=1 ... Maskrom
[1/2] 부트로더 다운로드 (MaskROM → Loader 전환)...
[2/2] wic 이미지 플래싱...
(375M 압축 → 약 756 MiB 전송, USB 2.0에서 1~3분 소요)
압축 해제 완료: 756M
==== 플래싱 완료! ====
보드를 재부팅합니다...
```

### 트러블슈팅

| 증상 | 원인 / 대처 |
|---|---|
| `rkdeveloptool ld` 출력 없음 | USB 케이블/포트 점검, RECOVERY 타이밍 재시도 |
| `Loader` (Maskrom 아님) 표시 | 이미 부트로더 살아있음 — 그대로 진행 가능 |
| `Write LBA failed` | USB 노이즈, 다른 포트 사용 |
| 플래싱 후 부팅 실패 | `sudo ./scripts/flash-emmc.sh --legacy-raw` 재시도 (BOOT1 우선 의심) |
| eMMC 손상 의심 | `--erase` 옵션으로 전체 0xFF 초기화 후 재플래싱 |

---

## Task 19 — 시리얼 부팅 로그 확인

### A. 시리얼 케이블 연결

- USB-to-UART 어댑터 (PL2303, FTDI, CH340 등)
- 보드 디버그 UART2 핀 → `/dev/ttyUSB0` 매핑
- 보레이트: **1,500,000 (1.5 Mbps)**

### B. 시리얼 콘솔 열기

```bash
# screen (호스트에 이미 설치됨)
sudo screen /dev/ttyUSB0 1500000
# 종료: Ctrl+A → K → y
# 디태치: Ctrl+A → d

# 또는 picocom (별도 설치 권장)
sudo apt install picocom
sudo picocom -b 1500000 /dev/ttyUSB0
# 종료: Ctrl+A → Ctrl+X

# 로그 저장하면서 보기
sudo screen -L -Logfile boot.log /dev/ttyUSB0 1500000
```

### C. 기대 부팅 흐름

```
DDR Version V1.18.x ...              ← Stage1 DDR init (보드 출하 DDR v1.18)
...                                  ← idblock (SPL/TPL)
TEE: ... / ATF: ...

U-Boot 2017.09-...                   ← uboot.img (BSP) 진입
Model: HDS RK3588
DRAM: ... GiB
MMC: mmc@fe2c0000: 0
Loading Environment from MMC... OK
Boot device: emmc

HDS> ...                             ← 자동 부팅 시작
... boot 파티션(p2)에서 커널(boot.img) 로드   ← BSP rkboot 형식

[    0.000000] Linux version 5.10.x ...        ← BSP 벤더 커널
[    x.xxxxxx] VFS: Mounted root (squashfs filesystem) readonly on device 179:3.  ← p3=rootfs_a
[    x.xxxxxx] Run /sbin/init as init process

systemd[1]: systemd 254 running ...
[  OK  ] Finished HDS First-boot Setup.
[  OK  ] Started HDS DVR/AI Container ...

hds-rk3588 login:
```

### 핵심 통과 포인트

| # | 출력 | 의미 |
|---|---|---|
| 1 | `Loading Environment from MMC... OK` | U-Boot env 정상 로드 |
| 2 | boot 파티션(p2)에서 boot.img 로드 | BSP rkboot 커널 로드 정상 |
| 3 | `VFS: Mounted root (squashfs filesystem) readonly on device 179:3` | p3=rootfs_a squashfs-lzo 정상 |
| 4 | `Finished HDS First-boot Setup` | hds-firstboot 정상 종료 |
| 5 | `login:` 프롬프트 | systemd 정상 |

### 트러블슈팅

| 증상 | 원인 / 대처 |
|---|---|
| DDR 단계에서 멈춤 | idblock 손상 → `flash-emmc.sh --legacy-raw` |
| `Card did not respond` | eMMC BOOT1 우선 → U-Boot 콘솔에서 `mmc partconf 0 0 0 0; reset` |
| `ext4load fail` | wks GPT 손상 → `--erase` 후 재플래싱 |
| 커널 패닉 `No working init` | rootfs 손상 또는 init 미설치 |
| login prompt 없음 | systemd 멈춤 — `systemctl status` 출력 보고 |

---

## Task 20 — hds-firstboot 동작 검증 (OS 로그인 후)

### A. 로그인

```
hds-rk3588 login: root
Password:           ← debug-tweaks 활성화 상태라 비밀번호 없음 (엔터)
```

### B. 검증 명령 (순서대로)

#### B1. hds-firstboot service 완료 확인

```bash
systemctl status hds-firstboot
```
기대: `Active: inactive (dead) since ...` + ExecStart=success

```bash
cat /var/lib/hds/firstboot-done
```
기대:
```
completed_at=2026-05-..Z
device=/dev/mmcblk0
data_partition=/dev/mmcblk0p7
gpp4_device=/dev/mmcblk0gp3
parted: ...
```

```bash
journalctl -u hds-firstboot --no-pager
```
기대:
```
[hds-firstboot] 1/5 GPT 백업 헤더 이동
[hds-firstboot] 2/5 partprobe / udev 동기화
[hds-firstboot] 3/5 data 파티션 100% 확장
[hds-firstboot] 4/5 resize2fs /dev/mmcblk0p7
[hds-firstboot] 5/5 eMMC BOOT_PARTITION_ENABLE 무력화 시도
[hds-firstboot]   BOOT_PARTITION_ENABLE=0 (disabled) 설정 완료
[hds-firstboot] 6/6 GPP4(/dev/mmcblk0gp3) journal 영속화 설정
[hds-firstboot]   journal 영속화 완료 (/var/log/journal)
[hds-firstboot] first-boot 완료. 다음 부팅부터는 건너뜀.
```

#### B2. data 파티션 확장 확인 (목표: 64GB 보드 ~56.6 GiB / 128GB 보드 ~38.7 GiB)

```bash
lsblk /dev/mmcblk0
```
기대 (BSP 6파티션, **p6=data** 크기에 주목 — 아래는 64GB 보드 실측):
```
NAME         MAJ:MIN  SIZE   TYPE
mmcblk0      ...     57.2G   disk
├─mmcblk0p1 ...      10M     part  (uboot)
├─mmcblk0p2 ...      ~32M    part  (boot)
├─mmcblk0p3 ...      193M    part  (rootfs_a)  ← 루트
├─mmcblk0p4 ...      193M    part  (rootfs_b)
├─mmcblk0p5 ...      256M    part  (config)
└─mmcblk0p6 ...     56.6G    part  (data)  ← 확장 성공
mmcblk0gp0..gp3 (GPP1~4)
mmcblk0boot0/1 (BOOT1/2)
```
> 128GB 보드는 disk 40.5G / data ~38.7G. idblock 은 raw 영역이라 파티션 번호 없음.

```bash
df -h /mnt/data
```
기대: 64GB 보드 ~56 GiB / 128GB 보드 ~38 GiB available

#### B3. rootfs read-only squashfs 확인

```bash
mount | grep " / "
```
기대: `/dev/mmcblk0p3 on / type squashfs (ro,relatime)`   ← **p3** (rootfs_a)

#### B4. GPP4 journal 영속화 확인

```bash
mount | grep journal
```
기대: `/dev/mmcblk0gp3 on /var/log/journal type ext4 (rw,noatime)`

```bash
journalctl --disk-usage
```
기대: `Archived and active journals take up XXX MiB`

```bash
cat /etc/systemd/journald.conf.d/hds-persistent.conf
```
기대:
```
[Journal]
Storage=persistent
SystemMaxUse=256M
MaxFileSec=1week
```

#### B5. eMMC BOOT_PARTITION_ENABLE 무력화 확인

```bash
mmc extcsd read /dev/mmcblk0 | grep -i "PARTITION_CONFIG\|Boot configuration"
```
기대: `Boot configuration bytes [PARTITION_CONFIG: 0x00]` 또는 `No access to boot partition`

#### B6. volatile-binds tmpfs 영역 확인

```bash
mount | grep -E "tmpfs|overlay" | head
```
기대: `/tmp`, `/run`, `/var/log` (journal 제외), `/var/lib` 등이 tmpfs

#### B7. hds-container.service 동작 확인

```bash
systemctl status hds-container
```
기대: `Active: active (running) since ...`

```bash
sudo nerdctl ps
```
기대: `hds-dvr` 컨테이너 실행 중 (이미지 hds-dvr:1.0.0, 엔트리 hds_system)

```bash
sudo nerdctl logs --tail 20 hds-dvr
```
기대: hds_system 시작 + 모듈 초기화 메시지

### 통과 기준 표

| # | 명령 | 통과 기준 |
|---|---|---|
| B1 | `systemctl status hds-firstboot` | `Active: active (exited)` + status=0 (RemainAfterExit=yes) |
| B2 | `lsblk` **p6** 크기 | 64GB 보드 ≥ 56 GiB / 128GB 보드 ≥ 36 GiB |
| B3 | `mount \| grep " / "` | `/dev/mmcblk0p3 ... squashfs (ro,...)` |
| B4 | `mount \| grep journal` | `/dev/mmcblk0gp3 on /var/log/journal type ext4` |
| B5 | `mmc extcsd read` | PARTITION_CONFIG enable bit = 0 |
| B6 | tmpfs 영역 | `/var/log`, `/tmp`, `/run` 가 tmpfs |
| B7 | `nerdctl ps` | `hds-dvr` 컨테이너 running (엔트리: hds_system) |

### 트러블슈팅

| 증상 | 원인 / 대처 |
|---|---|
| `firstboot-done` 없음 | service 미실행 — `journalctl -u hds-firstboot` 에러 확인 |
| p7 크기 8M 그대로 | sgdisk/parted 실패 — 수동 실행 후 재부팅 |
| journal 마운트 실패 | GPP4 미존재 (개발 보드) — 정상, 다음 부팅 fstab으로 자동 재시도 |
| `nerdctl ps` 빈 출력 | hds-container.service 실패 — `journalctl -u hds-container` 확인 |

---

## Task 21 — U-Boot OTA 명령 테스트 (선택)

> ⚠️ **주의**: 이 섹션의 U-Boot OTA env(`hds-uboot-env.txt`, `up_lnx/up_app/up_ubt`)는
> 초기 **mainline U-Boot(idbloader.img/u-boot.itb/fitImage)** 기준으로 설계되었다.
> 이후 BSP 2017.09 전환(idblock.img/uboot.img/boot.img)으로 산출물 파일명·형식이
> 바뀌었으므로, OTA env가 BSP 산출물에 맞게 갱신·재검증되기 전까지 아래 명령은
> 그대로 동작하지 않을 수 있다. 산출물명은 BSP 기준으로 치환해서 읽을 것
> (fitImage→boot.img, idbloader.img→idblock.img, u-boot.itb→uboot.img).

### A. TFTP 서버 준비 (PC)

```bash
sudo apt install tftpd-hpa
sudo systemctl enable --now tftpd-hpa

# /etc/default/tftpd-hpa 확인:
#   TFTP_DIRECTORY="/srv/tftp"
#   TFTP_ADDRESS=":69"

cd /media/ksw/dev/new_dev/rk3588/yocto/build/tmp-glibc/deploy/images/rk3588-hds
sudo cp idbloader.img u-boot.itb fitImage hds-uboot-env.txt /srv/tftp/
sudo cp hds-image-rk3588-hds.rootfs.squashfs-lzo /srv/tftp/
sudo chmod 644 /srv/tftp/*
```

### B. PC와 보드 IP 설정 (예: PC=192.168.2.10, 보드=192.168.2.20)

```bash
# PC
sudo ip addr add 192.168.2.10/24 dev eth0
sudo ip link set eth0 up
```

### C. 보드 U-Boot 콘솔 진입

부팅 중 시리얼 콘솔에서 `Hit any key to stop autoboot` 출력 시 아무 키 입력 → `HDS>` 프롬프트

### D. 최초 1회 env 등록

```
HDS> setenv serverip 192.168.2.10
HDS> setenv ipaddr 192.168.2.20
HDS> setenv netmask 255.255.255.0
HDS> tftpboot ${loadaddr} hds-uboot-env.txt
HDS> env import -t ${loadaddr} ${filesize}
HDS> saveenv
```

### E. 명령별 테스트

**커널 OTA**
```
HDS> run up_lnx
[HDS] up_lnx: fitImage 다운로드...
... TFTP ...
[HDS] up_lnx: 완료 (boot=p3)          ← bootpart=3 동적 조회 정상
```

**비활성 슬롯 rootfs OTA**
```
HDS> printenv boot_slot
boot_slot=a

HDS> run up_app
[HDS] up_app_b: rootfs 다운로드...
... 1~3분 ...
[HDS] up_app_b: 완료. 다음 부팅부터 슬롯 B 사용

HDS> reset
# (B 슬롯 부팅 후)
$ mount | grep " / "
/dev/mmcblk0p5 on / type squashfs (ro,...)   ← rootfs_b
```

**Rollback (슬롯 전환)**
```
HDS> run up_swap
[HDS] 슬롯 전환됨: a. reset 후 적용.
# (A 슬롯 복귀 후)
$ mount | grep " / "
/dev/mmcblk0p4 on / type squashfs (ro,...)   ← rootfs_a
```

**부트로더 OTA (주의)**
```
HDS> run up_ubt
[HDS] up_ubt: idbloader 다운로드... → LBA 0x40 mmc write
[HDS] up_ubt: u-boot.itb 다운로드... → LBA 0x4000 mmc write
[HDS] up_ubt: 완료
HDS> reset
# (새 부트로더로 부팅 검증)
```

### 통과 기준 표

| 명령 | 통과 기준 |
|---|---|
| `run up_lnx` | TFTP 성공 + `완료 (boot=p3)` 출력 + reset 후 새 fitImage 부팅 |
| `run up_app` | TFTP 성공 + `슬롯 B 사용` + reset 후 mmcblk0p5 마운트 |
| `run up_swap` | boot_slot 토글 + reset 후 원래 슬롯 부팅 |
| `run up_ubt` | raw 갱신 + reset 후 정상 부팅 |
| `run up_all` | 위 3개 순차 실행 + 정상 부팅 |

### 트러블슈팅

| 증상 | 원인 / 대처 |
|---|---|
| `TFTP error: ARP timeout` | PC IP/네트워크 설정 확인 |
| `*** ERROR: serverip not set` | env 미등록 — D 단계 재시도 |
| `Unknown command 'part'` | CONFIG_CMD_PART 미활성화 — Kconfig fragment 확인 |
| `ext4write fail` | boot 파티션 손상 — `--erase` 재플래싱 |
| `mmc write fail` (up_app) | slot_size 초과 — squashfs 크기 vs slot 비교 (193MB vs ~194MB이라 빠듯) |

---

## 검증 진행 트래커

각 항목 완료 시 체크:

### Task 18: 플래싱
- [ ] MaskROM 진입 (lsusb 인식)
- [ ] flash-emmc.sh 정상 종료
- [ ] 보드 자동 재부팅

### Task 19: 시리얼 부팅
- [ ] DDR/SPL/U-Boot 로그
- [ ] PARTLABEL 동적 조회 (`ext4load mmc 0:3`)
- [ ] squashfs ro 마운트
- [ ] login 프롬프트

### Task 20: hds-firstboot
- [ ] firstboot-done 생성
- [ ] p7 ~36.6 GiB 확장
- [ ] rootfs squashfs ro
- [ ] GPP4 → /var/log/journal
- [ ] BOOT_PARTITION_ENABLE=0
- [ ] tmpfs 영역
- [ ] hds-container 실행

### Task 21: U-Boot OTA (선택)
- [ ] env 등록
- [ ] run up_lnx
- [ ] run up_app + slot 전환
- [ ] run up_swap + rollback

---

## 참고 문서

- 빌드: `MarkDown/yocto-build/10_full_build_guide.md`
- U-Boot env: `MarkDown/yocto-build/09_uboot_update_guide.md`
- eMMC 사양: `MarkDown/emmc_partition_info.md`
- 유닛 테스트: `MarkDown/testing/01_unit_test_guide.md`
- 작성 일자: 2026-05-18 / 갱신: 2026-05-29 (BSP 전환 + 64GB 보드 실기 검증 반영)

---

## 실기 검증 결과 (2026-05-29, 64GB DV4064 보드)

첫 실기 부팅 검증 결과. 보드는 정상 부팅(BSP 2017.09 → squashfs ro → systemd → login).

### Task 20 결과
| # | 항목 | 결과 |
|---|---|---|
| B1 | hds-firstboot | ✅ `active (exited)` status=0 |
| B2 | data 확장 | ✅ p6 = 56.6 GiB (PARTLABEL 동적조회로 data=p6 정확히 탐지) |
| B3 | squashfs ro | ✅ `/dev/mmcblk0p3 on / squashfs (ro)` |
| B5 | BOOT_PARTITION_ENABLE=0 | ✅ 로그 `disabled` |
| B4 | GPP4 journal | ❌ → 🔧 수정함 (F1) |
| B7 | hds-container | ❌ → 🔧 수정함 (F2) |

### F1 — GPP4 journal 영속화 실패 (수정 완료)
- 증상: `mount: /var/log/journal: mount point does not exist`. 이후 firstboot 완료플래그로 재시도 안 됨.
- 원인: `hds-firstboot.service`가 `Before=local-fs.target`+`DefaultDependencies=no`로 매우 이른 단계 실행 → `/var/log`(volatile tmpfs) 미마운트 상태(read-only squashfs)라 마운트 지점 생성 실패.
- 수정: 마운트를 firstboot에서 분리.
  - `firstboot-setup.sh`: GPP4 ext4 **포맷만** 담당.
  - `hds-image.bb`: fstab에 `/dev/mmcblk0gp3 /var/log/journal ext4 defaults,noatime,nofail 0 2` 추가.
  - 원리: `systemd-journal-flush.service`의 내장 `RequiresMountsFor=/var/log/journal`이 해당 마운트를 자동 대기 후 flush → 매 부팅 올바른 시점 영속화.
- 수동 검증: `mount /dev/mmcblk0gp3 /var/log/journal` + journald restart 정상 동작 확인.

### F2 — hds-container.service 시작 실패 (수정 완료)
- 증상: `runc create failed: ... error mounting "mqueue" to rootfs at "/dev/mqueue": ... no such device`.
- 원인: **커널 `CONFIG_POSIX_MQUEUE` 누락**. runc가 모든 컨테이너에 /dev/mqueue(mqueue fs) 기본 마운트하는데 BSP 5.10 벤더 defconfig가 비활성 → mqueue fstype 미등록(ENODEV). (이미지 로드·device 매핑·seccomp·cgroup 모두 정상, mqueue가 유일 차단점)
- 수정: `hds.cfg`에 `CONFIG_POSIX_MQUEUE=y` + `CONFIG_POSIX_MQUEUE_SYSCTL=y` 추가.
- 적용: 커널 리빌드(`bitbake hds-image`) → 재플래싱(`flash-emmc.sh --erase`) → 재검증 필요.

### 재플래싱 후 재검증 항목
- [ ] `nerdctl ps` → hds-dvr running (F2 해결 확인)
- [ ] `mount | grep journal` → `/dev/mmcblk0gp3 on /var/log/journal` (F1 해결 확인, fstab 자동 마운트)
- [ ] 재부팅 1회 더 → journal 마운트가 매 부팅 유지되는지 (firstboot skip 후에도)
