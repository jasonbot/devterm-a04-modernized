package main

import (
	"fmt"
	"image/color"
	"strings"

	"github.com/boombuler/barcode/qr"
)

func qrLevel(name string) qr.ErrorCorrectionLevel {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "l", "low":
		return qr.L
	case "q", "quartile":
		return qr.Q
	case "h", "high":
		return qr.H
	default:
		return qr.M
	}
}

// qrCanvas draws a QR code scaled to the full print width with a four-module
// quiet zone on every side.
func qrCanvas(content string, level qr.ErrorCorrectionLevel, width int) (*Canvas, error) {
	bc, err := qr.Encode(content, level, qr.Auto)
	if err != nil {
		return nil, fmt.Errorf("qr: %w", err)
	}
	b := bc.Bounds()
	n := b.Dx()
	if n == 0 {
		return nil, fmt.Errorf("qr: empty matrix")
	}
	quiet := 4
	total := n + quiet*2
	scale := width / total
	if scale < 1 {
		scale = 1
	}
	size := total * scale
	c := NewCanvas(width)
	c.ensure(size)
	offX := (width - size) / 2
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			if !isDark(bc.At(b.Min.X+x, b.Min.Y+y)) {
				continue
			}
			c.fill(offX+(quiet+x)*scale, (quiet+y)*scale, scale, scale, color.Black)
		}
	}
	return c, nil
}

func isDark(col color.Color) bool {
	r, g, b, _ := col.RGBA()
	return (r+g+b)/3 < 0x8000
}
