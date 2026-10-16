package luasv

import (
	"bytes"
	"fmt"
	"math"
	"sort"
	"strconv"
)

// Write serialises the named variables in order, in the client's format.
// A name missing from vars is written as nil. If names is nil, all variables
// are written sorted by name.
func Write(vars map[string]Value, names []string) ([]byte, error) {
	if names == nil {
		for n := range vars {
			names = append(names, n)
		}
		sort.Strings(names)
	}
	var b bytes.Buffer
	for _, n := range names {
		b.WriteString(n)
		b.WriteString(" = ")
		if err := writeValue(&b, vars[n], 0); err != nil {
			return nil, fmt.Errorf("%s: %w", n, err)
		}
		b.WriteByte('\n')
	}
	return b.Bytes(), nil
}

// FormatNumber renders a number the way Write does.
func FormatNumber(f float64) string {
	switch {
	case math.IsInf(f, 1):
		return "1e999"
	case math.IsInf(f, -1):
		return "-1e999"
	case f == math.Trunc(f) && math.Abs(f) < 1e15:
		if f == 0 {
			return "0"
		}
		return strconv.FormatInt(int64(f), 10)
	}
	return strconv.FormatFloat(f, 'g', -1, 64)
}

func quote(b *bytes.Buffer, s string) {
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\':
			b.WriteString(`\\`)
		case c == '"':
			b.WriteString(`\"`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c < 32 || c == 127:
			fmt.Fprintf(b, `\%03d`, c)
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
}

func writeValue(b *bytes.Buffer, v Value, depth int) error {
	switch x := v.(type) {
	case nil:
		b.WriteString("nil")
	case bool:
		if x {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case float64:
		if math.IsNaN(x) {
			return fmt.Errorf("cannot write NaN")
		}
		b.WriteString(FormatNumber(x))
	case string:
		quote(b, x)
	case *Table:
		if x == nil || len(x.Entries) == 0 {
			b.WriteString("{\n")
			for i := 0; i < depth; i++ {
				b.WriteByte('\t')
			}
			b.WriteString("}")
			return nil
		}
		b.WriteString("{\n")
		for _, e := range x.Sorted() {
			for i := 0; i <= depth; i++ {
				b.WriteByte('\t')
			}
			b.WriteByte('[')
			switch k := e.Key.(type) {
			case string:
				quote(b, k)
			case float64:
				b.WriteString(FormatNumber(k))
			default:
				return fmt.Errorf("bad key type %T", e.Key)
			}
			b.WriteString("] = ")
			if err := writeValue(b, e.Val, depth+1); err != nil {
				return err
			}
			b.WriteString(",\n")
		}
		for i := 0; i < depth; i++ {
			b.WriteByte('\t')
		}
		b.WriteString("}")
	default:
		return fmt.Errorf("unsupported value type %T", v)
	}
	return nil
}
