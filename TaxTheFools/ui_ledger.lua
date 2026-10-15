TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, I, Ledger, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Ledger, TaxTheFools.UI
local LedgerUI = { pages = {} }
TaxTheFools.LedgerUI = LedgerUI

-- Where the gold went and came from (phase 6 spec section 4): a totals strip over a Days or Items list.
LedgerUI.PERIODS = { { label = "7 days", value = 7 }, { label = "30 days", value = 30 }, { label = "90 days", value = 90 } }
LedgerUI.EMPTY = "Nothing recorded in this period. The ledger records from now on, apart from past sales. "
  .. "Gold taken or sent through Blizzard's own mail window is not recorded; use the addon's mailbox."

local SEP = "  -  "

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

local function signed(v)
  if not v or v == 0 then return "-", "dim" end
  if v > 0 then return U.money(v, true), "good" end
  return U.money(v, true), "bad"
end

LedgerUI.DAY_COLUMNS = {
  { label = "Date", width = 64, sort = "day", desc = true,
    fmt = function(r) return date("%m-%d", r.day * 86400 + 43200) end },
  { label = "Sales", width = 84, align = "RIGHT", sort = "sale", fmt = function(r) return money(r.sale) end },
  { label = "Buys", width = 84, align = "RIGHT", sort = "buy", fmt = function(r) return money(r.buy) end },
  { label = "Deposits", width = 84, align = "RIGHT", sort = "deposit", fmt = function(r) return money(r.deposit) end },
  { label = "Vendor", width = 84, align = "RIGHT", sort = "vendor", fmt = function(r) return signed(r.vendor) end },
  { label = "Mail", width = 84, align = "RIGHT", sort = "mail", fmt = function(r) return signed(r.mail) end },
  { label = "Net", width = 90, align = "RIGHT", sort = "net", fmt = function(r) return signed(r.net) end },
}

LedgerUI.ITEM_COLUMNS = {
  { label = "Item", width = 150, flex = 1, sort = "name",
    fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Income", width = 90, align = "RIGHT", sort = "income", fmt = function(r) return money(r.income) end },
  { label = "Spend", width = 90, align = "RIGHT", sort = "spend", fmt = function(r) return money(r.spend) end },
  { label = "Net", width = 90, align = "RIGHT", sort = "net", desc = true, fmt = function(r) return signed(r.net) end },
  { label = "Sold", width = 46, align = "RIGHT", sort = "sold", fmt = function(r) return tostring(r.sold) end },
  { label = "Bought", width = 56, align = "RIGHT", sort = "bought", fmt = function(r) return tostring(r.bought) end },
}

function LedgerUI.Chars(who)
  local chars = DB.Realm().chars
  if who and who ~= "all" then
    local out = {}
    out[who] = chars[who]
    return out
  end
  return chars
end

function LedgerUI.Item(r)
  local id = U.keyId(r.key)
  local rec = I.Get(id)
  r.name, r.quality = I.Name(id), rec and rec.q
  return r
end

-- The totals strip text. Net takes the good or bad colour.
function LedgerUI.TotalsText(t)
  local token = t.net < 0 and "bad" or "good"
  return "In " .. U.money(t.inn) .. SEP .. "Out " .. U.money(t.out) .. SEP .. "Net " .. Th.Code(token)
    .. U.money(t.net, true) .. "|r (" .. U.money(t.perDay, true) .. "/day)" .. SEP .. "Transfers +"
    .. U.money(t.transferIn, true) .. " / -" .. U.money(t.transferOut, true)
end

function LedgerUI.Paint(p)
  local chars, now = LedgerUI.Chars(p.who), time()
  local t = Ledger.Totals(chars, p.days, now)
  local days = Ledger.Days(chars, p.days, now)
  local items = Ledger.ByItem(chars, p.days, now)
  for _, r in ipairs(items) do LedgerUI.Item(r) end
  p.totals:SetText(LedgerUI.TotalsText(t))
  p.dlist:SetData(days)
  p.ilist:SetData(items)
  Th.Color(p.daysBtn.label, p.view == "days" and "gold" or "white")
  Th.Color(p.itemsBtn.label, p.view == "items" and "gold" or "white")
  if p.view == "items" then p.dlist:Hide() p.ilist:Show() else p.ilist:Hide() p.dlist:Show() end
  if table.getn(days) == 0 then p.empty:Show() else p.empty:Hide() end
end

function LedgerUI.SetDays(p, days) p.days = days LedgerUI.Paint(p) end
function LedgerUI.SetChar(p, who) p.who = who LedgerUI.Paint(p) end
function LedgerUI.SetView(p, view) p.view = view LedgerUI.Paint(p) end

function LedgerUI.CharOptions()
  local opts, names = { { label = "All characters", value = "all" } }, {}
  for name in pairs(DB.Realm().chars) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do table.insert(opts, { label = name, value = name }) end
  return opts
end

-- One builder for both places the page appears: the AH tab and the standalone window.
function LedgerUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.days, p.who, p.view = 30, "all", "days"
  p.periodDD = W.Dropdown(p, 110, LedgerUI.PERIODS, function() return p.days end, function(v) LedgerUI.SetDays(p, v) end)
  p.periodDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.charDD = W.Dropdown(p, 150, LedgerUI.CharOptions(), function() return p.who end, function(v) LedgerUI.SetChar(p, v) end)
  p.charDD:SetPoint("LEFT", p.periodDD, "RIGHT", 6, 0)
  p.daysBtn = W.Button(p, "Days", 60, 22, function() LedgerUI.SetView(p, "days") end)
  p.daysBtn:SetPoint("LEFT", p.charDD, "RIGHT", 10, 0)
  p.itemsBtn = W.Button(p, "Items", 60, 22, function() LedgerUI.SetView(p, "items") end)
  p.itemsBtn:SetPoint("LEFT", p.daysBtn, "RIGHT", 2, 0)
  p.totals = Th.Text(p, "body", 12, "dim")
  p.totals:SetPoint("TOPLEFT", p.periodDD, "BOTTOMLEFT", 2, -6)
  p.totals:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.totals:SetJustifyH("LEFT")
  p.dlist = L.New(p, LedgerUI.DAY_COLUMNS, 18, nil)
  p.dlist.sortCol, p.dlist.sortDesc = LedgerUI.DAY_COLUMNS[1], true
  p.ilist = L.New(p, LedgerUI.ITEM_COLUMNS, 18, nil)
  p.ilist.sortCol, p.ilist.sortDesc = LedgerUI.ITEM_COLUMNS[4], true
  for _, l in ipairs({ p.dlist, p.ilist }) do
    l:SetPoint("TOPLEFT", p.totals, "BOTTOMLEFT", -2, -8)
    l:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  end
  p.ilist:Hide()
  p.empty = Th.Text(p, "body", 13, "dim")
  p.empty:SetPoint("CENTER", p, "CENTER", 0, -20)
  p.empty:SetWidth(420)
  p.empty:SetText(LedgerUI.EMPTY)
  p.empty:Hide()
  p.Refresh = function(self)
    self.charDD:SetOptions(LedgerUI.CharOptions())
    LedgerUI.Paint(self)
  end
  p.Layout = function(self)
    self.dlist:Paint()
    self.ilist:Paint()
  end
  table.insert(LedgerUI.pages, p)
  LedgerUI.Paint(p)
  return p
end

function LedgerUI.AHBuild(parent)
  LedgerUI.frame = LedgerUI.Build(parent)
  return LedgerUI.frame
end

function LedgerUI.Window()
  if LedgerUI.window then return LedgerUI.window end
  local f = W.Window("TaxTheFoolsLedger", 700, 440, "Tax the Fools  -  Ledger",
    { resizable = true, minW = 640, minH = 340, logo = true })
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 10, -10)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f.page = LedgerUI.Build(f.body)
  f.page:SetAllPoints(f.body)
  f:SetScript("OnShow", function() f.page:Refresh() end)
  f.onResize = function() f.page:Layout() end
  LedgerUI.window = f
  return f
end

function LedgerUI.Toggle()
  local f = LedgerUI.Window()
  if f:IsShown() then f:Hide() else f:Show() end
end

UI.builders.ledger = LedgerUI.AHBuild
