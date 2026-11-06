package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

type options struct {
	qr      string
	qrB4    string
	qrLevel string
	zpl     string
	mdStdin bool
	test    bool
	solid   bool

	font     string
	fontDirs string
	size     int
	width    int
	duospace bool
	density  int
	feed     int
	band     int
	lsb      bool

	verbose bool

	printer string
	out     string
	png     string
}

func main() {
	var o options
	flag.StringVar(&o.qr, "qr", "", "print TEXT as a full-width QR code")
	flag.StringVar(&o.qrB4, "qr-b4", "", "print a QR whose bytes are the base-4 PAYLOAD (0-3 digits)")
	flag.StringVar(&o.qrLevel, "level", "m", "QR error correction: l, m, q or h")
	flag.StringVar(&o.zpl, "zpl", "", "render a ZPL file (\"-\" reads stdin)")
	flag.BoolVar(&o.mdStdin, "md", false, "render markdown from the given files, or stdin when none")
	flag.BoolVar(&o.test, "test", false, "print an alignment and legibility test page")
	flag.BoolVar(&o.solid, "solid", false, "print a solid black block (paper side / head check)")

	flag.StringVar(&o.font, "font", "", "font family or file (default: Paper Mono Nerd Font)")
	flag.StringVar(&o.fontDirs, "font-dir", "", "extra font directories, comma separated")
	flag.IntVar(&o.size, "size", 22, "body text size in dots")
	flag.IntVar(&o.width, "width", printerWidth, "print width in dots")
	flag.BoolVar(&o.duospace, "duospace", false, "force one advance for ASCII inside a proportional font")
	flag.IntVar(&o.density, "density", 6, "print density 0-15")
	flag.IntVar(&o.feed, "feed", 3, "lines to feed after printing")
	flag.IntVar(&o.band, "band", maxBandRows, "rows per bitmap command (max 65535)")
	flag.BoolVar(&o.lsb, "lsb", false, "pack dots least-significant-bit first (the A04 head wants MSB; kept for other units)")

	flag.BoolVar(&o.verbose, "v", false, "report the chosen font and page height on stderr")

	flag.StringVar(&o.printer, "printer", "/tmp/DEVTERM_PRINTER_IN", "printer device")
	flag.StringVar(&o.out, "out", "", "write the ESC/POS stream to this file instead of printing")
	flag.StringVar(&o.png, "png", "", "also write the rendered page as PNG")

	flag.Usage = usage
	flag.Parse()

	for _, a := range flag.Args() {
		if strings.HasPrefix(a, "-") {
			fmt.Fprintf(os.Stderr, "devterm-print: options must come before file names (got %q)\n", a)
			os.Exit(2)
		}
	}
	if err := run(o, flag.Args()); err != nil {
		fmt.Fprintln(os.Stderr, "devterm-print:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `devterm-print - print QR codes, markdown and ZPL on the DevTerm A04 printer

usage:
  devterm-print --qr="https://example.com"
  devterm-print --qr-b4=01230123...
  devterm-print README.md [more.md ...]
  devterm-print --zpl label.zpl
  devterm-print --test
  devterm-print --solid --density=15

options:
`)
	flag.PrintDefaults()
}

func run(o options, args []string) error {
	var canvas *Canvas
	var err error

	switch {
	case o.qr != "" && o.qrB4 != "":
		return fmt.Errorf("--qr and --qr-b4 are mutually exclusive")
	case o.qr != "":
		canvas, err = qrCanvas(o.qr, qrLevel(o.qrLevel), o.width)
	case o.qrB4 != "":
		payload, derr := decodeBase4(o.qrB4)
		if derr != nil {
			return derr
		}
		canvas, err = qrCanvas(string(payload), qrLevel(o.qrLevel), o.width)
	case o.zpl != "":
		canvas, err = renderZPL(o, readInput(o.zpl))
	case o.solid:
		canvas = solidPage(o)
	case o.test:
		canvas = testPage(o)
	default:
		canvas, err = renderMarkdown(o, args)
	}
	if err != nil {
		return err
	}

	data := escposPreamble(o.density)
	data = append(data, canvas.Encode(o.band, !o.lsb)...)
	data = append(data, escposFeed(o.feed)...)

	if o.verbose {
		fmt.Fprintf(os.Stderr, "devterm-print: %dx%d dots, %d bytes\n", canvas.W, canvas.Height(), len(data))
	}
	if o.png != "" {
		pngData, perr := canvas.PNG()
		if perr != nil {
			return perr
		}
		if werr := os.WriteFile(o.png, pngData, 0o644); werr != nil {
			return werr
		}
	}
	if o.out != "" {
		return os.WriteFile(o.out, data, 0o644)
	}
	return writePrinter(o.printer, data)
}

func readInput(path string) []byte {
	if path == "-" {
		b, _ := io.ReadAll(os.Stdin)
		return b
	}
	b, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "devterm-print:", err)
		os.Exit(1)
	}
	return b
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
