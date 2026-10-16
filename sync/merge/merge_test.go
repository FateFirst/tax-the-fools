package merge

import (
	"reflect"
	"testing"

	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

const now = 1760000000 // 2025-10-09; every stamp below is within a day of it unless a test says otherwise

func lua(t *testing.T, src string) luasv.Value {
	t.Helper()
	vars, err := luasv.Parse([]byte("X = " + src))
	if err != nil {
		t.Fatalf("bad test Lua: %v\n%s", err, src)
	}
	return vars["X"]
}

func show(v luasv.Value) string {
	b, err := luasv.Write(map[string]luasv.Value{"X": v}, []string{"X"})
	if err != nil {
		return err.Error()
	}
	return string(b)
}

func run(l, r luasv.Value) (luasv.Value, Report) { return Merge(l, r, Options{Now: now}) }

func same(t *testing.T, what string, got, want luasv.Value) {
	t.Helper()
	if !luasv.Equal(got, want) {
		t.Errorf("%s:\n got %s\nwant %s", what, show(got), show(want))
	}
}

// Every rule of spec section 5. union marks the cases where the rule is a union, so merge(b,a)
// must give the same result.
var ruleCases = []struct {
	name          string
	local, remote string
	want          string
	union         bool
	unknown       []string
	pruned        bool // an input holds data old enough to be pruned, so merge(a, a) != a
}{
	{name: "items: fields unioned, local first for facts",
		local:  `{ items = { [4306] = { n = "Silk Cloth", q = 1 }, [2589] = { n = "Linen Cloth" } } }`,
		remote: `{ items = { [4306] = { n = "Silk Cloth", st = 20, t = "tex", v = 150 }, [2592] = { n = "Wool Cloth" } } }`,
		want: `{ items = { [4306] = { n = "Silk Cloth", q = 1, st = 20, t = "tex", v = 150 },
			[2589] = { n = "Linen Cloth" }, [2592] = { n = "Wool Cloth" } } }`,
		union: true},
	{name: "items: learned vb and dep from the remote side when both have them",
		local:  `{ items = { [1] = { vb = 10, vbLimited = true, dep = { [480] = 5, [120] = 1 } } } }`,
		remote: `{ items = { [1] = { vb = 12, dep = { [480] = 6, [1440] = 9 } } } }`,
		want:   `{ items = { [1] = { vb = 12, dep = { [480] = 6, [120] = 1, [1440] = 9 } } } }`},
	{name: "items: vb only locally stays",
		local:  `{ items = { [1] = { vb = 10, vbLimited = true } } }`,
		remote: `{ items = { [1] = { n = "x" } } }`,
		want:   `{ items = { [1] = { n = "x", vb = 10, vbLimited = true } } }`, union: true},
	{name: "history: union by day, larger n wins, months the same",
		local: `{ realms = { R = { history = { ["4306:0"] = {
			days = { [20370] = { n = 5, p25 = 100, src = "full" }, [20369] = { n = 9, p25 = 90 } },
			months = { [202508] = { n = 3, p25 = 80, d = 4 } } } } } } }`,
		remote: `{ realms = { R = { history = { ["4306:0"] = {
			days = { [20370] = { n = 7, p25 = 110, src = "full" }, [20368] = { n = 2, p25 = 95 } },
			months = { [202508] = { n = 2, p25 = 81, d = 9 }, [202507] = { n = 1, p25 = 70, d = 1 } } },
			["2589:0"] = { days = { [20370] = { n = 1 } }, months = {} } } } } }`,
		want: `{ realms = { R = { history = { ["4306:0"] = {
			days = { [20370] = { n = 7, p25 = 110, src = "full" }, [20369] = { n = 9, p25 = 90 }, [20368] = { n = 2, p25 = 95 } },
			months = { [202508] = { n = 3, p25 = 80, d = 4 }, [202507] = { n = 1, p25 = 70, d = 1 } } },
			["2589:0"] = { days = { [20370] = { n = 1 } }, months = {} } } } } }`,
		union: true},
	{name: "snapshot: the newer at",
		local:  `{ realms = { R = { snapshot = { at = 100, day = 1, rows = { a = { "1|2|3|x" } } } } } }`,
		remote: `{ realms = { R = { snapshot = { at = 200, day = 2, rows = { b = { "4|5|6|" } } } } } }`,
		want:   `{ realms = { R = { snapshot = { at = 200, day = 2, rows = { b = { "4|5|6|" } } } } } }`, union: true},
	{name: "market: the side whose history has the newest day for the key",
		local: `{ realms = { R = { history = { a = { days = { [10] = { n = 1 } } }, b = { days = { [12] = { n = 1 } } } },
			market = { a = { v = 1 }, b = { v = 1 }, c = { v = 1 } } } } }`,
		remote: `{ realms = { R = { history = { a = { days = { [11] = { n = 1 } } }, b = { days = { [11] = { n = 1 } } } },
			market = { a = { v = 2 }, b = { v = 2 }, d = { v = 2 } } } } }`,
		want: `{ realms = { R = { history = { a = { days = { [10] = { n = 1 }, [11] = { n = 1 } } },
			b = { days = { [12] = { n = 1 }, [11] = { n = 1 } } } },
			market = { a = { v = 2 }, b = { v = 1 }, c = { v = 1 }, d = { v = 2 } } } } }`, union: true},
	{name: "scan: lastFull max, resume stays local",
		local:  `{ realms = { R = { scan = { lastFull = 100, resume = { page = 3 } } } } }`,
		remote: `{ realms = { R = { scan = { lastFull = 300, resume = { page = 9 } } } } }`,
		want:   `{ realms = { R = { scan = { lastFull = 300, resume = { page = 3 } } } } }`},
	{name: "scan: a remote resume is never taken",
		local:  `{ realms = { R = { scan = { } } } }`,
		remote: `{ realms = { R = { scan = { lastFull = 5, resume = { page = 9 } } } } }`,
		want:   `{ realms = { R = { scan = { lastFull = 5 } } } }`},
	{name: "watch: union, the later add",
		local:  `{ realms = { R = { watch = { a = 100, b = true }, removed = { watch = {} } } } }`,
		remote: `{ realms = { R = { watch = { a = 200, c = 300 }, removed = { watch = {} } } } }`,
		want:   `{ realms = { R = { watch = { a = 200, b = true, c = 300 }, removed = { watch = {} } } } }`, union: true},
	{name: "watch: a removal beats an older add; a newer add beats a removal",
		local:  `{ realms = { R = { watch = { a = 1759990100, b = 1759990500 }, removed = { watch = { c = 1759990400 } } } } }`,
		remote: `{ realms = { R = { watch = { c = 1759990300 }, removed = { watch = { a = 1759990150, b = 1759990450 } } } } }`,
		want:   `{ realms = { R = { watch = { b = 1759990500 }, removed = { watch = { a = 1759990150, c = 1759990400 } } } } }`, union: true},
	{name: "watch: an old true entry loses to any removal",
		local:  `{ realms = { R = { watch = { a = true }, removed = { watch = {} } } } }`,
		remote: `{ realms = { R = { watch = {}, removed = { watch = { a = 1759990000 } } } } }`,
		want:   `{ realms = { R = { watch = {}, removed = { watch = { a = 1759990000 } } } } }`, union: true},
	{name: "removal records: the latest time, pruned after 90 days",
		local:  `{ realms = { R = { watch = {}, removed = { watch = { a = 100, b = 1759990000 }, snipe = { s = 1752000000 } } } } }`,
		remote: `{ realms = { R = { watch = {}, removed = { watch = { b = 1759995000 }, snipe = { t = 1759000000 } } } } }`,
		want:   `{ realms = { R = { watch = {}, removed = { watch = { b = 1759995000 }, snipe = { t = 1759000000 } } } } }`, union: true, pruned: true},
	{name: "snipe: union with removals, the newer at when both have it",
		local: `{ realms = { R = { snipe = { a = { max = 100, name = "A", at = 1759990010 }, b = { max = 5, at = 1759990050 } },
			removed = { snipe = { c = 1759990070, d = 1759990079 } } } } }`,
		remote: `{ realms = { R = { snipe = { a = { max = 90, name = "A", at = 1759990020 }, c = { max = 1, at = 1759990060 }, d = { max = 2, at = 1759990080 } },
			removed = { snipe = { b = 1759990040 } } } } }`,
		want: `{ realms = { R = { snipe = { a = { max = 90, name = "A", at = 1759990020 }, b = { max = 5, at = 1759990050 }, d = { max = 2, at = 1759990080 } },
			removed = { snipe = { c = 1759990070 } } } } }`, union: true},
	{name: "settings: the newer settingsAt wins; keep is unioned with its removals",
		local: `{ settingsAt = 1759990100, settings = { scale = 1, theme = "A", mail = { bankAlt = "Bank", keep = { a = 1759990050, b = 1759990060 }, keepRemoved = { c = 1759990090 } } } }`,
		remote: `{ settingsAt = 1759990200, settings = { scale = 2, deals = { snipe = false },
			mail = { keep = { c = 1759990080, d = 1759990070 }, keepRemoved = { b = 1759990065 } } } }`,
		want: `{ settingsAt = 1759990200, settings = { scale = 2, deals = { snipe = false },
			mail = { keep = { a = 1759990050, d = 1759990070 }, keepRemoved = { b = 1759990065, c = 1759990090 } } } }`, union: true},
	{name: "settings: local wins a tie",
		local:  `{ settingsAt = 100, settings = { scale = 1 } }`,
		remote: `{ settingsAt = 100, settings = { scale = 2 } }`,
		want:   `{ settingsAt = 100, settings = { scale = 1 } }`},
	{name: "chars: bags and bank go with the newer stamp, professions per profession",
		local: `{ realms = { R = { chars = { Al = { class = "MAGE", bags = { a = 1 }, bagsAt = 100, bank = { b = 1 }, bankAt = 300,
			professions = { Tailoring = { rank = 1, at = 10 }, Cooking = { rank = 5, at = 50 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { class = "MAGE", bags = { a = 2 }, bagsAt = 200, bank = { b = 2 }, bankAt = 250,
			professions = { Tailoring = { rank = 9, at = 20 }, Cooking = { rank = 4, at = 40 }, Mining = { rank = 1, at = 1 } } },
			Bo = { class = "ROGUE" } } } } }`,
		want: `{ realms = { R = { chars = { Al = { class = "MAGE", bags = { a = 2 }, bagsAt = 200, bank = { b = 1 }, bankAt = 300,
			professions = { Tailoring = { rank = 9, at = 20 }, Cooking = { rank = 5, at = 50 }, Mining = { rank = 1, at = 1 } } },
			Bo = { class = "ROGUE" } } } } }`, union: true},
	{name: "sales: union without duplicates; a key filled in later is the same sale",
		local: `{ realms = { R = { chars = { Al = { sales = {
			{ name = "Silk Cloth", outcome = "sold", money = 900, at = 1759990000 },
			{ key = "1:0", name = "Linen", outcome = "expired", money = 0, at = 1759990100 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { sales = {
			{ key = "4306:0", name = "Silk Cloth", outcome = "sold", money = 900, at = 1759990000, qty = 5 },
			{ key = "1:0", name = "Linen", outcome = "expired", money = 0, at = 1759990100 },
			{ key = "1:0", name = "Linen", outcome = "sold", money = 50, at = 1759990200 } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { sales = {
			{ key = "4306:0", name = "Silk Cloth", outcome = "sold", money = 900, at = 1759990000, qty = 5 },
			{ key = "1:0", name = "Linen", outcome = "expired", money = 0, at = 1759990100 },
			{ key = "1:0", name = "Linen", outcome = "sold", money = 50, at = 1759990200 } } } } } } }`, union: true},
	{name: "sales: identical results in one second are kept as many times as one side has them",
		local: `{ realms = { R = { chars = { Al = { sales = {
			{ name = "S", outcome = "sold", money = 9, at = 1759990000 }, { name = "S", outcome = "sold", money = 9, at = 1759990000 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { sales = {
			{ name = "S", outcome = "sold", money = 9, at = 1759990000 }, { name = "T", outcome = "sold", money = 9, at = 1759990001 } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { sales = {
			{ name = "S", outcome = "sold", money = 9, at = 1759990000 }, { name = "S", outcome = "sold", money = 9, at = 1759990000 },
			{ name = "T", outcome = "sold", money = 9, at = 1759990001 } } } } } } }`, union: true},
	{name: "postings: union; done on either side stays done",
		local: `{ realms = { R = { chars = { Al = { postings = {
			{ key = "a", stack = 20, buyout = 500, at = 1759990000, done = "sold" },
			{ key = "a", stack = 20, buyout = 500, at = 1759990000 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { postings = {
			{ key = "a", stack = 20, buyout = 500, at = 1759990000 },
			{ key = "a", stack = 20, buyout = 500, at = 1759990000, done = "expired" },
			{ key = "b", stack = 1, buyout = 9, at = 1759990500, deposit = 3 } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { postings = {
			{ key = "a", stack = 20, buyout = 500, at = 1759990000, done = "sold" },
			{ key = "a", stack = 20, buyout = 500, at = 1759990000 },
			{ key = "b", stack = 1, buyout = 9, at = 1759990500, deposit = 3 } } } } } } }`},
	{name: "postings: one side finished it",
		local:  `{ realms = { R = { chars = { Al = { postings = { { key = "a", stack = 1, buyout = 5, at = 1759990000 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { postings = { { key = "a", stack = 1, buyout = 5, at = 1759990000, done = "sold" } } } } } } }`,
		want:   `{ realms = { R = { chars = { Al = { postings = { { key = "a", stack = 1, buyout = 5, at = 1759990000, done = "sold" } } } } } } }`, union: true},
	{name: "ledger: union by (at, kind, amount, key); a vendor or postage entry keeps the larger amount",
		local: `{ realms = { R = { chars = { Al = { ledger = {
			{ at = 1759990000, kind = "buy", amount = 100, key = "a", qty = 1 },
			{ at = 1759990100, kind = "vendorIn", amount = 40 },
			{ at = 1759990200, kind = "mailOut", amount = 5000, who = "Bob" },
			{ at = 1759990200, kind = "mailOut", amount = 60, who = "Bob" } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { ledger = {
			{ at = 1759990000, kind = "buy", amount = 100, key = "a", qty = 1 },
			{ at = 1759990100, kind = "vendorIn", amount = 25 },
			{ at = 1759990200, kind = "mailOut", amount = 5000, who = "Bob" },
			{ at = 1759990200, kind = "mailOut", amount = 30, who = "Bob" },
			{ at = 1759990300, kind = "sale", amount = 70, key = "b" } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { ledger = {
			{ at = 1759990000, kind = "buy", amount = 100, key = "a", qty = 1 },
			{ at = 1759990100, kind = "vendorIn", amount = 40 },
			{ at = 1759990200, kind = "mailOut", amount = 5000, who = "Bob" },
			{ at = 1759990200, kind = "mailOut", amount = 60, who = "Bob" },
			{ at = 1759990300, kind = "sale", amount = 70, key = "b" } } } } } } }`, union: true},
	{name: "seenMail: the larger n; the old bare-time format counts as one",
		local:  `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990000, n = 2 }, b = 1759990000 } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990000, n = 1 }, b = { at = 1759990000, n = 3 }, c = { at = 1759990000, n = 1 } } } } } } }`,
		want:   `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990000, n = 2 }, b = { at = 1759990000, n = 3 }, c = { at = 1759990000, n = 1 } } } } } } }`, union: true},
	{name: "pending bids and buys: union by (name, amount, at)",
		local: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000, key = "a" } },
			pendingBuys = { { name = "B", at = 1759990000 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000, key = "a" }, { name = "A", amount = 6, at = 1759990001 } },
			pendingBuys = { { name = "C", at = 1759990002 } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000, key = "a" }, { name = "A", amount = 6, at = 1759990001 } },
			pendingBuys = { { name = "B", at = 1759990000 }, { name = "C", at = 1759990002 } } } } } } }`, union: true},
	{name: "seenMail: the entry changed last wins, so a forget (n = 0) isn't undone by an older count",
		local:  `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990500, n = 0 }, b = { at = 1759990000, n = 2 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990000, n = 1 }, b = { at = 1759990600, n = 1 } } } } } } }`,
		want:   `{ realms = { R = { chars = { Al = { seenMail = { a = { at = 1759990500, n = 0 }, b = { at = 1759990600, n = 1 } } } } } } }`, union: true},
	{name: "pending bids and buys: a settled entry stays settled, the latest used",
		local: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000 }, { name = "B", amount = 1, at = 1759990001, used = 1759990100 } },
			pendingBuys = { { name = "C", at = 1759990002 } } } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000, used = 1759990050 }, { name = "B", amount = 1, at = 1759990001, used = 1759990200 } },
			pendingBuys = { { name = "C", at = 1759990002, used = 1759990003 } } } } } } }`,
		want: `{ realms = { R = { chars = { Al = { pendingBids = { { name = "A", amount = 5, at = 1759990000, used = 1759990050 }, { name = "B", amount = 1, at = 1759990001, used = 1759990200 } },
			pendingBuys = { { name = "C", at = 1759990002, used = 1759990003 } } } } } } }`, union: true},
	{name: "snapshot: the newer changedAt, falling back to at",
		local:  `{ realms = { R = { snapshot = { at = 1759990000, changedAt = 1759990500, rows = { a = { "1|2|3|x" } } } }, S = { snapshot = { at = 1759990000, rows = {} } } } }`,
		remote: `{ realms = { R = { snapshot = { at = 1759990200, rows = { b = { "4|5|6|" } } } }, S = { snapshot = { at = 1759980000, changedAt = 1759990001, rows = { c = {} } } } } }`,
		want:   `{ realms = { R = { snapshot = { at = 1759990000, changedAt = 1759990500, rows = { a = { "1|2|3|x" } } } }, S = { snapshot = { at = 1759980000, changedAt = 1759990001, rows = { c = {} } } } } }`, union: true},
	{name: "history: a day older than 60 days is dropped when either side has its month",
		local:  `{ realms = { R = { history = { k = { days = { [20300] = { n = 1 }, [20200] = { n = 1 }, [20369] = { n = 1 } }, months = {} } } } } }`,
		remote: `{ realms = { R = { history = { k = { days = {}, months = { [202507] = { n = 4, p25 = 9, d = 3 } } } } } } }`,
		want:   `{ realms = { R = { history = { k = { days = { [20200] = { n = 1 }, [20369] = { n = 1 } }, months = { [202507] = { n = 4, p25 = 9, d = 3 } } } } } } }`, union: true},
	{name: "ledgerBackfilled: or",
		local:  `{ realms = { R = { chars = { Al = { ledgerBackfilled = false }, Bo = { ledgerBackfilled = false } } } } }`,
		remote: `{ realms = { R = { chars = { Al = { ledgerBackfilled = true }, Bo = { ledgerBackfilled = false } } } } }`,
		want:   `{ realms = { R = { chars = { Al = { ledgerBackfilled = true }, Bo = { ledgerBackfilled = false } } } } }`, union: true},
	{name: "recipes: trainer and seen, the newer at",
		local:  `{ recipes = { Tailoring = { trainer = { A = { c = 1, s = 1, at = 10 } }, seen = { [1] = { n = "x", at = 50 } } } } }`,
		remote: `{ recipes = { Tailoring = { trainer = { A = { c = 2, s = 1, at = 20 }, B = { c = 3, at = 1 } }, seen = { [1] = { n = "y", at = 40 } } } } }`,
		want:   `{ recipes = { Tailoring = { trainer = { A = { c = 2, s = 1, at = 20 }, B = { c = 3, at = 1 } }, seen = { [1] = { n = "x", at = 50 } } } } }`, union: true},
	{name: "top level: dataVersion max; version, sync and probe stay local",
		local:  `{ dataVersion = 1, version = "0.11.0", sync = { at = 5, device = "PC" } }`,
		remote: `{ dataVersion = 2, version = "0.12.0", sync = { at = 9, device = "Deck" }, probe = { "x" } }`,
		want:   `{ dataVersion = 2, version = "0.11.0", sync = { at = 5, device = "PC" } }`},
	{name: "unknown paths: local wins, remote fills a gap, each path reported once",
		local:   `{ futureThing = 1, realms = { R = { odd = 1 }, S = { odd = 2 } } }`,
		remote:  `{ futureThing = 2, other = "r", realms = { R = { odd = 3, chars = { Al = { newField = 1 } } } } }`,
		want:    `{ futureThing = 1, other = "r", realms = { R = { odd = 1, chars = { Al = { newField = 1 } } }, S = { odd = 2 } } }`,
		unknown: []string{"futureThing", "other", "realms.*.chars.*.newField", "realms.*.odd"}},
}

func TestRules(t *testing.T) {
	for _, c := range ruleCases {
		t.Run(c.name, func(t *testing.T) {
			l, r, want := lua(t, c.local), lua(t, c.remote), lua(t, c.want)
			got, rep := run(l, r)
			same(t, "merge(local, remote)", got, want)
			if c.union {
				back, _ := run(r, l)
				same(t, "merge(remote, local)", back, want)
			}
			again, _ := run(got, got)
			same(t, "merge(m, m)", again, got)
			if c.unknown != nil || len(rep.Unknown) > 0 {
				if !reflect.DeepEqual(rep.Unknown, c.unknown) {
					t.Errorf("unknown = %q, want %q", rep.Unknown, c.unknown)
				}
			}
		})
	}
}

func TestIdempotentOnEachInput(t *testing.T) {
	for _, c := range ruleCases {
		if c.pruned {
			continue
		}
		for _, src := range []string{c.local, c.remote, c.want} {
			v := lua(t, src)
			got, _ := run(v, v)
			// Records that lose to an entry the same side holds aren't realistic input; every input
			// above keeps entries and records apart, so a self-merge changes nothing.
			if !luasv.Equal(got, v) {
				t.Errorf("%s: merge(a, a) != a\n got %s\nwant %s", c.name, show(got), show(v))
			}
		}
	}
}

func TestInputsUntouched(t *testing.T) {
	for _, c := range ruleCases {
		l, r := lua(t, c.local), lua(t, c.remote)
		lc, rc := canon(l), canon(r)
		got, _ := run(l, r)
		if canon(l) != lc || canon(r) != rc {
			t.Fatalf("%s: an input changed", c.name)
		}
		// The result shares no table with the inputs.
		if gt := asTable(got); gt != nil {
			gt.SetS("settingsAt", 1.0)
			if canon(l) != lc || canon(r) != rc {
				t.Fatalf("%s: result aliases an input", c.name)
			}
		}
	}
}

func TestMissingSides(t *testing.T) {
	v := lua(t, `{ realms = { R = { scan = { lastFull = 1, resume = { page = 2 } }, watch = { a = 5 } } } }`)
	got, _ := run(nil, v)
	same(t, "nothing local", got, lua(t, `{ realms = { R = { scan = { lastFull = 1 }, watch = { a = 5 } } } }`))
	got, _ = run(v, nil)
	same(t, "nothing remote", got, v)
	if got, _ := run(nil, nil); got != nil {
		t.Errorf("merge(nil, nil) = %v", got)
	}
}
