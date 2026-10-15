TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Auction = TaxTheFools.Auction
local AuctionsUI = { frame = nil }
TaxTheFools.AuctionsUI = AuctionsUI

-- One page of your own auctions (phase 3b spec section 5).
AuctionsUI.MAX = 50
AuctionsUI.TIMES = { "short", "medium", "long", "very long" }

function AuctionsUI.TimeText(n) return AuctionsUI.TIMES[n or 0] or "?" end

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

AuctionsUI.COLUMNS = {
  { label = "Item", width = 190, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Qty", width = 40, align = "RIGHT", sort = "count", fmt = function(r) return tostring(r.count) end },
  { label = "Bid", width = 84, align = "RIGHT", sort = "bidNow", fmt = function(r) return money(r.bidNow) end },
  { label = "Buyout", width = 84, align = "RIGHT", sort = "buyout", fmt = function(r) return money(r.buyout) end },
  { label = "Time left", width = 70, sort = "timeLeft", fmt = function(r) return r.timeText end },
  { label = "Status", width = 150,
    fmt = function(r)
      if r.status == "undercut" then return "Undercut " .. U.money(r.rival), "bad" end
      if r.status == "cheapest" then return "Cheapest", "good" end
      return "No competition", "dim"
    end },
}

-- The cheapest competing price per unit for key, from the latest browse and the snapshot.
-- Your own listings (by owner name) do not compete.
function AuctionsUI.Rival(key)
  local best = nil
  local me = DB.charName
  for _, r in ipairs(Scan.lastRows) do
    if r.key == key and r.unit and r.owner ~= me and (not best or r.unit < best) then best = r.unit end
  end
  local snap = DB.Realm().snapshot
  local rows = snap and snap.rows and snap.rows[key]
  if rows then
    for _, s in ipairs(rows) do
      local count, buyout, _, owner = Scan.ParseSnapRow(s)
      if count and count > 0 and buyout and buyout > 0 and owner ~= me then
        local unit = buyout / count
        if not best or unit < best then best = unit end
      end
    end
  end
  return best
end

function AuctionsUI.Decorate(r)
  r.bidNow = (r.bid > 0) and r.bid or r.minBid
  r.timeLeft = GetAuctionItemTimeLeft("owner", r.index) or 0
  r.timeText = AuctionsUI.TimeText(r.timeLeft)
  local rival = AuctionsUI.Rival(r.key)
  r.rival = rival
  if not rival or not r.unit then r.status = "none"
  elseif rival < r.unit then r.status = "undercut"
  else r.status = "cheapest" end
  return r
end

-- AUCTION_OWNED_LIST_UPDATE (through Core.Safe): read the owner list.
function AuctionsUI.Read()
  local p = AuctionsUI.frame
  if not p then return end
  local n, total = GetNumAuctionItems("owner")
  n = n or 0
  local rows = {}
  for i = 1, math.min(n, AuctionsUI.MAX) do
    local r = Auction.OwnerRow(i)
    if r then table.insert(rows, AuctionsUI.Decorate(r)) end
  end
  p.total = total or n
  p.list:SetData(rows)
  AuctionsUI.Paint()
end

function AuctionsUI.Request() GetOwnerAuctionItems(0) end

function AuctionsUI.Paint()
  local p = AuctionsUI.frame
  if not p then return end
  local n = table.getn(p.list.data)
  local text = n .. ((n == 1) and " active auction" or " active auctions")
  if p.total and p.total > n then text = text .. " (showing " .. n .. " of " .. p.total .. ")" end
  p.summary:SetText(text)
  AuctionsUI.UpdateBar()
end

function AuctionsUI.UpdateBar()
  local p = AuctionsUI.frame
  if not p then return end
  local sel = p.list.selected
  p.cancelBtn:SetEnabled((sel and not Auction.busy) and true or false)
  W.Tip(p.cancelBtn, "Cancel auction", sel and "Take the selected auction down." or "Select an auction first.")
end

-- The Cancel button's OnClick only. Auction.Cancel re-reads the row, asks first when it has a bid, and
-- re-requests the owner list after the server confirms.
function AuctionsUI.Cancel()
  local p = AuctionsUI.frame
  local sel = p and p.list.selected
  if not sel then return false end
  return Auction.Cancel(sel.index, Auction.Sig(sel))
end

function AuctionsUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.total = 0
  p.summary = Th.Text(p, "body", 12, "dim")
  p.summary:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -2)
  p.list = L.New(p, AuctionsUI.COLUMNS, 18, function() AuctionsUI.UpdateBar() end)
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -22)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 32)
  p.cancelBtn = W.Button(p, "Cancel auction", 160, 24, function() AuctionsUI.Cancel() end, "accent")
  p.cancelBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.Refresh = function(self)
    AuctionsUI.Request()
    AuctionsUI.Paint()
  end
  p.Layout = function(self) self.list:Paint() end
  AuctionsUI.frame = p
  Auction.OnChange(function() AuctionsUI.UpdateBar() end)
  AuctionsUI.Paint()
  return p
end

UI.builders.auctions = AuctionsUI.Build
