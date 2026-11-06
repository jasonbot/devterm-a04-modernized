package main

import (
	"fmt"
	"image/color"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	extast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/text"
)

type styledRun struct {
	text   string
	face   *textFace
	bold   bool // synthetic: draw twice
	italic bool
}

type mdLine struct {
	runs []styledRun
	x    int  // left indent in dots
	bar  bool // vertical rule (block quote / code)
	rule bool // horizontal rule
	gap  int  // space before this line
}

type mdRenderer struct {
	o        options
	body     *textFace
	bodyBold *textFace
	bodyItal *textFace
	mono     *textFace
	h1       *textFace
	h2       *textFace
	h3       *textFace
	boldOK   bool
	italOK   bool
	lines    []mdLine
	width    int
}

type fontSet struct {
	base     FontEntry
	body     *textFace
	bold     *textFace
	italic   *textFace
	mono     *textFace
	h1       *textFace
	h2       *textFace
	h3       *textFace
	boldOK   bool
	italicOK bool
}

func loadFontSet(o options) (*fontSet, error) {
	dirs := append(defaultFontDirs, splitList(o.fontDirs)...)
	base, err := resolveFont(o.font, dirs)
	if err != nil {
		return nil, err
	}
	idx, err := buildFontIndex(dirs)
	if err != nil {
		return nil, err
	}
	size := float64(o.size)
	fs := &fontSet{base: base}
	if fs.body, err = newTextFace(base, size); err != nil {
		return nil, err
	}
	if e, ok := siblingFor(idx, base, true, false); ok {
		fs.bold, _ = newTextFace(e, size)
	}
	if e, ok := siblingFor(idx, base, false, true); ok {
		fs.italic, _ = newTextFace(e, size)
	}
	fs.boldOK = fs.bold != nil
	fs.italicOK = fs.italic != nil
	monoEntry, ok := monoFamily(idx, base)
	if !ok {
		monoEntry = base
	}
	if fs.mono, err = newTextFace(monoEntry, size*0.95); err != nil {
		return nil, err
	}
	if fs.h1, err = newTextFace(base, size*1.7); err != nil {
		return nil, err
	}
	if fs.h2, err = newTextFace(base, size*1.4); err != nil {
		return nil, err
	}
	if fs.h3, err = newTextFace(base, size*1.15); err != nil {
		return nil, err
	}
	return fs, nil
}

func newMDRenderer(o options) (*mdRenderer, error) {
	fs, err := loadFontSet(o)
	if err != nil {
		return nil, err
	}
	return &mdRenderer{
		o: o, body: fs.body, bodyBold: fs.bold, bodyItal: fs.italic, mono: fs.mono,
		h1: fs.h1, h2: fs.h2, h3: fs.h3, boldOK: fs.boldOK, italOK: fs.italicOK,
		width: o.width - 16,
	}, nil
}

func renderMarkdown(o options, files []string) (*Canvas, error) {
	var src []byte
	if len(files) == 0 {
		b, err := io.ReadAll(os.Stdin)
		if err != nil {
			return nil, err
		}
		src = b
	} else {
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				return nil, err
			}
			src = append(src, b...)
			src = append(src, '\n', '\n')
		}
	}
	r, err := newMDRenderer(o)
	if err != nil {
		return nil, err
	}
	doc := goldmark.New(goldmark.WithExtensions(extension.GFM)).Parser().
		Parse(text.NewReader(src))
	r.walk(doc, src, 0)
	return r.draw()
}

func (r *mdRenderer) walk(n ast.Node, src []byte, indent int) {
	switch node := n.(type) {
	case *ast.Heading:
		face := r.h1
		switch node.Level {
		case 2:
			face = r.h2
		case 3, 4, 5, 6:
			face = r.h3
		}
		r.emitParagraph(r.inline(node, src, face), indent, 10)
	case *ast.Paragraph:
		r.emitParagraph(r.inline(node, src, r.body), indent, 6)
	case *ast.TextBlock:
		r.emitParagraph(r.inline(node, src, r.body), indent, 0)
	case *ast.Blockquote:
		r.walkChildren(node, src, indent+8, true)
	case *ast.List:
		r.walkList(node, src, indent)
	case *ast.FencedCodeBlock, *ast.CodeBlock:
		r.emitCode(n, src, indent)
	case *ast.ThematicBreak:
		r.lines = append(r.lines, mdLine{rule: true, gap: 8})
	case *ast.HTMLBlock:
		// raw HTML is ignored
	case *extast.Table:
		r.walkTable(node, src)
	default:
		r.walkChildren(n, src, indent, false)
	}
}

func (r *mdRenderer) walkChildren(n ast.Node, src []byte, indent int, bar bool) {
	for c := n.FirstChild(); c != nil; c = c.NextSibling() {
		start := len(r.lines)
		r.walk(c, src, indent)
		if bar {
			for i := start; i < len(r.lines); i++ {
				r.lines[i].bar = true
			}
		}
	}
}

func (r *mdRenderer) walkList(n *ast.List, src []byte, indent int) {
	num := n.Start
	if num == 0 {
		num = 1
	}
	for item := n.FirstChild(); item != nil; item = item.NextSibling() {
		marker := "• "
		if n.IsOrdered() {
			marker = strconv.Itoa(num) + ". "
			num++
		}
		start := len(r.lines)
		for c := item.FirstChild(); c != nil; c = c.NextSibling() {
			isPara := false
			switch c.(type) {
			case *ast.Paragraph, *ast.TextBlock:
				isPara = true
			}
			if isPara && len(r.lines) == start {
				runs := r.inline(c, src, r.body)
				if len(runs) > 0 {
					runs[0].text = marker + runs[0].text
				} else {
					runs = []styledRun{{text: marker, face: r.body}}
				}
				r.emitParagraph(runs, indent+4, 4)
				continue
			}
			switch c.(type) {
			case *ast.List:
				r.walkList(c.(*ast.List), src, indent+12)
			default:
				r.walk(c, src, indent+12)
			}
		}
		if len(r.lines) == start {
			r.lines = append(r.lines, mdLine{x: indent + 4, gap: 4})
		}
	}
}

func (r *mdRenderer) emitCode(n ast.Node, src []byte, indent int) {
	var b strings.Builder
	lines := n.Lines()
	for i := 0; i < lines.Len(); i++ {
		seg := lines.At(i)
		b.Write(seg.Value(src))
	}
	text := strings.TrimRight(b.String(), "\n")
	for _, ln := range strings.Split(text, "\n") {
		for _, part := range wrapRunes(r.mono, strings.ReplaceAll(ln, "\t", "    "), r.width-indent-8) {
			r.lines = append(r.lines, mdLine{
				runs: []styledRun{{text: part, face: r.mono}},
				x:    indent + 8, bar: true, gap: 1,
			})
		}
	}
	r.lines = append(r.lines, mdLine{gap: 6})
}

func (r *mdRenderer) walkTable(n ast.Node, src []byte) {
	first := true
	for c := n.FirstChild(); c != nil; c = c.NextSibling() {
		var cells []string
		for cell := c.FirstChild(); cell != nil; cell = cell.NextSibling() {
			cells = append(cells, plainText(cell, src))
		}
		for _, part := range wrapRunes(r.body, strings.Join(cells, " │ "), r.width-8) {
			r.lines = append(r.lines, mdLine{
				runs: []styledRun{{text: part, face: r.body}}, x: 4, gap: 1,
			})
		}
		if first {
			r.lines = append(r.lines, mdLine{rule: true, gap: 0})
			first = false
		}
	}
	r.lines = append(r.lines, mdLine{gap: 6})
}

func plainText(n ast.Node, src []byte) string {
	var b strings.Builder
	var walk func(ast.Node)
	walk = func(n ast.Node) {
		switch t := n.(type) {
		case *ast.Text:
			seg := t.Segment
			b.Write(seg.Value(src))
		case *ast.String:
			b.Write(t.Value)
		case *ast.AutoLink:
			b.Write(t.URL(src))
		}
		for c := n.FirstChild(); c != nil; c = c.NextSibling() {
			walk(c)
		}
	}
	walk(n)
	return strings.TrimSpace(b.String())
}

func (r *mdRenderer) inline(n ast.Node, src []byte, face *textFace) []styledRun {
	var runs []styledRun
	var walk func(ast.Node, bool, bool)
	walk = func(n ast.Node, bold, italic bool) {
		switch t := n.(type) {
		case *ast.Text:
			seg := t.Segment
			runs = r.addRun(runs, string(seg.Value(src)), face, bold, italic)
		case *ast.String:
			runs = r.addRun(runs, string(t.Value), face, bold, italic)
		case *ast.CodeSpan:
			runs = r.addRun(runs, plainText(t, src), r.mono, bold, italic)
			return
		case *ast.Emphasis:
			if t.Level >= 2 {
				bold = true
			} else {
				italic = true
			}
		case *ast.Image:
			alt := plainText(t, src)
			if alt == "" {
				alt = "image"
			}
			runs = r.addRun(runs, "[image: "+alt+"]", face, bold, italic)
			return
		case *ast.AutoLink:
			runs = r.addRun(runs, string(t.URL(src)), face, bold, italic)
			return
		case *ast.RawHTML:
			return
		}
		for c := n.FirstChild(); c != nil; c = c.NextSibling() {
			walk(c, bold, italic)
		}
		if l, ok := n.(*ast.Link); ok {
			dest := string(l.Destination)
			if dest != "" && !strings.HasPrefix(dest, "#") && !strings.Contains(dest, plainText(l, src)) {
				runs = r.addRun(runs, " ("+dest+")", face, false, false)
			}
		}
	}
	walk(n, false, false)
	return runs
}

func (r *mdRenderer) addRun(runs []styledRun, s string, face *textFace, bold, italic bool) []styledRun {
	s = strings.ReplaceAll(strings.ReplaceAll(s, "\n", " "), "\t", "    ")
	if s == "" {
		return runs
	}
	if bold && r.boldOK {
		face = r.bodyBold
	}
	if italic && r.italOK {
		face = r.bodyItal
	}
	return append(runs, styledRun{text: s, face: face,
		bold: bold && !r.boldOK, italic: italic && !r.italOK})
}

// emitParagraph wraps the runs to the content width and appends them.
func (r *mdRenderer) emitParagraph(runs []styledRun, indent, gap int) {
	limit := r.o.width - 8 - indent
	type word struct {
		text   string
		face   *textFace
		bold   bool
		italic bool
		space  bool
	}
	var words []word
	pendingSpace := false
	for _, run := range runs {
		parts := strings.Split(run.text, " ")
		for i, p := range parts {
			if p == "" {
				continue
			}
			words = append(words, word{
				text: p, face: run.face, bold: run.bold, italic: run.italic,
				space: pendingSpace || i > 0,
			})
			pendingSpace = false
		}
		if strings.HasSuffix(run.text, " ") {
			pendingSpace = true
		}
	}
	if len(words) == 0 {
		r.lines = append(r.lines, mdLine{gap: gap})
		return
	}
	var line []styledRun
	width := 0
	flush := func() {
		if len(line) > 0 {
			r.lines = append(r.lines, mdLine{runs: line, x: indent, gap: gap})
			gap = 2
			line = nil
			width = 0
		}
	}
	for _, w := range words {
		text := w.text
		w0 := w.face.measure(text).Ceil()
		sp := 0
		if w.space && width > 0 {
			sp = w.face.measure(" ").Ceil()
		}
		if width+sp+w0 > limit && width > 0 {
			flush()
			sp = 0
		}
		if sp > 0 {
			text = " " + text
		}
		line = append(line, styledRun{text: text, face: w.face, bold: w.bold, italic: w.italic})
		width += sp + w0
	}
	flush()
}

func wrapRunes(f *textFace, s string, limit int) []string {
	if limit <= 0 || s == "" {
		return []string{s}
	}
	var out []string
	var cur strings.Builder
	w := 0
	for _, r := range s {
		rw := f.advance(r).Ceil()
		if w+rw > limit && cur.Len() > 0 {
			out = append(out, cur.String())
			cur.Reset()
			w = 0
		}
		cur.WriteRune(r)
		w += rw
	}
	out = append(out, cur.String())
	return out
}

func (r *mdRenderer) draw() (*Canvas, error) {
	c := NewCanvas(r.o.width)
	margin := 8
	lineHeight := func(f *textFace) int {
		m := f.metrics()
		return (m.Ascent + m.Descent).Ceil() + 4
	}
	y := 0
	for _, line := range r.lines {
		y += line.gap
		if line.rule {
			y += 2
			c.ensure(y + 2)
			c.fill(margin, y, r.o.width-2*margin, 1, color.Black)
			y += 4
			continue
		}
		if len(line.runs) == 0 {
			continue
		}
		maxFace := line.runs[0].face
		for _, run := range line.runs {
			if run.face.metrics().Ascent > maxFace.metrics().Ascent {
				maxFace = run.face
			}
		}
		h := lineHeight(maxFace)
		baseline := y + maxFace.metrics().Ascent.Ceil()
		c.ensure(y + h + 2)
		if line.bar {
			c.fill(margin-4, y, 2, h, color.Black)
		}
		x := line.x
		for _, run := range line.runs {
			run.face.draw(c, x, baseline, run.text)
			if run.bold {
				run.face.draw(c, x+1, baseline, run.text)
			}
			x += run.face.measure(run.text).Ceil()
		}
		y += h
	}
	if y == 0 {
		c.ensure(8)
	}
	return c, nil
}

func testPage(o options) *Canvas {
	fs, err := loadFontSet(o)
	if err != nil {
		fmt.Fprintln(os.Stderr, "devterm-print:", err)
		os.Exit(1)
	}
	c := NewCanvas(o.width)
	h := 40 + o.size*5
	c.ensure(h)
	// left and right edge markers: a filled block on each side tells us the
	// bit order and the head registration.
	c.fill(0, 0, 8, 8, color.Black)
	c.fill(o.width-8, 0, 8, 8, color.Black)
	for x := 0; x < o.width; x += 8 {
		c.fill(x, 12, 1, 6, color.Black)
	}
	baseline := 30 + fs.body.metrics().Ascent.Ceil()
	fs.body.draw(c, 2, baseline, "left 0")
	label := "right " + strconv.Itoa(o.width-1)
	fs.body.draw(c, o.width-2-fs.body.measure(label).Ceil(), baseline, label)
	baseline += fs.body.metrics().Height.Ceil() + 4
	fs.body.draw(c, 2, baseline, "abcdefghijklmnopqrstuvwxyz")
	baseline += fs.body.metrics().Height.Ceil() + 4
	fs.body.draw(c, 2, baseline, "0123456789 !@#$%^&*()")
	baseline += fs.body.metrics().Height.Ceil() + 4
	fs.mono.draw(c, 2, baseline, "mono 0123456789")
	return c
}

// solidPage is the hardware check: a full-width black block means the head,
// its voltage rail and the paper coating are all working.  A blank strip means
// one of them is not.
func solidPage(o options) *Canvas {
	fs, _ := loadFontSet(o)
	c := NewCanvas(o.width)
	rows := 96
	c.ensure(rows + 40)
	c.fill(0, 0, o.width, rows, color.Black)
	if fs != nil {
		label := "SOLID"
		w := fs.body.measure(label).Ceil()
		fs.body.drawInk(c, (o.width-w)/2, rows+fs.body.metrics().Ascent.Ceil()+8, label, color.Black)
	}
	return c
}
