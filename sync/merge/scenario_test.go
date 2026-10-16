package merge

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

// path walks string and number keys (int means a number key).
func path(t *testing.T, v luasv.Value, keys ...interface{}) luasv.Value {
	t.Helper()
	for _, k := range keys {
		tb := asTable(v)
		if tb == nil {
			return nil
		}
		if i, ok := k.(int); ok {
			k = float64(i)
		}
		v, _ = field(tb, k)
	}
	return v
}

func count(t *testing.T, v luasv.Value, keys ...interface{}) int {
	t.Helper()
	tb := asTable(path(t, v, keys...))
	if tb == nil {
		return 0
	}
	return tb.Len()
}

// Review focus 1: a sale recorded on the laptop and a scan run on the PC both survive, once each,
// whichever device syncs first.
func TestFocusSaleOnLaptopScanOnPC(t *testing.T) {
	server := `{ realms = { R = {
		history = { ["4306:0"] = { days = { [20369] = { n = 4, p25 = 100 } } } },
		scan = { lastFull = 1759900000 },
		chars = { Al = {
			sales = { { name = "Silk Cloth", key = "4306:0", outcome = "sold", money = 900, at = 1759950000 } },
			ledger = { { at = 1759950000, kind = "sale", amount = 900, key = "4306:0" } },
			postings = { { key = "4306:0", stack = 20, buyout = 1000, at = 1759940000, done = "sold" },
			             { key = "4306:0", stack = 20, buyout = 1000, at = 1759941000 } },
			seenMail = { k1 = { at = 1759950000, n = 1 } } } } } } }`
	laptop := `{ realms = { R = {
		history = { ["4306:0"] = { days = { [20369] = { n = 4, p25 = 100 } } } },
		scan = { lastFull = 1759900000 },
		chars = { Al = {
			sales = { { name = "Silk Cloth", key = "4306:0", outcome = "sold", money = 900, at = 1759950000 },
			          { name = "Silk Cloth", key = "4306:0", outcome = "sold", money = 950, at = 1759990000, qty = 20 } },
			ledger = { { at = 1759950000, kind = "sale", amount = 900, key = "4306:0" },
			           { at = 1759990000, kind = "sale", amount = 950, key = "4306:0", qty = 20 } },
			postings = { { key = "4306:0", stack = 20, buyout = 1000, at = 1759940000, done = "sold" },
			             { key = "4306:0", stack = 20, buyout = 1000, at = 1759941000, done = "sold" } },
			seenMail = { k1 = { at = 1759950000, n = 1 }, k2 = { at = 1759990000, n = 1 } } } } } } }`
	pc := `{ realms = { R = {
		history = { ["4306:0"] = { days = { [20369] = { n = 4, p25 = 100 }, [20370] = { n = 12, p25 = 105 } } } },
		market = { ["4306:0"] = { v = 103 } },
		snapshot = { at = 1759995000, day = 20370, rows = { ["4306:0"] = { "20|1000|900|Bob" } } },
		scan = { lastFull = 1759995000 },
		chars = { Al = {
			sales = { { name = "Silk Cloth", key = "4306:0", outcome = "sold", money = 900, at = 1759950000 } },
			ledger = { { at = 1759950000, kind = "sale", amount = 900, key = "4306:0" } },
			postings = { { key = "4306:0", stack = 20, buyout = 1000, at = 1759940000, done = "sold" },
			             { key = "4306:0", stack = 20, buyout = 1000, at = 1759941000 } },
			seenMail = { k1 = { at = 1759950000, n = 1 } } } } } } }`
	S, L, P := lua(t, server), lua(t, laptop), lua(t, pc)

	laptopFirst, _ := run(L, S)
	laptopFirst, _ = run(P, laptopFirst)
	pcFirst, _ := run(P, S)
	pcFirst, _ = run(L, pcFirst)

	for name, m := range map[string]luasv.Value{"laptop first": laptopFirst, "PC first": pcFirst} {
		al := path(t, m, "realms", "R", "chars", "Al")
		if n := count(t, al, "sales"); n != 2 {
			t.Errorf("%s: %d sales, want 2", name, n)
		}
		if n := count(t, al, "ledger"); n != 2 {
			t.Errorf("%s: %d ledger entries, want 2", name, n)
		}
		if n := count(t, al, "postings"); n != 2 {
			t.Errorf("%s: %d postings, want 2", name, n)
		}
		if path(t, al, "postings", 2, "done") != "sold" {
			t.Errorf("%s: the laptop's sold posting reopened", name)
		}
		if count(t, al, "seenMail") != 2 {
			t.Errorf("%s: seenMail lost a key", name)
		}
		r := path(t, m, "realms", "R")
		if path(t, r, "history", "4306:0", "days", 20370, "n") != 12.0 || path(t, r, "scan", "lastFull") != 1759995000.0 {
			t.Errorf("%s: the PC's scan is missing", name)
		}
		if path(t, r, "snapshot", "at") != 1759995000.0 || path(t, r, "market", "4306:0", "v") != 103.0 {
			t.Errorf("%s: the PC's snapshot or market is missing", name)
		}
	}
	same(t, "both orders", laptopFirst, pcFirst)
	// Each device pulling the final state again changes nothing.
	for _, dev := range []luasv.Value{L, P} {
		again, _ := run(dev, laptopFirst)
		same(t, "a device pulls the final state", again, laptopFirst)
	}
}

// Review focus 2: a snipe item removed on the Deck stays removed when the PC and the laptop, which
// still list it, sync afterwards; a later add on the PC brings it back everywhere.
func TestFocusSnipeRemovedOnDeckStaysRemoved(t *testing.T) {
	listed := `{ realms = { R = { snipe = { ["14047:0"] = { max = 300, name = "Runecloth", at = 1759900000 },
		["4306:0"] = { max = 99, name = "Silk Cloth", at = 1759900000 } }, removed = { snipe = {} } } } }`
	deck := `{ realms = { R = { snipe = { ["4306:0"] = { max = 99, name = "Silk Cloth", at = 1759900000 } },
		removed = { snipe = { ["14047:0"] = 1759950000 } } } } }`
	server := lua(t, listed)
	pc, laptop := lua(t, listed), lua(t, listed)

	m, _ := run(lua(t, deck), server)
	m, _ = run(pc, m)
	m, _ = run(laptop, m)
	m, _ = run(lua(t, deck), m)
	if path(t, m, "realms", "R", "snipe", "14047:0") != nil {
		t.Fatalf("the removed snipe came back: %s", show(m))
	}
	if path(t, m, "realms", "R", "removed", "snipe", "14047:0") != 1759950000.0 {
		t.Error("the removal record is gone")
	}
	if path(t, m, "realms", "R", "snipe", "4306:0", "max") != 99.0 {
		t.Error("the other snipe entry is gone")
	}
	// The other order: the PC syncs first, then the Deck.
	m2, _ := run(pc, server)
	m2, _ = run(lua(t, deck), m2)
	m2, _ = run(laptop, m2)
	same(t, "either order", m2, m)

	readd := lua(t, `{ realms = { R = { snipe = { ["14047:0"] = { max = 250, name = "Runecloth", at = 1759960000 },
		["4306:0"] = { max = 99, name = "Silk Cloth", at = 1759900000 } }, removed = { snipe = {} } } } }`)
	m3, _ := run(readd, m)
	m3, _ = run(lua(t, deck), m3)
	if path(t, m3, "realms", "R", "snipe", "14047:0", "max") != 250.0 {
		t.Errorf("a re-add after the removal was lost: %s", show(m3))
	}
	if path(t, m3, "realms", "R", "removed", "snipe", "14047:0") != nil {
		t.Error("the re-added key kept its removal record")
	}
}

func entries(n int, start int64, step int64, f func(i int, at int64) string) string {
	var b strings.Builder
	b.WriteString("{")
	for i := 0; i < n; i++ {
		b.WriteString(f(i, start+int64(i)*step))
		b.WriteString(",")
	}
	b.WriteString("}")
	return b.String()
}

func TestCaps(t *testing.T) {
	cases := []struct {
		list string
		cap  int
		item func(i int, at int64) string
	}{
		{"ledger", MaxLedger, func(i int, at int64) string {
			return fmt.Sprintf(`{ at = %d, kind = "buy", amount = %d, key = "k" }`, at, i+1)
		}},
		{"sales", MaxSales, func(i int, at int64) string {
			return fmt.Sprintf(`{ at = %d, outcome = "sold", money = %d, name = "x" }`, at, i+1)
		}},
		{"postings", MaxPostings, func(i int, at int64) string {
			return fmt.Sprintf(`{ at = %d, key = "k", stack = 1, buyout = %d }`, at, i+1)
		}},
	}
	for _, c := range cases {
		t.Run(c.list, func(t *testing.T) {
			// local: cap entries, the oldest first; remote: the newest 10 of them plus 10 newer ones.
			start := int64(now - 86400)
			lsrc := entries(c.cap, start, 1, c.item)
			off := c.cap - 10
			rsrc := entries(20, start+int64(off), 1, func(i int, at int64) string { return c.item(i+off, at) })
			wrap := func(list string) luasv.Value {
				return lua(t, `{ realms = { R = { chars = { Al = { `+c.list+` = `+list+` } } } } }`)
			}
			for _, order := range []string{"local first", "remote first"} {
				l, r := wrap(lsrc), wrap(rsrc)
				if order == "remote first" {
					l, r = r, l
				}
				m, _ := run(l, r)
				got := asTable(path(t, m, "realms", "R", "chars", "Al", c.list))
				if got.Len() != c.cap {
					t.Fatalf("%s: %d entries, want %d", order, got.Len(), c.cap)
				}
				first, _ := got.GetN(1)
				last, _ := got.GetN(float64(c.cap))
				if atOf(first) != float64(start+10) || atOf(last) != float64(start+int64(c.cap)+9) {
					t.Errorf("%s: kept %v..%v, want the newest %d", order, atOf(first), atOf(last), c.cap)
				}
			}
		})
	}
}

func TestAgePruning(t *testing.T) {
	old := func(days int) int64 { return now - int64(days)*86400 - 1 }
	src := fmt.Sprintf(`{ realms = { R = { chars = { Al = {
		sales = { { at = %d, outcome = "sold", money = 1, name = "a" }, { at = %d, outcome = "sold", money = 2, name = "a" } },
		ledger = { { at = %d, kind = "buy", amount = 1 }, { at = %d, kind = "buy", amount = 2 } },
		postings = { { at = %d, key = "k", stack = 1, buyout = 1 }, { at = %d, key = "k", stack = 1, buyout = 2 } },
		pendingBids = { { at = %d, name = "a", amount = 1 }, { at = %d, name = "a", amount = 2 } },
		pendingBuys = { { at = %d, name = "a" }, { at = %d, name = "b" } },
		seenMail = { old = { at = %d, n = 1 }, new = { at = %d, n = 1 }, bare = %d } } } } } }`,
		old(120), now-10, old(180), now-10, old(35), now-10, old(7), now-10, old(7), now-10, old(120), now-10, old(120))
	v := lua(t, src)
	m, _ := run(v, nil)
	al := path(t, m, "realms", "R", "chars", "Al")
	for _, l := range []string{"sales", "ledger", "postings", "pendingBids", "pendingBuys"} {
		if n := count(t, al, l); n != 1 {
			t.Errorf("%s: %d left, want 1", l, n)
		}
	}
	if count(t, al, "seenMail") != 1 || path(t, al, "seenMail", "new") == nil {
		t.Errorf("seenMail: %s", show(path(t, al, "seenMail")))
	}
	// Now = 0 keeps everything.
	m, _ = Merge(v, nil, Options{})
	same(t, "no clock, no age pruning", m, v)
}

func TestBigFixture(t *testing.T) {
	src, err := os.ReadFile("../luasv/testdata/big.lua")
	if err != nil {
		t.Fatal(err)
	}
	parse := func() luasv.Value {
		vars, err := luasv.Parse(src)
		if err != nil {
			t.Fatal(err)
		}
		return vars["TaxTheFoolsDB"]
	}
	opts := Options{Now: 1760000000 + 1000}
	big := parse()

	self, rep := Merge(big, big, opts)
	t.Logf("unknown: %q", rep.Unknown)
	same(t, "merge(big, big)", self, big)
	// The fixture is written by tools/sv-fixture.lua, which uses a few shapes the addon doesn't (a
	// scan record, recipe names under recipes[prof]): those are reported, not lost.
	for _, p := range []string{"realms.*.scan.pages", "recipes.*.Bolt of Runecloth"} {
		if !strings.Contains(strings.Join(rep.Unknown, "\n"), p) {
			t.Errorf("unknown paths %q lack %s", rep.Unknown, p)
		}
	}

	// A second device: a new sale for Zeppo, a snipe removed, a new history day, newer settings and
	// a newer bag count for Fizzlebang.
	mod := parse()
	r := asTable(path(t, mod, "realms", "Medivh"))
	sales := asTable(path(t, r, "chars", "Zeppo", "sales"))
	sales.SetN(3, lua(t, `{ at = 1760000500, key = "4306", name = "Silk Cloth", outcome = "sold", money = 1500 }`))
	asTable(path(t, r, "snipe")).Delete("14047")
	asTable(path(t, r, "removed", "snipe")).SetS("14047", 1760000600.0)
	asTable(path(t, r, "history", "4306", "days")).SetN(20030, lua(t, `{ n = 3, p25 = 999 }`))
	asTable(mod).SetS("settingsAt", 1760000700.0)
	asTable(path(t, mod, "settings")).SetS("scale", 2.0)
	fizz := asTable(path(t, r, "chars", "Fizzlebang"))
	fizz.SetS("bagsAt", 1760000800.0)
	fizz.SetS("bags", lua(t, `{ ["14047"] = 1 }`))

	ab, _ := Merge(big, mod, opts)
	ba, _ := Merge(mod, big, opts)
	same(t, "merge(big, mod) == merge(mod, big)", ab, ba)
	same(t, "the second device's copy is the merge", ab, mod)
	m := path(t, ab, "realms", "Medivh")
	if count(t, m, "chars", "Zeppo", "sales") != 3 || count(t, m, "chars", "Zeppo", "ledger") != 25 {
		t.Error("Zeppo's lists")
	}
	if path(t, m, "snipe", "14047") != nil || path(t, m, "snipe", "4306") == nil {
		t.Error("snipe removal")
	}
	if _, err := luasv.Write(map[string]luasv.Value{"TaxTheFoolsDB": ab}, []string{"TaxTheFoolsDB"}); err != nil {
		t.Fatal(err)
	}
}
