#!/usr/bin/env bash
# One-shot, rootless build: fetch -> U-Boot/ATF -> Debian rootfs -> image.
set -euo pipefail
cd "$(dirname "$0")"

./scripts/fetch.sh
./scripts/build-uboot.sh
./scripts/build-ly.sh
./scripts/build-chawan.sh
./scripts/build-rootfs.sh
./scripts/build-image.sh

printf '\nBuilt:\n'
ls -lh artifacts/devterm-a04.img artifacts/devterm-a04.img.zst
cat artifacts/SHA256SUMS
