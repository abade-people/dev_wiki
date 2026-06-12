#!/usr/bin/env bash
# 프로젝트 저장소(new_dev/rk3588/MarkDown/)의 문서를 vault로 동기화한다.
# 원본은 항상 프로젝트 쪽이며, vault 쪽 동일 파일은 덮어쓴다.
# (Troubleshooting/ 등 vault 전용 폴더는 건드리지 않는다)
set -euo pipefail

SRC=/home/ksw/dev/new_dev/rk3588/MarkDown
DST="$(cd "$(dirname "$0")/.." && pwd)/RK3588-HDS"

rsync -av --include='*.md' --exclude='*' "$SRC/yocto-build/"   "$DST/Yocto-Build/"
rsync -av --include='*.md' --exclude='*' "$SRC/feature_spec/"  "$DST/Feature-Spec/"
rsync -av --include='*.md' --exclude='*' "$SRC/testing/"       "$DST/Testing/"
rsync -av "$SRC/emmc_partition_info.md"                        "$DST/Hardware/"

echo "동기화 완료: $SRC → $DST"
