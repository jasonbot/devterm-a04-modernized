package main

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"os"
)

// The vendor daemon's undocumented bitmap command: GS v 0 p wL wH hL hH,
// followed by one bit per dot.  Width is in bytes (8 dots), height in rows.
// The daemon pads to the 384-dot print head.  On the A04 the most significant
// bit is the leftmost dot: packing it the other way round mirrors every glyph
// in 8-dot slices (the 2021 forum notes claim LSB, but the hardware says MSB).  See clockworkpi/DevTerm thermal_printer and
// forum.clockworkpi.com/t/7650.
const (
	printerWidth = 384
	maxBandRows  = 192 // what the vendor tests use; keeps each image small
	headerSize   = 8
)

// Canvas is a 384-dot-wide monochrome strip that grows downwards.
type Canvas struct {
	W   int
	Img *image.Gray
}

func NewCanvas(w int) *Canvas {
	return &Canvas{W: w, Img: image.NewGray(image.Rect(0, 0, w, 0))}
}

func (c *Canvas) Height() int { return c.Img.Bounds().Dy() }

func (c *Canvas) ensure(rows int) {
	if rows <= c.Height() {
		return
	}
	next := image.NewGray(image.Rect(0, 0, c.W, rows))
	draw.Draw(next, image.Rect(0, 0, c.W, c.Height()), c.Img, image.Point{}, draw.Src)
	// new rows default to zero; paint them white (no ink)
	draw.Draw(next, image.Rect(0, c.Height(), c.W, rows), image.NewUniform(color.White), image.Point{}, draw.Src)
	c.Img = next
}

func (c *Canvas) fill(x, y, w, h int, col color.Color) {
	if w <= 0 || h <= 0 || x >= c.W || y >= c.Height() {
		return
	}
	r := image.Rect(x, y, min(x+w, c.W), min(y+h, c.Height()))
	draw.Draw(c.Img, r, image.NewUniform(col), image.Point{}, draw.Src)
}

// Encode turns the canvas into the daemon's bitmap commands, splitting it into
// bands so no single image is oversized.
func (c *Canvas) Encode(bandRows int, msbFirst bool) []byte {
	if bandRows <= 0 || bandRows > 65535 {
		bandRows = maxBandRows
	}
	var out bytes.Buffer
	h := c.Height()
	rowBytes := (c.W + 7) / 8
	for y := 0; y < h; y += bandRows {
		rows := min(bandRows, h-y)
		out.Write([]byte{0x1d, 0x76, 0x30, 0x70})
		out.WriteByte(byte(rowBytes & 0xff))
		out.WriteByte(byte(rowBytes >> 8))
		out.WriteByte(byte(rows & 0xff))
		out.WriteByte(byte(rows >> 8))
		for row := 0; row < rows; row++ {
			line := make([]byte, rowBytes)
			base := (y + row) * c.Img.Stride
			for x := 0; x < c.W; x++ {
				// Gray 0 is black ink, 255 is paper.
				if c.Img.Pix[base+x] < 128 {
					bit := uint(x % 8)
					if msbFirst {
						line[x/8] |= 0x80 >> bit
					} else {
						line[x/8] |= 1 << bit
					}
				}
			}
			out.Write(line)
		}
	}
	return out.Bytes()
}

func (c *Canvas) PNG() ([]byte, error) {
	var buf bytes.Buffer
	if err := png.Encode(&buf, c.Img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// escposPreamble sets the print density (DC2 '#' n) and clears text state.
// n is 0..15; the vendor default is 6.
func escposPreamble(density int) []byte {
	if density < 0 {
		density = 0
	}
	if density > 15 {
		density = 15
	}
	return []byte{0x12, 0x23, byte(density)}
}

// escposFeed advances n lines (ESC d n).
func escposFeed(n int) []byte {
	if n <= 0 {
		return nil
	}
	if n > 255 {
		n = 255
	}
	return []byte{0x1b, 0x64, byte(n)}
}

func writePrinter(path string, data []byte) error {
	if path == "" {
		path = "/tmp/DEVTERM_PRINTER_IN"
	}
	f, err := os.OpenFile(path, os.O_WRONLY, 0)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("%s is missing: is devterm-socat.service running?", path)
		}
		return err
	}
	defer f.Close()
	_, err = f.Write(data)
	return err
}
