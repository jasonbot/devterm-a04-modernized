#!/usr/bin/env bash
# Verify the partition table, U-Boot location, ext4 filesystem and boot files.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

IMG="$ART/devterm-a04.img"
[ -s "$IMG" ] || die "image not found: $IMG"

log "partition table"
sfdisk -d "$IMG"

magic=$(dd if="$IMG" bs=1 skip=8192 count=8 status=none | od -An -tx1 | tr -d ' \n')
[ "$magic" = "160000ea65474f4e" ] || die "no U-Boot SPL eGON header at 8 KiB"
log "U-Boot SPL header at 8 KiB: ok"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
part="$tmp/root.ext4"
log "extracting root partition for fsck"
dd if="$IMG" of="$part" bs=1M skip=2 status=none
fsck.ext4 -fn "$part"
[ "$(e2label "$part")" = devterm-root ] || die "wrong ext4 label"
for f in /boot/Image /boot/devterm-a04.dtb /boot/initrd.img \
         /boot/extlinux/extlinux.conf /etc/vconsole.conf \
         /opt/carbonyl/carbonyl /usr/bin/kmscon /etc/kmscon/kmscon.conf \
         /usr/bin/ly /etc/ly/config.lua /etc/pam.d/ly \
         /usr/lib/systemd/system/ly-kmsconvt@.service \
         /etc/apt/preferences.d/00-devterm-kernel.pref \
         /usr/local/share/fonts/nerd-fonts/PaperMonoNerdFont-Regular.otf; do
    debugfs -R "stat $f" "$part" >/dev/null 2>&1 || die "missing $f"
done
debugfs -R 'cat /boot/extlinux/extlinux.conf' "$part" 2>/dev/null | \
    grep -q 'root=LABEL=devterm-root' || die "extlinux.conf is wrong"
debugfs -R 'cat /etc/fstab' "$part" 2>/dev/null | \
    grep -q 'LABEL=devterm-root' || die "/etc/fstab is wrong"
debugfs -R 'cat /etc/apt/preferences.d/00-devterm-kernel.pref' "$part" 2>/dev/null | \
    grep -q 'Pin-Priority: -1' || die "kernel apt pin is missing"
debugfs -R 'cat /etc/kmscon/kmscon.conf' "$part" 2>/dev/null | \
    grep -q '^font-size=10$' || die "kmscon default font size is not 10"
status=$(debugfs -R 'cat /var/lib/dpkg/status' "$part" 2>/dev/null)
printf '%s\n' "$status" | grep -A2 '^Package: libasound2t64$' | \
    grep -q 'Status: install ok installed' || die "libasound2t64 is not installed"
printf '%s\n' "$status" | grep -A1 '^Package: devterm-kernel-current-cpi-a04$' | \
    grep -q 'Status: hold ok installed' || die "vendor kernel is not held"
printf '%s\n' "$status" | grep -A1 '^Package: devterm-audio-patch$' | \
    grep -q 'Status: hold ok installed' || die "vendor audio package is not held"
multi_user=$(debugfs -R 'ls -l /etc/systemd/system/multi-user.target.wants' "$part" 2>/dev/null)
printf '%s\n' "$multi_user" | grep -q 'ly-kmsconvt@tty1.service' || \
    die "Ly kmscon tty1 is not enabled"
printf '%s\n' "$multi_user" | grep -qE '(^|[[:space:]])kmsconvt@tty1\.service' && \
    die "plain kmscon tty1 is still enabled"
debugfs -R 'stat /etc/systemd/system/autovt@.service' "$part" 2>/dev/null | \
    grep -q 'ly-kmsconvt@.service' || die "autovt does not point at Ly"
log "boot files, Ly+kmscon, apt pin/hold, libasound2t64: ok"

if [ -s "$IMG.zst" ]; then
    zstd -t "$IMG.zst"
    log "zstd image: ok"
fi
log "verification passed"
