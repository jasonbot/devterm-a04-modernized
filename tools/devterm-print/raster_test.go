package main

import (
	"bytes"
	"image/color"
	"testing"
)

func TestEncodeHeaderAndBits(t *testing.T) {
	c := NewCanvas(16)
	c.ensure(2)
	// first row: leftmost and eighth dot set; second row: dots 2 and 3
	c.fill(0, 0, 1, 1, color.Black)
	c.fill(7, 0, 1, 1, color.Black)
	c.fill(2, 1, 2, 1, color.Black)

	lsb := c.Encode(192, false)
	wantHeader := []byte{0x1d, 0x76, 0x30, 0x70, 2, 0, 2, 0}
	if !bytes.HasPrefix(lsb, wantHeader) {
		t.Fatalf("header % x, want % x", lsb[:8], wantHeader)
	}
	// 16 dots = 2 bytes per row, LSB first
	if got, want := lsb[8:12], []byte{0x81, 0x00, 0x0c, 0x00}; !bytes.Equal(got, want) {
		t.Fatalf("lsb data % x want % x", got, want)
	}

	msb := c.Encode(192, true)
	if got, want := msb[8:12], []byte{0x81, 0x00, 0x30, 0x00}; !bytes.Equal(got, want) {
		t.Fatalf("msb data % x want % x", got, want)
	}
}

func TestEncodeBands(t *testing.T) {
	c := NewCanvas(8)
	c.ensure(400)
	out := c.Encode(192, false)
	// three bands: 192, 192, 16 rows
	var bands []int
	for i := 0; i < len(out); {
		if out[i] != 0x1d {
			t.Fatalf("bad marker at %d", i)
		}
		rows := int(out[i+6]) | int(out[i+7])<<8
		bands = append(bands, rows)
		i += 8 + rows*1 // 8 dots wide = 1 byte rows
	}
	if len(bands) != 3 || bands[0] != 192 || bands[1] != 192 || bands[2] != 16 {
		t.Fatalf("bands %v", bands)
	}
}
