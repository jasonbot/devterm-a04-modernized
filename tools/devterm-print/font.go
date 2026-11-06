package main

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/image/math/fixed"
)

var defaultFontDirs = []string{
	"/usr/local/share/fonts/nerd-fonts",
	"/usr/local/share/fonts",
	"/usr/share/fonts/truetype",
	"/usr/share/fonts/opentype",
	"/usr/share/fonts",
}

// FontEntry is one face inside a font file (a .ttc holds several).
type FontEntry struct {
	Path   string
	Index  int
	Family string
	Style  string // Regular, Bold, Italic, Bold Italic, ...
	Mono   bool
}

// FontIndex maps lower-case family names to every face found.
type FontIndex map[string][]FontEntry

func buildFontIndex(dirs []string) (FontIndex, error) {
	idx := FontIndex{}
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			ext := strings.ToLower(filepath.Ext(path))
			if ext != ".ttf" && ext != ".otf" && ext != ".ttc" {
				return nil
			}
			entries := readFontNames(path)
			for _, e := range entries {
				fam := strings.ToLower(e.Family)
				if fam != "" {
					idx[fam] = append(idx[fam], e)
				}
			}
			return nil
		})
		if err != nil && !os.IsNotExist(err) {
			return nil, err
		}
	}
	for k := range idx {
		sort.Slice(idx[k], func(i, j int) bool {
			return styleRank(idx[k][i].Style) < styleRank(idx[k][j].Style)
		})
	}
	return idx, nil
}

func styleRank(style string) int {
	s := strings.ToLower(style)
	switch {
	case s == "regular" || s == "":
		return 0
	case strings.Contains(s, "bold") && strings.Contains(s, "italic"):
		return 3
	case strings.Contains(s, "bold"):
		return 1
	case strings.Contains(s, "italic") || strings.Contains(s, "oblique"):
		return 2
	}
	return 4
}

// readFontNames reads only the sfnt table directory and the name table, so
// indexing a thousand installed fonts does not mean parsing a thousand glyph
// tables.
func readFontNames(path string) []FontEntry {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	head := make([]byte, 12)
	if _, err := f.ReadAt(head, 0); err != nil {
		return nil
	}
	var offsets []int64
	switch string(head[0:4]) {
	case "ttcf":
		n := int(be16(head[8:]))
		buf := make([]byte, n*4)
		if _, err := f.ReadAt(buf, 12); err != nil {
			return nil
		}
		for i := 0; i < n; i++ {
			offsets = append(offsets, int64(be32(buf[i*4:])))
		}
	default:
		offsets = []int64{0}
	}

	var out []FontEntry
	for i, off := range offsets {
		family, style := nameTable(f, off)
		if family == "" {
			continue
		}
		out = append(out, FontEntry{
			Path: path, Index: i, Family: family, Style: style,
			Mono: strings.Contains(strings.ToLower(family+" "+filepath.Base(path)), "mono"),
		})
	}
	return out
}

func be16(b []byte) uint16 { return uint16(b[0])<<8 | uint16(b[1]) }
func be32(b []byte) uint32 {
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}

// nameTable returns the family and subfamily names of the face at off.
func nameTable(f *os.File, off int64) (string, string) {
	dir := make([]byte, 12)
	if _, err := f.ReadAt(dir, off); err != nil {
		return "", ""
	}
	numTables := int(be16(dir[4:]))
	recs := make([]byte, numTables*16)
	if _, err := f.ReadAt(recs, off+12); err != nil {
		return "", ""
	}
	var nameOff, nameLen int64
	for i := 0; i < numTables; i++ {
		r := recs[i*16:]
		if string(r[0:4]) == "name" {
			nameOff = off + int64(be32(r[8:]))
			nameLen = int64(be32(r[12:]))
			break
		}
	}
	if nameOff == 0 || nameLen <= 0 || nameLen > 1<<20 {
		return "", ""
	}
	tbl := make([]byte, nameLen)
	if _, err := f.ReadAt(tbl, nameOff); err != nil {
		return "", ""
	}
	count := int(be16(tbl[2:]))
	strOff := int(be16(tbl[4:]))
	if 6+count*12 > len(tbl) {
		return "", ""
	}
	family, style := "", ""
	for i := 0; i < count; i++ {
		r := tbl[6+i*12:]
		platform := be16(r[0:])
		encoding := be16(r[2:])
		language := be16(r[4:])
		nameID := be16(r[6:])
		length := int(be16(r[8:]))
		offset := int(be16(r[10:]))
		if nameID != 1 && nameID != 2 {
			continue
		}
		if platform != 3 && platform != 0 && platform != 1 {
			continue
		}
		if platform == 3 && language != 0x409 && language != 0 {
			continue
		}
		start := strOff + offset
		if start < 0 || start+length > len(tbl) {
			continue
		}
		raw := tbl[start : start+length]
		var val string
		if platform == 3 || (platform == 0) {
			if len(raw)%2 != 0 {
				continue
			}
			rs := make([]rune, 0, len(raw)/2)
			for j := 0; j < len(raw); j += 2 {
				rs = append(rs, rune(be16(raw[j:])))
			}
			val = string(rs)
		} else {
			val = string(raw)
		}
		val = strings.TrimSpace(strings.TrimRight(val, "\x00"))
		if nameID == 1 && family == "" {
			family = val
		}
		if nameID == 2 && style == "" {
			style = val
		}
		_ = encoding
	}
	return family, style
}

func resolveFont(spec string, dirs []string) (FontEntry, error) {
	if spec == "" {
		spec = "PaperMono Nerd Font"
	}
	if _, err := os.Stat(spec); err == nil {
		entries := readFontNames(spec)
		if len(entries) == 0 {
			return FontEntry{}, fmt.Errorf("%s: no usable font faces", spec)
		}
		return entries[0], nil
	}
	idx, err := buildFontIndex(dirs)
	if err != nil {
		return FontEntry{}, err
	}
	want := strings.ToLower(strings.TrimSpace(spec))
	if list, ok := idx[want]; ok {
		return list[0], nil
	}
	var matches []string
	for fam := range idx {
		if strings.Contains(fam, want) || strings.Contains(want, fam) {
			matches = append(matches, fam)
		}
	}
	if len(matches) == 0 {
		var names []string
		for fam := range idx {
			names = append(names, fam)
		}
		sort.Strings(names)
		if len(names) > 6 {
			names = names[:6]
		}
		return FontEntry{}, fmt.Errorf("font %q not found (have: %s); use --font=/path/to/font.otf or --font-dir",
			spec, strings.Join(names, ", "))
	}
	sort.Slice(matches, func(i, j int) bool { return len(matches[i]) < len(matches[j]) })
	return idx[matches[0]][0], nil
}

// siblingFor returns a face of the same family with the wanted style bits.
func siblingFor(idx FontIndex, base FontEntry, bold, italic bool) (FontEntry, bool) {
	list := idx[strings.ToLower(base.Family)]
	for _, e := range list {
		s := strings.ToLower(e.Style)
		hasBold := strings.Contains(s, "bold")
		hasItalic := strings.Contains(s, "italic") || strings.Contains(s, "oblique")
		if hasBold == bold && hasItalic == italic {
			return e, true
		}
	}
	return FontEntry{}, false
}

// monoFamily returns the "Mono" sibling family for fonts that ship both
// proportional and monospaced variants (Nerd Fonts' Propo/Mono pairs).
func monoFamily(idx FontIndex, base FontEntry) (FontEntry, bool) {
	fam := strings.ToLower(base.Family)
	if strings.Contains(fam, "mono") {
		return base, true
	}
	for _, suffix := range []string{" mono", "mono"} {
		if list, ok := idx[fam+suffix]; ok {
			return list[0], true
		}
	}
	return FontEntry{}, false
}

// textFace wraps an opentype face with the advance logic used for layout.
type textFace struct {
	face font.Face
	// duospace forces a single advance for ASCII so tables and code line up
	// inside an otherwise proportional font.
	duo    bool
	duoAdv fixed.Int26_6
}

func newTextFace(e FontEntry, size float64) (*textFace, error) {
	f, err := loadSfnt(e)
	if err != nil {
		return nil, err
	}
	face, err := opentype.NewFace(f, &opentype.FaceOptions{Size: size, DPI: 72, Hinting: font.HintingFull})
	if err != nil {
		return nil, err
	}
	tf := &textFace{face: face}
	if adv, ok := face.GlyphAdvance('M'); ok {
		tf.duoAdv = adv
	}
	return tf, nil
}

func loadSfnt(e FontEntry) (*sfnt.Font, error) {
	ext := strings.ToLower(filepath.Ext(e.Path))
	if ext == ".ttc" {
		data, err := os.ReadFile(e.Path)
		if err != nil {
			return nil, err
		}
		coll, err := sfnt.ParseCollection(data)
		if err != nil {
			return nil, err
		}
		return coll.Font(e.Index)
	}
	data, err := os.ReadFile(e.Path)
	if err != nil {
		return nil, err
	}
	return sfnt.Parse(data)
}

func (t *textFace) metrics() font.Metrics { return t.face.Metrics() }

func (t *textFace) advance(r rune) fixed.Int26_6 {
	if t.duo && r >= 0x20 && r < 0x7f {
		return t.duoAdv
	}
	if adv, ok := t.face.GlyphAdvance(r); ok {
		return adv
	}
	return t.duoAdv
}

func (t *textFace) measure(s string) fixed.Int26_6 {
	var w fixed.Int26_6
	for _, r := range s {
		w += t.advance(r)
	}
	return w
}

// draw renders s with its left edge at x and baseline at y.
func (t *textFace) draw(c *Canvas, x, y int, s string) {
	t.drawInk(c, x, y, s, color.Black)
}

// drawInk renders s in the given colour, which is how reverse video fields
// paint white glyphs over a black box.
func (t *textFace) drawInk(c *Canvas, x, y int, s string, ink color.Color) {
	d := font.Drawer{
		Dst:  c.Img,
		Src:  image.NewUniform(ink),
		Face: t.face,
	}
	if !t.duo {
		d.Dot = fixed.P(x, y)
		d.DrawString(s)
		return
	}
	pen := fixed.P(x, y)
	for _, r := range s {
		d.Dot = pen
		d.DrawString(string(r))
		pen.X += t.advance(r)
	}
}
