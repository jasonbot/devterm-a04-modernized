# DevTerm A04 Debian Image

This project builds a ready-to-use Debian 13 Linux image for the ClockworkPi
DevTerm A04. The A04 is a small computer with an Allwinner H6 chip and a
480x1280 screen.

The image is **live**. It is not an installer. You write it to a TF/microSD
card, put the card in the DevTerm, and turn the device on. On the first boot,
the system makes the root filesystem use the rest of the card.

## What you get

- Debian 13 (`trixie`) for 64-bit ARM.
- A text console with **kmscon**.
- **Ly**, a text login screen, running inside kmscon.
- **Starship** as the default prompt, using the image's Paper Mono Nerd
  Font/Powerline glyphs.
- Login shells attach to a persistent tmux session named `login`.
- The power button suspends the A04 (long press powers off).
- **Paper Mono Nerd Font** at a 16 px / 8x16 cell size as the console font.
- Every NerdFont from your font folder, installed for all programs.
- Two text-mode browsers, both usable without X or Wayland:
  **Carbonyl** (Chromium) and **Chawan** (small Nim engine).
- Wi-Fi, SSH, **Tailscale**, sound, fan control and the 58 mm thermal
  printer.
- **Yazi**, a fast terminal file manager (text previews; optional preview
  tools can be installed from apt).
- **tmux** configured with a `Ctrl-a` prefix and a clickable Wi-Fi status
  section; the bar also shows live Tailscale, battery (Nerd Font icon) and
  the clock.
- The special ClockworkPi A04 kernel. Debian kernel packages are pinned so a
  normal `apt update && apt upgrade` cannot replace it by accident.

The A04 panel, backlight, sound codec and printer pins need the vendor Linux
5.10 kernel. A normal Debian kernel does not support them yet.

## First boot

Use a card **larger than 4 GiB**. An 8 GB, 16 GB or 32 GB card is a good
choice.

1. Flash the image to the card.
2. Put the card in the DevTerm.
3. Turn it on.
4. Wait for the first boot. `devterm-growroot.service` grows the root
   partition and filesystem to fill the card.
5. Log in with:

   ```text
   user: devterm
   pass: devterm
   ```

   The root password is also `devterm`. Change both passwords.

The Ly login screen shows the users. Pick `devterm`, type the password, and
choose the **Shell** session. You then get a normal Linux shell.

## Build it

You need:

- a Linux PC with an x86_64 CPU
- Podman, with arm64 container support
- about 25 GB of free disk space
- internet access
- Python 3 with Pillow and fontTools
- the font folder at `~/Sync/Fonts` (or set `DEVTERM_FONT_DIR`)

Build everything:

```sh
./build.sh
```

Or run the steps one at a time:

```sh
make fetch     # download sources, packages, fonts and browsers
make uboot     # build TF-A and U-Boot
make ly        # build the Ly login screen
make chawan    # build Chawan
make kmscon    # kmscon with the A04 guard band
make rootfs    # build the Debian root filesystem
make image     # make the card image
make verify    # check the image
```

The first build takes a while because it builds an arm64 Debian system, Ly
and Chawan. Later builds reuse cached downloads and build trees.

When it finishes, the flashable files are:

```text
artifacts/devterm-a04.img.zst
artifacts/devterm-a04.img
artifacts/SHA256SUMS
```

The `.img.zst` file is about 750 MiB. The uncompressed image is 4 GiB.

## Flash the card

Check the card device name first. This command destroys everything on the
target card:

```sh
zstd -dc artifacts/devterm-a04.img.zst |
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

You can also decompress the image and use balenaEtcher or Raspberry Pi Imager.

## Project layout

```text
containers/   container files used to build U-Boot, Debian and Ly
overlay/      files copied into the Debian system
scripts/      build and verification scripts
vendor/       U-Boot board files
docs/         kernel and hardware notes
artifacts/    built image and downloaded files (not committed)
```

## More information

- [BUILD.md](BUILD.md) explains the build in more detail.
- [USAGE.md](USAGE.md) explains Wi-Fi, the browser, the printer, fonts and
  recovery.
- [docs/KERNEL.md](docs/KERNEL.md) explains why the image uses the vendor
  kernel.
- [docs/HARDWARE.md](docs/HARDWARE.md) has notes about the A04 hardware.

## Important notes

- This image is only for the **DevTerm A04**. Do not use it on the A06, CM4 or
  RISC-V models.
- The vendor kernel is Linux 5.10.75. It does not get Debian kernel security
  updates.
- No physical A04 was available while the image was built. The image layout,
  filesystem, U-Boot boot files, kmscon/Ly setup and package pins were checked,
  but the first real boot should be treated as hardware bring-up.
- Change the default passwords before putting the device on a network.
