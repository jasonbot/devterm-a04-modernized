#!/usr/bin/env bash
# Shared paths and helpers for the DevTerm A04 image build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ART="$ROOT/artifacts"
BUILD="$ROOT/build"
VENDOR="$ROOT/vendor"
FONT_SRC="${DEVTERM_FONT_DIR:-$HOME/Sync/Fonts}"

export ROOT ART BUILD VENDOR FONT_SRC

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ensure_dirs() {
    mkdir -p "$ART" "$ART/src" "$ART/vendor" "$ART/fonts" \
             "$ART/consolefonts" "$ART/uboot" "$ART/export" "$BUILD"
}
