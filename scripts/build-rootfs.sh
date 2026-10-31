#!/usr/bin/env bash
# Build a Debian 13 arm64 rootfs with the ClockworkPi A04 kernel and overlays.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman
need mkimage

[ -d "$ART/vendor" ] && [ -d "$ART/fonts" ] && [ -d "$ART/carbonyl" ] || \
    die "run scripts/fetch.sh first"
[ -x "$ART/ly/ly" ] || die "run scripts/build-ly.sh first"
[ -s "$ART/uboot/u-boot-sunxi-with-spl.bin" ] || \
    die "run scripts/build-uboot.sh first"

if ! podman image exists devterm-rootfs-builder; then
    log "building arm64 rootfs container"
    podman build --arch arm64 -t devterm-rootfs-builder \
        -f "$ROOT/containers/rootfs.Dockerfile" "$ROOT"
fi

log "generating boot.scr fallback"
mkimage -A arm64 -O linux -T script -C none -n "DevTerm A04 boot" \
    -d "$ROOT/overlay/boot/boot.cmd" "$ART/uboot/boot.scr" >/dev/null

chmod 777 "$ART/export"
rm -f "$ART/export/rootfs.tar"

packages="systemd-sysv,systemd-timesyncd,udev,dbus,initramfs-tools,kmod,e2fsprogs,fdisk,cloud-guest-utils,zram-tools,locales,tzdata,console-setup,keyboard-configuration,kbd,network-manager,wpasupplicant,iw,wireless-tools,rfkill,wireless-regdb,firmware-brcm80211,openssh-server,sudo,libpam-systemd,python3,socat,fonts-noto-cjk,fontconfig,fonts-dejavu-core,libfreetype6,libnss3,libnspr4,libexpat1,libasound2t64,libgbm1,libdrm2,libxkbcommon0,w3m,ca-certificates,curl,wget,less,nano,git,rsync,unzip,xz-utils,zstd,bzip2,alsa-utils,usbutils,pciutils,procps,psmisc,iproute2,iputils-ping,net-tools,htop,tmux,brightnessctl"

log "building Debian trixie arm64 rootfs (this takes a few minutes)"
podman run --rm --arch arm64 --network=host \
    -v "$ROOT:/work:ro" -v "$ART/export:/export:rw" \
    devterm-rootfs-builder \
    mmdebstrap --arch=arm64 --mode=root --variant=minbase \
        --components=main,non-free-firmware \
        --aptopt='APT::Install-Recommends "false";' \
        --include="$packages" \
        --customize-hook='/work/scripts/customize-rootfs.sh "$1"' \
        --format=tar \
        trixie /export/rootfs.tar http://deb.debian.org/debian

[ -s "$ART/export/rootfs.tar" ] || die "mmdebstrap did not produce rootfs.tar"
log "rootfs tar: $(du -h "$ART/export/rootfs.tar" | cut -f1)"

log "extracting rootfs (device nodes are supplied by devtmpfs at boot)"
rm -rf "$ART/rootfs"
mkdir -p "$ART/rootfs"
tar -xpf "$ART/export/rootfs.tar" -C "$ART/rootfs" \
    --exclude='./dev/*' --no-same-owner
rm -f "$ART/export/rootfs.tar"

# Sanity checks that must be true before we spend time making an image.
for f in boot/Image boot/devterm-a04.dtb boot/initrd.img \
         boot/extlinux/extlinux.conf etc/vconsole.conf \
         usr/local/share/fonts/nerd-fonts/PaperMonoNerdFont-Regular.otf \
         opt/carbonyl/carbonyl usr/local/bin/devterm-kiosk \
         usr/bin/ly etc/ly/config.lua \
         usr/lib/systemd/system/ly-kmsconvt@.service \
         usr/lib/aarch64-linux-gnu/libasound.so.2; do
    [ -e "$ART/rootfs/$f" ] || die "rootfs is missing /$f"
done
grep -A2 '^Package: libasound2t64$' "$ART/rootfs/var/lib/dpkg/status" | \
    grep -q 'Status: install ok installed' || die "libasound2t64 is not installed"
log "rootfs ready: $(du -sh "$ART/rootfs" | cut -f1)"
