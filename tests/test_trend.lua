-- trends: price, tooltip and browse column
local DB, P, Tip, Browse, U = TaxTheFools.DB, TaxTheFools.Price, TaxTheFools.Tooltip, TaxTheFools.Browse, TaxTheFools.Util

local TODAY = 20400

-- Builds an entry with p25 per age: ages = { [0] = 100, [1] = 100 ... }
local function entry(ages)
  local e = { days = {}, months = {} }
  for age, p in pairs(ages) do e.days[TODAY - age] = { p25 = p, min = p, n = 5 } end
  return e
end

local function flat(recent, prior)
  local a = {}
  for d = 0, 6 do a[d] = recent end
  for d = 7, 13 do a[d] = prior end
  return entry(a)
end

T.test("Trend: rising, falling and steady", function()
  local t = P.Trend(flat(112, 100), TODAY)
  T.eq(t.dir, "rising") T.eq(t.pct, 12) T.eq(t.recent, 112) T.eq(t.prior, 100)
  t = P.Trend(flat(92, 100), TODAY)
  T.eq(t.dir, "falling") T.eq(t.pct, -8)
  t = P.Trend(flat(103, 100), TODAY)
  T.eq(t.dir, "steady") T.eq(t.pct, 3)
  T.eq(P.Trend(flat(100, 100), TODAY).pct, 0)
  T.eq(P.Trend(flat(105, 100), TODAY).dir, "rising")
  T.eq(P.Trend(flat(95, 100), TODAY).dir, "falling")
end)

T.test("Trend: needs 3 days each side, tolerates gaps", function()
  T.eq(P.Trend(nil, TODAY), nil)
  T.eq(P.Trend(entry({ [0] = 100, [1] = 100, [7] = 100, [8] = 100, [9] = 100 }), TODAY), nil)
  T.eq(P.Trend(entry({ [0] = 100, [1] = 100, [2] = 100, [7] = 100, [8] = 100 }), TODAY), nil)
  local t = P.Trend(entry({ [0] = 120, [3] = 120, [6] = 120, [7] = 100, [10] = 100, [13] = 100 }), TODAY)
  T.eq(t.pct, 20)
  -- days 14 and older and the future do not count
  T.eq(P.Trend(entry({ [0] = 100, [1] = 100, [2] = 100, [14] = 100, [15] = 100, [16] = 100 }), TODAY), nil)
end)

T.test("Trend: uses the median of each side", function()
  local t = P.Trend(entry({ [0] = 100, [1] = 100, [2] = 1000, [7] = 100, [8] = 100, [9] = 100 }), TODAY)
  T.eq(t.recent, 100) T.eq(t.dir, "steady")
end)

T.test("Series: oldest first, gaps left out, windowed", function()
  local s = P.Series(entry({ [0] = 50, [2] = 60, [5] = 70, [40] = 9 }), TODAY, 30)
  T.eq(table.getn(s), 3)
  T.eq(s[1].day, TODAY - 5) T.eq(s[1].p25, 70)
  T.eq(s[3].day, TODAY) T.eq(s[3].p25, 50)
  T.eq(table.getn(P.Series(entry({ [0] = 50, [2] = 60, [5] = 70 }), TODAY, 3)), 2)
  T.eq(table.getn(P.Series(nil, TODAY, 30)), 0)
end)

local function trendLine(lines)
  for _, l in ipairs(lines) do if l[1] == "Trend 7d" then return l[2] end end
end

T.test("the tooltip shows the trend, and not when off or unknown", function()
  DB.Realm().market["14047:0"] = { v = 400, conf = 0.8, seen = 6 }
  DB.Realm().history["14047:0"] = flat(112, 100)
  local now = TODAY * 86400 + 100
  local t = trendLine(Tip.Lines("14047:0", 1, now))
  T.ok(t and string.find(t, "+12% rising", 1, true), tostring(t))
  DB.Realm().history["14047:0"] = flat(92, 100)
  T.ok(string.find(trendLine(Tip.Lines("14047:0", 1, now)), "-8% falling", 1, true))
  DB.Realm().history["14047:0"] = flat(100, 100)
  T.ok(string.find(trendLine(Tip.Lines("14047:0", 1, now)), "0% steady", 1, true))
  DB.S().trend.tooltip = false
  T.eq(trendLine(Tip.Lines("14047:0", 1, now)), nil)
  DB.S().trend.tooltip = true
  DB.Realm().history["14047:0"] = nil
  T.eq(trendLine(Tip.Lines("14047:0", 1, now)), nil)
end)

T.test("Browse rows get a trend and the column shows it", function()
  local history = { ["1:0"] = flat(112, 100), ["2:0"] = flat(92, 100), ["3:0"] = flat(100, 100) }
  local rows = Browse.Decorate({ { key = "1:0" }, { key = "2:0" }, { key = "3:0" }, { key = "4:0" } }, {}, history, TODAY)
  local col
  for _, c in ipairs(Browse.COLUMNS) do if c.label == "Trend" then col = c end end
  T.ok(col) T.eq(col.width, 56) T.eq(col.flex, nil) T.ok(col.sort)
  T.eq(col.fmt(rows[1]), "+12%") T.eq(col.fmt(rows[2]), "-8%") T.eq(col.fmt(rows[3]), "0%") T.eq(col.fmt(rows[4]), "-")
  T.eq(rows[1][col.sort], 12) T.eq(rows[4][col.sort], nil)
end)

T.test("Browse columns still fit the 660 wide window", function()
  local sum = 0
  for _, c in ipairs(Browse.COLUMNS) do sum = sum + c.width end
  T.ok(sum <= 660 - 20 - 12, "fixed widths " .. sum)
end)
