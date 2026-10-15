local L = TaxTheFools.Ledger
local DAY = 86400
local NOW = 100 * DAY + 5000
local function chars() return { A = {}, B = {} } end

T.test("settings.ledger and settings.trend defaults", function()
  local d = TaxTheFools.Data.DEFAULTS.settings
  T.eq(d.ledger.vendor, true) T.eq(d.trend.tooltip, true)
end)

T.test("Add appends, ignores non-positive amounts and caps at 5000", function()
  local c = {}
  T.eq(L.Add(c, { kind = "sale", amount = 0 }, NOW), nil)
  T.eq(L.Add(c, { kind = "sale", amount = -5 }, NOW), nil)
  T.eq(L.Add(c, { kind = "bogus", amount = 5 }, NOW), nil)
  T.eq(c.ledger, nil)
  local e = L.Add(c, { kind = "sale", amount = 10, key = "1:0", qty = 2 }, NOW)
  T.eq(e.at, NOW) T.eq(table.getn(c.ledger), 1)
  for i = 1, 5000 do L.Add(c, { kind = "buy", amount = i }, NOW) end
  T.eq(table.getn(c.ledger), 5000)
  T.eq(c.ledger[1].amount, 1)
end)

T.test("Prune drops entries older than 180 days", function()
  local c = {}
  L.Add(c, { kind = "sale", amount = 1, at = NOW - 181 * DAY }, NOW)
  L.Add(c, { kind = "sale", amount = 2, at = NOW - 179 * DAY }, NOW)
  L.Prune(c, NOW)
  T.eq(table.getn(c.ledger), 1) T.eq(c.ledger[1].amount, 2)
  L.Prune({}, NOW)
end)

T.test("Sign is +1 in, -1 out, 0 transfers", function()
  for _, k in ipairs({ "sale", "vendorIn", "mailIn" }) do T.eq(L.Sign(k), 1) end
  for _, k in ipairs({ "buy", "bid", "deposit", "vendorOut", "mailOut" }) do T.eq(L.Sign(k), -1) end
  T.eq(L.Sign("transferIn"), 0) T.eq(L.Sign("transferOut"), 0)
end)

T.test("Totals sums in, out, net, per day; transfers stay out of profit", function()
  local cs = chars()
  L.Add(cs.A, { kind = "sale", amount = 1000 }, NOW)
  L.Add(cs.A, { kind = "buy", amount = 300 }, NOW)
  L.Add(cs.A, { kind = "transferOut", amount = 5000 }, NOW)
  L.Add(cs.B, { kind = "transferIn", amount = 5000 }, NOW)
  L.Add(cs.B, { kind = "deposit", amount = 100 }, NOW)
  L.Add(cs.B, { kind = "sale", amount = 50, at = NOW - 40 * DAY }, NOW)
  local t = L.Totals(cs, 10, NOW)
  T.eq(t.inn, 1000) T.eq(t.out, 400) T.eq(t.net, 600) T.eq(t.perDay, 60)
  T.eq(t.transferIn, 5000) T.eq(t.transferOut, 5000)
  T.eq(t.byKind.sale, 1000) T.eq(t.byKind.deposit, 100)
  local b = L.Totals(cs, 10, NOW, "B")
  T.eq(b.inn, 0) T.eq(b.out, 100) T.eq(b.transferIn, 5000)
  T.eq(L.Totals(cs, 60, NOW).inn, 1050)
end)

T.test("Totals window is calendar days", function()
  local cs = chars()
  L.Add(cs.A, { kind = "sale", amount = 7, at = 99 * DAY }, NOW)
  T.eq(L.Totals(cs, 1, NOW).inn, 0)
  T.eq(L.Totals(cs, 2, NOW).inn, 7)
end)

T.test("Days gives one row per day, newest first, with transfers left out", function()
  local cs = chars()
  L.Add(cs.A, { kind = "sale", amount = 1000, at = 98 * DAY + 1 }, NOW)
  L.Add(cs.A, { kind = "sale", amount = 500, at = 100 * DAY + 1 }, NOW)
  L.Add(cs.B, { kind = "bid", amount = 200, at = 100 * DAY + 2 }, NOW)
  L.Add(cs.B, { kind = "buy", amount = 100, at = 100 * DAY + 3 }, NOW)
  L.Add(cs.A, { kind = "deposit", amount = 30, at = 100 * DAY + 4 }, NOW)
  L.Add(cs.A, { kind = "vendorIn", amount = 40, at = 100 * DAY + 5 }, NOW)
  L.Add(cs.A, { kind = "vendorOut", amount = 15, at = 100 * DAY + 6 }, NOW)
  L.Add(cs.A, { kind = "mailIn", amount = 60, at = 100 * DAY + 7 }, NOW)
  L.Add(cs.A, { kind = "mailOut", amount = 10, at = 100 * DAY + 8 }, NOW)
  L.Add(cs.A, { kind = "transferOut", amount = 9999, at = 100 * DAY + 9 }, NOW)
  local rows = L.Days(cs, 30, NOW)
  T.eq(table.getn(rows), 2)
  local r = rows[1]
  T.eq(r.day, 100) T.eq(r.sale, 500) T.eq(r.buy, 300) T.eq(r.deposit, 30)
  T.eq(r.vendor, 25) T.eq(r.mail, 50) T.eq(r.net, 500 - 300 - 30 + 25 + 50)
  T.eq(rows[2].day, 98) T.eq(rows[2].net, 1000)
  T.eq(table.getn(L.Days(cs, 30, NOW, "B")), 1)
end)

T.test("ByItem groups by key and sorts by net descending", function()
  local cs = chars()
  L.Add(cs.A, { kind = "sale", amount = 900, key = "1:0", qty = 3 }, NOW)
  L.Add(cs.A, { kind = "buy", amount = 400, key = "1:0", qty = 2 }, NOW)
  L.Add(cs.A, { kind = "deposit", amount = 50, key = "1:0" }, NOW)
  L.Add(cs.B, { kind = "bid", amount = 700, key = "2:0", qty = 1 }, NOW)
  L.Add(cs.B, { kind = "sale", amount = 100, key = "3:0", qty = 1 }, NOW)
  L.Add(cs.B, { kind = "vendorIn", amount = 100 }, NOW)
  local rows = L.ByItem(cs, 30, NOW)
  T.eq(table.getn(rows), 3)
  T.eq(rows[1].key, "1:0") T.eq(rows[1].income, 900) T.eq(rows[1].spend, 450) T.eq(rows[1].net, 450)
  T.eq(rows[1].sold, 3) T.eq(rows[1].bought, 2)
  T.eq(rows[2].key, "3:0") T.eq(rows[3].key, "2:0") T.eq(rows[3].net, -700)
  T.eq(table.getn(L.ByItem(cs, 30, NOW, "A")), 1)
end)

T.test("Backfill adds sold entries once", function()
  local c = { sales = {
    { key = "1:0", outcome = "sold", money = 95, qty = 2, at = NOW - DAY },
    { key = "1:0", outcome = "expired", money = 0, qty = 2, at = NOW - DAY },
    { key = "2:0", outcome = "won", money = 50, qty = 1, at = NOW - DAY },
    { key = "3:0", outcome = "sold", money = 10, qty = 1, at = NOW - 2 * DAY } } }
  T.eq(L.Backfill(c), true)
  T.eq(table.getn(c.ledger), 2)
  T.eq(c.ledger[1].kind, "sale") T.eq(c.ledger[1].amount, 95) T.eq(c.ledger[1].qty, 2) T.eq(c.ledger[1].at, NOW - DAY)
  T.eq(c.ledgerBackfilled, true)
  T.eq(L.Backfill(c), false)
  T.eq(table.getn(c.ledger), 2)
end)

T.test("a won bid becomes a bid entry, newest pending first", function()
  local c = {}
  L.PendingBid(c, "Linen Cloth", 100, NOW, "1:0")
  L.PendingBid(c, "Linen Cloth", 150, NOW + 10, "1:0")
  L.PendingBid(c, "Wool", 70, NOW + 20)
  local e = L.BidWon(c, "Linen Cloth", NOW + 30)
  T.eq(e.kind, "bid") T.eq(e.amount, 150) T.eq(e.key, "1:0") T.eq(e.at, NOW + 30)
  T.eq(table.getn(c.pendingBids), 2)
  T.eq(L.BidWon(c, "Nothing", NOW + 30), nil)
  T.eq(table.getn(c.ledger), 1)
end)

T.test("an outbid bid never becomes spending", function()
  local c = {}
  L.PendingBid(c, "Linen Cloth", 100, NOW)
  T.eq(L.BidLost(c, "Linen Cloth"), true)
  T.eq(table.getn(c.pendingBids), 0)
  T.eq(L.BidWon(c, "Linen Cloth", NOW + 5), nil)
  T.eq(c.ledger, nil)
  T.eq(L.BidLost(c, "Linen Cloth"), false)
  T.eq(L.Totals({ A = c }, 30, NOW + 5).out, 0)
end)

T.test("pending bids older than 7 days are dropped", function()
  local c = {}
  L.PendingBid(c, "Linen Cloth", 100, NOW)
  L.PendingBid(c, "Wool", 50, NOW + 8 * DAY)
  T.eq(table.getn(c.pendingBids), 1) T.eq(c.pendingBids[1].name, "Wool")
  L.PendingBid(c, "Silk", 60, NOW + 8 * DAY)
  T.eq(L.BidWon(c, "Wool", NOW + 16 * DAY + 1), nil)
  T.eq(c.ledger, nil)
end)
