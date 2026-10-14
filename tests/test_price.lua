local P = TaxTheFools.Price
local TODAY = 20375

local function L(unit, qty, owner) return { key = "14047:0", unit = unit, qty = qty, owner = owner } end

T.test("summary weights by quantity and ignores one cheap single unit", function()
  local rows = P.Summarize({ L(1, 1, "Troll"), L(400, 20, "A"), L(410, 20, "B"), L(900, 20, "A") })
  local r = rows["14047:0"]
  T.eq(r.n, 4) T.eq(r.qty, 61)
  T.eq(r.min, 1, "min is honest")
  T.eq(r.p25, 400, "p25 isn't fooled by the troll")
  T.eq(r.med, 410)
  T.eq(r.sellers, 3)
end)

T.test("bid-only listings count but carry no price", function()
  local rows = P.Summarize({ L(nil, 5, nil) })
  local r = rows["14047:0"]
  T.eq(r.n, 1) T.eq(r.qty, 5)
  T.eq(r.p25, nil) T.eq(r.min, nil) T.eq(r.sellers, nil)
end)

T.test("a browse never overwrites a full scan's row from the same day", function()
  local hist = {}
  P.Record(hist, { ["14047:0"] = { n = 100, p25 = 400 } }, TODAY, "full")
  local touched = P.Record(hist, { ["14047:0"] = { n = 3, p25 = 999 } }, TODAY, "browse")
  T.eq(table.getn(touched), 0)
  T.eq(hist["14047:0"].days[TODAY].p25, 400)
  T.eq(hist["14047:0"].days[TODAY].src, "full")
end)

T.test("watch replaces, and browse replaces a browse", function()
  local hist = {}
  P.Record(hist, { k = { n = 1, p25 = 10 } }, TODAY, "browse")
  P.Record(hist, { k = { n = 2, p25 = 20 } }, TODAY, "browse")
  T.eq(hist.k.days[TODAY].p25, 20)
  P.Record(hist, { k = { n = 3, p25 = 30 } }, TODAY, "watch")
  T.eq(hist.k.days[TODAY].p25, 30)
end)

local function entry(days) local e = { days = {}, months = {} } for d, v in pairs(days) do e.days[TODAY - d] = v end return e end

T.test("recent days count more than old ones", function()
  local m = P.Market(entry({ [0] = { p25 = 100, min = 90 }, [10] = { p25 = 200, min = 150 } }), TODAY)
  T.eq(m.v, 100)
  T.eq(m.low, 90, "low comes from the newest row")
  T.eq(m.lowDay, TODAY)
end)

T.test("confidence grows with days seen and falls with volatility", function()
  local three = P.Market(entry({ [0] = { p25 = 100 }, [1] = { p25 = 100 }, [2] = { p25 = 100 } }), TODAY)
  T.near(three.conf, 0.6, 0.001) T.eq(P.ConfLabel(three.conf), "medium")
  local five = P.Market(entry({ [0] = { p25 = 100 }, [1] = { p25 = 100 }, [2] = { p25 = 100 }, [3] = { p25 = 100 }, [4] = { p25 = 100 } }), TODAY)
  T.eq(five.conf, 1) T.eq(P.ConfLabel(five.conf), "high")
  local wild = P.Market(entry({ [0] = { p25 = 50 }, [1] = { p25 = 150 }, [2] = { p25 = 50 }, [3] = { p25 = 150 }, [4] = { p25 = 50 } }), TODAY)
  T.near(wild.conf, 0.5464, 0.001)
  T.eq(P.ConfLabel(0.2), "low")
end)

T.test("days older than 30 are left out of market value", function()
  local m = P.Market(entry({ [0] = { p25 = 100 }, [31] = { p25 = 5000 } }), TODAY)
  T.eq(m.v, 100) T.eq(m.seen, 1)
end)

T.test("only monthly data falls back with low confidence", function()
  local e = { days = {}, months = { [202501] = { p25 = 300, n = 5, d = 4 } } }
  local m = P.Market(e, TODAY)
  T.eq(m.v, 300) T.eq(m.conf, 0.1)
end)

T.test("no priced data, or a damaged entry, gives no market value", function()
  T.eq(P.Market(entry({ [0] = { n = 2 } }), TODAY), nil)
  T.eq(P.Market({}, TODAY), nil, "entry without days/months tables")
  T.eq(P.Market(nil, TODAY), nil)
end)

T.test("old days fold into months and very old months are dropped", function()
  local e = entry({ [0] = { p25 = 100 }, [70] = { p25 = 200, n = 4 }, [71] = { p25 = 300, n = 6 } })
  e.months[201001] = { p25 = 1, n = 1, d = 1 }
  local empty = P.Compact(e, TODAY)
  T.eq(empty, false)
  T.eq(e.days[TODAY - 70], nil)
  T.ok(e.days[TODAY], "recent day kept")
  local month = tonumber(date("!%Y%m", (TODAY - 70) * 86400))
  T.eq(e.months[month].p25, 250, "mean of the folded days")
  T.eq(e.months[month].d, 2)
  T.eq(e.months[201001], nil, "month older than a year dropped")
end)

T.test("compacting an entry with nothing recent reports it empty", function()
  local e = entry({ [400] = { n = 1 } })
  T.eq(P.Compact(e, TODAY), true)
end)
