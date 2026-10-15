local A = TaxTheFools
local UI, DB, LU, Th, L = A.UI, A.DB, A.LedgerUI, A.Theme, A.List
local DAY = 86400

local function plain(s) return (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")) end

local function seed()
  A.Items.Remember(14047, "Runecloth", 1, 20)
  A.Items.Remember(2589, "Linen Cloth", 1, 20)
  local now = time()
  local me = DB.Char()
  me.ledger = {}
  A.Ledger.Add(me, { kind = "sale", amount = 10000, key = "14047:0", qty = 20, at = now }, now)
  A.Ledger.Add(me, { kind = "buy", amount = 3000, key = "2589:0", qty = 5, at = now }, now)
  A.Ledger.Add(me, { kind = "deposit", amount = 500, key = "14047:0", at = now }, now)
  A.Ledger.Add(me, { kind = "vendorIn", amount = 200, at = now - DAY }, now)
  A.Ledger.Add(me, { kind = "transferOut", amount = 700, at = now - DAY }, now)
  A.Ledger.Add(me, { kind = "sale", amount = 9000, key = "2589:0", qty = 1, at = now - 60 * DAY }, now)
  local alt = { ledger = {} }
  DB.Realm().chars["Alt"] = alt
  A.Ledger.Add(alt, { kind = "sale", amount = 1000, key = "2589:0", qty = 2, at = now }, now)
  return me, alt
end

local function page()
  UI.CreateAH()
  local p = LU.frame
  if not p then p = LU.AHBuild(UI.ah.body) end
  p.days, p.who, p.view = 30, "all", "days"
  p.dlist:SetHeight(300) p.ilist:SetHeight(300)
  p:Refresh()
  return p
end

T.test("the tab is registered right after History", function()
  T.ok(UI.builders.ledger)
  local ih, il
  for i, t in ipairs(UI.TABS) do
    if t.key == "history" then ih = i end
    if t.key == "ledger" then il = i T.eq(t.label, "Ledger") end
  end
  T.eq(il, ih + 1)
end)

T.test("totals strip: In, Out, Net with per-day, and transfers", function()
  seed()
  local p = page()
  -- in 10000 + 200 + 1000, out 3000 + 500
  T.eq(plain(p.totals:GetText()),
    "In 1g 12s  -  Out 35s  -  Net 77s (2s 57c/day)  -  Transfers +0c / -7s")
  T.ok(string.find(p.totals:GetText(), Th.Code("good") .. "77s", 1, true))
  LU.SetChar(p, "Alt")
  T.eq(plain(p.totals:GetText()), "In 10s  -  Out 0c  -  Net 10s (33c/day)  -  Transfers +0c / -0c")
end)

T.test("a negative net takes the bad colour", function()
  local me = seed()
  local p = page()
  LU.SetChar(p, DB.charName)
  A.Ledger.Add(me, { kind = "buy", amount = 500000, key = "2589:0", qty = 1 }, time())
  p:Refresh()
  T.ok(string.find(p.totals:GetText(), Th.Code("bad") .. "-", 1, true))
end)

T.test("Days view: one row per day with sales, buys, deposits, vendor, mail and net, newest first", function()
  seed()
  local p = page()
  T.eq(table.getn(p.dlist.data), 2)
  local r = p.dlist.data[1]
  T.eq(r.sale, 11000) T.eq(r.buy, 3000) T.eq(r.deposit, 500) T.eq(r.net, 7500)
  T.eq(p.dlist.data[2].vendor, 200)
  T.eq(plain(p.dlist.rows[1].cells[2]:GetText()), "1g 10s")
  T.eq(plain(p.dlist.rows[1].cells[7]:GetText()), "75s")
  T.eq(plain(p.dlist.rows[2].cells[5]:GetText()), "2s")
  T.eq(p.dlist.rows[2].cells[2]:GetText(), "-")
  T.ok(p.dlist:IsShown()) T.ok(not p.ilist:IsShown())
end)

T.test("Items view: toggle, rows by net, names and counts", function()
  seed()
  local p = page()
  WoW.runScript(p.itemsBtn, "OnClick")
  T.eq(p.view, "items")
  T.ok(p.ilist:IsShown()) T.ok(not p.dlist:IsShown())
  T.eq(table.getn(p.ilist.data), 2)
  local r1, r2 = p.ilist.data[1], p.ilist.data[2]
  T.eq(r1.name, "Runecloth") T.eq(r1.income, 10000) T.eq(r1.spend, 500) T.eq(r1.net, 9500) T.eq(r1.sold, 20)
  T.eq(r2.name, "Linen Cloth") T.eq(r2.bought, 5)
  T.eq(p.ilist.rows[1].cells[1]:GetText(), "|cffffffffRunecloth|r")
  T.eq(plain(p.ilist.rows[1].cells[4]:GetText()), "95s")
  WoW.runScript(p.daysBtn, "OnClick")
  T.eq(p.view, "days")
end)

T.test("period and character filters", function()
  seed()
  local p = page()
  LU.SetDays(p, 90)
  T.ok(string.find(plain(p.totals:GetText()), "In 2g 2s", 1, true))
  LU.SetDays(p, 7)
  LU.SetChar(p, "Alt")
  T.eq(table.getn(p.dlist.data), 1)
  T.eq(p.dlist.data[1].sale, 1000)
  T.eq(table.getn(LU.CharOptions()), 3)
end)

T.test("empty state explains the ledger and the Blizzard mail gap", function()
  DB.Char().ledger = nil
  for _, c in pairs(DB.Realm().chars) do c.ledger = nil end
  local p = page()
  T.ok(p.empty:IsShown())
  T.ok(string.find(p.empty:GetText(), "from now on, apart from past sales", 1, true))
  T.ok(string.find(p.empty:GetText(), "Blizzard's own mail window", 1, true))
  seed()
  p:Refresh()
  T.ok(not p.empty:IsShown())
end)

T.test("both column sets fit the AH window at its minimum width", function()
  -- 660 wide, less 10 + 10 margins and the 20 px scroll bar
  for _, cols in ipairs({ LU.DAY_COLUMNS, LU.ITEM_COLUMNS }) do
    local sum = 0
    for _, c in ipairs(cols) do sum = sum + c.width end
    T.ok(sum <= 660 - 20 - 20, "columns need " .. sum)
  end
  local w = L.Widths(LU.ITEM_COLUMNS, 700)
  T.ok(w[1] > LU.ITEM_COLUMNS[1].width, "the item column flexes")
end)

T.test("/ttf ledger opens and closes the standalone window", function()
  local f = LU.Window()
  f:Hide()
  SlashCmdList["TAXTHEFOOLS"]("ledger")
  T.ok(f:IsShown())
  seed()
  f.page:Refresh()
  T.ok(f.page.dlist.data[1])
  SlashCmdList["TAXTHEFOOLS"]("ledger")
  T.eq(f:IsShown(), false)
end)
