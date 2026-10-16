package luasv

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"
)

// The JSON form keeps number keys apart from string keys:
//   - a table is an object; a number key n is "#n"; a string key starting with
//     '#', '!' or '$' gets a '!' in front; other string keys are as they are.
//   - a string that is not valid UTF-8 is {"$b": "<base64>"}.
// Entry order is kept.

func jsonKey(k Value) string {
	switch x := k.(type) {
	case float64:
		return "#" + FormatNumber(x)
	case string:
		if x != "" && strings.IndexByte("#!$", x[0]) >= 0 {
			return "!" + x
		}
		return x
	}
	return ""
}

// MarshalJSON encodes a value.
func MarshalJSON(v Value) ([]byte, error) {
	var b bytes.Buffer
	if err := encJSON(&b, v); err != nil {
		return nil, err
	}
	return b.Bytes(), nil
}

func encStr(b *bytes.Buffer, s string) error {
	if utf8.ValidString(s) {
		j, _ := json.Marshal(s)
		b.Write(j)
		return nil
	}
	b.WriteString(`{"$b":"` + base64.StdEncoding.EncodeToString([]byte(s)) + `"}`)
	return nil
}

func encJSON(b *bytes.Buffer, v Value) error {
	switch x := v.(type) {
	case nil:
		b.WriteString("null")
	case bool:
		b.WriteString(strconv.FormatBool(x))
	case float64:
		if math.IsNaN(x) {
			return fmt.Errorf("cannot encode NaN")
		}
		if math.IsInf(x, 0) {
			return fmt.Errorf("cannot encode infinity")
		}
		b.WriteString(FormatNumber(x))
	case string:
		return encStr(b, x)
	case *Table:
		b.WriteByte('{')
		for i, e := range x.Entries {
			if i > 0 {
				b.WriteByte(',')
			}
			k := jsonKey(e.Key)
			if !utf8.ValidString(k) {
				return fmt.Errorf("key %q is not valid UTF-8", k)
			}
			kj, _ := json.Marshal(k)
			b.Write(kj)
			b.WriteByte(':')
			if err := encJSON(b, e.Val); err != nil {
				return err
			}
		}
		b.WriteByte('}')
	default:
		return fmt.Errorf("unsupported value type %T", v)
	}
	return nil
}

// UnmarshalJSON decodes what MarshalJSON wrote.
func UnmarshalJSON(data []byte) (Value, error) {
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	v, err := decJSON(d)
	if err != nil {
		return nil, err
	}
	if _, err := d.Token(); err != io.EOF {
		return nil, fmt.Errorf("trailing data after JSON value")
	}
	return v, nil
}

func decJSON(d *json.Decoder) (Value, error) {
	tok, err := d.Token()
	if err != nil {
		return nil, err
	}
	switch x := tok.(type) {
	case nil:
		return nil, nil
	case bool:
		return x, nil
	case string:
		return x, nil
	case json.Number:
		f, err := strconv.ParseFloat(string(x), 64)
		if err != nil {
			return nil, err
		}
		return f, nil
	case json.Delim:
		if x != '{' {
			return nil, fmt.Errorf("arrays are not part of the value model")
		}
		t := NewTable()
		for d.More() {
			kt, err := d.Token()
			if err != nil {
				return nil, err
			}
			ks := kt.(string)
			v, err := decJSON(d)
			if err != nil {
				return nil, err
			}
			if ks == "$b" && !d.More() && t.Len() == 0 {
				if s, ok := v.(string); ok {
					raw, err := base64.StdEncoding.DecodeString(s)
					if err != nil {
						return nil, err
					}
					if _, err := d.Token(); err != nil { // closing brace
						return nil, err
					}
					return string(raw), nil
				}
			}
			switch {
			case strings.HasPrefix(ks, "#"):
				f, err := strconv.ParseFloat(ks[1:], 64)
				if err != nil {
					return nil, fmt.Errorf("bad number key %q", ks)
				}
				t.Set(f, v)
			case strings.HasPrefix(ks, "!"):
				t.Set(ks[1:], v)
			default:
				t.Set(ks, v)
			}
		}
		if _, err := d.Token(); err != nil {
			return nil, err
		}
		return t, nil
	}
	return nil, fmt.Errorf("unexpected JSON token")
}
