#!/usr/bin/env bash
# Build TF-A BL31 and U-Boot for the ClockworkPi DevTerm A04 (H6).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman

UBOOT_VER=2025.01
ATF_VER=2.11.0
SRC="$ART/src"
[ -s "$SRC/u-boot-${UBOOT_VER}.tar.bz2" ] || die "run scripts/fetch.sh first"
[ -s "$SRC/arm-trusted-firmware-${ATF_VER}.tar.gz" ] || die "run scripts/fetch.sh first"

if ! podman image exists devterm-builder; then
    log "building cross toolchain container"
    podman build --arch amd64 -t devterm-builder -f "$ROOT/containers/builder.Dockerfile" "$ROOT"
fi

mkdir -p "$BUILD/uboot" "$BUILD/atf" "$ART/uboot"
rm -rf "$BUILD/atf/arm-trusted-firmware-${ATF_VER}" \
       "$BUILD/uboot/u-boot-${UBOOT_VER}"
tar -xzf "$SRC/arm-trusted-firmware-${ATF_VER}.tar.gz" -C "$BUILD/atf"
tar -xjf "$SRC/u-boot-${UBOOT_VER}.tar.bz2" -C "$BUILD/uboot"

cp "$VENDOR/uboot/sun50i-h6-clockworkpi-a04.dts" \
   "$BUILD/uboot/u-boot-${UBOOT_VER}/arch/arm/dts/"
cp "$VENDOR/uboot/clockworkpi-a04-h6_defconfig" \
   "$BUILD/uboot/u-boot-${UBOOT_VER}/configs/"

# Register the board DTS.  Keep the trailing backslash: the U-Boot DTS
# Makefile continues the dtb-$(CONFIG_MACH_SUN50I_H6) list on the next line.
python3 - "$BUILD/uboot/u-boot-${UBOOT_VER}/arch/arm/dts/Makefile" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
entry = "\tsun50i-h6-clockworkpi-a04.dtb \\\n"
if "sun50i-h6-clockworkpi-a04.dtb" not in text:
    needle = "\tsun50i-h6-beelink-gs1.dtb \\\n"
    if needle not in text:
        raise SystemExit("cannot find sun50i-h6-beelink-gs1.dtb in U-Boot DTS Makefile")
    text = text.replace(needle, needle + entry, 1)
    path.write_text(text)
PY

# U-Boot 2025 treats SCP firmware as a required external blob when the H6
# SCP base is non-zero.  Crust is only needed for suspend, so omit it; BL31
# still supplies PSCI.  This is the minimal source change needed to build a
# functional boot chain without an OR1K toolchain.
kconfig="$BUILD/uboot/u-boot-${UBOOT_VER}/arch/arm/mach-sunxi/Kconfig"
grep -q 'default 0x00114000 if MACH_SUN50I_H6' "$kconfig" || \
    die "unexpected U-Boot H6 SCP default; cannot disable optional SCP"
sed -i 's/default 0x00114000 if MACH_SUN50I_H6/default 0x0 if MACH_SUN50I_H6/' "$kconfig"

podman run --rm --userns=keep-id --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -v "$ROOT:/work" -w /work devterm-builder bash -c "
set -euo pipefail
make -C build/atf/arm-trusted-firmware-${ATF_VER} \
    CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_h6 -j\"\$(nproc)\" bl31
cp build/atf/arm-trusted-firmware-${ATF_VER}/build/sun50i_h6/release/bl31.bin \
   artifacts/uboot/bl31.bin
make -C build/uboot/u-boot-${UBOOT_VER} \
    CROSS_COMPILE=aarch64-linux-gnu- clockworkpi-a04-h6_defconfig
make -C build/uboot/u-boot-${UBOOT_VER} \
    CROSS_COMPILE=aarch64-linux-gnu- BL31=/work/artifacts/uboot/bl31.bin \
    -j\"\$(nproc)\"
cp build/uboot/u-boot-${UBOOT_VER}/u-boot-sunxi-with-spl.bin \
   artifacts/uboot/u-boot-sunxi-with-spl.bin
"

[ -s "$ART/uboot/u-boot-sunxi-with-spl.bin" ] || die "U-Boot image was not produced"
log "U-Boot: $(du -h "$ART/uboot/u-boot-sunxi-with-spl.bin" | cut -f1)"
