# devterm-print

Print QR codes, markdown and ZPL labels on the DevTerm A04 thermal printer.

## How it reaches the printer

The vendor daemon (`devterm_thermal_printer.elf`) reads the `DEVTERM_PRINTER_IN`
pty and drives the print head over SPI.  Besides text it understands an
undocumented bitmap command, `GS v 0 p wL wH hL hH`, followed by one bit per
dot (MSB = leftmost dot, 1 = ink), with the width given in bytes.  The A04 head
needs MSB-first; `--lsb` packs the other way for units that differ.  This tool
renders everything to 384-dot-wide 1-bit images and streams them as bands of
at most 192 rows, which keeps each command small and the paper advance
seamless.

## Commands

```sh
devterm-print --qr="https://example.com"
devterm-print --qr-b4=0132...          # base-4 encoded bytes
devterm-print --font="Iosevka Nerd Font" README.md
devterm-print --zpl label.zpl
devterm-print --test                   # alignment and font legibility page
devterm-print --qr=hello --png=out.png --out=out.escpos   # preview, no paper
devterm-print --feed-only=20                              # blank feed, no print
devterm-print photo.jpg                                   # fit, rotate, dither
```

## Images

PNG, JPEG, GIF (first frame), BMP and TIFF are decoded with the Go standard
library and `x/image`, scaled to the print width with a Catmull-Rom filter, and
dithered to one bit with gamma-corrected error diffusion (Floyd-Steinberg by
default, Atkinson on request).  Landscape pictures are rotated 90° by default
because the paper is a narrow strip; `--rotate=0` keeps the original and
`--rotate=180/270` suite scans and upside-down photos.

`--feed-only N` sends the daemon's `ESC d N`, which feeds N font-height lines
(about 2 mm each with the default 8x16 font).  The raw equivalent is
`printf '\x1b\x64\x14' > /tmp/DEVTERM_PRINTER_IN` for 20 lines.

`--qr-b4` decodes four base-4 digits per byte (most significant pair first) and
prints the resulting bytes, so binary payloads can travel through a shell or a
chat message.

## Fonts and duospace

`--font` takes a family name (matched against the installed fonts, including
`/usr/local/share/fonts/nerd-fonts`) or a font file.  Bold and italic use the
family's own faces when present and fall back to a synthetic double-draw.

For families that ship both proportional and monospaced variants (Nerd Fonts'
`Propo` and `Mono` siblings), code spans and code blocks automatically use the
mono face while body text keeps the requested one.

`--duospace` forces every ASCII glyph to a single advance inside an otherwise
proportional font, so tables and code line up while non-Latin scripts keep
their natural widths.

## ZPL

`--zpl` approximates a usable subset: `^XA/^XZ`, `^PW`, `^FO/^FT`, `^A0N`,
`^FD/^FS`, `^GB` boxes, `^BY`/`^BC` Code 128, `^BQ` QR, `^PQ` copies and `^FR`
reverse video.  Other commands are accepted and ignored, so real labels print
recognisably rather than failing.
