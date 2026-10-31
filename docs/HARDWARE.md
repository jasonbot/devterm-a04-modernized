# A04 hardware notes

## Display

- 6.86 inch IPS, 480x1280 portrait
- DSI panel described as `clockwork,cpi3-lcd` in the vendor DTB
- `panel-simple` + vendor TCON-LCD changes
- backlight: `ocp8178-backlight`, controlled by a GPIO
- console: Ly inside kmscon on tty1 with `rotate=right`; the Ly-on-kernel-VT
  fallback uses `fbcon=rotate:1`

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
- `brcmfmac` + `brcmfmac43455-sdio.bin` from `firmware-brcm80211`
- `wireless-regdb`, NetworkManager, wpa_supplicant
- board-specific NVRAM is the main bring-up variable; Debian's package
  provides many board NVRAM files but not an A04-specific one
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

- AXP221 PMIC, H6
- UART0 is the debug console: **115200 8N1**
- U-Boot does not initialize the panel; serial is the reliable early console
- root partition is plain ext4, so it can be edited from another Linux

## SD card

The image is an 8 GiB MBR disk.  `devterm-growroot.service` expands the last
partition to the SD card size on first boot.  Use a good-quality card; sunxi
SPL is sensitive to some cheap or counterfeit cards.

## Device tree sources

The U-Boot DTS is in `vendor/uboot/sun50i-h6-clockworkpi-a04.dts`.  The Linux
DTB comes from the vendor kernel package and is copied to
`/boot/devterm-a04.dtb`.  The vendor Linux DTS patch is not vendored here
because the package supplies the built DTB; the relevant patch is referenced
in `docs/KERNEL.md` and can be extracted from ClockworkPi's DevTerm repository
if a kernel rebuild is needed.
