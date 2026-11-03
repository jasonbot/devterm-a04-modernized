# Building the DevTerm A04 image

The build is entirely rootless.  It uses two containers:

1. an x86_64 Debian 13 container with `gcc-aarch64-linux-gnu` for TF-A and
   U-Boot;
2. an arm64 Debian 13 container with `mmdebstrap` for the root filesystem;
3. an arm64 Debian 13 container with Zig 0.17 for Ly.

The host assembles the image with `fakeroot`, `mke2fs -d`, `sfdisk` and `dd`.
No loop devices, mounts or `sudo` are required.

## Requirements

- Linux x86_64 host (other architectures work if the cross toolchain is
  available; the scripts assume `gcc-aarch64-linux-gnu`)
- rootless Podman with arm64 binfmt support
- ~20 GB free disk (sources, rootfs, 4 GiB image and compressed copy)
- network access to Debian, GitHub, DENX and ClockworkPi
- host tools: `curl`, `unzip`, `tar`, `fakeroot`, `e2fsprogs`, `sfdisk`,
  `zstd`, `mkimage`, Python 3 + Pillow + fontTools

On Debian/Ubuntu:

```sh
sudo apt install podman qemu-user-static binfmt-support \
    fakeroot e2fsprogs fdisk util-linux zstd u-boot-tools \
    python3-pil python3-fonttools curl unzip
```

Check arm64 containers:

```sh
podman run --rm --arch arm64 debian:13-slim uname -m
# aarch64
```

## Fonts

The console font and the system-wide NerdFont collection come from
`~/Sync/Fonts` by default.  Override with:

```sh
DEVTERM_FONT_DIR=/path/to/fonts ./scripts/fetch.sh
```

`fetch.sh` copies every `*NerdFont*` file and generates four PSF2 console
fonts from `PaperMonoNerdFont-Regular.otf`:

- `PaperMonoNerdFont-8x16.psf.gz` (default, 8x16 cells)
- `PaperMonoNerdFont-9x18.psf.gz` (9x18 cells)
- `PaperMonoNerdFont-10x20.psf.gz`
- `PaperMonoNerdFont-16x32.psf.gz`

The generator is `scripts/make-console-font.py`; it writes a valid PSF2 with a
UTF-8 Unicode table, including Nerd Font private-use glyphs.

## Build

```sh
./build.sh
```

Equivalent:

```sh
make fetch
make uboot
make ly
make chawan     # Chawan
make kmscon     # patched kmscon (A04 guard band)
make rootfs
make image
make verify
```

### Stage details

`make fetch` downloads:

- U-Boot `2025.01`
- ARM Trusted Firmware `v2.11.0`
- ClockworkPi A04 kernel `devterm-kernel-current-cpi-a04_0.6_arm64.deb`
- ClockworkPi audio/fan/gearbox/wiringPi/printer packages
- Carbonyl `v0.0.3` arm64
- Chawan `0.5.1` source and the kmscon `10.0.4` source
- Debian 13 arm64 packages during the rootfs stage

`make uboot`:

- builds TF-A BL31 for `sun50i_h6`
- copies `vendor/uboot/clockworkpi-a04-h6_defconfig` and
  `vendor/uboot/sun50i-h6-clockworkpi-a04.dts`
- registers the DTS in U-Boot's DTS Makefile
- disables the optional H6 SCP firmware blob in U-Boot's Kconfig, because
  Crust is only needed for suspend and would require an OR1K toolchain;
  BL31 still provides PSCI
- writes `artifacts/uboot/u-boot-sunxi-with-spl.bin`

`make ly`:

- downloads Zig 0.17 for arm64 into `artifacts/src`
- clones Ly at its pinned commit and builds it with X11 support disabled
- builds Ly with `-Dcpu=cortex_a53`: the A04's H6 is an ARMv8.0 Cortex-A53,
  and Zig's native/container CPU would emit ARMv8.1+ instructions (LSE) that
  SIGILL on the device
- writes `artifacts/ly/ly`

`make kmscon`:

- builds kmscon `10.0.4` for arm64 against `libtsm` from trixie-backports
- applies `patches/kmscon-a04-pad.patch`: an 8px total guard band split
  between the rotated top and bottom edges, because the A04 panel wraps its
  first active lines to the bottom; kmscon drops one text row to make room
- writes `artifacts/kmscon/usr`; `make rootfs` replaces the distro binary

`make chawan`:

- builds a Debian trixie arm64 container with the official Nim `2.2.12`
  aarch64 compiler (trixie has no Nim package)
- runs `make` and `make install PREFIX=/usr` for Chawan `0.5.1`
- writes the staged `/usr` tree to `artifacts/chawan/`

`make rootfs`:

- creates an arm64 `trixie` rootfs with `mmdebstrap --format=tar`
- installs NetworkManager, SSH, console-setup, fonts, Chromium runtime
  dependencies and the rest of the package list in `scripts/build-rootfs.sh`
- adds the Tailscale and Yazi apt repositories and installs `tailscale`
  and `yazi`
- installs `kmscon` from `trixie-backports`, replaces it with the patched
  A04 build, and sets up Ly as the tty1 login screen;
  kmscon uses its dumb-buffer drm2d backend, which the vendor sun4i-drm driver
  supports, with Ly on the kernel fbcon only as a failed-start fallback
- runs `scripts/rootfs-install.sh` inside the target:
  - vendor kernel, audio, fan, gearbox and wiringPi packages
  - apt kernel pinning (`overlay/etc/apt/preferences.d/00-devterm-kernel.pref`)
    and `apt-mark hold` for the vendor kernel/audio packages
  - Ly inside kmscon on tty1 (drm2d, `hwaccel=off`); `ly@tty1` is the
    kernel-VT fallback for a kmscon initialisation failure
  - printer daemon extracted without CUPS
  - `/boot/Image`, `/boot/initrd.img`, `/boot/devterm-a04.dtb`
  - `/boot/extlinux/extlinux.conf` and `/boot/boot.scr`
  - console font, NerdFonts, Carbonyl, Chawan, Tailscale, Yazi, nmtui-go,
    Starship prompt, services, user and Wi-Fi config
- extracts the tar as the normal user and checks required files

`make image`:

- creates a 4 GiB MBR disk image
- builds an ext4 filesystem labeled `devterm-root` with `fakeroot` +
  `mke2fs -d`
- writes the filesystem at 2 MiB
- writes U-Boot at 8 KiB (the H6 BootROM location)
- compresses with zstd and writes `artifacts/SHA256SUMS`

`make verify` checks the partition table, the SPL eGON header, the ext4
filesystem, the label and the boot files.

## Customizing

- **Packages:** edit the `packages` string in `scripts/build-rootfs.sh`.
- **Files/services:** add them under `overlay/`; the whole tree is copied into
  the rootfs.
- **Kernel command line:** edit `overlay/boot/boot.cmd` and the `APPEND` line
  in `scripts/rootfs-install.sh`.  The current line is:

  ```text
  root=LABEL=devterm-root rootfstype=ext4 rootwait rw \
  console=ttyS0,115200 console=tty0 fbcon=rotate:1 loglevel=4
  ```

- **Default console font:** change `font-name`/`font-size` in the kmscon
  config written by `scripts/rootfs-install.sh`, and the `FONT`/`FONTFACE`
  fallback values there.
- **Image size:** change `IMG_BYTES` in `scripts/build-image.sh`.
- **Default user/password:** edit `scripts/rootfs-install.sh`.

## Rebuilding only part of the image

Cached sources and vendor packages are reused:

```sh
# rootfs or overlay change
rm -rf artifacts/rootfs
./scripts/build-rootfs.sh
./scripts/build-image.sh

# U-Boot change
./scripts/build-uboot.sh
./scripts/build-image.sh

# console font change only
FORCE_FONTS=1 ./scripts/fetch.sh
rm -rf artifacts/rootfs
./scripts/build-rootfs.sh && ./scripts/build-image.sh
```

The build is not bit-for-bit reproducible: ext4 UUIDs, filesystem timestamps
and Debian package versions change over time.

## Flashing

```sh
zstd -dc artifacts/devterm-a04.img.zst |
  sudo dd of=/dev/sdX bs=4M iflag=fullblock oflag=direct status=progress conv=fsync
```

or decompress and use Etcher.  This is a live image, not an installer: the
image is 4 GiB and the first boot expands the root partition to the full SD
card via `devterm-growroot.service`.  Use a card larger than 4 GiB.

## What is not verified here

There is no physical A04 in this environment, so the following need hardware
bring-up: DDR training/SPL boot on the A04, panel timings and rotation,
backlight, Wi-Fi NVRAM/calibration, printer GPIO/SPI behaviour, fan/audio GPIO
and Carbonyl rendering on fbcon.  The image was checked structurally (U-Boot
SPL header, ext4 `fsck`, boot files, initramfs modules).  See
`docs/KERNEL.md` and `USAGE.md` for the first-boot checks.
