package luasv

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func tbl(kv ...Value) *Table {
	t := NewTable()
	for i := 0; i < len(kv); i += 2 {
		t.Set(kv[i], kv[i+1])
	}
	return t
}

func mustWrite(t *testing.T, vars map[string]Value, names []string) []byte {
	t.Helper()
	b, err := Write(vars, names)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestRoundTripNasty(t *testing.T) {
	nasty := "q\"uote \\ back\\\\slash\nnew\rline\x00nul\x01\x7f tab\t |cff1eff00|Hitem:19019:0:0:0|h[Thunderfury]|h|r \xe9\xff end\\n"
	x := map[string]Value{
		"A": tbl(
			"1", "string one", 1.0, "number one",
			nasty, nasty,
			"n", tbl(2.0, true, 1.0, false, -3.5, nil, "big", 1760000000.0),
			"e", tbl(), "f", 0.1, "neg", -42.0, "huge", 1e300,
		),
		"B": "x", "C": true, "D": nil,
	}
	names := []string{"A", "B", "C", "D"}
	w1 := mustWrite(t, x, names)
	got, err := Parse(w1)
	if err != nil {
		t.Fatalf("%v\n%s", err, w1)
	}
	for _, n := range names {
		if !Equal(got[n], x[n]) {
			t.Fatalf("%s differs after round trip:\n%s", n, w1)
		}
	}
	if w2 := mustWrite(t, got, names); !bytes.Equal(w1, w2) {
		t.Fatalf("not byte-identical:\n%s\n---\n%s", w1, w2)
	}
	if !bytes.Contains(w1, []byte("|Hitem:19019")) || !bytes.Contains(w1, []byte("\xe9\xff")) {
		t.Fatal("links or high bytes were altered")
	}
	if !bytes.Contains(w1, []byte("[\"big\"] = 1760000000,")) {
		t.Fatalf("integer written badly:\n%s", w1)
	}
	v, _ := got["A"].(*Table).GetS("1")
	if v != "string one" {
		t.Fatal("string key 1 lost")
	}
	v, _ = got["A"].(*Table).GetN(1)
	if v != "number one" {
		t.Fatal("number key 1 lost")
	}
}

func TestWriteFormatAndOrder(t *testing.T) {
	x := map[string]Value{"T": tbl("b", 1.0, "a", 2.0, 10.0, 3.0, 2.0, 4.0)}
	want := "T = {\n\t[2] = 4,\n\t[10] = 3,\n\t[\"a\"] = 2,\n\t[\"b\"] = 1,\n}\n"
	if got := string(mustWrite(t, x, []string{"T"})); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestParseClientStyle(t *testing.T) {
	src := "-- comment\nA = {\n\t[\"k\"] = \"v\", -- [1]\n\t[1] = 5e2,\n\t\"pos\", 0x10,\n\tname = 'sq', --[[ long\ncomment ]]\n\t[\"n\"] = {\n\t},\n}\n--[==[ x\n]==]\nB = -1.5\nC = [[long\nstring]]\n"
	m, err := Parse([]byte(src))
	if err != nil {
		t.Fatal(err)
	}
	a := m["A"].(*Table)
	if v, _ := a.GetS("k"); v != "v" {
		t.Fatal("k")
	}
	if v, _ := a.GetN(1); v != "pos" { // positional entry overrides [1] written earlier
		t.Fatalf("1: %v", v)
	}
	if v, _ := a.GetN(2); v != 16.0 {
		t.Fatal("hex")
	}
	if v, _ := a.GetS("name"); v != "sq" {
		t.Fatal("name")
	}
	if m["B"] != -1.5 || m["C"] != "long\nstring" {
		t.Fatalf("%v %v", m["B"], m["C"])
	}
}

func TestParseErrors(t *testing.T) {
	cases := []struct{ src, want string }{
		{"A = {\n\t[\"k\"] = ,\n}", "line 2:"},
		{"\n\nA = \"unfinished\n", "line 3: unfinished string"},
		{"A = {\n1,\n2\n", "line 1: unfinished table"},
		{"A = 1\nB 2", "line 2: expected '='"},
		{"A = foo", "line 1: unexpected name"},
		{"A = \"\\q\"", "line 1: invalid escape"},
		{"A = {[true] = 1}", "line 1: a table key"},
		{"A = \"\\300\"", "too large"},
		{"A = 1x", "line 1:"},
	}
	for _, c := range cases {
		_, err := Parse([]byte(c.src))
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%q: got %v, want %q", c.src, err, c.want)
		}
	}
}

func TestTableOps(t *testing.T) {
	x := NewTable()
	x.SetS("a", 1.0)
	x.SetN(1, 2.0)
	x.Set("a", 3.0)
	if x.Len() != 2 {
		t.Fatal("len")
	}
	if v, _ := x.GetS("a"); v != 3.0 {
		t.Fatal("set")
	}
	if !x.Delete("a") || x.Delete("a") {
		t.Fatal("delete")
	}
	if _, ok := x.GetS("a"); ok {
		t.Fatal("still there")
	}
	if v, ok := x.Get(1); !ok || v != 2.0 {
		t.Fatal("int key")
	}
}

func TestJSONKeepsKeyKinds(t *testing.T) {
	v := tbl("1", "s", 1.0, "n", "#x", 1.0, "!y", 2.0, "$b", 3.0, "bin", "\xe9\xff|h",
		"nest", tbl(2.5, tbl(), "z", nil), "t", true, "big", 1760000000.0)
	j, err := MarshalJSON(v)
	if err != nil {
		t.Fatal(err)
	}
	back, err := UnmarshalJSON(j)
	if err != nil {
		t.Fatalf("%v: %s", err, j)
	}
	if !Equal(v, back) {
		t.Fatalf("differs: %s", j)
	}
	// order and exactness
	j2, _ := MarshalJSON(back)
	if !bytes.Equal(j, j2) {
		t.Fatalf("JSON not stable:\n%s\n%s", j, j2)
	}
	if !strings.Contains(string(j), `"big":1760000000`) {
		t.Fatalf("%s", j)
	}
	for _, s := range []string{"", "\xff", "$b"} {
		j, _ := MarshalJSON(s)
		b, err := UnmarshalJSON(j)
		if err != nil || b != s {
			t.Fatalf("scalar %q: %v %v", s, b, err)
		}
	}
}

func TestBigFixture(t *testing.T) {
	src, err := os.ReadFile("testdata/big.lua")
	if err != nil {
		t.Fatal(err)
	}
	vars, err := Parse(src)
	if err != nil {
		t.Fatal(err)
	}
	db := vars["TaxTheFoolsDB"].(*Table)
	w1, err := Write(vars, []string{"TaxTheFoolsDB"})
	if err != nil {
		t.Fatal(err)
	}
	// The Lua serialiser and the Go writer use the same shape.
	if !bytes.Equal(bytes.TrimSpace(w1), bytes.TrimSpace(src)) {
		t.Error("Go output differs from the Lua serialiser's output")
	}
	vars2, err := Parse(w1)
	if err != nil {
		t.Fatal(err)
	}
	if !Equal(vars["TaxTheFoolsDB"], vars2["TaxTheFoolsDB"]) {
		t.Fatal("round trip changed the value")
	}
	w2, _ := Write(vars2, []string{"TaxTheFoolsDB"})
	if !bytes.Equal(w1, w2) {
		t.Fatal("Write(Parse(Write(x))) is not byte-identical")
	}
	j, err := MarshalJSON(db)
	if err != nil {
		t.Fatal(err)
	}
	back, err := UnmarshalJSON(j)
	if err != nil || !Equal(db, back) {
		t.Fatalf("JSON round trip: %v", err)
	}

	get := func(v Value, path ...Value) Value {
		for _, k := range path {
			tb, ok := v.(*Table)
			if !ok {
				t.Fatalf("not a table at %v", k)
			}
			v, ok = tb.Get(k)
			if !ok {
				t.Fatalf("missing %v", k)
			}
		}
		return v
	}
	if get(db, "settingsAt") != 1760000000.0 {
		t.Error("settingsAt")
	}
	if get(db, "settings", "mail", "bankAlt") != `Bank "Alt"` {
		t.Error("bankAlt")
	}
	if get(db, "settings", "minimapAngle") != -37.5 {
		t.Error("minimapAngle")
	}
	if get(db, "items", "13468", "n") != `Black Lotus "Rare"` {
		t.Error("item name")
	}
	if get(db, "items", "13468", "dep", 480.0) != 75.0 {
		t.Error("number key under deposit")
	}
	if !strings.Contains(get(db, "items", "14048", "t").(string), `Icons\INV_Misc_14048`) {
		t.Error("texture path with backslashes")
	}
	r := get(db, "realms", "Medivh")
	if get(r, "chars", "Zeppo", "class") != "ROGUE" {
		t.Error("class")
	}
	if get(r, "history", "14048", "days", 20344.0, "src") != "browse" {
		t.Error("day src")
	}
	if get(r, "chars", "Fizzlebang", "ledger", 25.0, "who") != `Someone's "Alt"` {
		t.Error("ledger who")
	}
	if get(r, "chars", "Dragonbait", "ledgerBackfilled") != false {
		t.Error("bool")
	}
	if get(r, "watch", "14048") != 1759999500.0 {
		t.Error("watch")
	}
}
