TaxTheFools = TaxTheFools or {}
local U, Th, W, DB, Auction = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB,
  TaxTheFools.Auction
local Confirm = { frame = nil, pending = false }
TaxTheFools.Confirm = Confirm

function Confirm.ResetState()
  if Confirm.frame then Confirm.frame:Hide() end
  Confirm.pending = false
end

-- The window's three lines for listing row r and the item's market value (or nil).
function Confirm.Lines(r, market)
  local unit = r.buyout / r.count
  local head = U.quality(r.quality) .. r.name .. "|r  x" .. r.count
  local total = "Total " .. U.money(r.buyout)
  local each = "Each " .. U.money(unit)
  if market and market > 0 then
    each = each .. "   Market " .. U.money(market) .. "   " .. math.floor(unit / market * 100 + 0.5) .. "% of market"
  else
    each = each .. "   no market value"
  end
  return { head, total, each }
end

function Confirm.Create()
  if Confirm.frame then return Confirm.frame end
  local f = W.Window("TaxTheFoolsConfirm", 360, 150, "Confirm purchase")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f.lines = {}
  for i = 1, 3 do
    local fs = Th.Text(f, (i == 1) and "body2" or "body", (i == 1) and 13 or 12, (i == 2) and "gold" or "text")
    fs:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 14, -10 - (i - 1) * 20)
    fs:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.lines[i] = fs
  end
  f.buy = W.Button(f, "Buy", 100, 24, function() Confirm.Buy() end, "accent")
  f.buy:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
  f.cancel = W.Button(f, "Cancel", 100, 24, function() f:Hide() end)
  f.cancel:SetPoint("RIGHT", f.buy, "LEFT", -8, 0)
  -- Escape (UISpecialFrames), Cancel and the close button all end here.
  f:SetScript("OnHide", function() Confirm.pending = false end)
  Confirm.frame = f
  return f
end

-- Called by Auction.Buy for a buyout at or above the confirmation amount.
function Confirm.Open(index, sig, r, after, onFail)
  local f = Confirm.Create()
  local m = DB.Realm().market[r.key]
  local lines = Confirm.Lines(r, m and m.v)
  for i, fs in ipairs(f.lines) do fs:SetText(lines[i]) end
  f:Show()
  Confirm.pending = { index = index, sig = sig, after = after or false, onFail = onFail or false }
end

-- The window's Buy click: one more listing check inside Auction.Buy, then at most one PlaceAuctionBid.
function Confirm.Buy()
  local p = Confirm.pending
  Confirm.pending = false
  if Confirm.frame then Confirm.frame:Hide() end
  if not p then return false end
  return Auction.Buy(p.index, p.sig, p.after, true, p.onFail)
end

function Confirm.Cancel()
  if Confirm.frame then Confirm.frame:Hide() end
end
