TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Auction, P = TaxTheFools.Auction, TaxTheFools.Price
local Browse = { query = "", page = 0, frame = nil, back = false }
TaxTheFools.Browse = Browse

function Browse.ResetState() Browse.query, Browse.page, Browse.back = "", 0, false end

-- The "< Crafting" button: shown after a jump from another tab, until used or a different search is made.
function Browse.SetBack(to)
  Browse.back = to or false
  if Browse.frame then
    if to then Browse.frame.back:Show() else Browse.frame.back:Hide() end
    Browse.UpdatePager()
  end
end

-- At the narrowest window the "Page x of y" text would run into "< Crafting": it waits while that shows.
function Browse.UpdatePager()
  local p = Browse.frame
  if not p then return end
  if Browse.back then p.pageText:Hide() else p.pageText:Show() end
end

function Browse.GoBack()
  local to = Browse.back
  Browse.SetBack(false)
  if to == "craft" and UI.ah then UI.ah.tabs:Select("craft") end
end

-- A search the user asked for by typing: it ends any way back.
function Browse.Manual(text)
  Browse.SetBack(false)
  return Browse.Search(text, 0)
end

-- Put a name in the box and search for it (bag right-click, material click).
function Browse.Lookup(name)
  Browse.SetBack(false)
  Browse.frame.search:SetText(name)
  return Browse.Search(name, 0)
end

-- Jump to the Browse tab and look an item up. `back` names the tab a "< ..." button returns to.
function Browse.SearchFor(name, back)
  if not UI.ah then return false end
  UI.ah.tabs:Select("browse")
  local ok = Browse.Lookup(name)
  Browse.SetBack(back)
  return ok
end

-- Cheap against market reads green, dear reads red.
function Browse.PctToken(p)
  if not p then return "dim" end
  if p <= 70 then return "good" end
  if p >= 130 then return "bad" end
  return "text"
end

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

Browse.COLUMNS = {
  { label = "Item", width = 120, flex = 3, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Qty", width = 36, align = "RIGHT", sort = "count", desc = true, fmt = function(r) return tostring(r.count) end },
  { label = "Bid", width = 80, flex = 1, align = "RIGHT", sort = "bidNow", fmt = function(r) return money(r.bidNow) end },
  { label = "Buyout", width = 80, flex = 1, align = "RIGHT", sort = "buy", fmt = function(r) return money(r.buy) end },
  { label = "Each", width = 76, flex = 1, align = "RIGHT", sort = "unit", fmt = function(r) return money(r.unit) end },
  { label = "Market", width = 76, flex = 1, align = "RIGHT", sort = "market", fmt = function(r) return money(r.market) end },
  { label = "%", width = 40, align = "RIGHT", sort = "pct",
    fmt = function(r) return r.pct and (r.pct .. "%") or "-", Browse.PctToken(r.pct) end },
  { label = "Trend", width = 56, align = "RIGHT", sort = "trend",
    fmt = function(r)
      if not r.trend then return "-", "dim" end
      return ((r.trend > 0) and "+" or "") .. r.trend .. "%", P.TrendToken(r.trendDir)
    end },
  { label = "Seller", width = 64, flex = 1, sort = "owner", fmt = function(r) return r.owner or "?" end },
}

function Browse.Decorate(rows, market, history, today)
  for _, r in ipairs(rows) do
    local m = market[r.key]
    r.market = m and m.v or nil
    r.pct = nil
    local t = history and P.Trend(history[r.key], today or U.day())
    r.trend = t and t.pct or nil
    r.trendDir = t and t.dir or nil
    if r.unit and r.market and r.market > 0 then r.pct = math.floor(r.unit / r.market * 100 + 0.5) end
    r.bidNow = ((r.bid or 0) > 0) and r.bid or r.minBid
    r.buy = ((r.buyout or 0) > 0) and r.buyout or nil
  end
  return rows
end

-- The price chart sits bottom-left, beside the Buy / Bid buttons, and the list gives up its height.
Browse.CHART_H, Browse.CHART_MIN_W, Browse.CHART_MIN_PAGE_H = 44, 160, 220
Browse.CHART_RIGHT = 278   -- Buy (140) + Bid (120) + gaps

function Browse.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.search = W.EditBox(p, 220, function(text) Browse.Manual(text) end)
  p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.go = W.Button(p, "Search", 80, 22, function() Browse.Manual(p.search:GetText()) end, "accent")
  p.go:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
  p.watchBtn = W.Button(p, "Watch", 90, 22, function() Browse.ToggleWatch() end)
  p.watchBtn:SetPoint("LEFT", p.go, "RIGHT", 6, 0)
  W.Tip(p.watchBtn, "Watchlist", "Watched items are priced by the quick Watchlist scan.")
  p.back = W.Button(p, "< Crafting", 100, 22, function() Browse.GoBack() end)
  p.back:SetPoint("LEFT", p.watchBtn, "RIGHT", 6, 0)
  W.Tip(p.back, "Back to Crafting", "Return to the recipe you came from.")
  p.back:Hide()
  p.next = W.IconButton(p, "icon-arrow-right", 22, function() Browse.Search(Browse.query, Browse.page + 1) end)
  p.next:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  p.prev = W.IconButton(p, "icon-arrow-left", 22, function() Browse.Search(Browse.query, Browse.page - 1) end)
  p.prev:SetPoint("RIGHT", p.next, "LEFT", -4, 0)
  p.pageText = Th.Text(p, "body", 11, "dim")
  p.pageText:SetPoint("RIGHT", p.prev, "LEFT", -8, 0)
  p.pageText:SetJustifyH("RIGHT")
  p.list = L.New(p, Browse.COLUMNS, 18, function() Browse.UpdateWatchButton() Browse.UpdateBar() end)
  p.list:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 32)
  -- The action bar: one click each, no double-click or modifier-click buying.
  p.buyBtn = W.Button(p, "Buy", 140, 24, function() Browse.Buy() end, "accent")
  p.buyBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.bidBtn = W.Button(p, "Bid", 120, 24, function() Browse.Bid() end)
  p.bidBtn:SetPoint("RIGHT", p.buyBtn, "LEFT", -6, 0)
  p.chart = W.Chart(p, 200, Browse.CHART_H)
  p.chart:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  p.chart:Hide()
  p.list.onEnter = function(row, item) Browse.RowTip(row, item) end
  p.Refresh = function(self) Browse.Paint() end
  p.Layout = function(self) Browse.UpdateChart() self.list:Paint() end
  Browse.frame = p
  Scan.OnChange(function() if p:IsVisible() then Browse.Paint() end end)
  Auction.OnChange(function() Browse.UpdateBar() end)
  Browse.Paint()
  return p
end

function Browse.Paint()
  local p = Browse.frame
  if not p then return end
  p.list:SetData(Browse.Decorate(Scan.lastRows, DB.Realm().market, DB.Realm().history, U.day()))
  local pages = math.max(1, math.ceil(Scan.lastTotal / 50))
  p.pageText:SetText("Page " .. (Scan.lastPage + 1) .. " of " .. pages .. ", " .. Scan.lastTotal .. " found")
  Browse.UpdateWatchButton()
  Browse.UpdateBar()
end

function Browse.Search(text, page)
  if page < 0 then return false end
  if page > 0 and page * 50 >= Scan.lastTotal then return false end
  local ok, why = Scan.Browse(text or "", page, GetTime())
  if ok then Browse.query, Browse.page = text or "", page end
  if not ok and why == "busy" then U.msg("A scan is using the auction house. Pause it to search.") end
  return ok and true or false
end

function Browse.UpdateWatchButton()
  local p = Browse.frame
  if not p then return end
  local sel = p.list.selected
  p.watchBtn:SetEnabled(sel and true or false)
  p.watchBtn:SetLabel((sel and DB.Realm().watch[sel.key]) and "Unwatch" or "Watch")
end

-- Why Buy / Bid is unavailable for row r, or nil when it is available.
function Browse.WhyNot(kind, r)
  if not r then return "Select a listing first." end
  if Auction.busy then return "Waiting for the auction house to answer." end
  if Scan.Busy() and Scan.job.kind ~= "browse" then return "A scan is using the auction house." end
  if Auction.Own(r) then return "That is your own auction." end
  if kind == "buy" then
    if not r.buy then return "This listing has no buyout." end
    if r.buy > GetMoney() then return "You can't afford " .. U.money(r.buy, true) .. "." end
  else
    local amount = Auction.BidAmount(r)
    if r.buy and amount >= r.buy then return "The next bid would reach the buyout. Use Buy." end
    if r.high then return "You are already the high bidder." end
    if amount > GetMoney() then return "You can't afford " .. U.money(amount, true) .. "." end
  end
  return nil
end

-- Shows the selected item's chart when the page has room for it, else hides it and gives the list its height back.
function Browse.UpdateChart()
  local p = Browse.frame
  if not p then return end
  local r = p.list.selected or nil
  local w = p:GetWidth() - Browse.CHART_RIGHT
  local fits = r and w >= Browse.CHART_MIN_W and p:GetHeight() >= Browse.CHART_MIN_PAGE_H
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, fits and (Browse.CHART_H + 8) or 32)
  if (fits and true or false) ~= p.chartOn then
    p.chartOn = fits and true or false
    p.list:Paint()                              -- the list's height changed: rows must follow it
  end
  if not fits then
    p.chart:Hide()
    return
  end
  local realm = DB.Realm()
  local m = realm.market[r.key]
  p.chart:SetSize(w, Browse.CHART_H)
  p.chart:SetSeries(P.Series(realm.history[r.key], U.day(), 30), m and m.v or nil)
  p.chart:Show()
end

function Browse.UpdateBar()
  local p = Browse.frame
  if not p then return end
  Browse.UpdateChart()
  local r = p.list.selected or nil
  local buyWhy, bidWhy = Browse.WhyNot("buy", r), Browse.WhyNot("bid", r)
  p.buyBtn:SetEnabled(not buyWhy)
  p.bidBtn:SetEnabled(not bidWhy)
  p.buyBtn:SetLabel((r and r.buy) and ("Buy " .. U.money(r.buy)) or "Buy")
  p.bidBtn:SetLabel(r and ("Bid " .. U.money(Auction.BidAmount(r))) or "Bid")
  W.Tip(p.buyBtn, "Buy", buyWhy or "Buy out the selected listing.")
  W.Tip(p.bidBtn, "Bid", bidWhy or "Place the next bid on the selected listing.")
end

-- After a confirmed buy or bid: look at the same page again.
local function again() Browse.Search(Browse.query, Browse.page) end

-- Button OnClick only. Auction.Buy / Auction.Bid re-read the listing first.
function Browse.Buy()
  local item = Browse.frame and Browse.frame.list.selected
  if not item then return false end
  return Auction.Buy(item.index, Auction.Sig(item), again)
end

function Browse.Bid()
  local item = Browse.frame and Browse.frame.list.selected
  if not item then return false end
  return Auction.Bid(item.index, Auction.Sig(item), again)
end

function Browse.ToggleWatch()
  local p = Browse.frame
  local item = p and p.list.selected
  if not item then
    U.msg("Select an item first.")
    return
  end
  local watch = DB.Realm().watch
  if watch[item.key] then watch[item.key] = nil else watch[item.key] = true end
  Browse.UpdateWatchButton()
end

-- A hyperlink rather than SetAuctionItem: a scan may have replaced the
-- auction list since this page was drawn. Anchored at the cursor: a row is as
-- wide as the window, so anchoring to its right puts the tooltip far away.
function Browse.RowTip(row, item)
  local link = U.linkString(item.link)
  if not link then return end
  GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
  GameTooltip:SetHyperlink(link)
  GameTooltip:Show()
end

UI.builders.browse = Browse.Build
