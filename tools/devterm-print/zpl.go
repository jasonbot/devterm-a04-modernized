package main

import (
	"fmt"
	"image/color"
	"strconv"
	"strings"

	"github.com/boombuler/barcode/code128"
	"github.com/boombuler/barcode/qr"
)

// renderZPL approximates the parts of ZPL II that labels actually use: label
// and field origins, scalable text fields, graphic boxes, Code 128 and QR
// barcodes, copies and reverse print.  Unknown commands are ignored so real
// label files still come out recognisable.
func renderZPL(o options, src []byte) (*Canvas, error) {
	st := &zplState{o: o, width: o.width, fontH: 24, module: 2, copies: 1}
	st.reset()
	s := string(src)
	for i := 0; i < len(s); {
		if s[i] != '^' || i+3 > len(s) {
			i++
			continue
		}
		name := s[i+1 : i+3]
		i += 3
		if name == "FD" {
			// field data runs until ^FS and may contain anything
			end := strings.Index(s[i:], "^FS")
			data := s[i:]
			if end >= 0 {
				data = s[i : i+end]
				i += end + 3
			} else {
				i = len(s)
			}
			st.field(data)
			continue
		}
		end := strings.IndexByte(s[i:], '^')
		params := s[i:]
		if end >= 0 {
			params = s[i : i+end]
			i += end
		} else {
			i = len(s)
		}
		if err := st.command(name, params); err != nil {
			return nil, err
		}
	}
	return st.finish()
}

type zplState struct {
	o      options
	width  int
	fontH  int
	fontW  int
	module int
	copies int

	x, y    int
	barKind string // "", "BC", "BQ"
	barH    int
	barEC   qr.ErrorCorrectionLevel
	reverse bool
	canvas  *Canvas
}

func (st *zplState) reset() {
	st.x, st.y = 0, 0
	st.barKind = ""
	st.reverse = false
	st.canvas = NewCanvas(st.width)
}

func (st *zplState) command(name, params string) error {
	args := strings.Split(params, ",")
	atoi := func(i, def int) int {
		if i >= len(args) {
			return def
		}
		v := strings.TrimSpace(args[i])
		if v == "" {
			return def
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return def
		}
		return n
	}
	switch name {
	case "XA":
		st.reset()
	case "XZ":
		// end of label: nothing more to do
	case "FO", "FT":
		st.x, st.y = atoi(0, 0), atoi(1, 0)
	case "A0", "A":
		h := atoi(1, 24)
		if h <= 0 {
			h = 24
		}
		st.fontH = h
		st.fontW = atoi(2, 0)
	case "AY":
		// font name only, keep the size
	case "GB":
		w, h := atoi(0, 0), atoi(1, 0)
		t := atoi(2, 1)
		st.box(w, h, t)
	case "BY":
		if m := atoi(0, 2); m > 0 {
			st.module = m
		}
	case "BC":
		st.barKind = "BC"
		st.barH = atoi(1, 40)
		st.reverse = false
	case "BQ":
		st.barKind = "BQ"
		st.barH = atoi(1, 2) // magnification
		st.barEC = qr.M
		switch atoi(3, 3) {
		case 1:
			st.barEC = qr.H
		case 2:
			st.barEC = qr.Q
		case 4:
			st.barEC = qr.L
		}
	case "FR":
		st.reverse = true
	case "PQ":
		if n := atoi(0, 1); n > 0 {
			st.copies = n
		}
	case "PW":
		if w := atoi(0, 0); w > 0 {
			st.width = min(w, printerWidth)
			st.canvas.W = st.width
		}
	case "LL", "LH", "CI", "MM", "MT", "MD", "PR", "JM", "LS", "CW", "FX", "CF", "FS", "JJ", "MN", "PM", "SN", "WD":
		// accepted and ignored
	case "XG", "XF", "JB", "GF", "ID", "DF", "DG", "IS", "SQ", "FXA":
		// graphics/objects we do not approximate
	default:
		// unknown command: ignore
	}
	return nil
}

func (st *zplState) field(data string) {
	switch st.barKind {
	case "BC":
		st.barcode128(data)
	case "BQ":
		st.qr(data)
	default:
		st.text(data)
	}
	st.barKind = ""
	st.reverse = false
}

func (st *zplState) text(s string) {
	fs, err := loadFontSet(st.o)
	if err != nil {
		return
	}
	face := fs.body
	if st.fontH != st.o.size {
		if f, err := newTextFace(fs.base, float64(st.fontH)); err == nil {
			face = f
		}
	}
	baseline := st.y + face.metrics().Ascent.Ceil()
	w := face.measure(s).Ceil()
	h := (face.metrics().Ascent + face.metrics().Descent).Ceil()
	if st.reverse {
		st.canvas.ensure(st.y + h + 2)
		st.canvas.fill(st.x, st.y, w+2, h+2, color.Black)
		face.drawInk(st.canvas, st.x+1, baseline, s, color.White)
		return
	}
	st.canvas.ensure(st.y + h + 2)
	face.draw(st.canvas, st.x, baseline, s)
}

func (st *zplState) box(w, h, t int) {
	if w <= 0 || h <= 0 {
		return
	}
	st.canvas.ensure(st.y + h + 2)
	if t <= 0 || t >= w || t >= h {
		st.canvas.fill(st.x, st.y, w, h, color.Black)
		return
	}
	col := color.Black
	st.canvas.fill(st.x, st.y, w, t, col)
	st.canvas.fill(st.x, st.y+h-t, w, t, col)
	st.canvas.fill(st.x, st.y, t, h, col)
	st.canvas.fill(st.x+w-t, st.y, t, h, col)
}

func (st *zplState) barcode128(data string) {
	bc, err := code128.Encode(data)
	if err != nil {
		return
	}
	b := bc.Bounds()
	scale := st.module
	if scale < 1 {
		scale = 1
	}
	h := st.barH
	if h <= 0 {
		h = 40
	}
	st.canvas.ensure(st.y + h + 2)
	for y := 0; y < h; y++ {
		for x := 0; x < b.Dx(); x++ {
			if isDark(bc.At(b.Min.X+x, b.Min.Y)) {
				st.canvas.fill(st.x+x*scale, st.y+y, scale, 1, color.Black)
			}
		}
	}
}

func (st *zplState) qr(data string) {
	mag := st.barH
	if mag <= 0 {
		mag = 2
	}
	bc, err := qr.Encode(data, st.barEC, qr.Auto)
	if err != nil {
		return
	}
	b := bc.Bounds()
	size := b.Dx() * mag
	st.canvas.ensure(st.y + size + 2)
	for y := 0; y < b.Dy(); y++ {
		for x := 0; x < b.Dx(); x++ {
			if isDark(bc.At(b.Min.X+x, b.Min.Y+y)) {
				st.canvas.fill(st.x+x*mag, st.y+y*mag, mag, mag, color.Black)
			}
		}
	}
}

func (st *zplState) finish() (*Canvas, error) {
	label := st.canvas
	if st.copies <= 1 {
		return label, nil
	}
	gap := 8
	total := NewCanvas(label.W)
	rows := label.Height()
	for i := 0; i < st.copies; i++ {
		total.ensure(i*(rows+gap) + rows)
		for y := 0; y < rows; y++ {
			copy(total.Img.Pix[(i*(rows+gap)+y)*total.Img.Stride:],
				label.Img.Pix[y*label.Img.Stride:y*label.Img.Stride+label.Img.Stride])
		}
	}
	return total, nil
}

func zplError(format string, a ...any) error { return fmt.Errorf(format, a...) }
