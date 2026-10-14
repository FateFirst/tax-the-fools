TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Browse = { query = "", page = 0, frame = nil }
TaxTheFools.Browse = Browse

function Browse.ResetState() Browse.query, Browse.page = "", 0 end

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
  { label = "Item", width = 220, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Qty", width = 44, align = "RIGHT", sort = "count", desc = true, fmt = function(r) return tostring(r.count) end },
  { label = "Bid", width = 92, align = "RIGHT", sort = "bidNow", fmt = function(r) return money(r.bidNow) end },
  { label = "Buyout", width = 92, align = "RIGHT", sort = "buy", fmt = function(r) return money(r.buy) end },
  { label = "Each", width = 84, align = "RIGHT", sort = "unit", fmt = function(r) return money(r.unit) end },
  { label = "Market", width = 84, align = "RIGHT", sort = "market", fmt = function(r) return money(r.market) end },
  { label = "%", width = 48, align = "RIGHT", sort = "pct",
    fmt = function(r) return r.pct and (r.pct .. "%") or "-", Browse.PctToken(r.pct) end },
  { label = "Seller", width = 92, sort = "owner", fmt = function(r) return r.owner or "?" end },
}

function Browse.Decorate(rows, market)
  for _, r in ipairs(rows) do
    local m = market[r.key]
    r.market = m and m.v or nil
    r.pct = nil
    if r.unit and r.market and r.market > 0 then r.pct = math.floor(r.unit / r.market * 100 + 0.5) end
    r.bidNow = ((r.bid or 0) > 0) and r.bid or r.minBid
    r.buy = ((r.buyout or 0) > 0) and r.buyout or nil
  end
  return rows
end

function Browse.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.search = W.EditBox(p, 220, function(text) Browse.Search(text, 0) end)
  p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.go = W.Button(p, "Search", 80, 22, function() Browse.Search(p.search:GetText(), 0) end, "accent")
  p.go:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
  p.watchBtn = W.Button(p, "Watch", 90, 22, function() Browse.ToggleWatch() end)
  p.watchBtn:SetPoint("LEFT", p.go, "RIGHT", 6, 0)
  W.Tip(p.watchBtn, "Watchlist", "Watched items are priced by the quick Watchlist scan.")
  p.next = W.IconButton(p, "icon-arrow-right", 22, function() Browse.Search(Browse.query, Browse.page + 1) end)
  p.next:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  p.prev = W.IconButton(p, "icon-arrow-left", 22, function() Browse.Search(Browse.query, Browse.page - 1) end)
  p.prev:SetPoint("RIGHT", p.next, "LEFT", -4, 0)
  p.pageText = Th.Text(p, "body", 11, "dim")
  p.pageText:SetPoint("RIGHT", p.prev, "LEFT", -8, 0)
  p.pageText:SetJustifyH("RIGHT")
  p.list = L.New(p, Browse.COLUMNS, 18, function() Browse.UpdateWatchButton() end)
  p.list:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.list.onEnter = function(row, item) Browse.RowTip(row, item) end
  p.Refresh = function(self) Browse.Paint() end
  p.Layout = function(self) self.list:Paint() end
  Browse.frame = p
  Scan.OnChange(function() if p:IsVisible() then Browse.Paint() end end)
  Browse.Paint()
  return p
end

function Browse.Paint()
  local p = Browse.frame
  if not p then return end
  p.list:SetData(Browse.Decorate(Scan.lastRows, DB.Realm().market))
  local pages = math.max(1, math.ceil(Scan.lastTotal / 50))
  p.pageText:SetText("Page " .. (Scan.lastPage + 1) .. " of " .. pages .. ", " .. Scan.lastTotal .. " found")
  Browse.UpdateWatchButton()
end

function Browse.Search(text, page)
  if page < 0 then return false end
  if page > 0 and page * 50 >= Scan.lastTotal then return false end
  Browse.query, Browse.page = text or "", page
  local ok, why = Scan.Browse(Browse.query, page, GetTime())
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
