TaxTheFools = TaxTheFools or {}
local U, D, DB = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.DB
local Alerts = { seen = {}, soundAt = -1000 }
TaxTheFools.Alerts = Alerts

-- Deal and snipe alerts while scanning (phase 7 spec section 4). Prints and plays a sound only:
-- nothing here buys, bids, posts or cancels.
Alerts.SOUND_GAP = 5

function Alerts.ResetState() Alerts.seen, Alerts.soundAt = {}, -1000 end

-- listings: { key, unit, qty, owner, buyout }. ctx is built once per call by the caller or here.
-- s = DB.S().alerts. Returns the list of alerts raised: { kind = "snipe"|"deal", key, count, buyout, ... }.
function Alerts.Check(listings, ctx, s, now)
  local out = {}
  if not s or not s.on then return out end
  local me = DB.charName
  local snipeList = DB.Realm().snipe or {}
  local dealSettings = DB.S().deals
  for _, l in ipairs(listings) do
    local count, buyout = l.qty or 1, l.buyout or 0
    if buyout > 0 and not (me and l.owner and l.owner == me) then
      local sig = l.key .. "/" .. count .. "/" .. buyout .. "/" .. (l.owner or "")
      if not Alerts.seen[sig] then
        local unit = buyout / count
        local a = nil
        local e = snipeList[l.key]
        if s.snipe and e and TaxTheFools.Snipe.Match(snipeList, l.key, unit) then
          a = { kind = "snipe", key = l.key, count = count, buyout = buyout, unit = unit, max = e.max }
        else
          local deal = TaxTheFools.Deals.ListingProfit(l.key, count, buyout, ctx, dealSettings)
          if deal and deal.profit >= (s.minProfit or 0) then
            a = { kind = "deal", key = l.key, count = count, buyout = buyout, unit = unit, profit = deal.profit }
          end
        end
        if a then
          Alerts.seen[sig] = true
          table.insert(out, a)
        end
      end
    end
  end
  for _, a in ipairs(out) do
    local rec = TaxTheFools.Items.Get(U.keyId(a.key))
    local name = (rec and rec.n) or a.key
    if a.kind == "snipe" then
      U.msg("Snipe: " .. name .. " x" .. a.count .. " at " .. U.money(math.floor(a.unit), true)
        .. " each (max " .. U.money(a.max, true) .. ")")
    else
      U.msg("Deal: " .. name .. " x" .. a.count .. " for " .. U.money(a.buyout, true)
        .. " (profit " .. U.money(a.profit, true) .. ")")
    end
  end
  if table.getn(out) > 0 and s.sound and now - Alerts.soundAt >= Alerts.SOUND_GAP then
    Alerts.soundAt = now
    PlaySound("TellMessage")
  end
  return out
end

-- Scan.OnRows listener: one context per page, and only when there is something that could alert.
function Alerts.OnRows(rows)
  local s = DB.S().alerts
  if not s or not s.on or table.getn(rows) == 0 then return end
  Alerts.Check(rows, TaxTheFools.TradeSkill.Context(), s, GetTime())
end
