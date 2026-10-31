#!/bin/bash
# Runs inside the target arm64 rootfs.  Installs the vendor A04 bits,
# configures console-first boot, fonts, Wi-Fi and the optional kiosk browser.
set -eu
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PAYLOAD=/opt/devterm-payload
KVER=5.10.75-sunxi64

[ -d "$PAYLOAD" ] || { echo "missing $PAYLOAD" >&2; exit 1; }

log() { echo "  [rootfs] $*"; }

# Carbonyl needs ALSA even though this is a console-only image.  It is in the
# initial mmdebstrap package set; fail early if that ever regresses.
dpkg-query -W -f='${Status}\n' libasound2t64 2>/dev/null | \
    grep -q 'install ok installed' || {
        echo "libasound2t64 is not installed" >&2
        exit 1
    }

# Keep package maintainer scripts from trying to start services in the chroot.
cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 /usr/sbin/policy-rc.d

log "base identity"
echo devterm-a04 >/etc/hostname
cat >/etc/hosts <<'EOF'
127.0.0.1       localhost
127.0.1.1       devterm-a04
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo UTC >/etc/timezone

log "locale"
sed -i 's/^# *\(en_US.UTF-8[[:space:]]\+UTF-8\)/\1/' /etc/locale.gen || true
locale-gen >/dev/null 2>&1 || true
cat >/etc/default/locale <<'EOF'
LANG=en_US.UTF-8
EOF

log "users"
for g in audio video gpio spi i2c plugdev netdev dialout; do
    getent group "$g" >/dev/null 2>&1 || groupadd "$g"
done
if ! id devterm >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,gpio,spi,i2c,plugdev,netdev,dialout devterm
fi
echo 'devterm:devterm' | chpasswd
echo 'root:devterm' | chpasswd
echo 'devterm ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/010-devterm
chmod 440 /etc/sudoers.d/010-devterm
chown -R devterm:devterm /home/devterm

log "kmscon console"
# kmscon is the userspace DRM console requested for this image.  It lives in
# trixie-backports; the PSF/fbcon path below remains as a safe fallback.
cat >/etc/apt/sources.list.d/backports.list <<'EOF'
deb http://deb.debian.org/debian trixie-backports main
EOF
apt-get update -qq
apt-get -y -o APT::Install-Recommends=false -t trixie-backports install kmscon
cat >/etc/kmscon/kmscon.conf <<'EOF'
# Paper Mono Nerd Font is installed system-wide by this image.
font-engine=freetype
font-name=PaperMono Nerd Font
font-size=10
rotate=right
xkb-model=pc105
xkb-layout=us
term=xterm-256color
EOF

log "filesystem layout"
cat >/etc/fstab <<'EOF'
LABEL=devterm-root  /       ext4    defaults,noatime  0 1
tmpfs               /tmp    tmpfs   defaults,nosuid,nodev,size=512M  0 0
EOF
mkdir -p /boot/extlinux

log "console font and keyboard"
mkdir -p /usr/share/consolefonts /usr/share/kbd/consolefonts
for f in "$PAYLOAD"/consolefonts/*.psf.gz; do
    base=$(basename "$f" .psf.gz)
    cp "$f" /usr/share/consolefonts/
    cp "$f" /usr/share/kbd/consolefonts/
    gzip -dc "$f" >"/usr/share/consolefonts/${base}.psf"
    gzip -dc "$f" >"/usr/share/kbd/consolefonts/${base}.psf"
done
cat >/etc/vconsole.conf <<'EOF'
KEYMAP=us
FONT=PaperMonoNerdFont-9x18
FONT_MAP=
FONT_UNIMAP=
EOF
cat >/etc/default/console-setup <<'EOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="PaperMonoNerdFont"
FONTSIZE="9x18"
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
cat >/etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

log "font and display modules"
cat >/etc/initramfs-tools/modules <<'EOF'
# Load these before the root filesystem so the panel and backlight come up
# while initramfs is still printing to the console.
panel_simple
ocp8178_bl
pwm_sun4i
EOF
sed -i 's/^MODULES=.*/MODULES=most/' /etc/initramfs-tools/initramfs.conf
cat >/etc/modules-load.d/devterm.conf <<'EOF'
panel_simple
ocp8178_bl
pwm_sun4i
spidev
brcmfmac
EOF
cat >/etc/modprobe.d/devterm.conf <<'EOF'
# The A04 panel is matched by panel-simple ("clockwork,cpi3-lcd").
# Keep the backlight module loadable even if the panel probes late.
softdep panel_simple pre: pwm_sun4i
EOF

log "system tuning"
cat >/etc/sysctl.d/90-devterm.conf <<'EOF'
vm.swappiness=100
vm.vfs_cache_pressure=50
EOF
mkdir -p /etc/systemd/logind.conf.d /etc/systemd/journald.conf.d
cat >/etc/systemd/logind.conf.d/devterm.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
cat >/etc/systemd/journald.conf.d/devterm.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=200M
RuntimeMaxUse=64M
EOF
cat >/etc/default/zramswap <<'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

log "Wi-Fi / SSH"
# mmdebstrap copies the build host's resolver into the target.  That host may
# use systemd-resolved (127.0.0.53), which is not installed here.  Let
# NetworkManager create the real /etc/resolv.conf when a link comes up.
rm -f /etc/resolv.conf
mkdir -p /etc/NetworkManager/conf.d /etc/ssh/sshd_config.d
cat >/etc/NetworkManager/conf.d/devterm.conf <<'EOF'
[main]
dns=default

[device]
wifi.scan-rand-mac-address=no
EOF
cat >/etc/ssh/sshd_config.d/devterm.conf <<'EOF'
PasswordAuthentication yes
PermitRootLogin prohibit-password
EOF
# Do not ship the build-time host keys.  sshd-keygen.service creates unique
# keys on the first boot of each card.
rm -f /etc/ssh/ssh_host_*

log "install vendor packages"
# Audio/fan postinst scripts call systemctl start, which cannot work in a
# chroot.  Use a temporary stub and enable the units ourselves below.
mkdir -p /tmp/devterm-fakebin
printf '#!/bin/sh\nexit 0\n' >/tmp/devterm-fakebin/systemctl
chmod 755 /tmp/devterm-fakebin/systemctl

for deb in "$PAYLOAD"/devterm-audio-patch_*.deb "$PAYLOAD"/devterm-fan-daemon-cpi-a04_*.deb; do
    PATH="/tmp/devterm-fakebin:$PATH" dpkg -i "$deb"
done
dpkg -i "$PAYLOAD"/devterm-wiringpi-cpi-a04_*.deb
dpkg -i "$PAYLOAD"/devterm-gearbox-a04_*.deb
rm -rf /tmp/devterm-fakebin

# The printer package depends on CUPS, which we deliberately do not install.
# Extract the raw SPI printer daemon and its systemd units instead.
dpkg-deb -x "$PAYLOAD"/devterm-thermal-printer_*.deb /
chmod 755 /usr/local/bin/devterm_thermal_printer.elf /usr/local/bin/devterm_socat.sh

# The vendor kernel package's postinst is what creates /boot/Image and the
# initramfs.  Install it after initramfs-tools is in place.
dpkg -i "$PAYLOAD"/devterm-kernel-current-cpi-a04_*.deb
# Belt and braces: apt preferences in /etc/apt/preferences.d block Debian
# kernel images; apt-mark also keeps apt from proposing removal/upgrade of the
# vendor kernel and its audio dependency.
apt-mark hold devterm-kernel-current-cpi-a04 devterm-audio-patch >/dev/null

# Make stable, non-symlink boot files for U-Boot/extlinux.  U-Boot's ext4
# loader can follow symlinks, but plain files remove a class of boot failures.
rm -f /boot/Image /boot/devterm-a04.dtb /boot/initrd.img
cp "/boot/vmlinuz-${KVER}" /boot/Image
cp "/boot/dtb-${KVER}/allwinner/sun50i-h6-clockworkpi-a04.dtb" /boot/devterm-a04.dtb
[ -s "/boot/initrd.img-${KVER}" ] || update-initramfs -c -k "$KVER"
cp "/boot/initrd.img-${KVER}" /boot/initrd.img

cat >/boot/extlinux/extlinux.conf <<'EOF'
DEFAULT devterm
LABEL devterm
  LINUX /boot/Image
  FDT /boot/devterm-a04.dtb
  INITRD /boot/initrd.img
  APPEND root=LABEL=devterm-root rootfstype=ext4 rootwait rw console=ttyS0,115200 console=tty0 fbcon=rotate:1 loglevel=4
EOF

log "fonts"
mkdir -p /usr/local/share/fonts/nerd-fonts
cp -a "$PAYLOAD"/fonts/. /usr/local/share/fonts/nerd-fonts/
chmod -R a+rX /usr/local/share/fonts
fc-cache -f >/tmp/fontconfig.log 2>&1 || true

log "kiosk browser"
rm -rf /opt/carbonyl
mkdir -p /opt/carbonyl
cp -a "$PAYLOAD"/carbonyl/. /opt/carbonyl/
chmod 755 /opt/carbonyl/carbonyl
ln -sf /opt/carbonyl/carbonyl /usr/local/bin/carbonyl

log "Ly display manager"
install -m 755 "$PAYLOAD/ly/ly" /usr/bin/ly
chmod 755 /etc/ly/startup.sh /etc/ly/setup.sh
# Ly's own PAM service and config were copied from overlay/.
if [ ! -f /etc/ly/config.lua ]; then
    echo "Ly config missing" >&2
    exit 1
fi

log "wiringPi runtime symlinks"
ln -sf libwiringPi.so.2.50 /usr/lib/libwiringPi.so
ln -sf libwiringPiDev.so.2.50 /usr/lib/libwiringPiDev.so
ldconfig

log "services"
enable_unit() {
    unit="$1"
    if [ -e "/etc/systemd/system/$unit" ] || [ -e "/lib/systemd/system/$unit" ]; then
        systemctl --no-reload enable "$unit" >/dev/null 2>&1 || true
    fi
}
enable_unit NetworkManager.service
enable_unit ssh.service
enable_unit serial-getty@ttyS0.service
enable_unit zramswap.service
enable_unit fstrim.timer
enable_unit rfkill-unblock.service
enable_unit devterm-socat.service
enable_unit devterm-printer.service
enable_unit devterm-fan-temp-daemon-a04.service
enable_unit devterm-audio-patch.service
enable_unit devterm-growroot.service
# Hand tty1 and the autovt alias to Ly running inside kmscon.  Ly's
# ly-kmsconvt@.service has OnFailure=ly@tty1.service, so a kmscon/DRM failure
# falls back to Ly on the kernel VT.
systemctl disable autovt@.service >/dev/null 2>&1 || true
systemctl disable getty@tty1.service >/dev/null 2>&1 || true
systemctl disable kmsconvt@.service >/dev/null 2>&1 || true
systemctl disable kmsconvt@tty1.service >/dev/null 2>&1 || true
enable_unit ly-kmsconvt@.service
enable_unit ly-kmsconvt@tty1.service
systemctl set-default multi-user.target >/dev/null 2>&1 || true
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

log "cleanup"
# File capabilities are lost when the tar is extracted as an unprivileged
# user.  A setuid-root ping is the portable fallback on this kernel.
[ -e /usr/bin/ping ] && chmod u+s /usr/bin/ping || true
rm -f /usr/sbin/policy-rc.d
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/fontconfig.log
sync

cat >/etc/devterm-release <<EOF
DevTerm A04 Debian 13 image
Kernel: ${KVER} (ClockworkPi vendor kernel)
Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
log "done"
