---
tags: [project, rk3588]
프로젝트경로: /home/ksw/dev/new_dev/rk3588
저장소문서: MarkDown/ (원본 소스)
---

# RK3588 HDS — 프로젝트 허브

RK3588 기반 **HDS(Hazard Detection System) DVR/AI 시스템**.
차량용 영상녹화 + AI 위험감지 장비를 Yocto Linux 위에서 컨테이너 기반으로 재구현.

- **아키텍처**: Yocto Host OS → containerd + nerdctl → Application Container
- **HW Passthrough**: NPU (6 TOPS) + GPU (Mali G610) + VPU (H.264/H.265 HW codec)
- **OTA 전략**: 컨테이너 이미지만 업데이트 (Host OS 고정)

> [!note] 문서 원본
> 이 폴더의 문서 원본은 프로젝트 저장소 `new_dev/rk3588/MarkDown/`입니다.
> 프로젝트 쪽이 갱신되면 vault 루트에서 `scripts/sync-from-project.sh`를 실행해 가져오세요.

## 📋 기능 사양 (Feature Spec)

| # | 문서 | 주제 |
|---|---|---|
| 00 | [[Feature-Spec/00_overview\|개요]] | 시스템 전체 개요 |
| 01 | [[Feature-Spec/01_system_architecture\|시스템 아키텍처]] | 컨테이너/프로세스 구조 |
| 02 | [[Feature-Spec/02_video_pipeline\|비디오 파이프라인]] | 카메라 → 인코딩 경로 |
| 03 | [[Feature-Spec/03_recording_and_storage\|녹화/저장]] | 녹화 정책 |
| 04 | [[Feature-Spec/04_playback\|재생]] | 재생 기능 |
| 05 | [[Feature-Spec/05_display_and_view_modes\|디스플레이/뷰 모드]] | 화면 출력 |
| 06 | [[Feature-Spec/06_ai_object_detection\|AI 객체 감지]] | NPU 추론 |
| 07 | [[Feature-Spec/07_hds_hazard_detection\|HDS 위험 감지]] | 핵심 위험감지 로직 |
| 08 | [[Feature-Spec/08_io_and_vehicle_interface\|I/O·차량 인터페이스]] | GPIO/CAN 등 |
| 09 | [[Feature-Spec/09_audio_system\|오디오 시스템]] | 녹음/경고음 |
| 10 | [[Feature-Spec/10_network_and_streaming\|네트워크/스트리밍]] | 통신 |
| 11 | [[Feature-Spec/11_fleet_management\|플릿 관리]] | 관제 연동 |
| 12 | [[Feature-Spec/12_ui_osd\|UI/OSD]] | 화면 UI |
| 13 | [[Feature-Spec/13_storage_management\|스토리지 관리]] | 용량/순환 정책 |
| 14 | [[Feature-Spec/14_configuration_system\|설정 시스템]] | 설정 관리 |
| 15 | [[Feature-Spec/15_data_formats\|데이터 포맷]] | 파일/메타데이터 |
| 16 | [[Feature-Spec/16_event_system\|이벤트 시스템]] | 이벤트 처리 |
| 17 | [[Feature-Spec/17_ota_and_boot\|OTA/부팅]] | A/B 슬롯, 업데이트 |
| 18 | [[Feature-Spec/18_hal_specification\|HAL 사양]] | 하드웨어 추상화 |

## 🏗️ Yocto 빌드

| # | 문서 |
|---|---|
| 00 | [[Yocto-Build/00_yocto_build_guide\|빌드 가이드 (시작점)]] |
| 01 | [[Yocto-Build/01_layer_structure\|레이어 구조]] |
| 02 | [[Yocto-Build/02_machine_conf\|Machine 설정]] |
| 03 | [[Yocto-Build/03_recipes_bsp\|BSP 레시피]] |
| 04 | [[Yocto-Build/04_recipes_libs\|라이브러리 레시피]] |
| 05 | [[Yocto-Build/05_recipes_app\|앱 레시피]] |
| 06 | [[Yocto-Build/06_recipes_image\|이미지 레시피]] |
| 07 | [[Yocto-Build/07_distro_conf\|Distro 설정]] |
| 08 | [[Yocto-Build/08_soc_porting_guide\|SoC 포팅 가이드]] |
| 09 | [[Yocto-Build/09_uboot_update_guide\|U-Boot 업데이트]] |
| 10 | [[Yocto-Build/10_full_build_guide\|풀 빌드 가이드]] |

## 🧪 테스트

- [[Testing/01_unit_test_guide|단위 테스트 가이드]]
- [[Testing/02_flash_verification_guide|플래싱 검증 가이드]]

## 💾 하드웨어

- [[Hardware/emmc_partition_info|eMMC 파티션·용량 정보]] (64GB/128GB, pSLC, A/B OTA 슬롯)

## 🔥 트러블슈팅

`Troubleshooting/` 폴더에 문제 해결 기록을 쌓습니다. → [[Templates/troubleshooting|템플릿]]
