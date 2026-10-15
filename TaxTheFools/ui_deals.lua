TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Auction, Deals, TS, I, Price = TaxTheFools.Auction, TaxTheFools.Deals, TaxTheFools.TradeSkill, TaxTheFools.Items, TaxTheFools.Price
local DealsUI = { frame = nil }
TaxTheFools.DealsUI = DealsUI

DealsUI.RAIL = 150
DealsUI.STALE_DAYS = 2
DealsUI.TYPE = { market = "Market", vendor = "Vendor", mats = "Mats", under = "Under" }
DealsUI.CONFIDENCE = { { value = 0, label = "Low" }, { value = 0.4, label = "Medium" }, { value = 0.7, label = "High" } }

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

DealsUI.COLUMNS = {
  { label = "Item", width = 190, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Qty", width = 40, align = "RIGHT", sort = "count", fmt = function(r) return tostring(r.count) end },
  { label = "Buyout", width = 84, align = "RIGHT", sort = "buyout", fmt = function(r) return money(r.buyout) end },
  { label = "Each", width = 76, align = "RIGHT", sort = "unit", fmt = function(r) return money(r.unit) end },
  { label = "Market", width = 76, align = "RIGHT", sort = "market", fmt = function(r) return money(r.market) end },
  -- A deal with no market value has no percentage.
  { label = "%", width = 44, align = "RIGHT", sort = "pctRound",
    fmt = function(r) return r.pctRound and (r.pctRound .. "%") or "-", TaxTheFools.Browse.PctToken(r.pctRound) end },
  { label = "Profit", width = 84, align = "RIGHT", sort = "profit", desc = true,
    fmt = function(r) return U.money(r.profit, true), (r.profit >= 0) and "good" or "bad" end },
  { label = "Type", width = 56, sort = "typeLabel", fmt = function(r) return r.typeLabel end },
}

-- The banner for a snapshot taken `age` days ago (nil: there is none).
function DealsUI.BannerText(age)
  if not age then return "No scan yet. Run a full scan.", "warn" end
  if age >= DealsUI.STALE_DAYS then
    return "Deals are from a scan " .. age .. " days ago. Run a full scan for fresh deals.", "warn"
  end
  if age <= 0 then return "Deals from a scan today", "dim" end
  return "Deals from a scan " .. age .. " day ago", "dim"
end

function DealsUI.Decorate(deals)
  for _, d in ipairs(deals) do
    local rec = TaxTheFoolsDB.items[U.keyId(d.key)]
    d.name = (rec and rec.n) or ("Item #" .. (U.keyId(d.key) or "?"))
    d.quality = rec and rec.q
    d.typeLabel = DealsUI.TYPE[d.type] or d.type
    d.pctRound = d.pct and math.floor(d.pct + 0.5) or nil
  end
  return deals
end

-- The recipe name for a mats deal sits in the type column's tooltip.
function DealsUI.RowTip(row, d)
  GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
  GameTooltip:SetText(d.name, 1, 1, 1)
  if d.type == "mats" and d.recipe then GameTooltip:AddLine("Materials for " .. d.recipe, 0.78, 0.78, 0.74, 1) end
  if d.type == "under" then
    GameTooltip:AddLine("You hold " .. d.held .. ". Few are listed and it sells.", 0.78, 0.78, 0.74, 1)
    GameTooltip:AddLine("Suggested price " .. U.money(d.suggest, true) .. " each.", 0.78, 0.78, 0.74, 1)
  end
  if d.type == "market" and d.depositUnknown then GameTooltip:AddLine("Deposit unknown: profit may be a little lower.", 0.78, 0.78, 0.74, 1) end
  GameTooltip:Show()
end

local function same(a, b)
  return a and b and a.key == b.key and a.count == b.count and a.buyout == b.buyout and a.owner == b.owner
end

local function sw(p, label, field, hint)
  local s = W.Switch(p.rail, label, function() return DB.S().deals[field] end,
    function(v) DB.S().deals[field] = v and true or false DealsUI.Paint() end, hint)
  s:SetWidth(DealsUI.RAIL)
  return s
end

local function slider(p, label, field, min, max, step, fmt)
  local s = W.Slider(p.rail, label, min, max, step, function() return DB.S().deals[field] end,
    function(v) DB.S().deals[field] = v DealsUI.Paint() end, fmt)
  s:SetWidth(DealsUI.RAIL)
  return s
end

local function pct(v) return v .. "%" end

function DealsUI.BuildRail(p)
  local rail = CreateFrame("Frame", nil, p)
  rail:SetWidth(DealsUI.RAIL)
  rail:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  p.rail = rail
  p.marketSw = sw(p, "Below market", "market", "Listings well under the usual price.")
  p.vendorSw = sw(p, "Below vendor", "vendor", "Listings under what a vendor pays.")
  p.matsSw = sw(p, "Cheap materials", "mats", "Materials that make a recipe you know more profitable.")
  p.marketSw:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)
  p.vendorSw:SetPoint("TOPLEFT", p.marketSw, "BOTTOMLEFT", 0, -2)
  p.matsSw:SetPoint("TOPLEFT", p.vendorSw, "BOTTOMLEFT", 0, -2)
  p.underSw = sw(p, "Undersupplied", "under", "Items you hold that sell well and are scarce now. Sell opens the Sell tab.")
  p.underSw:SetPoint("TOPLEFT", p.matsSw, "BOTTOMLEFT", 0, -2)
  p.belowSl = slider(p, "Below market", "belowMarketPct", 50, 95, 5, pct)
  p.belowSl:SetPoint("TOPLEFT", p.underSw, "BOTTOMLEFT", 0, -14)
  p.profitSl = slider(p, "Minimum profit", "minProfit", 0, 100000, 1000, function(v) return U.money(v) end)
  p.profitSl:SetPoint("TOPLEFT", p.belowSl, "BOTTOMLEFT", 0, -8)
  p.matSl = slider(p, "Materials", "matPct", 50, 100, 5, pct)
  p.matSl:SetPoint("TOPLEFT", p.profitSl, "BOTTOMLEFT", 0, -8)
  p.confLabel = Th.Text(rail, "body", 13, "text")
  p.confLabel:SetPoint("TOPLEFT", p.matSl, "BOTTOMLEFT", 0, -8)
  p.confLabel:SetText("Minimum confidence")
  p.confDD = W.Dropdown(rail, DealsUI.RAIL, DealsUI.CONFIDENCE, function() return DB.S().deals.minConfidence end,
    function(v) DB.S().deals.minConfidence = v DealsUI.Paint() end)
  p.confDD:SetPoint("TOPLEFT", p.confLabel, "BOTTOMLEFT", 0, -4)
  -- underPct and premiumPct are Options-page settings only: more rail rows overflow the minimum window height.
end

function DealsUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.found, p.searching = false, false
  DealsUI.BuildRail(p)
  p.banner = Th.Text(p, "body", 12, "dim")
  p.banner:SetPoint("TOPLEFT", p, "TOPLEFT", DealsUI.RAIL + 12, -2)
  p.banner:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.banner:SetJustifyH("LEFT")
  p.list = L.New(p, DealsUI.COLUMNS, 18, function(item) DealsUI.Selected(item) end)
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", DealsUI.RAIL + 12, -22)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 32)
  p.list.onEnter = function(row, item) DealsUI.RowTip(row, item) end
  -- The action bar: Find pages through a search (a scan); only Buy spends, one click each.
  p.findBtn = W.Button(p, "Find", 160, 24, function() DealsUI.Click() end, "accent")
  p.findBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.status = Th.Text(p, "body", 12, "dim")
  p.status:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", DealsUI.RAIL + 12, 6)
  p.status:SetPoint("RIGHT", p.findBtn, "LEFT", -8, 0)
  p.status:SetJustifyH("LEFT")
  p.Refresh = function(self) DealsUI.Paint() end
  p.Layout = function(self) self.list:Paint() end
  DealsUI.frame = p
  Scan.OnChange(function() if p:IsVisible() then DealsUI.Paint() end end)
  Auction.OnChange(function() DealsUI.UpdateBar() end)
  DealsUI.Paint()
  return p
end

function DealsUI.Say(text, token)
  local p = DealsUI.frame
  if not p then return end
  p.status:SetText(text or "")
  Th.Color(p.status, token or "dim")
end

-- Recomputed from the snapshot on show, on any rail change and on Scan.OnChange.
-- The selected deal stays selected when it is still a deal.
function DealsUI.Paint()
  local p = DealsUI.frame
  if not p then return end
  local snap = DB.Realm().snapshot
  local text, token = DealsUI.BannerText(Scan.SnapshotAge(U.day(time())))
  p.banner:SetText(text)
  Th.Color(p.banner, token)
  for _, c in ipairs({ p.marketSw, p.vendorSw, p.matsSw, p.underSw, p.belowSl, p.profitSl, p.matSl, p.confDD }) do c:Refresh() end
  local keep = p.list.selected and Auction.Sig(p.list.selected)
  local ctx = TS.Context()
  local deals = Deals.Find(snap, ctx, DB.S().deals, DB.charName)
  for _, u in ipairs(Deals.FindUnder(snap, ctx, DB.S().deals, DealsUI.UnderSource(ctx))) do table.insert(deals, u) end
  table.sort(deals, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    if a.key ~= b.key then return a.key < b.key end
    return (a.buyout or 0) < (b.buyout or 0)
  end)
  p.list:SetData(DealsUI.Decorate(deals))
  for _, d in ipairs(p.list.data) do
    if same(keep, Auction.Sig(d)) then p.list.selected = d end
  end
  p.list:Paint()
  if not p.list.selected then p.found = false end
  DealsUI.UpdateBar()
end

-- Holdings, sell-rate stats over the Sales window and the median listing count per key.
function DealsUI.UnderSource(ctx)
  local realm, now, today = DB.Realm(), time(), U.day(time())
  return {
    held = ctx.held,
    stats = function(key) return TaxTheFools.Sales.Stats(realm.chars, key, DB.S().sales.days, now) end,
    median = function(key)
      local m = Price.Market(realm.history[key], today)
      return m and m.n
    end,
  }
end

function DealsUI.Selected(item)
  local p = DealsUI.frame
  if p.found and not same(p.found.sig, Auction.Sig(item)) then p.found = false end
  if not p.found and not p.searching then DealsUI.Say("") end
  DealsUI.UpdateBar()
end

-- Why Buy is unavailable for a located deal, or nil.
function DealsUI.WhyNot(d)
  if Auction.busy then return "Waiting for the auction house to answer." end
  if Auction.Own(d) then return "That is your own auction." end
  if d.buyout > GetMoney() then return "You can't afford " .. U.money(d.buyout, true) .. "." end
  return nil
end

function DealsUI.UpdateBar()
  local p = DealsUI.frame
  if not p then return end
  -- A Find that was cut off without telling us must not leave the button dead.
  if p.searching and not Scan.Busy() then p.searching = false end
  local d = p.list.selected or nil
  if d and d.type == "under" then
    p.findBtn:SetLabel("Sell")
    p.findBtn:SetEnabled(not p.searching)
    W.Tip(p.findBtn, "Sell", "Open the Sell tab with this item selected.")
    return
  end
  local found = d and p.found and same(p.found.sig, Auction.Sig(d))
  if found then
    local why = DealsUI.WhyNot(d)
    p.findBtn:SetLabel("Buy " .. U.money(d.buyout))
    p.findBtn:SetEnabled(not why)
    W.Tip(p.findBtn, "Buy", why or "Buy out the located listing.")
  else
    p.findBtn:SetLabel("Find")
    p.findBtn:SetEnabled(d and not p.searching and true or false)
    W.Tip(p.findBtn, "Find", d and "Search the auction house for this listing." or "Select a deal first.")
  end
end

-- The Find / Buy button's OnClick.
function DealsUI.Click()
  local p = DealsUI.frame
  local d = p.list.selected
  if not d or p.searching then return false end
  if d.type == "under" then return DealsUI.Sell(d) end
  if p.found and same(p.found.sig, Auction.Sig(d)) then return DealsUI.Buy(d) end
  return DealsUI.Find(d)
end

-- Switches to the Sell tab and selects the item. Never a buy, a search or a post.
function DealsUI.Sell(d)
  -- The tab strip owns the highlight and calls UI.ShowPage("sell") itself.
  if UI.ah and UI.ah.tabs then UI.ah.tabs:Select("sell") else UI.ShowPage("sell") end
  local SellUI = TaxTheFools.SellUI
  local it = SellUI.Find(d.key)
  if not it then
    SellUI.Refresh()
    it = SellUI.Find(d.key)
  end
  if it then SellUI.Select(it) else SellUI.Say("Can't auction that", "warn") end
  return true
end

-- Paging is a scan, never a buy: nothing here reaches Auction.Buy.
function DealsUI.Find(d)
  local p = DealsUI.frame
  if Scan.Busy() then
    Auction.Say("A scan is using the auction house. Pause it to search.", "bad")
    return false
  end
  local rec = TaxTheFoolsDB.items[U.keyId(d.key)]
  if not rec or not rec.n then
    Auction.Say("That item's name is not known yet. Search for it in Browse.", "bad")
    return false
  end
  local sig = Auction.Sig(d)
  p.found, p.searching = false, true
  DealsUI.Say("Searching...")
  local ok = Scan.Locate(rec.n, sig, function(index, page, err) DealsUI.Located(sig, index, page, err) end)
  if not ok then
    p.searching = false
    Auction.Say("A scan is using the auction house. Pause it to search.", "bad")
  end
  DealsUI.UpdateBar()
  return ok
end

function DealsUI.Located(sig, index, page, err)
  local p = DealsUI.frame
  p.searching = false
  if err == "paused" then
    DealsUI.Say("Search interrupted. Press Find again.", "warn")
  elseif err then
    DealsUI.Say("No reply from the auction house. Try again.", "bad")
  elseif index then
    p.found = { sig = sig, index = index, page = page }
    DealsUI.Say("Found on page " .. (page + 1), "good")
  else
    DealsUI.Say("Gone", "warn")
    Scan.SnapshotRemove(sig)
    DealsUI.Paint()
  end
  DealsUI.UpdateBar()
end

-- Button OnClick only. Auction.Buy re-reads the listing at the found index and
-- refuses when another query has replaced the list since.
function DealsUI.Buy(d)
  local p = DealsUI.frame
  local f = p.found
  local r = Auction.Buy(f.index, f.sig, function()
    p.found = false
    DealsUI.Say("")
    DealsUI.Paint()
  end, false, function(text) DealsUI.BuyFailed(f.sig, text) end)
  -- A refusal (not a spend, not the confirmation window) means the listing moved.
  if not r then
    p.found = false
    DealsUI.Say("Listing changed. Press Find again.", "warn")
    DealsUI.UpdateBar()
  end
  return r
end

-- The reply to a Deals buy said it failed: the located listing is no longer usable.
function DealsUI.BuyFailed(sig, text)
  local p = DealsUI.frame
  p.found = false
  if ERR_ITEM_NOT_FOUND and text == ERR_ITEM_NOT_FOUND then
    Scan.SnapshotRemove(sig)
    DealsUI.Say("Gone: someone else bought it.", "warn")
    DealsUI.Paint()
  else
    DealsUI.Say(text or "", "bad")
  end
  DealsUI.UpdateBar()
end

UI.builders.deals = DealsUI.Build
