TaxTheFools = TaxTheFools or {}
local U, D, DB = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.DB
local Alerts = { seen = {}, soundAt = -1000 }
TaxTheFools.Alerts = Alerts

-- Deal and snipe alerts while scanning (phase 7 spec section 4). Prints and plays a sound only:
-- nothing here buys, bids, posts or cancels.
Alerts.SOUND_GAP = 5
Alerts.MAX_LINES = 8   -- chat lines per scanned page; the rest are summed up in one line

function Alerts.ResetState() Alerts.seen, Alerts.soundAt, Alerts.ctx, Alerts.ctxJob = {}, -1000, nil, nil end

-- listings: { key, unit, qty, owner, buyout }. ctx is built once per call by the caller or here.
-- s = DB.S().alerts. Returns the list of alerts raised: { kind = "snipe"|"deal", key, count, buyout, ... }.
function Alerts.Check(listings, ctx, s, now)
  local out = {}
  if not s or not s.on then return out end
  local me = DB.charName
  local snipeList = DB.Realm().snipe or {}
  -- Alerts have their own minimum profit; deals.minProfit must not hide an alert.
  local dealSettings = {}
  for k, v in pairs(DB.S().deals) do dealSettings[k] = v end
  dealSettings.minProfit = s.minProfit or 0
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
  local shown = 0
  for _, a in ipairs(out) do
    shown = shown + 1
    if shown > Alerts.MAX_LINES then break end
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
  if table.getn(out) > Alerts.MAX_LINES then
    U.msg("...and " .. (table.getn(out) - Alerts.MAX_LINES) .. " more alerts on this page")
  end
  if table.getn(out) > 0 and s.sound and now - Alerts.soundAt >= Alerts.SOUND_GAP then
    Alerts.soundAt = now
    PlaySound("TellMessage")
  end
  return out
end

function Alerts.BuildContext() return TaxTheFools.TradeSkill.Context() end

-- Scan.OnRows listener. The context (holdings, recipe index) is built once per scan job and reused
-- for every page; a new job builds a fresh one.
function Alerts.OnRows(rows)
  local s = DB.S().alerts
  if not s or not s.on or table.getn(rows) == 0 then return end
  local job = TaxTheFools.Scan.job
  if not Alerts.ctx or Alerts.ctxJob ~= job then
    Alerts.ctx, Alerts.ctxJob = Alerts.BuildContext(), job
  end
  Alerts.Check(rows, Alerts.ctx, s, GetTime())
end
