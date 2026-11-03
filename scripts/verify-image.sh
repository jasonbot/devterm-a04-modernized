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

tmp=$(mktemp -d "$BUILD/verify.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
part="$tmp/root.ext4"
log "extracting root partition for fsck"
dd if="$IMG" of="$part" bs=1M skip=2 status=none
fsck.ext4 -fn "$part"
[ "$(e2label "$part")" = devterm-root ] || die "wrong ext4 label"
for f in /boot/Image /boot/devterm-a04.dtb /boot/initrd.img \
         /boot/extlinux/extlinux.conf /etc/vconsole.conf \
         /opt/carbonyl/carbonyl /usr/bin/kmscon /etc/kmscon/kmscon.conf \
         /usr/bin/cha /usr/bin/mancha /usr/libexec/chawan/cgi-bin/ssl \
         /usr/share/doc/kmscon/A04-GUARD \
         /usr/local/bin/nmtui-go \
         /usr/bin/starship /etc/starship.toml /etc/profile.d/starship.sh \
         /etc/skel/.config/starship.toml /home/devterm/.config/starship.toml \
         /usr/bin/tailscale /usr/sbin/tailscaled /usr/bin/yazi /etc/tmux.conf \
         /usr/lib/firmware/brcm/brcmfmac43455-sdio.txt \
         /usr/lib/firmware/brcm/brcmfmac43455-sdio.clockwork,devterm-a04.txt \
         /usr/lib/firmware/brcm/brcmfmac43456-sdio.bin \
         /usr/lib/firmware/brcm/brcmfmac43456-sdio.clm_blob \
         /usr/lib/firmware/brcm/brcmfmac43456-sdio.txt \
         /usr/lib/firmware/brcm/brcmfmac43456-sdio.clockwork,devterm-a04.txt \
         /usr/local/bin/devterm-wifi /usr/local/bin/devterm-tailscale-status \
         /usr/local/bin/devterm-battery \
         /usr/lib/systemd/system/devterm-tailscale-operator.service \
         /usr/bin/ly /etc/ly/config.lua /etc/pam.d/ly \
         /usr/local/sbin/devterm-ly-console \
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
debugfs -R 'cat /etc/sudoers.d/010-devterm' "$part" 2>/dev/null | \
    grep -q 'NOPASSWD: ALL' || die "devterm does not have passwordless sudo"
debugfs -R 'cat /etc/kmscon/kmscon.conf' "$part" 2>/dev/null | \
    grep -q '^no-hwaccel$' || die "kmscon hwaccel is not disabled"
debugfs -R 'cat /etc/kmscon/kmscon.conf' "$part" 2>/dev/null | \
    grep -q '^font-size=16$' || die "kmscon default font size is not 16"
debugfs -R 'cat /etc/vconsole.conf' "$part" 2>/dev/null | \
    grep -q '^FONT=PaperMonoNerdFont-8x16$' || die "default console font is not 8x16"
debugfs -R 'cat /etc/tmux.conf' "$part" 2>/dev/null | \
    grep -q 'MouseDown1Status' || die "tmux Wi-Fi status bind is missing"
debugfs -R 'cat /etc/tmux.conf' "$part" 2>/dev/null | \
    grep -q 'devterm-battery' || die "tmux battery status is missing"

# The image is arm64; if qemu-user is available, run the two binaries that
# matter on the A04's ARMv8.0 CPU.  A native/container build of Ly emits
# ARMv8.1 instructions and dies with SIGILL on a Cortex-A53.
if command -v qemu-aarch64-static >/dev/null 2>&1 && [ -d "$ART/rootfs" ]; then
    log "arm64 smoke test on cortex-a53"
    debugfs -R "dump /usr/bin/ly $tmp/ly" "$part" >/dev/null 2>&1
    debugfs -R "dump /usr/bin/kmscon $tmp/kmscon" "$part" >/dev/null 2>&1
    chmod 755 "$tmp/ly" "$tmp/kmscon"
    if ! ly_out=$(qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
            "$tmp/ly" --version 2>&1); then
        printf '%s\n' "$ly_out" >&2
        die "Ly does not run on Cortex-A53 (illegal instruction?)"
    fi
    qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
        "$tmp/kmscon" --version --verbose 2>&1 | \
        grep -q 'DRM 2D support: enabled' || \
        die "kmscon was built without DRM 2D support"

    debugfs -R "dump /usr/bin/cha $tmp/cha" "$part" >/dev/null 2>&1
    debugfs -R "dump /usr/bin/yazi $tmp/yazi" "$part" >/dev/null 2>&1
    chmod 755 "$tmp/cha" "$tmp/yazi"
    qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
        "$tmp/cha" --version >/dev/null 2>&1 || \
        die "Chawan does not run on Cortex-A53"
    qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
        "$tmp/yazi" --version >/dev/null 2>&1 || \
        die "Yazi does not run on Cortex-A53"

    debugfs -R "dump /usr/local/bin/nmtui-go $tmp/nmtui-go" "$part" >/dev/null 2>&1
    debugfs -R "dump /usr/bin/starship $tmp/starship" "$part" >/dev/null 2>&1
    chmod 755 "$tmp/nmtui-go" "$tmp/starship"
    qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
        "$tmp/nmtui-go" --version >/dev/null 2>&1 || \
        die "nmtui-go does not run on Cortex-A53"
    qemu-aarch64-static -cpu cortex-a53 -L "$ART/rootfs" \
        "$tmp/starship" --version >/dev/null 2>&1 || \
        die "starship does not run on Cortex-A53"

    # The status-bar helper must parse under the image's shell and emit the
    # Nerd Font battery glyph for a fake AXP221 fuel gauge.
    debugfs -R "dump /usr/local/bin/devterm-battery $tmp/devterm-battery" "$part" >/dev/null 2>&1
    debugfs -R "dump /bin/dash $tmp/dash" "$part" >/dev/null 2>&1
    chmod 755 "$tmp/dash"
    mkdir -p "$tmp/ps/axp20x-battery"
    printf 'Battery\n' > "$tmp/ps/axp20x-battery/type"
    printf '57\n' > "$tmp/ps/axp20x-battery/capacity"
    printf 'Charging\n' > "$tmp/ps/axp20x-battery/status"
    batt_out=$(POWER_SUPPLY_DIR="$tmp/ps" qemu-aarch64-static -cpu cortex-a53 \
        -L "$ART/rootfs" "$tmp/dash" "$tmp/devterm-battery") || \
        die "devterm-battery does not run on Cortex-A53"
    printf '%s' "$batt_out" | grep -qF "$(printf '\357\211\202') 57%" || \
        die "devterm-battery does not report the half-full glyph and 57%"
    printf '%s' "$batt_out" | grep -qF "$(printf '\357\203\247')" || \
        die "devterm-battery does not report the charging bolt"
    log "Ly runs on Cortex-A53; kmscon DRM 2D, Chawan, Yazi, nmtui-go, starship and devterm-battery: ok"
else
    warn "qemu-aarch64-static or artifacts/rootfs missing; skipping arm64 smoke test"
fi
status=$(debugfs -R 'cat /var/lib/dpkg/status' "$part" 2>/dev/null)
printf '%s\n' "$status" | grep -A2 '^Package: libasound2t64$' | \
    grep -q 'Status: install ok installed' || die "libasound2t64 is not installed"
printf '%s\n' "$status" | grep -A1 '^Package: devterm-kernel-current-cpi-a04$' | \
    grep -q 'Status: hold ok installed' || die "vendor kernel is not held"
printf '%s\n' "$status" | grep -A1 '^Package: devterm-audio-patch$' | \
    grep -q 'Status: hold ok installed' || die "vendor audio package is not held"
printf '%s\n' "$status" | grep -A1 '^Package: tailscale$' | \
    grep -q 'Status: install ok installed' || die "tailscale is not installed"
printf '%s\n' "$status" | grep -A1 '^Package: yazi$' | \
    grep -q 'Status: install ok installed' || die "yazi is not installed"
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
