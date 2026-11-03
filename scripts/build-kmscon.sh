#!/usr/bin/env bash
# Build kmscon 10.0.4 for arm64 with the A04 1px rotation guard band.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman
need curl
need tar

KMS_VER="${KMS_VER:-10.0.4}"
TARBALL="$ART/src/kmscon-${KMS_VER}.tar.gz"
SRC="$BUILD/kmscon-src"
STAGE="$ART/kmscon"
URL="https://deb.debian.org/debian/pool/main/k/kmscon/kmscon_${KMS_VER}.orig.tar.gz"

if [ -x "$STAGE/usr/bin/kmscon" ] && [ "${FORCE_KMS:-0}" != 1 ]; then
    log "kmscon already built: $STAGE/usr/bin/kmscon"
    exit 0
fi

if [ ! -s "$TARBALL" ]; then
    log "downloading kmscon $KMS_VER"
    curl -fL --retry 3 --progress-bar -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi

if [ "$(cat "$SRC/.devterm-version" 2>/dev/null)" != "$KMS_VER" ]; then
    rm -rf "$SRC"
    mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components=1
    echo "$KMS_VER" >"$SRC/.devterm-version"
fi

if ! grep -q 'A04 panel: the native x axis' "$SRC/src/render/bbulk.c"; then
    patch -d "$SRC" -p1 <"$ROOT/patches/kmscon-a04-pad.patch"
fi

if ! podman image exists devterm-kmscon-builder; then
    log "building arm64 kmscon container"
    podman build --arch arm64 -t devterm-kmscon-builder \
        -f "$ROOT/containers/kmscon.Dockerfile" "$ROOT"
fi

log "building kmscon with the A04 guard band"
podman run --rm --arch arm64 --userns=keep-id --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$SRC:/src:rw" -w /src \
    devterm-kmscon-builder \
    bash -c '
set -euo pipefail
rm -rf builddir stage
meson setup builddir --prefix=/usr --buildtype=release \
    -Ddocs=disabled -Dtests=false -Dlibseat=disabled \
    -Dvideo_fbdev=enabled -Dvideo_drm2d=enabled -Dvideo_drm3d=enabled \
    -Dfont_freetype=enabled -Dfont_pango=enabled -Dfont_psf=enabled \
    -Dfont_unifont=disabled
ninja -C builddir
DESTDIR=/src/stage ninja -C builddir install
'

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$SRC/stage/usr" "$STAGE/usr"
chmod 755 "$STAGE/usr/bin/kmscon"
log "kmscon built: $(du -sh "$STAGE" | cut -f1)"
