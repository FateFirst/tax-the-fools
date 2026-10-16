package luasv

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

// ParseError carries the line of the problem.
type ParseError struct {
	Line int
	Msg  string
}

func (e *ParseError) Error() string { return fmt.Sprintf("line %d: %s", e.Line, e.Msg) }

type parser struct {
	src  []byte
	pos  int
	line int
}

func (p *parser) fail(format string, a ...interface{}) error {
	return &ParseError{p.line, fmt.Sprintf(format, a...)}
}

// Parse reads top-level `NAME = value` assignments.
func Parse(src []byte) (map[string]Value, error) {
	p := &parser{src: src, line: 1}
	out := map[string]Value{}
	for {
		if err := p.skip(); err != nil {
			return nil, err
		}
		if p.pos >= len(p.src) {
			return out, nil
		}
		if p.src[p.pos] == ';' {
			p.pos++
			continue
		}
		name := p.ident()
		if name == "" {
			return nil, p.fail("expected a variable name, found %s", p.near())
		}
		if err := p.skip(); err != nil {
			return nil, err
		}
		if p.pos >= len(p.src) || p.src[p.pos] != '=' || (p.pos+1 < len(p.src) && p.src[p.pos+1] == '=') {
			return nil, p.fail("expected '=' after %s", name)
		}
		p.pos++
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		out[name] = v
	}
}

func (p *parser) near() string {
	if p.pos >= len(p.src) {
		return "end of file"
	}
	end := p.pos + 10
	if end > len(p.src) {
		end = len(p.src)
	}
	return strconv.Quote(string(p.src[p.pos:end]))
}

func isIdentStart(c byte) bool { return c == '_' || (c|0x20 >= 'a' && c|0x20 <= 'z') }
func isDigit(c byte) bool      { return c >= '0' && c <= '9' }

func (p *parser) ident() string {
	s := p.pos
	if p.pos < len(p.src) && isIdentStart(p.src[p.pos]) {
		p.pos++
		for p.pos < len(p.src) && (isIdentStart(p.src[p.pos]) || isDigit(p.src[p.pos])) {
			p.pos++
		}
	}
	return string(p.src[s:p.pos])
}

// longBracket checks for [=*[ at pos and returns its level, or -1.
func (p *parser) longBracket() int {
	i := p.pos
	if i >= len(p.src) || p.src[i] != '[' {
		return -1
	}
	i++
	lvl := 0
	for i < len(p.src) && p.src[i] == '=' {
		lvl++
		i++
	}
	if i < len(p.src) && p.src[i] == '[' {
		return lvl
	}
	return -1
}

func (p *parser) longString(lvl int) (string, error) {
	start := p.line
	p.pos += lvl + 2
	if p.pos < len(p.src) && p.src[p.pos] == '\r' {
		p.pos++
	}
	if p.pos < len(p.src) && p.src[p.pos] == '\n' {
		p.pos++
		p.line++
	}
	closer := "]" + strings.Repeat("=", lvl) + "]"
	rest := string(p.src[p.pos:])
	i := strings.Index(rest, closer)
	if i < 0 {
		p.line = start
		return "", p.fail("unfinished long string")
	}
	body := rest[:i]
	p.line += strings.Count(body, "\n")
	p.pos += i + len(closer)
	return body, nil
}

// skip passes whitespace and comments.
func (p *parser) skip() error {
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		switch {
		case c == '\n':
			p.line++
			p.pos++
		case c == ' ' || c == '\t' || c == '\r':
			p.pos++
		case c == '-' && p.pos+1 < len(p.src) && p.src[p.pos+1] == '-':
			p.pos += 2
			if lvl := p.longBracket(); lvl >= 0 {
				if _, err := p.longString(lvl); err != nil {
					return p.fail("unfinished long comment")
				}
				continue
			}
			for p.pos < len(p.src) && p.src[p.pos] != '\n' {
				p.pos++
			}
		default:
			return nil
		}
	}
	return nil
}

func (p *parser) value() (Value, error) {
	if err := p.skip(); err != nil {
		return nil, err
	}
	if p.pos >= len(p.src) {
		return nil, p.fail("expected a value, found end of file")
	}
	c := p.src[p.pos]
	switch {
	case c == '{':
		return p.table()
	case c == '"' || c == '\'':
		return p.quoted(c)
	case c == '[':
		if lvl := p.longBracket(); lvl >= 0 {
			return p.longString(lvl)
		}
	case c == '-' || c == '+' || isDigit(c) || c == '.':
		return p.number()
	case isIdentStart(c):
		w := p.ident()
		switch w {
		case "nil":
			return nil, nil
		case "true":
			return true, nil
		case "false":
			return false, nil
		}
		return nil, p.fail("unexpected name %q (only nil, true and false are allowed)", w)
	}
	return nil, p.fail("unexpected %s", p.near())
}

func (p *parser) number() (Value, error) {
	s := p.pos
	if p.src[p.pos] == '-' || p.src[p.pos] == '+' {
		p.pos++
	}
	hex := p.pos+1 < len(p.src) && p.src[p.pos] == '0' && (p.src[p.pos+1]|0x20) == 'x'
	if hex {
		p.pos += 2
	}
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		isExp := !hex && (c|0x20) == 'e'
		if isDigit(c) || c == '.' || (hex && ((c|0x20) >= 'a' && (c|0x20) <= 'f')) || isExp {
			p.pos++
			if isExp && p.pos < len(p.src) && (p.src[p.pos] == '-' || p.src[p.pos] == '+') {
				p.pos++
			}
			continue
		}
		break
	}
	txt := string(p.src[s:p.pos])
	if hex {
		neg := strings.HasPrefix(txt, "-")
		u, err := strconv.ParseUint(strings.TrimLeft(txt, "+-")[2:], 16, 64)
		if err != nil {
			return nil, p.fail("malformed number %q", txt)
		}
		f := float64(u)
		if neg {
			f = -f
		}
		return f, nil
	}
	f, err := strconv.ParseFloat(txt, 64)
	if err != nil {
		if ne, ok := err.(*strconv.NumError); ok && ne.Err == strconv.ErrRange {
			return f, nil // 1e999 is +Inf
		}
		return nil, p.fail("malformed number %q", txt)
	}
	if math.IsNaN(f) {
		return nil, p.fail("malformed number %q", txt)
	}
	return f, nil
}

func (p *parser) quoted(q byte) (Value, error) {
	p.pos++
	var b []byte
	for {
		if p.pos >= len(p.src) {
			return nil, p.fail("unfinished string")
		}
		c := p.src[p.pos]
		switch {
		case c == q:
			p.pos++
			return string(b), nil
		case c == '\n':
			return nil, p.fail("unfinished string (newline in a quoted string)")
		case c == '\\':
			p.pos++
			if p.pos >= len(p.src) {
				return nil, p.fail("unfinished string")
			}
			e := p.src[p.pos]
			p.pos++
			switch e {
			case 'a':
				b = append(b, 7)
			case 'b':
				b = append(b, 8)
			case 'f':
				b = append(b, 12)
			case 'n':
				b = append(b, '\n')
			case 'r':
				b = append(b, '\r')
			case 't':
				b = append(b, '\t')
			case 'v':
				b = append(b, 11)
			case '\\', '"', '\'':
				b = append(b, e)
			case '\n':
				b = append(b, '\n')
				p.line++
			default:
				if !isDigit(e) {
					return nil, p.fail("invalid escape \\%c", e)
				}
				n := int(e - '0')
				for i := 0; i < 2 && p.pos < len(p.src) && isDigit(p.src[p.pos]); i++ {
					n = n*10 + int(p.src[p.pos]-'0')
					p.pos++
				}
				if n > 255 {
					return nil, p.fail("escape sequence \\%d is too large", n)
				}
				b = append(b, byte(n))
			}
		default:
			b = append(b, c)
			p.pos++
		}
	}
}

func (p *parser) table() (Value, error) {
	open := p.line
	p.pos++
	t := NewTable()
	next := 1.0
	for {
		if err := p.skip(); err != nil {
			return nil, err
		}
		if p.pos >= len(p.src) {
			return nil, &ParseError{open, "unfinished table (opened here)"}
		}
		c := p.src[p.pos]
		if c == '}' {
			p.pos++
			return t, nil
		}
		var key Value
		isKeyed := false
		if c == '[' && p.longBracket() < 0 {
			p.pos++
			k, err := p.value()
			if err != nil {
				return nil, err
			}
			if err := p.skip(); err != nil {
				return nil, err
			}
			if p.pos >= len(p.src) || p.src[p.pos] != ']' {
				return nil, p.fail("expected ']'")
			}
			p.pos++
			switch k.(type) {
			case string, float64:
			default:
				return nil, p.fail("a table key must be a string or a number")
			}
			if err := p.skip(); err != nil {
				return nil, err
			}
			if p.pos >= len(p.src) || p.src[p.pos] != '=' {
				return nil, p.fail("expected '=' after key")
			}
			p.pos++
			key, isKeyed = k, true
		} else if isIdentStart(c) {
			save, saveLine := p.pos, p.line
			name := p.ident()
			if err := p.skip(); err != nil {
				return nil, err
			}
			if p.pos < len(p.src) && p.src[p.pos] == '=' && !(p.pos+1 < len(p.src) && p.src[p.pos+1] == '=') {
				p.pos++
				key, isKeyed = name, true
			} else {
				p.pos, p.line = save, saveLine
			}
		}
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		if isKeyed {
			t.Set(key, v)
		} else {
			t.Set(next, v)
			next++
		}
		if err := p.skip(); err != nil {
			return nil, err
		}
		if p.pos < len(p.src) && (p.src[p.pos] == ',' || p.src[p.pos] == ';') {
			p.pos++
			continue
		}
		if p.pos < len(p.src) && p.src[p.pos] == '}' {
			continue
		}
		if p.pos >= len(p.src) {
			return nil, &ParseError{open, "unfinished table (opened here)"}
		}
		return nil, p.fail("expected ',' or '}' in table, found %s", p.near())
	}
}
