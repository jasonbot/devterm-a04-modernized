package main

import "fmt"

// decodeBase4 turns a base-4 payload (characters '0'..'3', whitespace ignored)
// into bytes, four symbols per byte, most significant pair first.  This lets a
// binary payload travel through a shell or a chat message and still be printed
// as a QR code.
func decodeBase4(s string) ([]byte, error) {
	var nibbles []byte
	for _, r := range s {
		switch r {
		case '0', '1', '2', '3':
			nibbles = append(nibbles, byte(r-'0'))
		case ' ', '\t', '\r', '\n', '-', '_', ':':
			// separators are ignored
		default:
			return nil, fmt.Errorf("invalid base-4 character %q (expected 0-3)", r)
		}
	}
	if len(nibbles) == 0 {
		return nil, fmt.Errorf("empty base-4 payload")
	}
	if len(nibbles)%4 != 0 {
		return nil, fmt.Errorf("base-4 payload has %d symbols; a whole number of bytes needs a multiple of 4", len(nibbles))
	}
	out := make([]byte, 0, len(nibbles)/4)
	for i := 0; i < len(nibbles); i += 4 {
		b := nibbles[i]<<6 | nibbles[i+1]<<4 | nibbles[i+2]<<2 | nibbles[i+3]
		out = append(out, b)
	}
	return out, nil
}
