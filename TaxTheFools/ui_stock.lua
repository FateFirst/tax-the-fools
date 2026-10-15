TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan
local Sell, Stock, P, SellUI = TaxTheFools.Sell, TaxTheFools.Stock, TaxTheFools.Price, TaxTheFools.SellUI
local StockUI = {}
TaxTheFools.StockUI = StockUI

-- Phase 8 spec section 3: the Repost and Stock views of the Sell tab. Nothing here spends. Clicking a
-- Repost row only selects the item, as the grid does; Post is still the one button on the Sell panel.

StockUI.VIEWS = { "bags", "repost", "stock" }

-- Compact money so the columns fit: 12.34g, 34s, 56c, and whole gold from 100g.
local function short(c)
  if not c then return "-" end
  c = math.floor(c + 0.5)
  if c >= 1000000 then return math.floor(c / 10000) .. "g" end
  if c >= 10000 then
    local cents = math.floor(math.mod(c, 10000) / 100)
    return math.floor(c / 10000) .. "." .. (cents < 10 and "0" or "") .. cents .. "g"
  end
  if c >= 100 then return math.floor(c / 100) .. "s" end
  return c .. "c"
end
StockUI.Short = short

local function pctText(v)
  if not v then return "-" end
  return ((v > 0) and "+" or "") .. v .. "%"
end

-- Repost: the 240 px the bag grid takes, less the scroll bar.
StockUI.REPOST_COLUMNS = {
  { label = "Item", width = 56, flex = 1, sort = "name", fmt = function(r) return r.name end },
  { label = "Have", width = 30, align = "RIGHT", sort = "have", fmt = function(r) return tostring(r.have) end },
  { label = "Last", width = 48, align = "RIGHT", sort = "lastBuyout", fmt = function(r) return short(r.lastBuyout) end },
  { label = "Now", width = 48, align = "RIGHT", sort = "suggest", fmt = function(r) return short(r.suggest) end },
  { label = "Change", width = 46, align = "RIGHT", sort = "change",
    fmt = function(r)
      if not r.change then return "-", "dim" end
      return pctText(r.change), (r.change > 0 and "good") or (r.change < 0 and "bad") or "dim"
    end },
}

StockUI.STOCK_COLUMNS = {
  { label = "Item", width = 150, flex = 1, sort = "name", fmt = function(r) return r.name end },
  { label = "Bags", width = 40, align = "RIGHT", sort = "bags", fmt = function(r) return tostring(r.bags) end },
  { label = "Bank", width = 40, align = "RIGHT", sort = "bank", fmt = function(r) return tostring(r.bank) end },
  { label = "On AH", width = 46, align = "RIGHT", sort = "onAH", fmt = function(r) return tostring(r.onAH) end },
  { label = "Total", width = 46, align = "RIGHT", sort = "total", fmt = function(r) return tostring(r.total) end },
  { label = "Each", width = 64, align = "RIGHT", sort = "unit", fmt = function(r) return short(r.unit) end },
  { label = "Value", width = 72, align = "RIGHT", sort = "value", fmt = function(r) return short(r.value) end },
  { label = "Sells", width = 46, align = "RIGHT", sort = "rate",
    fmt = function(r) if r.rate then return math.floor(r.rate * 100 + 0.5) .. "%" end return "-", "dim" end },
  { label = "Trend", width = 50, align = "RIGHT", sort = "trend",
    fmt = function(r)
      if not r.trend then return "-", "dim" end
      return pctText(r.trend), (r.trend >= 5 and "good") or (r.trend <= -5 and "bad") or "dim"
    end },
}

function StockUI.TotalsText(t)
  return t.items .. " items  -  " .. t.units .. " units  -  worth ~" .. math.floor(t.value / 10000 + 0.5)
    .. "g  (not counting mail)"
end

function StockUI.EmptyText(days)
  return "Nothing came back from the auction house in the last " .. days .. " days."
end

-- ---------- rows ----------

function StockUI.RepostRows(p)
  local counts = {}
  for _, it in ipairs(p.items) do counts[it.key] = it.total end
  local realm = DB.Realm()
  local rows = Stock.Repost(DB.Char(), counts, TaxTheFoolsDB.items, realm.market, DB.S().sell.repostDays, time())
  for _, r in ipairs(rows) do
    r.change = nil
    if r.lastBuyout and r.lastBuyout > 0 and r.suggest then
      r.change = math.floor((r.suggest - r.lastBuyout) / r.lastBuyout * 100 + 0.5)
    end
  end
  return rows
end

function StockUI.StockRows()
  local realm = DB.Realm()
  local stats = TaxTheFools.Sales.StatsAll(realm.chars, DB.S().sales.days or 30, time())
  local today = U.day()
  local function trend(key)
    local t = P.Trend(realm.history[key], today)
    return t and t.pct or nil
  end
  return Stock.Rows(realm.chars, realm.market, stats, trend, TaxTheFoolsDB.items)
end

-- ---------- painting ----------

function StockUI.Paint(p)
  if not p or not p.rlist then return end
  if p.view == "repost" then
    local rows = StockUI.RepostRows(p)
    p.rlist:SetData(rows)
    if table.getn(rows) == 0 then
      p.empty:SetText(StockUI.EmptyText(DB.S().sell.repostDays))
      p.empty:Show()
    else
      p.empty:Hide()
    end
  elseif p.view == "stock" then
    local rows = StockUI.StockRows()
    p.slist:SetData(rows)
    p.totals:SetText(StockUI.TotalsText(Stock.Total(rows)))
  end
end

local function panelWidgets(p)
  local out = { p.title, p.list, p.buyoutIn, p.bidIn, p.sizeBox, p.countBox, p.sourceText, p.depositText,
    p.netText, p.floorText, p.warnText, p.salesText, p.allowSw, p.postBtn, p.status }
  for _, l in ipairs(p.labels) do table.insert(out, l) end
  for _, b in pairs(p.durBtns) do table.insert(out, b) end
  return out
end

local function setShown(w, on)
  if on then w:Show() else w:Hide() end
end

function StockUI.SetView(p, view)
  if view ~= "bags" and view ~= "repost" and view ~= "stock" then view = "bags" end
  p.view = view
  if type(TaxTheFoolsCharDB) == "table" then TaxTheFoolsCharDB.sellView = view end
  for v, b in pairs(p.viewBtns) do Th.Color(b.label, v == view and "gold" or "white") end
  for _, w in ipairs(panelWidgets(p)) do setShown(w, view ~= "stock") end
  setShown(p.rlist, view == "repost")
  setShown(p.slist, view == "stock")
  setShown(p.totals, view == "stock")
  if view ~= "repost" then p.empty:Hide() end
  SellUI.PaintGrid()
  SellUI.Update()                    -- also puts the chart back, or keeps it hidden, for the selection
  StockUI.Paint(p)
  if p.rlist:IsShown() then p.rlist:Paint() end
  if p.slist:IsShown() then p.slist:Paint() end
end

-- A Repost row: select the item as the grid would, then preset the stack to the last posting's when the
-- bags still hold that many. Otherwise the Sell panel's own default stands.
function StockUI.Pick(row)
  local p = SellUI.frame
  local it = SellUI.Find(row.key)
  if not it then return end
  SellUI.Select(it)
  local want = row.lastStack
  if want and want >= 1 and it.total >= want then
    p.stackSize = math.min(want, it.maxStack)
    p.posted = 0
    p.nStacks = math.max(1, Sell.Stacks(it.total, p.stackSize, it.maxStack))
    SellUI.FillFields()
    SellUI.Update()
  end
end

-- ---------- tooltips ----------

function StockUI.StockTip(row, r)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(r.name)
  for _, c in ipairs(r.perChar) do
    GameTooltip:AddLine(c.name .. ": bags " .. c.bags .. ", bank " .. c.bank .. ", on AH " .. c.onAH, 1, 1, 1)
  end
  GameTooltip:AddLine("Total " .. r.total .. ". Mail is not counted.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function StockUI.RepostTip(row, r)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(r.name)
  if r.lastStack then
    GameTooltip:AddLine("Last posted: " .. r.lastStack .. " at " .. short(r.lastBuyout) .. " each, " .. r.outcome, 1, 1, 1)
  else
    GameTooltip:AddLine("It " .. r.outcome .. ". No posting is on record.", 1, 1, 1)
  end
  GameTooltip:Show()
end

-- ---------- building ----------

function StockUI.Build(p)
  local saved = type(TaxTheFoolsCharDB) == "table" and TaxTheFoolsCharDB.sellView or "bags"
  p.viewBtns = {}
  local x = 0
  for _, spec in ipairs({ { "bags", "Bags", 56 }, { "repost", "Repost", 64 }, { "stock", "Stock", 56 } }) do
    local v = spec[1]
    local b = W.Button(p, spec[2], spec[3], 22, function() StockUI.SetView(p, v) end)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", x, 0)
    x = x + spec[3] + 2
    p.viewBtns[v] = b
  end
  p.rlist = L.New(p, StockUI.REPOST_COLUMNS, 18, function(item) StockUI.Pick(item) end)
  p.rlist.onEnter = function(row, item) StockUI.RepostTip(row, item) end
  p.rlist:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -SellUI.GY)
  p.rlist:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  p.rlist:SetWidth(SellUI.RX - 12)
  p.rlist:Hide()
  p.empty = Th.Text(p, "body", 12, "dim")
  p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -(SellUI.GY + 34))
  p.empty:SetWidth(SellUI.RX - 24)
  p.empty:SetJustifyH("LEFT")
  p.empty:Hide()
  p.slist = L.New(p, StockUI.STOCK_COLUMNS, 18, nil)
  p.slist.onEnter = function(row, item) StockUI.StockTip(row, item) end
  p.slist.sortCol, p.slist.sortDesc = StockUI.STOCK_COLUMNS[7], true
  p.slist:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -SellUI.GY)
  p.slist:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 20)
  p.slist:Hide()
  p.totals = Th.Text(p, "body", 12, "text")
  p.totals:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 2)
  p.totals:SetJustifyH("LEFT")
  p.totals:Hide()
  local layout = p.Layout
  p.Layout = function(self)
    layout(self)
    self.rlist:Paint()
    self.slist:Paint()
  end
  Scan.OnChange(function() if p:IsVisible() and p.view == "stock" then StockUI.Paint(p) end end)
  StockUI.SetView(p, saved)
end
