#!/bin/sh
# Cross-build tools/devterm-print for the A04 (arm64) with the host Go.
# The result lands in artifacts/devterm-print and is picked up by the rootfs
# stage when present.
set -eu
cd "$(dirname "$0")/../tools/devterm-print"
command -v go >/dev/null 2>&1 || { echo "go (>= 1.23) is required to build devterm-print" >&2; exit 1; }
mkdir -p ../../artifacts/devterm-print
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' \
    -o ../../artifacts/devterm-print/devterm-print .
ls -lh ../../artifacts/devterm-print/devterm-print
