local A = TaxTheFools
local UI, DB, HU = A.UI, A.DB, A.HistoryUI

local function page()
  UI.CreateAH()
  local p = HU.frame
  if not p then p = HU.Build(UI.ah.body) end
  p.list:SetHeight(300)
  return p
end

local function sale(char, key, outcome, money, qty, unit, secs, daysAgo)
  char.sales = char.sales or {}
  table.insert(char.sales, { key = key, outcome = outcome, money = money, qty = qty, unit = unit, secs = secs,
    at = time() - (daysAgo or 1) * 86400 })
end

local function seed()
  A.Items.Remember(14047, "Runecloth", 1, 20)
  A.Items.Remember(2589, "Linen Cloth", 1, 20)
  local me = DB.Char()
  me.sales = {}
  sale(me, "14047:0", "sold", 4000, 20, 200, 3600, 2)
  sale(me, "14047:0", "sold", 2000, 10, 200, 7200, 3)
  sale(me, "14047:0", "expired", nil, nil, nil, nil, 4)
  sale(me, "2589:0", "sold", 500, 5, 100, 600, 5)
  sale(me, "2589:0", "sold", 9000, 1, 9000, 100, 60)   -- outside 30 days
  local alt = DB.Realm().chars["Alt"] or {}
  DB.Realm().chars["Alt"] = alt
  alt.sales = {}
  sale(alt, "2589:0", "sold", 300, 3, 100, 300, 2)
  return me, alt
end

T.test("the tab is registered after Auctions", function()
  T.ok(UI.builders.history)
  local keys = {}
  for _, t in ipairs(UI.TABS) do table.insert(keys, t.key) end
  local ia, ih
  for i, k in ipairs(keys) do
    if k == "auctions" then ia = i end
    if k == "history" then ih = i end
  end
  T.eq(ih, ia + 1)
end)

T.test("rows: one per item with sold, expired, rate, average and income, sorted by income", function()
  seed()
  local p = page()
  p:Refresh()
  T.eq(table.getn(p.list.data), 2)
  local r1, r2 = p.list.data[1], p.list.data[2]
  T.eq(r1.name, "Runecloth") T.eq(r1.sold, 2) T.eq(r1.expired, 1) T.eq(r1.income, 6000)
  T.eq(r2.name, "Linen Cloth") T.eq(r2.sold, 2) T.eq(r2.income, 800)
  T.eq(p.list.rows[1].cells[1]:GetText(), "|cffffffffRunecloth|r")
  T.eq(p.list.rows[1].cells[2]:GetText(), "2")
  T.eq(p.list.rows[1].cells[3]:GetText(), "1")
  T.eq(p.list.rows[1].cells[4]:GetText(), "67%")
end)

T.test("the totals line gives income, sold and the overall rate", function()
  seed()
  local p = page()
  p:Refresh()
  -- sold 4, expired 1: 80%; income 6800
  T.ok(string.find(p.totals:GetText(), "4 sold", 1, true), p.totals:GetText())
  T.ok(string.find(p.totals:GetText(), "80%", 1, true), p.totals:GetText())
  T.ok(string.find(p.totals:GetText(), A.Util.money(6800), 1, true), p.totals:GetText())
end)

T.test("the period filter widens to 90 days", function()
  seed()
  local p = page()
  p:Refresh()
  HU.SetDays(p, 90)
  T.eq(p.list.data[1].name, "Linen Cloth")      -- 9800 now outranks Runecloth
  T.eq(p.list.data[1].sold, 3)
  HU.SetDays(p, 7)
  HU.SetDays(p, 30)
  T.eq(p.list.data[2].sold, 2)
end)

T.test("the character filter limits to one character", function()
  seed()
  local p = page()
  p:Refresh()
  HU.SetChar(p, "Alt")
  T.eq(table.getn(p.list.data), 1)
  T.eq(p.list.data[1].name, "Linen Cloth")
  T.eq(p.list.data[1].sold, 1)
  HU.SetChar(p, "all")
  T.eq(table.getn(p.list.data), 2)
end)

T.test("no history shows an empty note", function()
  DB.Char().sales = {}
  for _, c in pairs(DB.Realm().chars) do c.sales = {} end
  local p = page()
  p:Refresh()
  T.eq(table.getn(p.list.data), 0)
  T.ok(string.find(p.totals:GetText(), "No sales", 1, true), p.totals:GetText())
end)
