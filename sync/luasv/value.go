// Package luasv reads and writes the Lua SavedVariables files the WoW 1.12
// client produces, into a value model that keeps number keys and string keys
// apart.
package luasv

import (
	"fmt"
	"math"
	"sort"
)

// Value is nil, bool, float64, string or *Table.
type Value interface{}

// Entry is one key/value pair. Key is a float64 or a string.
type Entry struct {
	Key Value
	Val Value
}

// Table is an ordered Lua table. Mutate it through Set and Delete; code that
// edits Entries directly must not change keys in place.
type Table struct {
	Entries []Entry
	idx     map[ikey]int
}

type ikey struct {
	str bool
	s   string
	n   float64
}

func toIkey(k Value) (ikey, bool) {
	switch v := k.(type) {
	case string:
		return ikey{str: true, s: v}, true
	case float64:
		return ikey{n: v}, true
	case int:
		return ikey{n: float64(v)}, true
	}
	return ikey{}, false
}

func normKey(k Value) Value {
	if i, ok := k.(int); ok {
		return float64(i)
	}
	return k
}

// NewTable returns an empty table.
func NewTable() *Table { return &Table{} }

func (t *Table) index() map[ikey]int {
	if t.idx == nil || len(t.idx) != len(t.Entries) {
		t.idx = make(map[ikey]int, len(t.Entries))
		for i, e := range t.Entries {
			k, _ := toIkey(e.Key)
			t.idx[k] = i
		}
	}
	return t.idx
}

// Len is the number of entries.
func (t *Table) Len() int { return len(t.Entries) }

// Get returns the value for a string or number key.
func (t *Table) Get(key Value) (Value, bool) {
	k, ok := toIkey(key)
	if !ok {
		return nil, false
	}
	i, ok := t.index()[k]
	if !ok {
		return nil, false
	}
	return t.Entries[i].Val, true
}

// GetS looks up a string key.
func (t *Table) GetS(key string) (Value, bool) { return t.Get(key) }

// GetN looks up a number key.
func (t *Table) GetN(key float64) (Value, bool) { return t.Get(key) }

// Set stores a value under a string or number key (int is accepted as a number).
// Setting nil keeps the entry with a nil value; use Delete to remove it.
func (t *Table) Set(key, val Value) {
	key = normKey(key)
	k, ok := toIkey(key)
	if !ok {
		panic(fmt.Sprintf("luasv: bad table key %T", key))
	}
	idx := t.index()
	if i, ok := idx[k]; ok {
		t.Entries[i].Val = val
		return
	}
	t.Entries = append(t.Entries, Entry{key, val})
	idx[k] = len(t.Entries) - 1
}

// SetS stores under a string key.
func (t *Table) SetS(key string, val Value) { t.Set(key, val) }

// SetN stores under a number key.
func (t *Table) SetN(key float64, val Value) { t.Set(key, val) }

// Delete removes a key, reporting whether it existed.
func (t *Table) Delete(key Value) bool {
	k, ok := toIkey(key)
	if !ok {
		return false
	}
	i, ok := t.index()[k]
	if !ok {
		return false
	}
	t.Entries = append(t.Entries[:i], t.Entries[i+1:]...)
	t.idx = nil
	return true
}

// Sorted returns the entries in the canonical order: number keys ascending,
// then string keys by bytes.
func (t *Table) Sorted() []Entry {
	out := make([]Entry, len(t.Entries))
	copy(out, t.Entries)
	sort.SliceStable(out, func(i, j int) bool {
		a, aok := out[i].Key.(float64)
		b, bok := out[j].Key.(float64)
		switch {
		case aok && bok:
			return a < b
		case aok != bok:
			return aok
		}
		return out[i].Key.(string) < out[j].Key.(string)
	})
	return out
}

// Equal compares two values deeply. Tables compare as sets of entries,
// ignoring order.
func Equal(a, b Value) bool {
	switch x := a.(type) {
	case nil:
		return b == nil
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case float64:
		y, ok := b.(float64)
		return ok && (x == y || (math.IsNaN(x) && math.IsNaN(y)))
	case string:
		y, ok := b.(string)
		return ok && x == y
	case *Table:
		y, ok := b.(*Table)
		if !ok || x == nil || y == nil {
			return ok && x == y
		}
		if len(x.Entries) != len(y.Entries) {
			return false
		}
		for _, e := range x.Entries {
			v, ok := y.Get(e.Key)
			if !ok || !Equal(e.Val, v) {
				return false
			}
		}
		return true
	}
	return false
}
