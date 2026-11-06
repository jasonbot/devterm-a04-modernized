package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func gradientPNG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			v := uint8(255 * x / max(w-1, 1))
			img.Set(x, y, color.RGBA{v, v, v, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestImageFitAndAutoRotate(t *testing.T) {
	land := gradientPNG(t, 100, 50) // landscape -> rotated to 50x100
	c, err := renderImage(options{width: 384, dither: "floyd"}, land)
	if err != nil {
		t.Fatal(err)
	}
	if c.W != 384 {
		t.Fatalf("width %d", c.W)
	}
	// 100 wide becomes 50 after rotation, so height is 384*100/50
	if c.Height() != 768 {
		t.Fatalf("rotated landscape height %d, want 768", c.Height())
	}

	port := gradientPNG(t, 50, 100) // portrait stays
	c, err = renderImage(options{width: 384, dither: "floyd"}, port)
	if err != nil {
		t.Fatal(err)
	}
	if c.Height() != 768 {
		t.Fatalf("portrait height %d, want 768", c.Height())
	}

	c, err = renderImage(options{width: 384, dither: "none", rotate: "0"}, land)
	if err != nil {
		t.Fatal(err)
	}
	if c.Height() != 192 {
		t.Fatalf("unrotated landscape height %d, want 192", c.Height())
	}
}

func TestDitherProducesInkAndPaper(t *testing.T) {
	src := gradientPNG(t, 64, 8)
	c, err := renderImage(options{width: 384, dither: "floyd"}, src)
	if err != nil {
		t.Fatal(err)
	}
	ink, paper := 0, 0
	for _, p := range c.Img.Pix {
		if p < 128 {
			ink++
		} else {
			paper++
		}
	}
	if ink == 0 || paper == 0 {
		t.Fatalf("dither output is uniform: ink=%d paper=%d", ink, paper)
	}
}
