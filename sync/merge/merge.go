// Package merge reconciles two copies of TaxTheFoolsDB rule by rule (phase 9 spec section 5,
// catalogued in sync/SCHEMA.md). It is pure: nothing is read from the clock or the disk, and
// neither input is changed.
package merge

import (
	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

// Limits the addon applies to the same data (sales.lua, sell.lua, ledger.lua). The merge applies
// them again so a union never leaves more than the addon itself would keep.
const (
	MaxLedger       = 5000 // Ledger.MAX_ENTRIES
	MaxSales        = 2000 // Sales.MAX_SALES
	MaxPostings     = 500  // Sell.LOG_MAX
	LedgerKeepDays  = 180  // Ledger.KEEP_DAYS
	SalesKeepDays   = 120  // Sales.KEEP_DAYS, also seenMail
	PostingKeepDays = 35   // Sell.LOG_DAYS (Sell.Prune runs at login)
	PendingKeepDays = 7    // Ledger.BID_DAYS, pendingBids and pendingBuys
	RemovalKeepDays = 90   // spec section 5: removal records
	secondsPerDay   = 86400
)

// Options for one merge.
type Options struct {
	// Now is the current time in Unix seconds. It drives the age pruning; 0 turns age pruning
	// off (caps still apply).
	Now int64
}

// Report says what the merge could not place under a rule.
type Report struct {
	// Unknown lists the paths (dynamic keys shown as *) that have no rule in SCHEMA.md. Their local
	// value was kept (the remote one when only the remote had it). Sorted, each once.
	Unknown []string
}

type merger struct {
	now     float64
	unknown map[string]bool
}

// rule merges the values of one key. ok reports whether either side had it; the result is absent
// when present is false.
type rule func(l, r luasv.Value, lok, rok bool, path string) (v luasv.Value, present bool)

// Merge returns local ⊕ remote: the TaxTheFoolsDB values of this device and of the server. Either may
// be nil (no file yet, or an empty server).
func Merge(local, remote luasv.Value, opts Options) (luasv.Value, Report) {
	m := &merger{now: float64(opts.Now), unknown: map[string]bool{}}
	l, r := asTable(local), asTable(remote)
	var out luasv.Value
	if l == nil && r == nil {
		out = clone(local)
	} else {
		out = m.top(l, r)
	}
	return out, Report{Unknown: sortedStrings(m.unknown)}
}

// fields merges two tables key by key. Keys without a rule go to m.other.
func (m *merger) fields(l, r *luasv.Table, path string, rules map[string]rule) *luasv.Table {
	out := luasv.NewTable()
	for _, k := range keys(l, r) {
		lv, lok := field(l, k)
		rv, rok := field(r, k)
		p := keyName(k)
		if path != "" {
			p = path + "." + p
		}
		fn := m.other
		if s, isStr := k.(string); isStr {
			if f, ok := rules[s]; ok {
				fn = f
			}
		}
		if v, ok := fn(lv, rv, lok, rok, p); ok {
			out.Set(k, v)
		}
	}
	return out
}

// other is the rule for a path SCHEMA.md doesn't list: local wins, and the path is reported.
func (m *merger) other(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	m.unknown[path] = true
	return preferLocal(l, r, lok, rok, path)
}

// mapOf applies f to every key of a map table (keys dynamic, shown as * in paths).
func (m *merger) mapOf(f rule) rule {
	return func(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
		lt, rt := asTable(l), asTable(r)
		if (lok && lt == nil) || (rok && rt == nil) {
			return m.other(l, r, lok, rok, path)
		}
		out := luasv.NewTable()
		for _, k := range keys(lt, rt) {
			lv, lok := field(lt, k)
			rv, rok := field(rt, k)
			if v, ok := f(lv, rv, lok, rok, path+".*"); ok {
				out.Set(k, v)
			}
		}
		return out, true
	}
}

// table applies fields to a sub-table with its own rules.
func (m *merger) table(rules map[string]rule) rule {
	return func(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
		lt, rt := asTable(l), asTable(r)
		if (lok && lt == nil) || (rok && rt == nil) {
			return m.other(l, r, lok, rok, path)
		}
		return m.fields(lt, rt, path, rules), true
	}
}

func preferLocal(l, r luasv.Value, lok, rok bool, _ string) (luasv.Value, bool) {
	if lok {
		return clone(l), true
	}
	if rok {
		return clone(r), true
	}
	return nil, false
}

func preferRemote(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	return preferLocal(r, l, rok, lok, path)
}

func localOnly(l, _ luasv.Value, lok, _ bool, _ string) (luasv.Value, bool) {
	if lok {
		return clone(l), true
	}
	return nil, false
}

func maxNum(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	a, aok := asNum(l)
	b, bok := asNum(r)
	if aok && bok && b > a {
		return b, true
	}
	if aok || !rok {
		return preferLocal(l, r, lok, rok, path)
	}
	return clone(r), true
}

func or(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	a, aok := l.(bool)
	b, bok := r.(bool)
	if aok && bok {
		return a || b, true
	}
	if lok && rok && (a || b) {
		return true, true
	}
	return preferLocal(l, r, lok, rok, path)
}

// newerAt keeps the table with the larger `at` (local on a tie).
func newerAt(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	if lok && rok && numOr(asTable(r), "at", -1) > numOr(asTable(l), "at", -1) {
		return clone(r), true
	}
	return preferLocal(l, r, lok, rok, path)
}

func (m *merger) top(l, r *luasv.Table) *luasv.Table {
	rules := map[string]rule{
		"settings":    m.settings(l, r),
		"settingsAt":  maxNum,
		"items":       m.mapOf(item),
		"realms":      m.mapOf(m.realm),
		"recipes":     m.mapOf(m.table(map[string]rule{"trainer": m.mapOf(newerAt), "seen": m.mapOf(newerAt)})),
		"dataVersion": maxNum,
		"version":     localOnly,
		"sync":        localOnly,
		"probe":       localOnly,
	}
	return m.fields(l, r, "", rules)
}

// settings: the whole table from the side with the newer settingsAt (local on a tie), except the
// mail keep list and its removal records, which are unioned.
func (m *merger) settings(lTop, rTop *luasv.Table) rule {
	return func(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
		lt, rt := asTable(l), asTable(r)
		win := lt
		if rt != nil && (lt == nil || numOr(rTop, "settingsAt", 0) > numOr(lTop, "settingsAt", 0)) {
			win = rt
		}
		if win == nil {
			return preferLocal(l, r, lok, rok, path)
		}
		out := clone(win).(*luasv.Table)
		lm, rm := fieldT(lt, "mail"), fieldT(rt, "mail")
		keep, removed := m.withRemovals(fieldT(lm, "keep"), fieldT(rm, "keep"),
			fieldT(lm, "keepRemoved"), fieldT(rm, "keepRemoved"), stampAdded, pickLater(stampAdded))
		if keep == nil && removed == nil {
			return out, true
		}
		mail := fieldT(out, "mail")
		if mail == nil {
			mail = luasv.NewTable()
			out.SetS("mail", mail)
		}
		if keep != nil {
			mail.SetS("keep", keep)
		}
		if removed != nil {
			mail.SetS("keepRemoved", removed)
		}
		return out, true
	}
}

// ---------- items ----------

// item: every field from whichever side has it. Learned facts (vb with vbLimited, and each dep
// duration) come from the remote side when both have them: the addon has no stamp on them.
func item(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	lt, rt := asTable(l), asTable(r)
	if lt == nil || rt == nil {
		return preferLocal(l, r, lok, rok, path)
	}
	out := luasv.NewTable()
	for _, k := range keys(lt, rt) {
		if k == "vb" || k == "vbLimited" || k == "dep" {
			continue
		}
		lv, lok := field(lt, k)
		rv, rok := field(rt, k)
		v, _ := preferLocal(lv, rv, lok, rok, "")
		out.Set(k, v)
	}
	vbSide := lt
	if _, ok := field(rt, "vb"); ok {
		vbSide = rt
	}
	for _, k := range []string{"vb", "vbLimited"} {
		if v, ok := field(vbSide, k); ok {
			out.SetS(k, clone(v))
		}
	}
	ld, lok2 := field(lt, "dep")
	rd, rok2 := field(rt, "dep")
	if lok2 || rok2 {
		ldt, rdt := asTable(ld), asTable(rd)
		if (lok2 && ldt == nil) || (rok2 && rdt == nil) {
			v, _ := preferRemote(ld, rd, lok2, rok2, "")
			out.SetS("dep", v)
		} else {
			dep := luasv.NewTable()
			for _, k := range keys(rdt, ldt) {
				lv, a := field(ldt, k)
				rv, b := field(rdt, k)
				v, _ := preferRemote(lv, rv, a, b, "")
				dep.Set(k, v)
			}
			out.SetS("dep", dep)
		}
	}
	return out, true
}

// ---------- realms ----------

func (m *merger) realm(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	lt, rt := asTable(l), asTable(r)
	if (lok && lt == nil) || (rok && rt == nil) {
		return m.other(l, r, lok, rok, path)
	}
	lrem, rrem := fieldT(lt, "removed"), fieldT(rt, "removed")
	watch, rmWatch := m.withRemovals(fieldT(lt, "watch"), fieldT(rt, "watch"),
		fieldT(lrem, "watch"), fieldT(rrem, "watch"), stampAdded, pickLater(stampAdded))
	snipe, rmSnipe := m.withRemovals(fieldT(lt, "snipe"), fieldT(rt, "snipe"),
		fieldT(lrem, "snipe"), fieldT(rrem, "snipe"), entryAt, pickLater(entryAt))
	fixed := func(v *luasv.Table) rule {
		return func(_, _ luasv.Value, _, _ bool, _ string) (luasv.Value, bool) { return v, v != nil }
	}
	lhist, rhist := fieldT(lt, "history"), fieldT(rt, "history")
	rules := map[string]rule{
		"history": m.mapOf(m.history),
		"market":  m.market(lhist, rhist),
		"scan": m.table(map[string]rule{
			"lastFull": maxNum,
			"resume":   localOnly,
		}),
		"snapshot": newerChange,
		"chars":    m.mapOf(m.char),
		"watch":    fixed(watch),
		"snipe":    fixed(snipe),
		"removed": m.table(map[string]rule{
			"watch": fixed(rmWatch),
			"snipe": fixed(rmSnipe),
		}),
	}
	return m.fields(lt, rt, path, rules), true
}

// history merges one key's price history. foldedTo, the newest day P.Compact has folded into months
// on either device, is the max of both sides; day rows at or below it are dropped (already counted in a
// month), the rest are unioned with dayRow. Months use the larger n.
func (m *merger) history(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	lt, rt := asTable(l), asTable(r)
	if (lok && lt == nil) || (rok && rt == nil) {
		return m.other(l, r, lok, rok, path)
	}
	out := m.fields(lt, rt, path, map[string]rule{
		"days":     m.mapOf(dayRow),
		"months":   m.mapOf(largerN),
		"foldedTo": maxNum,
	})
	fv, _ := field(out, "foldedTo")
	folded, ok := asNum(fv)
	days := fieldT(out, "days")
	if !ok || days == nil {
		return out, true
	}
	for _, k := range keys(days, nil) {
		if day, isNum := asNum(k); isNum && day <= folded {
			days.Delete(k)
		}
	}
	return out, true
}

// dayRow mirrors P.Record: a browse row never replaces a scan row (full, watch, mats, snipe) for the
// same day; within the same class the row with more listings (n) wins, local on a tie.
func dayRow(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	if !lok || !rok {
		return preferLocal(l, r, lok, rok, path)
	}
	class := func(v luasv.Value) int {
		src, _ := field(asTable(v), "src")
		if src == "browse" {
			return 0
		}
		return 1
	}
	if cl, cr := class(l), class(r); cl != cr {
		if cr > cl {
			return clone(r), true
		}
		return clone(l), true
	}
	return largerN(l, r, lok, rok, path)
}

// newerChange keeps the snapshot changed last: changedAt, else at (scan.lua). Local on a tie.
func newerChange(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	stamp := func(v luasv.Value) float64 {
		t := asTable(v)
		return numOr(t, "changedAt", numOr(t, "at", -1))
	}
	if lok && rok && stamp(r) > stamp(l) {
		return clone(r), true
	}
	return preferLocal(l, r, lok, rok, path)
}

// largerN keeps the history row with more listings (n), local on a tie.
func largerN(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	if lok && rok && numOr(asTable(r), "n", -1) > numOr(asTable(l), "n", -1) {
		return clone(r), true
	}
	return preferLocal(l, r, lok, rok, path)
}

// market: per key, the side whose history has the newest day for that key (local on a tie). The
// addon recomputes it at login anyway (Scan.RecomputeMarket).
func (m *merger) market(lhist, rhist *luasv.Table) rule {
	newest := func(hist *luasv.Table, k luasv.Value) float64 {
		best := -1.0
		e, _ := field(hist, k)
		for _, d := range keys(fieldT(asTable(e), "days"), nil) {
			if f, ok := asNum(d); ok && f > best {
				best = f
			}
		}
		return best
	}
	return func(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
		lt, rt := asTable(l), asTable(r)
		if (lok && lt == nil) || (rok && rt == nil) {
			return m.other(l, r, lok, rok, path)
		}
		out := luasv.NewTable()
		for _, k := range keys(lt, rt) {
			lv, a := field(lt, k)
			rv, b := field(rt, k)
			if a && b && newest(rhist, k) > newest(lhist, k) {
				out.Set(k, clone(rv))
				continue
			}
			v, _ := preferLocal(lv, rv, a, b, "")
			out.Set(k, v)
		}
		return out, true
	}
}

// ---------- characters ----------

func (m *merger) char(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	lt, rt := asTable(l), asTable(r)
	if (lok && lt == nil) || (rok && rt == nil) {
		return m.other(l, r, lok, rok, path)
	}
	// bags and bank go with their capture stamps.
	pair := map[string]*luasv.Table{}
	for _, p := range [][2]string{{"bags", "bagsAt"}, {"bank", "bankAt"}} {
		side := lt
		if lt == nil || (rt != nil && numOr(rt, p[1], -1) > numOr(lt, p[1], -1)) {
			side = rt
		}
		pair[p[0]], pair[p[1]] = side, side
	}
	fromPair := func(_, _ luasv.Value, _, _ bool, path string) (luasv.Value, bool) {
		k := path[lastDot(path)+1:]
		v, ok := field(pair[k], k)
		return clone(v), ok
	}
	rules := map[string]rule{
		"class":            preferLocal,
		"bags":             fromPair,
		"bagsAt":           fromPair,
		"bank":             fromPair,
		"bankAt":           fromPair,
		"professions":      m.mapOf(newerAt),
		"sales":            m.list(salesSpec),
		"postings":         m.list(postingsSpec),
		"ledger":           m.list(ledgerSpec),
		"pendingBids":      m.list(pendingSpec),
		"pendingBuys":      m.list(pendingSpec),
		"seenMail":         m.seenMail,
		"ledgerBackfilled": or,
	}
	return m.fields(lt, rt, path, rules), true
}

func lastDot(s string) int {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == '.' {
			return i
		}
	}
	return -1
}

// seenMail: per key the entry changed last (`at`, stamped by every write including Mail.Forget);
// on a tie the larger count n, then local. Keys older than 120 days go, as in Sales.Prune. The old
// format, a bare timestamp, counts as one mail stamped at that time.
func (m *merger) seenMail(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
	lt, rt := asTable(l), asTable(r)
	if (lok && lt == nil) || (rok && rt == nil) {
		return m.other(l, r, lok, rok, path)
	}
	count := func(v luasv.Value) float64 {
		if t := asTable(v); t != nil {
			return numOr(t, "n", 1)
		}
		return 1
	}
	stamp := func(v luasv.Value) float64 {
		if t := asTable(v); t != nil {
			return numOr(t, "at", -1)
		}
		if f, ok := asNum(v); ok {
			return f
		}
		return -1
	}
	newer := func(l, r luasv.Value) bool {
		if stamp(r) != stamp(l) {
			return stamp(r) > stamp(l)
		}
		return count(r) > count(l)
	}
	out := luasv.NewTable()
	for _, k := range keys(lt, rt) {
		lv, a := field(lt, k)
		rv, b := field(rt, k)
		v := lv
		if !a || (b && newer(lv, rv)) {
			v = rv
		}
		if m.now > 0 {
			at, ok := asNum(v)
			if t := asTable(v); t != nil {
				x, _ := field(t, "at")
				at, ok = asNum(x)
			}
			if !ok || at < m.now-SalesKeepDays*secondsPerDay {
				continue
			}
		}
		out.Set(k, clone(v))
	}
	return out, true
}

// ---------- lists with removal records ----------

// stampAdded: watch and keep values are the time added; an old `true` counts as 0.
func stampAdded(v luasv.Value) float64 {
	if f, ok := asNum(v); ok {
		return f
	}
	return 0
}

// entryAt: snipe entries carry `at`.
func entryAt(v luasv.Value) float64 { return numOr(asTable(v), "at", 0) }

// pickLater keeps the entry added later, local on a tie.
func pickLater(added func(luasv.Value) float64) func(l, r luasv.Value) luasv.Value {
	return func(l, r luasv.Value) luasv.Value {
		if added(r) > added(l) {
			return r
		}
		return l
	}
}

// withRemovals unions two keyed lists and their removal records. An entry survives when it was
// added after the latest removal of its key; a surviving entry's record is dropped (the addon
// clears the record on a re-add). Records are unioned keeping the latest time and pruned after 90
// days. Either result is nil when neither side had that table.
func (m *merger) withRemovals(le, re, lrm, rrm *luasv.Table, added func(luasv.Value) float64,
	pick func(l, r luasv.Value) luasv.Value) (entries, removed *luasv.Table) {
	rec := map[string]float64{}
	recKey := map[string]luasv.Value{}
	for _, t := range []*luasv.Table{lrm, rrm} {
		for _, k := range keys(t, nil) {
			v, _ := field(t, k)
			f, ok := asNum(v)
			if !ok {
				continue
			}
			c := canon(k)
			if old, seen := rec[c]; !seen || f > old {
				rec[c] = f
				recKey[c] = k
			}
		}
	}
	if le != nil || re != nil {
		entries = luasv.NewTable()
		for _, k := range keys(le, re) {
			lv, a := field(le, k)
			rv, b := field(re, k)
			v := lv
			switch {
			case a && b:
				v = pick(lv, rv)
			case b:
				v = rv
			}
			c := canon(k)
			if at, has := rec[c]; has {
				if added(v) <= at {
					continue
				}
				delete(rec, c)
			}
			entries.Set(k, clone(v))
		}
	}
	if lrm != nil || rrm != nil {
		removed = luasv.NewTable()
		for _, k := range keys(lrm, rrm) {
			c := canon(k)
			at, has := rec[c]
			if !has || (m.now > 0 && at < m.now-RemovalKeepDays*secondsPerDay) {
				continue
			}
			removed.Set(recKey[c], at)
		}
	}
	return entries, removed
}
