package main

import (
	"bytes"
	"fmt"
	"image"
	"image/draw"
	"math"
	"path/filepath"
	"strings"

	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"

	_ "golang.org/x/image/bmp"
	xdraw "golang.org/x/image/draw"
	_ "golang.org/x/image/tiff"
)

func isImagePath(p string) bool {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff":
		return true
	}
	return false
}

// renderImage scales an image to the print width, turns landscape shots
// sideways (or as asked) and dithers it to one bit.
func renderImage(o options, data []byte) (*Canvas, error) {
	src, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("decode image: %w", err)
	}
	_ = format

	// The paper is a narrow strip, so a landscape picture is turned on its
	// side to use the length of the receipt instead of printing a tiny
	// letterbox a few centimetres tall.
	rot := o.rotate
	if rot == "" || rot == "auto" {
		b := src.Bounds()
		if b.Dx() > b.Dy() {
			rot = "90"
		} else {
			rot = "0"
		}
	}
	src = rotateImage(src, rot)

	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	if sw == 0 || sh == 0 {
		return nil, fmt.Errorf("empty image")
	}
	dw := o.width
	dh := int(math.Round(float64(sh) * float64(dw) / float64(sw)))
	if dh < 1 {
		dh = 1
	}
	if dh > 20000 {
		return nil, fmt.Errorf("image would be %d dots long; crop it first", dh)
	}

	scaled := image.NewRGBA(image.Rect(0, 0, dw, dh))
	xdraw.CatmullRom.Scale(scaled, scaled.Bounds(), src, b, draw.Src, nil)

	gray := dither(scaled, o.dither)
	return &Canvas{W: o.width, Img: gray}, nil
}

func rotateImage(src image.Image, rot string) image.Image {
	deg := strings.TrimSuffix(strings.TrimSpace(rot), "deg")
	switch deg {
	case "0", "":
		return src
	case "90":
		return rotate90(src)
	case "180":
		return rotate180(src)
	case "270":
		return rotate270(src)
	}
	return src
}

func rotate90(src image.Image) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(h-1-y, x, src.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}

func rotate180(src image.Image) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(w-1-x, h-1-y, src.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}

func rotate270(src image.Image) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(y, w-1-x, src.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}

// dither converts to a 1-bit Gray image: 0 is ink, 255 is paper.  Floyd and
// Atkinson diffuse the error in linear light so mid-tones survive the shrink
// to one bit instead of banding.
func dither(src *image.RGBA, mode string) *image.Gray {
	w, h := src.Bounds().Dx(), src.Bounds().Dy()
	out := image.NewGray(image.Rect(0, 0, w, h))
	if strings.EqualFold(mode, "none") {
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				r, g, b, _ := src.At(x, y).RGBA()
				lum := (299*int(r>>8) + 587*int(g>>8) + 114*int(b>>8)) / 1000
				if lum < 128 {
					out.Pix[y*out.Stride+x] = 0
				} else {
					out.Pix[y*out.Stride+x] = 255
				}
			}
		}
		return out
	}

	buf := make([]float64, w*h)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			r, g, b, _ := src.At(x, y).RGBA()
			lum := 0.2126*float64(r>>8) + 0.7152*float64(g>>8) + 0.0722*float64(b>>8)
			buf[y*w+x] = 255 * math.Pow(lum/255, 2.2)
		}
	}

	atkinson := strings.EqualFold(mode, "atkinson")
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			i := y*w + x
			old := buf[i]
			var newVal float64
			if old >= 127.5 {
				newVal = 255
				out.Pix[y*out.Stride+x] = 255
			} else {
				newVal = 0
				out.Pix[y*out.Stride+x] = 0
			}
			err := old - newVal
			if atkinson {
				// 6/8 of the error to six neighbours, 1/8 each
				addErr := func(dx, dy int, f float64) {
					nx, ny := x+dx, y+dy
					if nx >= 0 && nx < w && ny >= 0 && ny < h {
						buf[ny*w+nx] += err * f
					}
				}
				addErr(1, 0, 1.0/8)
				addErr(2, 0, 1.0/8)
				addErr(-1, 1, 1.0/8)
				addErr(0, 1, 1.0/8)
				addErr(1, 1, 1.0/8)
				addErr(0, 2, 1.0/8)
				continue
			}
			// Floyd-Steinberg
			spread := func(dx, dy int, f float64) {
				nx, ny := x+dx, y+dy
				if nx >= 0 && nx < w && ny >= 0 && ny < h {
					buf[ny*w+nx] += err * f
				}
			}
			spread(1, 0, 7.0/16)
			spread(-1, 1, 3.0/16)
			spread(0, 1, 5.0/16)
			spread(1, 1, 1.0/16)
		}
	}
	return out
}
