package merge

import (
	"sort"
	"strings"

	"github.com/FateFirst/tax-the-fools/sync/luasv"
)

// listSpec describes one per-character list (sales, postings, ledger, pending bids and buys).
type listSpec struct {
	// id is the identity of an entry: entries with the same id on both sides are one entry.
	id []string
	// grow names kinds whose entries grow in place (one per merchant visit or send chain). They are
	// matched on (at, kind, who) and the larger amount is kept.
	grow map[string]bool
	// doneFirst pairs finished postings first within an identity group.
	doneFirst bool
	// maxFields take the larger number of a pair (`used` on a settled bid or buy marker).
	maxFields []string
	keepDays  float64
	cap       int
}

var (
	// Sales.Record entries { key, name, outcome, money, at, qty, unit, secs }. The name is used when
	// present (it is always set by Record): Sales.ResolveNames fills `key` in later, so the key
	// alone could differ between two copies of one sale.
	salesSpec = listSpec{id: []string{"at", "outcome", "money", "name|key"}, keepDays: SalesKeepDays, cap: MaxSales}
	// Sell.Log and Sales.Reconcile entries { key, stack, bid, buyout, minutes, deposit, at, done, reconciled }.
	postingsSpec = listSpec{id: []string{"at", "key", "stack", "buyout"}, doneFirst: true, keepDays: PostingKeepDays, cap: MaxPostings}
	// Ledger.Add entries { at, kind, amount, key, qty, who }.
	ledgerSpec = listSpec{id: []string{"at", "kind", "amount", "key"},
		grow: map[string]bool{"vendorIn": true, "vendorOut": true, "mailOut": true}, keepDays: LedgerKeepDays, cap: MaxLedger}
	// pendingBids { name, amount, at, key, used } and pendingBuys { name, at, used }. A settled entry
	// keeps `used`, the latest of both sides.
	pendingSpec = listSpec{id: []string{"name", "amount", "at"}, maxFields: []string{"used"}, keepDays: PendingKeepDays}
)

func (s listSpec) idOf(v luasv.Value) string {
	t := asTable(v)
	if t == nil {
		return "v" + canon(v)
	}
	if s.grow != nil {
		kind, _ := field(t, "kind")
		if k, ok := kind.(string); ok && s.grow[k] {
			at, _ := field(t, "at")
			who, _ := field(t, "who")
			return "g" + canon(at) + "\x00" + k + "\x00" + canon(who)
		}
	}
	var b strings.Builder
	b.WriteString("i")
	for _, f := range s.id {
		var v luasv.Value
		for _, alt := range strings.Split(f, "|") {
			if x, ok := field(t, alt); ok {
				v = x
				break
			}
		}
		b.WriteString(canon(v))
		b.WriteString("\x00")
	}
	return b.String()
}

// maxOf sets each of fields in merged to b's value when that is a larger number.
func maxOf(merged, b luasv.Value, fields []string) luasv.Value {
	mt, bt := asTable(merged), asTable(b)
	if mt == nil || bt == nil {
		return merged
	}
	for _, f := range fields {
		bv, ok := field(bt, f)
		bn, isNum := asNum(bv)
		if !ok || !isNum {
			continue
		}
		if mv, ok := field(mt, f); ok {
			if mn, isNum := asNum(mv); isNum && mn >= bn {
				continue
			}
		}
		mt.SetS(f, bn)
	}
	return merged
}

func atOf(v luasv.Value) float64 { return numOr(asTable(v), "at", 0) }

// unionFields: a's fields, plus b's where a has none.
func unionFields(a, b luasv.Value) luasv.Value {
	at, bt := asTable(a), asTable(b)
	if at == nil || bt == nil {
		return clone(a)
	}
	out := clone(at).(*luasv.Table)
	for _, k := range keys(bt, nil) {
		if _, ok := field(out, k); !ok {
			v, _ := field(bt, k)
			out.Set(k, clone(v))
		}
	}
	return out
}

// list merges a list as a multiset: each identity appears as many times as on the side that has it
// most often (identical entries in one second are real, for example two identical sold mails).
// Paired entries take the union of their fields, local first. Growable ledger entries pair largest
// with largest and keep the larger amount. When the result holds exactly one side's entries, that
// side's order is kept; otherwise entries are sorted by `at`. Then the addon's age limit and cap
// apply, dropping the oldest first.
func (m *merger) list(s listSpec) rule {
	return func(l, r luasv.Value, lok, rok bool, path string) (luasv.Value, bool) {
		lt, rt := asTable(l), asTable(r)
		if (lok && lt == nil) || (rok && rt == nil) {
			return m.other(l, r, lok, rok, path)
		}
		le, re := elements(lt), elements(rt)
		lg, order := group(s, le, nil)
		rg, order := group(s, re, order)
		var out []luasv.Value
		for _, id := range order {
			a, b := lg[id], rg[id]
			if strings.HasPrefix(id, "g") {
				byAmount := func(xs []luasv.Value) {
					sort.SliceStable(xs, func(i, j int) bool {
						return numOr(asTable(xs[i]), "amount", 0) > numOr(asTable(xs[j]), "amount", 0)
					})
				}
				byAmount(a)
				byAmount(b)
			} else if s.doneFirst {
				done := func(xs []luasv.Value) {
					sort.SliceStable(xs, func(i, j int) bool {
						_, di := field(asTable(xs[i]), "done")
						_, dj := field(asTable(xs[j]), "done")
						return di && !dj
					})
				}
				done(a)
				done(b)
			}
			for i := 0; i < len(a) || i < len(b); i++ {
				switch {
				case i >= len(b):
					out = append(out, clone(a[i]))
				case i >= len(a):
					out = append(out, clone(b[i]))
				case strings.HasPrefix(id, "g"):
					if numOr(asTable(b[i]), "amount", 0) > numOr(asTable(a[i]), "amount", 0) {
						out = append(out, clone(b[i]))
					} else {
						out = append(out, clone(a[i]))
					}
				default:
					out = append(out, maxOf(unionFields(a[i], b[i]), b[i], s.maxFields))
				}
			}
		}
		switch {
		case sameMultiset(out, le):
			out = cloneAll(le)
		case sameMultiset(out, re):
			out = cloneAll(re)
		default:
			sort.SliceStable(out, func(i, j int) bool {
				ai, aj := atOf(out[i]), atOf(out[j])
				if ai != aj {
					return ai < aj
				}
				return canon(out[i]) < canon(out[j])
			})
		}
		if m.now > 0 && s.keepDays > 0 {
			cutoff := m.now - s.keepDays*secondsPerDay
			kept := out[:0]
			for _, v := range out {
				if atOf(v) >= cutoff {
					kept = append(kept, v)
				}
			}
			out = kept
		}
		out = capOldest(out, s.cap)
		return list(out), true
	}
}

func group(s listSpec, vals []luasv.Value, order []string) (map[string][]luasv.Value, []string) {
	g := map[string][]luasv.Value{}
	seen := map[string]bool{}
	for _, id := range order {
		seen[id] = true
	}
	for _, v := range vals {
		id := s.idOf(v)
		g[id] = append(g[id], v)
		if !seen[id] {
			seen[id] = true
			order = append(order, id)
		}
	}
	return g, order
}

func cloneAll(vals []luasv.Value) []luasv.Value {
	out := make([]luasv.Value, len(vals))
	for i, v := range vals {
		out[i] = clone(v)
	}
	return out
}

func sameMultiset(a, b []luasv.Value) bool {
	if len(a) != len(b) {
		return false
	}
	n := map[string]int{}
	for _, v := range a {
		n[canon(v)]++
	}
	for _, v := range b {
		c := canon(v)
		if n[c] == 0 {
			return false
		}
		n[c]--
	}
	return true
}

// capOldest drops the oldest entries (by `at`, earlier position first on a tie) until at most max
// remain, keeping the order of the rest. max 0 means no cap.
func capOldest(vals []luasv.Value, max int) []luasv.Value {
	if max <= 0 || len(vals) <= max {
		return vals
	}
	idx := make([]int, len(vals))
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(i, j int) bool { return atOf(vals[idx[i]]) < atOf(vals[idx[j]]) })
	drop := map[int]bool{}
	for _, i := range idx[:len(vals)-max] {
		drop[i] = true
	}
	out := make([]luasv.Value, 0, max)
	for i, v := range vals {
		if !drop[i] {
			out = append(out, v)
		}
	}
	return out
}
