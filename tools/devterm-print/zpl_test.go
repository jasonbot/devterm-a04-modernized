package main

import "testing"

// Graphics only: no font is needed, so this runs anywhere.
func TestZPLGraphicsAndCopies(t *testing.T) {
	src := []byte("^XA^PW384^FO10,10^GB100,40,2^FS^FO10,80^GB50,50,60^FS^PQ2^XZ")
	c, err := renderZPL(options{width: printerWidth, size: 20}, src)
	if err != nil {
		t.Fatal(err)
	}
	if c.Height() < 100 {
		t.Fatalf("label too short: %d", c.Height())
	}
	// filled box at x=10..60, y=80..130 must be black in the middle
	if c.Img.Pix[100*c.Img.Stride+30] >= 128 {
		t.Fatal("filled box is not dark")
	}
	// two copies: the second label starts below the first
	one, _ := renderZPL(options{width: printerWidth, size: 20}, []byte("^XA^PW384^FO10,10^GB100,40,2^FS^XZ"))
	if c.Height() <= one.Height()+4 {
		t.Fatalf("copies did not add height: %d vs %d", c.Height(), one.Height())
	}
}
