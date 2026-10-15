local S = TaxTheFools.Sales
local DAY = 86400
local items = { [100] = { n = "Linen Cloth" }, [200] = { n = "Potion of (Fire)?" }, [300] = { n = "100% Pure-Ore [x]+$^" } }
local K1, K2 = "100:0", "200:0"

-- The client subject formats, as the probe showed them; restored after each test that sets them.
local FORMATS = { AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s", AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s",
  AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s", AUCTION_WON_MAIL_SUBJECT = "Auction won: %s",
  AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s" }
local function withFormats(fn)
  local keep = {}
  for k, v in pairs(FORMATS) do keep[k] = getglobal(k) setglobal(k, v) end
  fn()
  for k in pairs(FORMATS) do setglobal(k, keep[k]) end
end
local function post(key, stack, buyout, at, deposit) return { key = key, stack = stack, buyout = buyout, at = at, deposit = deposit } end

T.test("settings.sales defaults", function()
  local d = TaxTheFools.Data.DEFAULTS.settings.sales
  T.eq(d.days, 30) T.eq(d.warnPct, 120) T.eq(d.tooltip, true)
end)

T.test("classify maps every subject to its outcome and item name", function()
  withFormats(function()
    local o, n = S.Classify("Auction successful: Linen Cloth") T.eq(o, "sold") T.eq(n, "Linen Cloth")
    o, n = S.Classify("Auction expired: Linen Cloth") T.eq(o, "expired") T.eq(n, "Linen Cloth")
    o, n = S.Classify("Auction cancelled: Linen Cloth") T.eq(o, "cancelled") T.eq(n, "Linen Cloth")
    o, n = S.Classify("Auction won: Linen Cloth") T.eq(o, "won") T.eq(n, "Linen Cloth")
    o, n = S.Classify("Outbid on Linen Cloth") T.eq(o, "outbid") T.eq(n, "Linen Cloth")
    T.eq(S.Classify("Hello friend"), nil)
    T.eq(S.Classify(nil), nil)
  end)
end)

T.test("classify handles item names and formats with pattern magic characters", function()
  withFormats(function()
    local o, n = S.Classify("Auction successful: Potion of (Fire)?") T.eq(o, "sold") T.eq(n, "Potion of (Fire)?")
    o, n = S.Classify("Outbid on 100% Pure-Ore [x]+$^") T.eq(o, "outbid") T.eq(n, "100% Pure-Ore [x]+$^")
    -- a format that is itself full of magic characters: "(Sold) %s [100%]." must match literally.
    setglobal("AUCTION_SOLD_MAIL_SUBJECT", "(Sold) %s [100%].")
    o, n = S.Classify("(Sold) Linen Cloth [100%].") T.eq(o, "sold") T.eq(n, "Linen Cloth")
    T.eq(S.Classify("Sold Linen Cloth 100%x"), nil, "the dots and brackets are not wildcards")
    T.eq(S.Classify("(Sold) Linen Cloth [100%]x"), nil, "'.' is a literal dot")
  end)
end)

T.test("sold mail with one fitting stack and buyout gives qty, unit and secs", function()
  -- buyout 1000, 20 stack, deposit 30. floor(1000 * 0.95) = 950. Money 980 = 950 + 30 deposit back: |980 - 950| = 30 <= 1 + 30.
  local c = { postings = { post(K1, 20, 1000, 1000, 30) } }
  local e = S.Record(c, "sold", "Linen Cloth", 980, 4600, items)
  T.eq(e.key, K1) T.eq(e.outcome, "sold") T.eq(e.money, 980) T.eq(e.qty, 20)
  T.eq(e.unit, 50, "1000 / 20") T.eq(e.secs, 3600, "4600 - 1000") T.eq(e.at, 4600)
  T.eq(c.postings[1].done, "sold") T.eq(table.getn(c.sales), 1)
  -- one copper either way still fits (tolerance 1 + 0): 950 and 951 fit, 953 does not.
  local d = { postings = { post(K1, 20, 1000, 0) } }
  T.eq(S.Record(d, "sold", "Linen Cloth", 951, 10, items).qty, 20)
  local f = { postings = { post(K1, 20, 1000, 0) } }
  T.eq(S.Record(f, "sold", "Linen Cloth", 953, 10, items).qty, nil)
  T.eq(f.postings[1].done, nil, "no match leaves the posting open")
end)

T.test("identical open postings: the oldest is consumed", function()
  -- two posts of 20 at 1000 (money 950 for each), made at 500 and 100.
  local c = { postings = { post(K1, 20, 1000, 500), post(K1, 20, 1000, 100) } }
  local e = S.Record(c, "sold", "Linen Cloth", 950, 1100, items)
  T.eq(e.qty, 20) T.eq(e.secs, 1000, "1100 - 100, the oldest") T.eq(c.postings[2].done, "sold") T.eq(c.postings[1].done, nil)
end)

T.test("a sold mail fitting two different stack/buyout postings leaves qty unknown but still counts (Review Focus 2)", function()
  -- 20 at 1000 -> floor(950.0) = 950; 10 at 1001 -> floor(950.95) = 950. Money 950 fits both.
  local c = { postings = { post(K1, 20, 1000, 100), post(K1, 10, 1001, 200) } }
  local e = S.Record(c, "sold", "Linen Cloth", 950, 900, items)
  T.eq(e.outcome, "sold") T.eq(e.money, 950) T.eq(e.qty, nil) T.eq(e.unit, nil) T.eq(e.secs, nil)
  T.eq(c.postings[1].done, nil) T.eq(c.postings[2].done, nil, "neither is consumed")
  local st = S.Stats({ c }, K1, 30, 1000)
  T.eq(st.sold, 1) T.eq(st.rate, 1) T.eq(st.n, 1, "one result") T.eq(st.nKnown, 0) T.eq(st.avgUnit, nil) T.eq(st.income, 950)
end)

T.test("a sold mail with no posting, or an unknown item, records without qty", function()
  local c = {}
  local e = S.Record(c, "sold", "Linen Cloth", 950, 50, items)
  T.eq(e.key, K1) T.eq(e.qty, nil) T.eq(table.getn(c.sales), 1)
  local u = S.Record(c, "sold", "Mystery Item", 5, 60, items)
  T.eq(u.key, nil) T.eq(u.money, 5) T.eq(table.getn(c.sales), 2)
  -- another item's posting is never consumed.
  local d = { postings = { post(K2, 20, 1000, 0) } }
  T.eq(S.Record(d, "sold", "Linen Cloth", 950, 50, items).qty, nil)
  T.eq(d.postings[1].done, nil)
end)

T.test("expired and cancelled consume the oldest open posting of the item", function()
  local c = { postings = { post(K1, 20, 1000, 500), post(K2, 5, 90, 50), post(K1, 10, 700, 100) } }
  local e = S.Record(c, "expired", "Linen Cloth", 0, 900, items)
  T.eq(e.outcome, "expired") T.eq(e.money, 0) T.eq(e.qty, nil)
  T.eq(c.postings[3].done, "expired", "at 100 is the oldest Linen Cloth") T.eq(c.postings[1].done, nil) T.eq(c.postings[2].done, nil)
  S.Record(c, "cancelled", "Linen Cloth", 0, 950, items)
  T.eq(c.postings[1].done, "cancelled")
  -- none left: still recorded, nothing to consume.
  local g = S.Record(c, "expired", "Linen Cloth", 0, 960, items)
  T.eq(g.outcome, "expired") T.eq(table.getn(c.sales), 3)
end)

T.test("won and outbid are recorded and consume nothing", function()
  local c = { postings = { post(K1, 20, 1000, 0) } }
  S.Record(c, "won", "Linen Cloth", 0, 10, items)
  S.Record(c, "outbid", "Linen Cloth", 0, 20, items)
  T.eq(table.getn(c.sales), 2) T.eq(c.postings[1].done, nil)
  local st = S.Stats({ c }, K1, 30, 100)
  T.eq(st.sold + st.expired + st.cancelled, 0) T.eq(st.rate, nil)
end)

T.test("stats across two characters: rate, averages and income", function()
  local a = { sales = {
    { key = K1, outcome = "sold", money = 950, qty = 20, unit = 50, secs = 3600, at = 1000 * DAY },
    { key = K1, outcome = "expired", money = 0, at = 1000 * DAY },
    { key = K2, outcome = "sold", money = 99, qty = 1, unit = 99, secs = 1, at = 1000 * DAY } } }
  local b = { sales = {
    { key = K1, outcome = "sold", money = 400, qty = 10, unit = 40, secs = 7200, at = 995 * DAY },
    { key = K1, outcome = "sold", money = 123, at = 995 * DAY },
    { key = K1, outcome = "cancelled", money = 0, at = 995 * DAY },
    { key = K1, outcome = "won", money = 0, at = 995 * DAY },
    { key = K1, outcome = "sold", money = 777, qty = 5, unit = 1, secs = 1, at = 900 * DAY } } }
  local st = S.Stats({ a, b }, K1, 30, 1001 * DAY)
  -- in the window: sold 950, 400, 123 (3); expired 1; cancelled 1 -> rate 3 / 5 = 0.6. The 900-day sale is too old.
  T.eq(st.sold, 3) T.eq(st.expired, 1) T.eq(st.cancelled, 1) T.eq(st.rate, 0.6)
  -- n = 3 sold + 1 expired + 1 cancelled = 5. qty known on 2 sales (nKnown): avgUnit (50 + 40) / 2 = 45, avgSecs (3600 + 7200) / 2 = 5400. income 950 + 400 + 123 = 1473.
  T.eq(st.n, 5) T.eq(st.nKnown, 2) T.eq(st.avgUnit, 45) T.eq(st.avgSecs, 5400) T.eq(st.income, 1473)
  local none = S.Stats({ a, b }, "999:0", 30, 1001 * DAY)
  T.eq(none.rate, nil) T.eq(none.n, 0) T.eq(none.nKnown, 0) T.eq(none.avgUnit, nil) T.eq(none.income, 0)
  -- a 3-day window drops the 995-day sales (6 days old): sold 1, expired 1 -> 0.5.
  local w = S.Stats({ a, b }, K1, 3, 1001 * DAY)
  T.eq(w.sold, 1) T.eq(w.rate, 0.5) T.eq(w.n, 2)
  -- chars keyed by name works too.
  T.eq(S.Stats({ Alt = a, Main = b }, K1, 30, 1001 * DAY).sold, 3)
end)

T.test("reconcile adds a posting for an auction with none open, and only that", function()
  local c = { postings = { post(K1, 20, 1000, 100) } }
  local rows = { { key = K1, count = 20, buyout = 1000, minBid = 900 }, { key = K2, count = 5, buyout = 90, minBid = 80 } }
  S.Reconcile(c, rows, 5000)
  T.eq(table.getn(c.postings), 2)
  local p = c.postings[2]
  T.eq(p.key, K2) T.eq(p.stack, 5) T.eq(p.buyout, 90) T.eq(p.bid, 80) T.eq(p.at, 5000)
  S.Reconcile(c, rows, 6000)
  T.eq(table.getn(c.postings), 2, "idempotent")
  -- a consumed posting does not cover a current auction.
  c.postings[1].done = "sold"
  S.Reconcile(c, rows, 7000)
  T.eq(table.getn(c.postings), 3)
  -- two identical auctions with one open posting: one added.
  local d = { postings = { post(K1, 20, 1000, 1) } }
  S.Reconcile(d, { rows[1], rows[1] }, 9)
  T.eq(table.getn(d.postings), 2)
  -- entries are never removed, and a char with no log gets one.
  S.Reconcile(d, {}, 10) T.eq(table.getn(d.postings), 2)
  local e = {} S.Reconcile(e, { rows[2] }, 3) T.eq(table.getn(e.postings), 1)
end)

T.test("prune drops old sales and mail, caps sales, and drops old consumed postings", function()
  local now = 200 * DAY
  local c = { sales = { { key = K1, outcome = "sold", at = now - 121 * DAY }, { key = K1, outcome = "sold", at = now - 119 * DAY } },
    seenMail = { old = now - 121 * DAY, new = now - 119 * DAY },
    postings = { post(K1, 1, 1, now - 36 * DAY), post(K1, 1, 2, now - 36 * DAY), post(K1, 1, 3, now - 1 * DAY) } }
  c.postings[1].done = "sold" c.postings[3].done = "expired"
  S.Prune(c, now)
  T.eq(table.getn(c.sales), 1) T.eq(c.sales[1].at, now - 119 * DAY)
  T.eq(c.seenMail.old, nil) T.eq(c.seenMail.new, now - 119 * DAY)
  -- consumed and older than 35 days goes; open (left to Sell.Prune) and recent consumed stay.
  T.eq(table.getn(c.postings), 2) T.eq(c.postings[1].buyout, 2) T.eq(c.postings[2].buyout, 3)
  local big = { sales = {} }
  for i = 1, 2005 do table.insert(big.sales, { key = K1, outcome = "sold", money = i, at = now }) end
  S.Prune(big, now)
  T.eq(table.getn(big.sales), 2000) T.eq(big.sales[1].money, 6, "the oldest five go") T.eq(big.sales[2000].money, 2005)
  S.Prune({}, now)
end)
