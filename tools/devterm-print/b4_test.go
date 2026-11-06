package main

import (
	"bytes"
	"testing"
)

func TestDecodeBase4(t *testing.T) {
	cases := []struct {
		in   string
		want []byte
		ok   bool
	}{
		{"0000", []byte{0x00}, true},
		{"3333", []byte{0xff}, true},
		{"0123", []byte{0x1b}, true},
		{"0123 0123\n", []byte{0x1b, 0x1b}, true},
		{"000", nil, false},
		{"00000", nil, false},
		{"0124", nil, false},
		{"", nil, false},
	}
	for _, c := range cases {
		got, err := decodeBase4(c.in)
		if c.ok && err != nil {
			t.Fatalf("%q: unexpected error %v", c.in, err)
		}
		if !c.ok {
			if err == nil {
				t.Fatalf("%q: expected an error", c.in)
			}
			continue
		}
		if !bytes.Equal(got, c.want) {
			t.Fatalf("%q: got %x want %x", c.in, got, c.want)
		}
	}
}
