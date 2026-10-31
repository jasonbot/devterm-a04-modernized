#!/bin/sh
# mmdebstrap --customize-hook entry point.  Runs inside the arm64 builder
# container with the target rootfs as $1 and the repo mounted at /work.
set -eu

target="$1"
[ -d "$target" ] || { echo "bad target: $target" >&2; exit 1; }

# Device nodes exist in the mmdebstrap target, but make sure the chroot has
# the minimum it needs even if the host blocks device creation.
for spec in "null 1 3" "zero 1 5" "random 1 8" "urandom 1 9" "tty 5 0" "console 5 1"; do
    set -- $spec
    [ -e "$target/dev/$1" ] || mknod -m 666 "$target/dev/$1" c "$2" "$3" || true
done

cp -a /work/overlay/. "$target"/

mkdir -p "$target/opt/devterm-payload"
cp -a /work/artifacts/vendor/. "$target/opt/devterm-payload/"
cp -a /work/artifacts/fonts "$target/opt/devterm-payload/fonts"
cp -a /work/artifacts/consolefonts "$target/opt/devterm-payload/consolefonts"
cp -a /work/artifacts/carbonyl "$target/opt/devterm-payload/carbonyl"
cp -a /work/artifacts/ly "$target/opt/devterm-payload/ly"
cp /work/scripts/rootfs-install.sh "$target/tmp/rootfs-install.sh"
chmod 755 "$target/tmp/rootfs-install.sh"
if [ -s /work/artifacts/uboot/boot.scr ]; then
    cp /work/artifacts/uboot/boot.scr "$target/boot/boot.scr"
fi

chmod 755 "$target"/usr/local/bin/devterm-* "$target"/usr/local/sbin/devterm-*
chroot "$target" /bin/bash /tmp/rootfs-install.sh

rm -rf "$target/opt/devterm-payload" "$target/tmp/rootfs-install.sh"
