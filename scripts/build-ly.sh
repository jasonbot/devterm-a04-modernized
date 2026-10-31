#!/usr/bin/env bash
# Build Ly (the TUI display manager) for arm64 without a root shell.
# Ly is written in Zig; this uses the official Zig 0.17 compiler in an arm64
# container.  X11 support is disabled because this image is console-only.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman
need git
need tar
need curl

LY_REPO="${LY_REPO:-https://github.com/fairyglade/ly.git}"
LY_COMMIT="${LY_COMMIT:-747955ce3b654039c2aab9c2dbc089c26b07953c}"
ZIG_VER=0.17.0
ZIG_TAR="$ART/src/zig-aarch64-linux-${ZIG_VER}.tar.xz"
ZIG_DIR="$BUILD/zig-aarch64-linux-${ZIG_VER}"
LY_SRC="$BUILD/ly-src"
LY_BIN="$ART/ly/ly"

if [ -x "$LY_BIN" ] && [ "${FORCE_LY:-0}" != 1 ]; then
    log "Ly already built: $LY_BIN"
    exit 0
fi

mkdir -p "$ART/ly" "$ART/src" "$BUILD"
if [ ! -s "$ZIG_TAR" ]; then
    log "downloading Zig $ZIG_VER (arm64)"
    curl -fL --retry 3 --progress-bar -o "$ZIG_TAR.part" \
        "https://ziglang.org/download/${ZIG_VER}/zig-aarch64-linux-${ZIG_VER}.tar.xz"
    mv "$ZIG_TAR.part" "$ZIG_TAR"
fi
if [ ! -x "$ZIG_DIR/zig" ]; then
    rm -rf "$ZIG_DIR"
    tar -xJf "$ZIG_TAR" -C "$BUILD"
fi

if ! podman image exists devterm-ly-builder; then
    log "building Ly build container"
    podman build --arch arm64 -t devterm-ly-builder \
        -f "$ROOT/containers/ly-builder.Dockerfile" "$ROOT"
fi

if [ ! -d "$LY_SRC/.git" ]; then
    rm -rf "$LY_SRC"
    git clone --depth 1 "$LY_REPO" "$LY_SRC"
fi
if [ -n "$LY_COMMIT" ]; then
    git -C "$LY_SRC" fetch --depth 1 origin "$LY_COMMIT"
    git -C "$LY_SRC" checkout --detach "$LY_COMMIT"
fi

log "building Ly for arm64 (first build can take several minutes)"
podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
    --network=host -e HOME=/tmp \
    -v "$LY_SRC:/src" -v "$ZIG_DIR:/opt/zig:ro" -w /src \
    devterm-ly-builder bash -c '
set -euo pipefail
/opt/zig/zig build -Denable_x11_support=false -Doptimize=ReleaseSafe \
    -Ddefault_tty=1 -Dfallback_tty=1
cp zig-out/bin/ly /src/ly.built
'

cp "$LY_SRC/ly.built" "$LY_BIN"
chmod 755 "$LY_BIN"
log "Ly built: $(du -h "$LY_BIN" | cut -f1) -> $LY_BIN"
