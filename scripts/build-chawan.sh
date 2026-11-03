#!/usr/bin/env bash
# Build Chawan (TUI web browser) for arm64 in a Debian trixie container.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman
need curl
need tar

CHAWAN_VER="${CHAWAN_VER:-0.5.1}"
TARBALL="$ART/src/chawan-${CHAWAN_VER}.tar.gz"
SRC="$BUILD/chawan-src"
STAGE="$ART/chawan"
URL="https://git.sr.ht/~bptato/chawan/archive/v${CHAWAN_VER}.tar.gz"

if [ -x "$STAGE/usr/bin/cha" ] && [ "${FORCE_CHAWAN:-0}" != 1 ]; then
    log "Chawan already built: $STAGE/usr/bin/cha"
    exit 0
fi

if [ ! -s "$TARBALL" ]; then
    log "downloading Chawan $CHAWAN_VER"
    curl -fL --retry 3 --progress-bar -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi

if [ "$(cat "$SRC/.devterm-version" 2>/dev/null)" != "$CHAWAN_VER" ]; then
    rm -rf "$SRC"
    mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components=1
    echo "$CHAWAN_VER" >"$SRC/.devterm-version"
fi

if ! podman image exists devterm-chawan-builder; then
    log "building arm64 Chawan container"
    podman build --arch arm64 -t devterm-chawan-builder \
        -f "$ROOT/containers/chawan.Dockerfile" "$ROOT"
fi

log "building Chawan (Nim -> C, can take a few minutes)"
podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$SRC:/src:rw" -w /src \
    devterm-chawan-builder \
    bash -c '
set -euo pipefail
make -j"$(nproc)" TARGET=release
rm -rf stage
make install DESTDIR=/src/stage PREFIX=/usr
'

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$SRC/stage/usr" "$STAGE/usr"
chmod 755 "$STAGE/usr/bin/cha" "$STAGE/usr/bin/mancha"
log "Chawan built: $(du -sh "$STAGE" | cut -f1)"
