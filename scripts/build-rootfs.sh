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
[ -x "$ART/chawan/usr/bin/cha" ] || die "run scripts/build-chawan.sh first"
[ -x "$ART/kmscon/usr/bin/kmscon" ] || die "run scripts/build-kmscon.sh first"
[ -x "$ART/nmtui-go/nmtui-go" ] || die "run scripts/fetch.sh first (nmtui-go)"
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

packages="systemd-sysv,systemd-timesyncd,udev,dbus,initramfs-tools,kmod,e2fsprogs,fdisk,cloud-guest-utils,zram-tools,locales,tzdata,console-setup,keyboard-configuration,kbd,network-manager,wpasupplicant,iw,wireless-tools,rfkill,wireless-regdb,firmware-brcm80211,openssh-server,sudo,libpam-systemd,python3,socat,fonts-noto-cjk,fontconfig,fonts-dejavu-core,libfreetype6,libnss3,libnspr4,libexpat1,libasound2t64,libgbm1,libdrm2,libxkbcommon0,libstdc++6,zlib1g,libssh2-1t64,libbrotli1,libssl3t64,w3m,ca-certificates,curl,wget,less,nano,git,rsync,unzip,xz-utils,zstd,bzip2,alsa-utils,usbutils,pciutils,procps,psmisc,iproute2,iputils-ping,net-tools,htop,tmux,starship,brightnessctl"

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
         opt/rustel/rustel usr/local/bin/rustel \
         usr/bin/cha usr/bin/mancha usr/libexec/chawan/cgi-bin/ssl \
         usr/local/bin/carboxyl usr/local/bin/devterm-kiosk \
         usr/bin/kmscon usr/local/bin/nmtui-go \
         usr/lib/firmware/brcm/brcmfmac43455-sdio.txt \
         'usr/lib/firmware/brcm/brcmfmac43455-sdio.clockwork,devterm-a04.txt' \
         usr/lib/firmware/brcm/brcmfmac43456-sdio.bin \
         usr/lib/firmware/brcm/brcmfmac43456-sdio.clm_blob \
         usr/lib/firmware/brcm/brcmfmac43456-sdio.txt \
         'usr/lib/firmware/brcm/brcmfmac43456-sdio.clockwork,devterm-a04.txt' \
         usr/bin/tailscale usr/sbin/tailscaled usr/bin/yazi etc/tmux.conf \
         usr/local/bin/devterm-wifi usr/local/bin/devterm-tailscale-status \
         etc/profile.d/tmux-login.sh \
         usr/local/bin/devterm-battery usr/local/bin/devterm-power \
         usr/local/bin/devterm-web usr/local/bin/devterm-web-session \
         usr/bin/cage usr/bin/cog \
         usr/local/bin/devterm-kms \
         usr/local/bin/devterm-idle-suspend \
         usr/lib/systemd/system/devterm-idle-suspend.timer \
         usr/lib/systemd/system-sleep/devterm-resume-stamp \
         usr/lib/systemd/system-sleep/devterm-wifi-resume \
         usr/lib/systemd/system-sleep/devterm-sleep-screen \
         usr/local/bin/devterm-screen-restore \
         usr/bin/starship etc/starship.toml etc/profile.d/starship.sh \
         etc/skel/.config/yazi/theme.toml \
         etc/skel/.config/yazi/flavors/gruvbox-material.yazi/flavor.toml \
         etc/skel/.config/starship.toml home/devterm/.config/starship.toml \
         usr/lib/systemd/system/devterm-tailscale-operator.service \
         usr/bin/ly etc/ly/config.lua \
         usr/lib/systemd/system/ly-kmsconvt@.service \
         usr/lib/aarch64-linux-gnu/libasound.so.2; do
    [ -e "$ART/rootfs/$f" ] || [ -L "$ART/rootfs/$f" ] || die "rootfs is missing /$f"
done
grep -A2 '^Package: libasound2t64$' "$ART/rootfs/var/lib/dpkg/status" | \
    grep -q 'Status: install ok installed' || die "libasound2t64 is not installed"
log "rootfs ready: $(du -sh "$ART/rootfs" | cut -f1)"
