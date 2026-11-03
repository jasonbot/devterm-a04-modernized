#!/usr/bin/env bash
# Assemble a flashable MBR image: U-Boot at 8 KiB, one ext4 root partition
# starting at 2 MiB, with the kernel/initrd/dtb inside /boot.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ensure_dirs
need podman
need fakeroot
need mke2fs
need fsck.ext4
need debugfs
need sfdisk
need zstd

[ -d "$ART/rootfs" ] || die "run scripts/build-rootfs.sh first"
[ -s "$ART/uboot/u-boot-sunxi-with-spl.bin" ] || die "run scripts/build-uboot.sh first"

IMG_BYTES=$((4 * 1024 * 1024 * 1024))
PART_START=4096
PART_SECTORS=$(( IMG_BYTES / 512 - PART_START ))
FS_BYTES=$(( PART_SECTORS * 512 ))
IMG="$ART/devterm-a04.img"
EXT4="$ART/rootfs.ext4"

rootfs_bytes=$(du -sb "$ART/rootfs" | cut -f1)
if [ "$rootfs_bytes" -ge $((FS_BYTES - 512 * 1024 * 1024)) ]; then
    die "rootfs ($rootfs_bytes bytes) is too large for the 4 GiB image"
fi

dev_uid=$(awk -F: '$1 == "devterm" {print $3}' "$ART/rootfs/etc/passwd")
dev_gid=$(awk -F: '$1 == "devterm" {print $4}' "$ART/rootfs/etc/passwd")
gid_of() { awk -F: -v g="$1" '$1 == g {print $3}' "$ART/rootfs/etc/group"; }
shadow_gid=$(gid_of shadow)
messagebus_gid=$(gid_of messagebus)
utmp_gid=$(gid_of utmp)
mail_gid=$(gid_of mail)
for v in "$dev_uid" "$dev_gid" "$shadow_gid" "$messagebus_gid" "$utmp_gid" "$mail_gid"; do
    [ -n "$v" ] || die "cannot resolve a required uid/gid in rootfs"
done

log "creating ext4 filesystem ($(numfmt --to=iec "$FS_BYTES"))"
rm -f "$EXT4"
truncate -s "$FS_BYTES" "$EXT4"
fakeroot -- bash -c '
set -eu
chown -R 0:0 "$1"
chown -R "$3:$4" "$1/home/devterm"
# Restore the small set of non-root groups that matter at runtime.
for f in etc/shadow etc/gshadow usr/bin/chage usr/bin/expiry usr/sbin/unix_chkpwd; do
    [ -e "$1/$f" ] && chown "0:$5" "$1/$f"
done
[ -e "$1/usr/lib/dbus-1.0/dbus-daemon-launch-helper" ] && \
    chown "0:$6" "$1/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
[ -e "$1/var/mail" ] && chown "0:$8" "$1/var/mail"
for f in var/log/btmp var/log/wtmp var/log/lastlog; do
    [ -e "$1/$f" ] && chown "0:$7" "$1/$f"
done
if [ -e "$1/var/mail/devterm" ]; then chown "$3:$4" "$1/var/mail/devterm"; fi
chmod 755 "$1" "$1/etc" "$1/usr" "$1/usr/local" \
    "$1/usr/local/bin" "$1/usr/local/etc" \
    "$1/etc/systemd" "$1/etc/systemd/system"
mke2fs -q -F -t ext4 -L devterm-root -m 1 -b 4096 \
    -O ^orphan_file \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$1" "$2"
' sh "$ART/rootfs" "$EXT4" "$dev_uid" "$dev_gid" \
    "$shadow_gid" "$messagebus_gid" "$utmp_gid" "$mail_gid"

log "checking ext4"
fsck.ext4 -fn "$EXT4" >/tmp/devterm-fsck.log 2>&1 || {
    cat /tmp/devterm-fsck.log >&2
    die "ext4 filesystem failed fsck"
}
e2label "$EXT4" | grep -qx devterm-root || die "root filesystem label is wrong"
image_size=$(debugfs -R 'stat /boot/Image' "$EXT4" 2>/dev/null | \
    sed -n 's/.*Size: \([0-9][0-9]*\).*/\1/p' | head -1)
[ "${image_size:-0}" -gt 1000000 ] || die "/boot/Image is missing or too small"
debugfs -R 'cat /boot/extlinux/extlinux.conf' "$EXT4" 2>/dev/null | grep -q 'root=LABEL=devterm-root' || \
    die "extlinux.conf is wrong"

log "writing MBR and partition table"
rm -f "$IMG"
truncate -s "$IMG_BYTES" "$IMG"
sfdisk --force --label dos "$IMG" >/dev/null <<EOF
label: dos
unit: sectors

start=$PART_START, size=$PART_SECTORS, type=83, bootable
EOF

log "copying ext4 root filesystem into image"
dd if="$EXT4" of="$IMG" bs=1M seek=2 conv=notrunc,sparse status=none
rm -f "$EXT4"

log "writing U-Boot at 8 KiB"
dd if="$ART/uboot/u-boot-sunxi-with-spl.bin" of="$IMG" bs=1024 seek=8 conv=notrunc status=none
sync

# Verify the SPL eGON header is exactly where the H6 BootROM looks for it.
magic=$(dd if="$IMG" bs=1 skip=8192 count=8 status=none | od -An -tx1 | tr -d ' \n')
[ "$magic" = "160000ea65474f4e" ] || die "U-Boot SPL header not found at 8 KiB (got $magic)"

log "image: $(ls -lh "$IMG" | awk '{print $5}') apparent, $(du -h "$IMG" | cut -f1) on disk"
sfdisk -d "$IMG" >"$ART/devterm-a04.img.partition-table.txt"

log "compressing (zstd)"
rm -f "$IMG.zst"
zstd -q -T0 -6 -f "$IMG" -o "$IMG.zst"
sha256sum "$IMG" "$IMG.zst" >"$ART/SHA256SUMS"
log "compressed image: $(ls -lh "$IMG.zst" | awk '{print $5}')"
cat "$ART/SHA256SUMS"
