#!/usr/bin/env bash
# Download upstream sources/packages and stage fonts into artifacts/.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs

UBOOT_VER=2025.01
ATF_VER=2.11.0
CARBONYL_VER=0.0.3
CHAWAN_VER=0.5.1
VENDOR_BASE=https://raw.githubusercontent.com/clockworkpi/apt/main/debian

download() {
    local url="$1" out="$2"
    if [ -s "$out" ]; then
        log "cached $(basename "$out")"
        return 0
    fi
    log "downloading $(basename "$out")"
    curl -fL --retry 3 --progress-bar -o "$out.part" "$url"
    mv "$out.part" "$out"
}

download "https://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VER}.tar.bz2" \
    "$ART/src/u-boot-${UBOOT_VER}.tar.bz2"
download "https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/v${ATF_VER}.tar.gz" \
    "$ART/src/arm-trusted-firmware-${ATF_VER}.tar.gz"

# ClockworkPi's A04 kernel and board packages.  These are the only public
# binaries with the A04 panel/backlight/audio/printer wiring.
vendor_pkgs=(
    "devterm-audio-patch/devterm-audio-patch_0.04_all.deb"
    "devterm-fan-daemon-cpi-a04/devterm-fan-daemon-cpi-a04_0.15_arm64.deb"
    "devterm-gearbox-a04/devterm-gearbox-a04_0.13_arm64.deb"
    "devterm-kernel-current-cpi-a04/devterm-kernel-current-cpi-a04_0.6_arm64.deb"
    "devterm-thermal-printer/devterm-thermal-printer_0.38_arm64.deb"
    "devterm-wiringpi-cpi-a04/devterm-wiringpi-cpi-a04_0.11_arm64.deb"
)
for pkg in "${vendor_pkgs[@]}"; do
    download "$VENDOR_BASE/pool/main/d/$pkg" "$ART/vendor/$(basename "$pkg")"
done

if [ ! -x "$ART/carbonyl/carbonyl" ]; then
    download "https://github.com/fathyb/carbonyl/releases/download/v${CARBONYL_VER}/carbonyl.linux-arm64.zip" \
        "$ART/src/carbonyl.linux-arm64.zip"
    need unzip
    rm -rf "$ART/src/carbonyl-extract"
    mkdir -p "$ART/src/carbonyl-extract"
    unzip -q "$ART/src/carbonyl.linux-arm64.zip" -d "$ART/src/carbonyl-extract"
    rm -rf "$ART/carbonyl"
    mkdir -p "$ART/carbonyl"
    cp -a "$ART/src/carbonyl-extract/carbonyl-${CARBONYL_VER}/." "$ART/carbonyl/"
    chmod +x "$ART/carbonyl/carbonyl"
fi
log "Carbonyl: $(du -sh "$ART/carbonyl" | cut -f1)"

# Source for the additional terminal browser.  The build script does the
# container build; caching the tarball here keeps it reproducible.
download "https://git.sr.ht/~bptato/chawan/archive/v${CHAWAN_VER}.tar.gz" \
    "$ART/src/chawan-${CHAWAN_VER}.tar.gz"

# Nerd Fonts: keep every NerdFont file from the user's font directory and
# install them system-wide later.  Hard links avoid duplicating ~0.6 GiB.
[ -d "$FONT_SRC" ] || die "font directory not found: $FONT_SRC (set DEVTERM_FONT_DIR)"
font_count=0
while IFS= read -r -d '' src; do
    dst="$ART/fonts/$(basename "$src")"
    if [ ! -e "$dst" ]; then
        cp -a "$src" "$dst" 2>/dev/null || ln "$src" "$dst"
    fi
    font_count=$((font_count + 1))
done < <(find "$FONT_SRC" -maxdepth 1 -type f -iname '*nerdfont*' -print0)
[ "$font_count" -gt 0 ] || die "no *NerdFont* files found in $FONT_SRC"
log "staged $font_count NerdFont files"

paper="$ART/fonts/PaperMonoNerdFont-Regular.otf"
[ -f "$paper" ] || die "PaperMonoNerdFont-Regular.otf not found in $FONT_SRC"

if ! python3 -c 'import PIL, fontTools' >/dev/null 2>&1; then
    die "python3 Pillow and fonttools are required to build the console font"
fi

for spec in "8 16" "9 18" "10 20" "16 32"; do
    set -- $spec
    out="$ART/consolefonts/PaperMonoNerdFont-$1x$2.psf.gz"
    if [ ! -s "$out" ] || [ "${FORCE_FONTS:-0}" = 1 ]; then
        log "building console font $1x$2"
        python3 "$ROOT/scripts/make-console-font.py" "$paper" "$out" \
            --width "$1" --height "$2"
    fi
done

log "fetch complete"
