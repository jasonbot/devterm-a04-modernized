# Using the DevTerm A04 image

## Live image: flash once, boot, grow

This is a live image, not an installer.  Write it to the TF/microSD card once,
insert it, and boot.  There is no install wizard.  On first boot,
`devterm-growroot.service` grows the root partition and ext4 filesystem to the
full card size.  Use a card larger than 4 GiB; 8 GB or more is recommended.

## Flash and first boot

Write `artifacts/devterm-a04.img.zst` to an SD card:

```sh
zstd -dc artifacts/devterm-a04.img.zst |
  sudo dd of=/dev/sdX bs=4M iflag=fullblock oflag=direct status=progress conv=fsync
```

Use the correct device.  Alternatively decompress to `.img` and use Etcher.
Insert the card, connect power, and turn the DevTerm on.  The first boot takes
longer than later boots; `devterm-growroot.service` expands the root partition
to fill the card, and systemd generates SSH host keys and machine IDs.

Text appears on the built-in 480x1280 panel, rotated to 1280x480 by
`fbcon=rotate:1`.  U-Boot itself does not drive the panel; if the screen stays
blank for more than a minute, use the serial console (UART0, 115200 8N1) and
see Troubleshooting.

## Login and accounts

The boot screen is **Ly**.  Pick the `devterm` user, enter the password, and
choose the **Shell** session.  Ly then starts a normal Linux shell on tty1.

```text
devterm / devterm
root    / devterm
```

Change both:

```sh
passwd
sudo passwd root
```

`devterm` is in `sudo`, `audio`, `video`, `gpio`, `spi`, `i2c`, `plugdev`,
`netdev` and `dialout`.  Sudo is passwordless for `devterm` on this image;
remove `/etc/sudoers.d/010-devterm` or change it if that is not acceptable.

The default `devterm` user has a normal home directory at `/home/devterm`.

## Wi-Fi

NetworkManager is enabled.  The interactive UI works on the console:

```sh
sudo nmtui-go            # nmtui-go UI (nmtui stays installed as a fallback)
```

or:

```sh
devterm-wifi                 # same as sudo nmtui-go
devterm-wifi "My SSID" "password"
```

List and inspect:

```sh
nmcli device status
nmcli device wifi list
nmcli connection show
ip addr
```

The A04 uses a Broadcom BCM4345C5 over SDIO (`brcmfmac`).  If a network is
advertised as WPA3-only, try WPA2/WPA3 mixed or WPA2-personal; the vendor
firmware/driver combination is old.  The image ships `firmware-brcm80211` and
`wireless-regdb`; set the regulatory domain if needed:

```sh
sudo iw reg set US
```

## Console and font: kmscon + Paper Mono Nerd Font

`tty1` is served by **Ly**, normally on top of **kmscon**.  kmscon renders the
OpenType **Paper Mono Nerd Font** at 16 px (8x16 cells), rotated to the panel's landscape
orientation (`rotate=right`).

kmscon uses its software **drm2d** backend.  The vendor 5.10 sun4i-drm driver
implements DRM dumb buffers (`drm_sun4i_gem_dumb_create`), which is what drm2d
needs; the H6 has no usable 3D driver in this kernel, so `hwaccel=off` and
`drm=on` are set in `/etc/kmscon/kmscon.conf` and the wrapper also passes
`--no-hwaccel`.

kmscon carries an 8px black guard band split between the top and bottom of
the rotated screen to hide the A04 panel's first-line wrap.  It drops one
text row to make room, so at 8x16 the terminal has 29 rows and every row is
fully visible.  `devterm-ly-console` falls
back to **Ly on the kernel fbcon** (with the PSF2
font) only when kmscon fails to initialise: a non-zero exit within 10 seconds.
A normal logout exits kmscon cleanly, systemd restarts it, and the next login
screen is kmscon again.  If kmscon cannot use DRM, the fallback still gives a
working login on the kernel VT.

List and switch both the kmscon size and the fbcon fallback:

```sh
devterm-font
devterm-font PaperMonoNerdFont-8x16
devterm-font PaperMonoNerdFont-10x20
devterm-font PaperMonoNerdFont-16x32
```

The choice is written to `/etc/vconsole.conf`, `/etc/default/console-setup`
and `/etc/kmscon/kmscon.conf`, so it survives a reboot.  The kmscon/Ly size
takes effect after Ly restarts kmscon (log out and back in, or reboot); the
wrapper does not kill your current session.  To apply the fbcon fallback
immediately:

```sh
sudo setfont /usr/share/consolefonts/PaperMonoNerdFont-8x16.psf.gz
sudo systemctl restart systemd-vconsole-setup
```

The fbcon fallback uses a PSF2 bitmap, not the OpenType file.  Nerd Font
private-use icons are included in the bitmap, so tools such as `eza`,
`starship`, `powerline` and `tmux` can use icons on the text console if their
terminal output supports them.  kmscon uses the actual NerdFont OTF.

### All NerdFonts system-wide

All 263 `*NerdFont*` files from `~/Sync/Fonts` are installed under:

```text
/usr/local/share/fonts/nerd-fonts/
```

Fontconfig indexes them at boot.  Check:

```sh
fc-list | grep -i 'PaperMono Nerd Font'
fc-match 'PaperMono Nerd Font'
```

Applications that use fontconfig can select any installed family.  The
console itself can only use the generated PSF2 sizes above.

## Terminal browsers without X or Wayland

Browsers that render into the text console, no window server needed.

```sh
devterm-kiosk https://example.com   # Carboxyl (Servo) when installed
carboxyl https://example.com        # Carboxyl directly
cha https://example.com             # Chawan (Nim), smallest and fastest
```

- **Carboxyl** is the Servo-based successor to Carbonyl.  `carboxyl` sets
  `LIBGL_ALWAYS_SOFTWARE=1` because the A04's Mesa driver otherwise reports
  OpenGL 2.1 and Servo needs 3.2; rendering then goes through llvmpipe.  It
  uses about 180 MB of RAM and roughly a fifth of one core on a static page
  at `-f 10`.  `-f <fps>`, `--scale <percent>`,
  `--graphics auto|kitty|sixel|quadrant` and `--no-native-text` control the
  output; the console uses quadrant blocks.
- **Carbonyl** is the older Chromium-based browser, kept as the fallback and
  what `devterm-kiosk` used before Carboxyl was installed.  Profile:
  `~/.cache/carbonyl`.
- **Chawan** is a small, self-contained Nim engine with CSS, forms and an
  optional JavaScript mode.  It is the lightest of the three.  `mancha` reads
  man pages through it.

The A04 has 2 GB of RAM.  Close other programs before using a full browser;
the image enables a 1 GB zram swap device.

Useful checks:

```sh
carboxyl --version
cha -h
TERM=xterm-256color LIBGL_ALWAYS_SOFTWARE=1 /opt/carboxyl/carboxyl --help
```

## Live-coding music: rustel

`rustel` is the native Strudel engine: patterns, synths and samples without a
browser.  It is installed from the upstream arm64 release at `/opt/rustel`
with `/usr/local/bin/rustel` on `PATH`.

```sh
rustel studio                     # terminal editor, Ctrl+Enter updates
rustel song.strudel --watch       # play, reload on every save
rustel render song.strudel -o take.wav --duration 60
rustel check song.strudel         # parse without sound
rustel devices                    # ALSA and MIDI devices
rustel doctor                     # DSP paths and buffer settings
```

Audio goes through ALSA to the AC200 codec; `rustel devices` lists the
`alsa:default` output.  Studio is tuned for a graphical terminal — on the
60-column kmscon console it runs, but the piano roll, mixer and theme chrome
are cramped and colours are limited; the command-line modes (`--watch`,
`render`, `check`) are the comfortable fit there.  Csound instruments need
`--allow-csound` and a 6.x Csound installation (not shipped).

## Fullscreen DRM programs

Software that talks to KMS/DRM directly (SDL's `kmsdrm` driver, ebitengine with
a KMS backend) needs two things: read/write access to `/dev/dri/card0` and the
**DRM master** role.  Access is a group matter — `devterm` is in `video` (card
nodes) and `input` (`/dev/input/event*`).  Master is not a permission: it is an
exclusive per-card role, and kmscon holds it while the login screen is up, so a
second `drmSetMaster()` fails with `EPERM` no matter what groups you are in.

`devterm-kms` performs the hand-off:

```sh
devterm-kms ./my-game --fullscreen
```

It stops `ly-kmsconvt@tty1`, waits for kmscon to exit, runs the command as you
on tty1 (systemd gives it the VT as its controlling terminal) and restarts the
login screen when the program exits.  The program itself keeps your uid; sudo
is used only for the hand-off.  The console session, including the tmux
`login` session, ends while the program runs.

Check the pieces with:

```sh
id                                                   # video, input
ls -l /dev/dri/card0 /dev/input/event0
sudo devterm-kms --help   # prints its usage and exits
```

## Ly login screen

Ly is built from source with the kmscon lock-LED error suppressed (kmscon's
PTY does not implement `KDGKBLED`).  The default theme uses a green Matrix
rain, a large clock and a dark box titled "DevTerm A04"; edit
`/etc/ly/config.lua` and restart `ly-kmsconvt@tty1` to change it.

## Shell prompt: Starship

Starship is the default interactive Bash prompt.  The configuration is
installed at `/etc/starship.toml`; `/etc/skel/.config/starship.toml`, the
`devterm` user and root use it.  The prompt uses Nerd Font/Powerline glyphs;
Paper Mono Nerd Font is the default console font and kmscon's freetype
backend also falls back to Debian's other fonts for the few non-Nerd symbols
in the config.

Run `starship --version`, or edit `~/.config/starship.toml` for a per-user
config.

## Printing

`devterm-print` renders to the 58 mm printer as 384-dot bitmaps: QR codes,
markdown and a usable subset of ZPL.

```sh
devterm-print --qr="https://example.com"
devterm-print --qr-b4=01320132...        # four base-4 digits per byte
devterm-print notes.md                   # flags must precede file names
devterm-print --font="0xProto Nerd Font" --size=24 notes.md
devterm-print --zpl=label.zpl
devterm-print --test                     # alignment and legibility page
devterm-print --qr=hello --png=/tmp/q.png --out=/tmp/q.escpos   # preview only
```

Markdown covers headings, paragraphs with bold/italic/inline code, links,
ordered and unordered lists, block quotes, fenced code, tables and rules.
`--font` takes a family name from the installed fonts or a font file;
families with `Propo`/`Mono` siblings use the mono face for code, and
`--duospace` forces a single ASCII advance inside a proportional font so
columns line up.  `--size` is in dots.

`--zpl` handles `^XA/^XZ`, `^PW`, `^FO/^FT`, `^A0N`, `^FD/^FS`, `^GB`,
`^BY`/`^BC` (Code 128), `^BQ` (QR), `^PQ` and `^FR`; unknown commands are
ignored.

Images (PNG, JPEG, GIF, BMP, TIFF) are scaled to the 384-dot width and
dithered to one bit:

```sh
devterm-print photo.jpg                  # landscape gets turned sideways
devterm-print --image=scan.png --rotate=180 --dither=atkinson
```

`--rotate=auto` (the default) turns landscape pictures 90° so they use the
length of the receipt rather than printing a short letterbox; `0/90/180/270`
override it.  `--dither=floyd` (default), `atkinson` or `none` picks the
halftoning.  HEIC needs converting first (`heif-convert photo.heic photo.jpg`).

## Yazi file manager

`yazi` is installed from the official Yazi apt repository:

```sh
yazi            # current directory
yazi /path      # another directory
```

The default theme is
[Gruvbox Material](https://github.com/matt-dong-123/gruvbox-material.yazi),
vendored under `/etc/skel/.config/yazi` and seeded into the `devterm` and
`root` accounts.  Yazi only applies a flavour after its terminal replies to
the DA1 probe; kmscon (libtsm) and normal SSH terminals do.  Pick another
flavour by editing `~/.config/yazi/theme.toml`.

Yazi uses the terminal's own fonts and images where the terminal supports
them; kmscon renders text previews.  For richer previews install the optional
tools, for example:

```sh
sudo apt install ffmpeg 7zip poppler-utils fd-find ripgrep fzf zoxide
```

The image is small and the A04 has 2 GB RAM, so add only what you use.

## tmux

The image ships `/etc/tmux.conf`:

- prefix is `Ctrl-a` (like screen), mouse is enabled
- `|` and `-` split the window vertically and horizontally
- the status bar is bright white; the right side shows the Wi-Fi network with
  a Nerd Font signal-strength icon (one to four bars) and its link quality,
  the Tailscale IPv4 address (or login/off), the battery charge with a Nerd
  Font battery icon (plus a bolt while charging), and the time.  The console
  is 60 columns wide, so tmux drops the left end of the right side when it
  does not fit: long SSIDs are cut before the icons, the battery and the time
- clicking the status bar opens `nmtui-go` in a tmux popup via
  `sudo devterm-wifi`, except on a window name: that click selects the window
- local console logins attach to the persistent tmux session `login`
  (detaching and logging in again reattaches it); SSH logins stay plain
  shells, join the session with `tmux new -A -s login`
- `devterm-wifi status` and `devterm-tailscale-status` print the same
  one-line summaries for scripts; `devterm-battery` prints the battery
  segment

Useful checks:

```sh
tmux -V
tmux show-options -g prefix
/usr/local/bin/devterm-wifi status
/usr/local/bin/devterm-battery
cat /sys/class/power_supply/axp20x-battery/capacity
```

## Power button and suspend

A short power-button press suspends the machine through systemd-logind; a long
press powers off.  The kernel command line selects `s2idle` and the suspend
targets are not masked.  If suspend/resume is unreliable on your A04 revision,
use the long press or `sudo poweroff`; deep suspend would require the Crust
SCP firmware, which this image does not ship.

The panel is blanked before suspending and restored about three seconds after
resume, so the last frame does not look like a live UI while the session is
still thawing.  Both the screen restore and the Wi-Fi recovery below run from
transient units: systemd-sleep holds `user.slice` frozen until its post hooks
return, so anything slow done inline would make the restored screen
unresponsive for that much longer.

Wi-Fi needs a nudge on resume: the SDIO card is re-probed as a new phy and
NetworkManager can stay stuck in state `asleep`, where nothing reactivates it
(`nmcli networking on` does not clear that state).  The system-sleep hook
`/usr/lib/systemd/system-sleep/devterm-wifi-resume` waits a few seconds and
restarts NetworkManager when that happens, so the link returns about ten
seconds after waking.  Check it with:

```sh
journalctl -t devterm-wifi -b --no-pager
```

On battery, `devterm-idle-suspend.timer` suspends after 15 minutes without
keyboard or mouse activity on the console tmux client.  It stays awake while a
remote (SSH) session exists, while charging, while the load is above 0.75, and
for a full idle period after boot or resume.  Change the interval with a
drop-in:

```sh
sudo systemctl edit devterm-idle-suspend.service
# [Service]
# Environment=DEVT_IDLE_TIMEOUT=1800
```

## Battery and power draw

`devterm-power [seconds]` samples the AXP221 fuel gauge and prints the pack
draw, for example:

```text
3.40 W draw (min 3.12, max 3.67) | pack 3.77V 0.90A 83% Discharging AC=0 | 30s
```

Run it on battery; while charging the current is the charge current, not the
system load.

The AXP221 has no coulomb counter.  `capacity` follows the open-circuit
voltage and is re-estimated after a resume, so a percentage jump across a sleep
is normal; `energy_now` is derived from the percentage rather than a learned
full-charge capacity, and `health` only reports the driver's coarse state
(`Good`/`Unknown`).  For a real health check, compare the internal resistance:
run `devterm-power 20` idle and again with the CPUs busy, then divide the
voltage drop by the current rise.  A healthy 18650 pair is in the tens of
milliohms; a few hundred means the pack is tired.

Idle draw is about 3.4 W, dominated by the SoC, Wi-Fi and DRAM rather than the
display (0/9 backlight is only ~0.2 W below 5/9).

Useful checks:

```sh
/usr/local/bin/devterm-power 30
cat /sys/class/power_supply/axp20x-battery/{capacity,health,voltage_now,current_now}
systemctl list-timers devterm-idle-suspend.timer
```

## Tailscale

The official Tailscale package for Debian trixie is installed and
`tailscaled.service` is enabled.  It is not logged in automatically; after the
first boot run:

```sh
sudo tailscale up
sudo tailscale status
```

Then reach the DevTerm by its Tailscale name or IP, for example:

```sh
ssh devterm@devterm-a04
```

`tailscale up --ssh` additionally enables Tailscale SSH.  The daemon needs
`/dev/net/tun`; the image loads the `tun` module at boot.  A oneshot unit sets
`devterm` as the Tailscale operator so the tmux status bar can query the
node without running `sudo` every five seconds.

## Thermal printer (58 mm)

The vendor printer daemon is installed without CUPS.  It talks to
`/dev/spidev0.0` through wiringPi and creates two PTYs via `socat`:

```text
/tmp/DEVTERM_PRINTER_IN    write text/ESC-POS here
/tmp/DEVTERM_PRINTER_OUT   daemon reads this side
```

Print the self-test:

```sh
devterm-thermal-test
```

Print text:

```sh
devterm-printer "Hello from the DevTerm"
echo "line one" | devterm-printer
devterm-printer -f receipt.bin       # raw bytes
```

The wrapper starts the services if needed.  Inspect them with:

```sh
systemctl status devterm-socat.service devterm-printer.service
ls -l /dev/spidev* /tmp/DEVTERM_PRINTER_*
tail -50 /tmp/devterm_printer.log
tail -50 /tmp/devterm_printer.err.log
```

The printer font is the vendor Noto Sans CJK TTC at
`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` (provided by
`fonts-noto-cjk`).  Paper is standard 58 mm thermal roll.

The vendor daemon uses raw SPI and GPIO, so there is no CUPS queue and no
`lp` command.  Use `devterm-printer` or write to the PTY directly.

## Audio, fan and gearbox

The A04 audio switch service toggles the speaker/headphone GPIO:

```sh
systemctl status devterm-audio-patch.service
alsamixer
aplay -l
speaker-test -c 2 -t sine -l 1
```

The fan daemon reads thermal zones and drives the fan GPIO:

```sh
systemctl status devterm-fan-temp-daemon-a04.service
cat /sys/class/thermal/thermal_zone0/temp
```

The gearbox helper is available as `devterm-a04-gearbox`; it is the vendor
CPU/GPU tuning script, not required for normal use.

## SSH and package management

SSH is enabled.  Find the address with `ip addr` and connect:

```sh
ssh devterm@192.168.1.50
```

`sshd` allows password authentication and root login only with a key
(`PermitRootLogin prohibit-password`).  Add your key and then consider
disabling passwords:

```sh
ssh-copy-id devterm@192.168.1.50
sudoedit /etc/ssh/sshd_config.d/devterm.conf
sudo systemctl restart ssh
```

Install normal Debian packages:

```sh
sudo apt update
sudo apt install htop tmux git
```

The image automatically protects the A04 kernel:

- `/etc/apt/preferences.d/00-devterm-kernel.pref` gives all Debian
  `linux-image-*`, `linux-headers-*`, `linux-modules-*` and `linux-dtb-*`
  packages priority `-1`, so `apt upgrade` / `apt full-upgrade` will not pull
  in a replacement kernel.
- `devterm-kernel-current-cpi-a04` and `devterm-audio-patch` are marked
  `apt-mark hold`, so apt will not upgrade or autoremove them either.

Normal `sudo apt update && sudo apt upgrade` is therefore safe.  Do **not**
force-install `linux-image-arm64` or `linux-image-current-sunxi64`: the A04
display/backlight/printer support lives in the vendor 5.10.75 kernel.  If
ClockworkPi publishes a newer A04 kernel package, install it deliberately:

```sh
sudo apt-mark unhold devterm-kernel-current-cpi-a04 devterm-audio-patch
# install the new vendor package, then:
sudo apt-mark hold devterm-kernel-current-cpi-a04 devterm-audio-patch
```

Then re-check `/boot/Image`, `/boot/initrd.img` and `/boot/extlinux`.

Inspect the pins:

```sh
apt-cache policy linux-image-arm64
apt-mark showhold
cat /etc/apt/preferences.d/00-devterm-kernel.pref
```

## First-boot and health checks

```sh
devterm-info
uname -a
dmesg | grep -iE 'panel|backlight|dsi|drm|fb0|brcmfmac|spi'
lsblk
systemctl --failed
```

Expected display devices include `/dev/fb0` and a DRM card.  Expected printer
device is `/dev/spidev0.0`.  Expected Wi-Fi interface is usually `wlan0`.

## Troubleshooting

### Blank panel, but the device seems alive

Use the serial console (UART0, 115200 8N1) to see U-Boot and kernel messages.
At the U-Boot prompt:

```text
mmc list
mmc dev 0
ls mmc 0:1 /boot
cat mmc 0:1 /boot/extlinux/extlinux.conf
sysboot mmc 0:1 any 0x4FC00000 /boot/extlinux/extlinux.conf
```

If the panel is dark but the kernel booted, check:

```sh
dmesg | grep -iE 'panel|cwd|cpi3|ocp8178|backlight|dsi|drm|fb0'
cat /sys/class/graphics/fb0/virtual_size
```

`fbcon=rotate:1` gives 1280x480.  If the image is rotated the wrong way, edit
`/boot/extlinux/extlinux.conf` on another Linux (partition 1 is plain ext4)
and change `rotate:1` to `rotate:3`, then reboot.  Keep a backup.

### U-Boot does not start at all

- Re-verify the checksum and reflash; a truncated write is the usual cause.
- Try a different SD card.  Some cards are unreliable with sunxi SPL.
- Check the SPL header at 8 KiB on the host:

  ```sh
  dd if=devterm-a04.img bs=1 skip=8192 count=8 | od -An -tx1
  # 16 00 00 ea 65 47 4f 4e
  ```

- The image is A04-only.  Do not use it on A06, CM4 or RISC-V DevTerms.

### Wi-Fi does not appear

```sh
rfkill list
sudo rfkill unblock all
ip link
dmesg | grep -iE 'brcmfmac|mmc1|firmware'
nmcli device status
```

If `brcmfmac` reports a firmware or NVRAM failure, the SDIO card is present
but the board-specific NVRAM may not match.  The generic Debian firmware is
installed; the vendor image may carry a board-specific NVRAM file.  This is a
known bring-up item for this image.

### Printer does not print

```sh
systemctl status devterm-socat.service devterm-printer.service
ls -l /dev/spidev0.0 /tmp/DEVTERM_PRINTER_*
dmesg | grep -i spi
journalctl -u devterm-printer -b
```

The printer needs `spidev` and the vendor wiringPi library.  If
`/dev/spidev0.0` is missing, the SPI1 controller or spidev node did not probe;
check the DTB and `dmesg`.  The wrapper starts the services but does not
recover from a wedged daemon; `sudo systemctl restart devterm-socat
devterm-printer` is safe.

### Console font is not applied

```sh
cat /etc/vconsole.conf
ls /usr/share/consolefonts/PaperMonoNerdFont-*
sudo setupcon --force
sudo systemctl restart systemd-vconsole-setup
```

The font must be a PSF2 file.  The PSF files are installed in both
`/usr/share/consolefonts` and `/usr/share/kbd/consolefonts`.

### kmscon does not start

kmscon's diagnostics are written to `/var/log/kmscon-ttyN.log` (they are kept
off the VT so a failed start cannot flash and erase a message).  Check the log
and the unit:

```sh
cat /var/log/kmscon-tty1.log
systemctl status ly-kmsconvt@tty1
journalctl -b -u 'ly-kmsconvt@*'
```

The wrapper retries kmscon three times, then leaves the VT to Ly on the kernel
fbcon, so a working login remains available even if the DRM path fails.

### Browser runs out of memory

The A04 has 2 GB RAM.  Close other programs, use one tab, and check swap:

```sh
free -h
zramctl
```

If Carbonyl is unusable, try `cha`; it uses much less memory.
A graphical browser would require X/Wayland, which this console-first image
deliberately does not install.

### Root filesystem did not grow

```sh
systemctl status devterm-growroot.service
lsblk
sudo growpart /dev/mmcblk0 1
sudo resize2fs /dev/mmcblk0p1
```

### Recovering from a bad edit

The first partition is a normal ext4 filesystem.  On another Linux:

```sh
sudo mount /dev/sdX1 /mnt
sudoedit /mnt/boot/extlinux/extlinux.conf
sudo umount /mnt
```

Add `systemd.unit=rescue.target` or `init=/bin/bash` to `APPEND` for a
single-user recovery boot.  The root password is `devterm` unless changed.

## Known limitations

- Vendor Linux 5.10.75, not a mainline kernel.  It is not covered by Debian
  kernel security updates.
- No X11/Wayland; the browser is terminal-rendered.  Image-heavy sites and
  video are not practical.
- Wi-Fi NVRAM/calibration is board-specific and remains the main hardware
  bring-up risk.
- The image is built and structurally verified, but was not tested on a
  physical A04 in this environment.
