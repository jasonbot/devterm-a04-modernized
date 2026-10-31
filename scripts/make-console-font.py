#!/usr/bin/env python3
"""Build a Linux PSF2 console font from Paper Mono Nerd Font.

The console cannot use an OpenType/CFF font directly.  This renders every
codepoint the font advertises into a fixed cell and writes a PSF2 file with a
Unicode mapping table.  Nerd Font private-use glyphs are included, so terminal
programs (powerline, starship, eza, etc.) work on the framebuffer console.

Usage:
    python3 make-console-font.py FONT.otf OUT.psf [--width 9 --height 18]

Requires: python3-pil (Pillow), python3-fonttools.
"""

from __future__ import annotations

import argparse
import gzip
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

PSF2_FLAGS_HAS_UNICODE = 1
REPLACEMENT = 0xFFFD


def glyph_bitmap(
    draw_font: ImageFont.FreeTypeFont,
    char: str,
    width: int,
    height: int,
    baseline: int,
) -> bytes:
    """Render one character into a width x height, 1-bit, MSB-first bitmap."""
    # Draw on a generous canvas so negative bearings and tall Nerd Font icons
    # are not silently cut off.  The cell origin is (pad, 0).
    pad = width
    canvas = Image.new("L", (width + pad * 2, height * 3), 0)
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, baseline), char, font=draw_font, fill=255, anchor="ls")

    image = Image.new("L", (width, height), 0)
    bbox = canvas.getbbox()
    if bbox is not None:
        crop = canvas.crop(bbox)
        x = bbox[0] - pad
        y = bbox[1]
        if crop.width <= width and crop.height <= height and x >= 0 and x + crop.width <= width:
            image.paste(crop, (x, y))
        else:
            # Only oversized/oddly-positioned glyphs are scaled and centered.
            scale = min(width / max(1, crop.width), height / max(1, crop.height), 1.0)
            if scale < 1.0:
                crop = crop.resize(
                    (max(1, int(crop.width * scale)), max(1, int(crop.height * scale))),
                    Image.Resampling.LANCZOS,
                )
            image.paste(crop, ((width - crop.width) // 2, (height - crop.height) // 2))

    image = image.point(lambda p: 255 if p >= 110 else 0, mode="1")

    row_bytes = (width + 7) // 8
    out = bytearray(row_bytes * height)
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            if pixels[x, y]:
                out[y * row_bytes + (x >> 3)] |= 0x80 >> (x & 7)
    return bytes(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("font", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=9)
    parser.add_argument("--height", type=int, default=18)
    args = parser.parse_args()

    tt = TTFont(args.font)
    cmap = tt.getBestCmap() or {}
    codepoints = {cp for cp in cmap if 0 <= cp <= 0x10FFFF}

    # Always keep the usual console furniture even if the source font is
    # missing a few printable ASCII characters.
    codepoints.update(range(0x20, 0x7F))
    codepoints.add(REPLACEMENT)

    # Pick the largest pixel size whose font metrics and monospace advance fit
    # the cell.  For Paper Mono this gives 12px for 8x16, 14px for 9x18,
    # 16px for 10x20 and 26px for 16x32.
    pixel_size = 7
    for candidate in range(args.height, 6, -1):
        test_font = ImageFont.truetype(str(args.font), candidate)
        test_ascent, test_descent = test_font.getmetrics()
        if test_ascent + test_descent <= args.height and test_font.getlength("M") <= args.width:
            pixel_size = candidate
            break
    font = ImageFont.truetype(str(args.font), pixel_size)
    ascent, _descent = font.getmetrics()
    baseline = ascent

    # Glyph 0 is the "unknown" glyph.  '?' is a safe, visually obvious fallback.
    glyphs: list[tuple[int, bytes]] = [(REPLACEMENT, glyph_bitmap(font, "?", args.width, args.height, baseline))]

    for cp in sorted(codepoints):
        if cp == REPLACEMENT:
            continue
        ch = chr(cp)
        # Private-use codepoints (where Nerd Font icons live) are not
        # "printable" according to Python, but they are exactly what we need.
        if 0x00 <= cp <= 0x1F or 0x7F <= cp <= 0x9F or 0xD800 <= cp <= 0xDFFF:
            continue
        glyphs.append((cp, glyph_bitmap(font, ch, args.width, args.height, baseline)))

    charsize = ((args.width + 7) // 8) * args.height
    header_size = 32

    data = bytearray()
    data += b"\x72\xb5\x4a\x86"  # PSF2 magic bytes
    data += struct.pack(
        "<7I",
        0,  # version
        header_size,
        PSF2_FLAGS_HAS_UNICODE,
        len(glyphs),  # number of glyphs, not bytes
        charsize,
        args.height,
        args.width,
    )
    for _, bitmap in glyphs:
        assert len(bitmap) == charsize
        data += bitmap
    # PSF2 maps each glyph to one UTF-8 string terminated by 0xff (0xfe
    # introduces a UTF-8 sequence, which we do not need here).
    for cp, _ in glyphs:
        data += chr(cp).encode("utf-8") + b"\xff"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.output, "wb", compresslevel=9) as f:
        f.write(data)
    print(
        f"{args.output}: {len(glyphs)} glyphs, {args.width}x{args.height}, "
        f"{pixel_size}px, {len(data)} bytes ({len(data) / 1024:.0f} KiB)"
    )


if __name__ == "__main__":
    main()
