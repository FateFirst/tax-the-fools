package merge

import (
	"sort"
	"strconv"
	"strings"

	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

// asTable returns v as a table, or nil.
func asTable(v luasv.Value) *luasv.Table {
	t, _ := v.(*luasv.Table)
	return t
}

// field reads t[k]. A nil value counts as absent, the same as in Lua.
func field(t *luasv.Table, k luasv.Value) (luasv.Value, bool) {
	if t == nil {
		return nil, false
	}
	v, ok := t.Get(k)
	if !ok || v == nil {
		return nil, false
	}
	return v, true
}

func fieldT(t *luasv.Table, k string) *luasv.Table {
	v, _ := field(t, k)
	return asTable(v)
}

func asNum(v luasv.Value) (float64, bool) {
	f, ok := v.(float64)
	return f, ok
}

// numOr reads t[k] as a number, or def.
func numOr(t *luasv.Table, k string, def float64) float64 {
	v, _ := field(t, k)
	if f, ok := asNum(v); ok {
		return f
	}
	return def
}

// clone copies a value deeply, so the merged result never shares a table with an input.
func clone(v luasv.Value) luasv.Value {
	t, ok := v.(*luasv.Table)
	if !ok || t == nil {
		return v
	}
	out := luasv.NewTable()
	for _, e := range t.Entries {
		out.Set(e.Key, clone(e.Val))
	}
	return out
}

// keys lists the keys of a then the keys only b has, skipping nil values.
func keys(a, b *luasv.Table) []luasv.Value {
	var out []luasv.Value
	seen := map[string]bool{}
	for _, t := range []*luasv.Table{a, b} {
		if t == nil {
			continue
		}
		for _, e := range t.Entries {
			if e.Val == nil {
				continue
			}
			c := canon(e.Key)
			if !seen[c] {
				seen[c] = true
				out = append(out, e.Key)
			}
		}
	}
	return out
}

// canon is a deterministic encoding of a value: equal values give equal strings.
func canon(v luasv.Value) string {
	var b strings.Builder
	writeCanon(&b, v)
	return b.String()
}

func writeCanon(b *strings.Builder, v luasv.Value) {
	switch x := v.(type) {
	case nil:
		b.WriteString("n")
	case bool:
		if x {
			b.WriteString("T")
		} else {
			b.WriteString("F")
		}
	case float64:
		b.WriteString("#")
		b.WriteString(strconv.FormatFloat(x, 'g', -1, 64))
	case string:
		b.WriteString(strconv.Quote(x))
	case *luasv.Table:
		b.WriteString("{")
		if x != nil {
			for _, e := range x.Sorted() {
				if e.Val == nil {
					continue
				}
				writeCanon(b, e.Key)
				b.WriteString("=")
				writeCanon(b, e.Val)
				b.WriteString(",")
			}
		}
		b.WriteString("}")
	default:
		b.WriteString("?")
	}
}

// elements returns the values of a list table in key order.
func elements(t *luasv.Table) []luasv.Value {
	if t == nil {
		return nil
	}
	var out []luasv.Value
	for _, e := range t.Sorted() {
		if e.Val != nil {
			out = append(out, e.Val)
		}
	}
	return out
}

// list builds a Lua array 1..n.
func list(vals []luasv.Value) *luasv.Table {
	t := luasv.NewTable()
	for i, v := range vals {
		t.SetN(float64(i+1), v)
	}
	return t
}

func sortedStrings(set map[string]bool) []string {
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func keyName(k luasv.Value) string {
	if s, ok := k.(string); ok {
		return s
	}
	return canon(k)
}
