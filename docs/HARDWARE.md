# A04 hardware notes

## Display

- 6.86 inch IPS, 480x1280 portrait
- DSI panel described as `clockwork,cpi3-lcd` in the vendor DTB
- `panel-simple` + vendor TCON-LCD changes
- backlight: `ocp8178-backlight`, controlled by a GPIO
- console: Ly inside kmscon on tty1 with `rotate=right`; kmscon uses the
  dumb-buffer drm2d backend (`no-hwaccel`) at a 16 px / 8x16 cell size.  The Ly-on-kernel-VT fallback
  uses `fbcon=rotate:1`

Useful checks:

```sh
dmesg | grep -iE 'panel|cpi3|ocp8178|backlight|dsi|drm|fb0'
cat /sys/class/graphics/fb0/virtual_size
ls /sys/class/backlight/
```

## Thermal printer

- 58 mm roll, raw ESC/POS
- SPI1 on H6, exposed as `spidev@0`; with only SPI1 registered Linux usually
  exposes it as `/dev/spidev0.0`
- wiringPi maps the A04 BCM-style pin numbers to H6 GPIO banks through
  `/dev/mem`
- vendor daemon reads `/tmp/DEVTERM_PRINTER_OUT`; write to
  `/tmp/DEVTERM_PRINTER_IN`
- `socat` creates the two PTY links

The daemon uses the Noto Sans CJK TTC for text rendering and reads an ADC
thermal signal from `/tmp/devterm_adc` when available.

## Wi-Fi / Bluetooth

- Broadcom BCM4345C5 on SDIO (`mmc1`)
- `brcmfmac`; the A04 reports as BCM43456, so the vendor `brcmfmac43456-sdio.bin`, `.clm_blob` and NVRAM are installed
- the A04 NVRAM extracted from the vendor image, installed as
  `brcmfmac43455-sdio.clockwork,devterm-a04.txt` and as the generic
  `brcmfmac43455-sdio.txt`; the `macaddr=` line is removed so each device
  generates its own address
- `wireless-regdb`, NetworkManager, wpa_supplicant
- Bluetooth is not enabled by default; the same chip supports it, but the
  vendor image's Bluetooth firmware/NVRAM would need to be added

Useful checks:

```sh
rfkill list
dmesg | grep -iE 'brcmfmac|mmc1|sdio'
nmcli device status
```

## Fan, audio, gearbox

- fan: GPIO 41, vendor `temp_fan_daemon_a04.py`; runs as root
- audio switch: GPIO 10 (jack detect) and GPIO 11 (speaker enable), vendor
  `audio_3.5_patch.py`
- gearbox: vendor A04 CPU/GPU tuning helper
- both Python services need `wiringPi`'s `gpio` command

## Power and recovery

- power button: short press suspend (s2idle), long press poweroff
- deep suspend needs Crust/SCP, which this image does not ship

- AXP221 PMIC, H6
- UART0 is the debug console: **115200 8N1**
- U-Boot does not initialize the panel; serial is the reliable early console
- root partition is plain ext4, so it can be edited from another Linux

## HDMI

- micro-HDMI (type D) connector; H6 `dw-hdmi` + `hdmi-phy`, driver built in
  (`CONFIG_DRM_SUN4I_HDMI=y`)
- the vendor DTB disables `tcon_tv` and links TCON-TV directly to the HDMI
  encoder, which is not the documented H6 route
  (`mixer0 -> TCON-TOP -> TCON-TV -> TCON-TOP -> HDMI`), so the connector never
  registers
- the image builds the fixed tree as `/boot/devterm-a04.dtb.hdmi` from
  `/etc/devterm/hdmi.dts` (`tcon_tv` and `i2s1` enabled, TCON-TOP HDMI ports 4
  and 5 added, endpoints re-linked) and keeps the vendor tree as both the
  default `/boot/devterm-a04.dtb` and `/boot/devterm-a04.dtb.vendor`
- `sudo devterm-hdmi on|off` swaps the boot tree; it is opt-in because kmscon
  mirrors one console to all connected displays and shrinks it to the smallest,
  and the connector reads "connected" with no cable (the panel loses 64 columns)
- kmscon mirrors the console to every connected display

Useful checks:

```sh
ls /sys/class/drm/
fdtget -t s /boot/devterm-a04.dtb /soc/lcd-controller@6515000 status
dmesg | grep -iE 'dw-hdmi|tcon'
```

## SD card

The image is a 4 GiB MBR disk.  `devterm-growroot.service` expands the last
partition to the SD card size on first boot.  Use a good-quality card; sunxi
SPL is sensitive to some cheap or counterfeit cards.

## Device tree sources

The U-Boot DTS is in `vendor/uboot/sun50i-h6-clockworkpi-a04.dts`.  The Linux
DTB comes from the vendor kernel package and is copied to
`/boot/devterm-a04.dtb`.  The vendor Linux DTS patch is not vendored here
because the package supplies the built DTB; the relevant patch is referenced
in `docs/KERNEL.md` and can be extracted from ClockworkPi's DevTerm repository
if a kernel rebuild is needed.
