TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, I, Sales, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Sales, TaxTheFools.UI
local HistoryUI = { frame = nil }
TaxTheFools.HistoryUI = HistoryUI

-- What your auction mail says you sold, per item (phase 4 spec section 4).
HistoryUI.PERIODS = { { label = "7 days", value = 7 }, { label = "30 days", value = 30 }, { label = "90 days", value = 90 } }

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

HistoryUI.COLUMNS = {
  { label = "Item", width = 190, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Sold", width = 46, align = "RIGHT", sort = "sold", fmt = function(r) return tostring(r.sold) end },
  { label = "Expired", width = 56, align = "RIGHT", sort = "expired", fmt = function(r) return tostring(r.expired) end },
  { label = "Rate", width = 50, align = "RIGHT", sort = "rate",
    fmt = function(r) return math.floor((r.rate or 0) * 100 + 0.5) .. "%" end },
  { label = "Avg price", width = 90, align = "RIGHT", sort = "avgUnit", fmt = function(r) return money(r.avgUnit) end },
  { label = "Avg time", width = 70, align = "RIGHT", sort = "avgSecs",
    fmt = function(r) if r.avgSecs then return UI.Duration(r.avgSecs) end return "-" end },
  { label = "Income", width = 90, align = "RIGHT", sort = "income", desc = true, fmt = function(r) return money(r.income) end },
}

-- The character records the filter selects: every character, or the one named.
function HistoryUI.Chars(who)
  local chars = DB.Realm().chars
  if who and who ~= "all" then
    local out = {}
    out[who] = chars[who]
    return out
  end
  return chars
end

-- One row per item with results in the window, plus the overall totals.
function HistoryUI.Compute(who, days, now)
  local chars = HistoryUI.Chars(who)
  local all = Sales.StatsAll(chars, days, now)
  local keys = {}
  for key in pairs(all) do table.insert(keys, key) end
  table.sort(keys)
  local rows = {}
  local tot = { sold = 0, n = 0, income = 0 }
  for _, key in ipairs(keys) do
    local s = all[key]
    local id = U.keyId(key)
    local rec = I.Get(id)
    s.key, s.name, s.quality = key, I.Name(id), rec and rec.q
    table.insert(rows, s)
    tot.sold, tot.n, tot.income = tot.sold + s.sold, tot.n + s.n, tot.income + s.income
  end
  if tot.n > 0 then tot.rate = tot.sold / tot.n end
  return rows, tot
end

function HistoryUI.Paint()
  local p = HistoryUI.frame
  if not p then return end
  local rows, tot = HistoryUI.Compute(p.who, p.days, time())
  p.list:SetData(rows)
  if tot.n == 0 then
    p.totals:SetText("No sales in the last " .. p.days .. " days. Open your mail at a mailbox to record them.")
  else
    p.totals:SetText("Income " .. U.money(tot.income) .. "  -  " .. tot.sold .. " sold  -  "
      .. math.floor(tot.rate * 100 + 0.5) .. "% sell rate")
  end
end

function HistoryUI.SetDays(p, days)
  p.days = days
  HistoryUI.Paint()
end

function HistoryUI.SetChar(p, who)
  p.who = who
  HistoryUI.Paint()
end

function HistoryUI.CharOptions()
  local opts, names = { { label = "All characters", value = "all" } }, {}
  for name in pairs(DB.Realm().chars) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do table.insert(opts, { label = name, value = name }) end
  return opts
end

function HistoryUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  HistoryUI.frame = p
  local d = DB.S().sales and DB.S().sales.days
  p.days = (d == 7 or d == 30 or d == 90) and d or 30
  p.who = "all"
  p.periodDD = W.Dropdown(p, 110, HistoryUI.PERIODS, function() return p.days end, function(v) HistoryUI.SetDays(p, v) end)
  p.periodDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.charDD = W.Dropdown(p, 150, HistoryUI.CharOptions(), function() return p.who end, function(v) HistoryUI.SetChar(p, v) end)
  p.charDD:SetPoint("LEFT", p.periodDD, "RIGHT", 6, 0)
  p.totals = Th.Text(p, "body", 12, "dim")
  p.totals:SetPoint("LEFT", p.charDD, "RIGHT", 12, 0)
  p.list = L.New(p, HistoryUI.COLUMNS, 18, nil)
  p.list.sortCol, p.list.sortDesc = HistoryUI.COLUMNS[7], true
  p.list:SetPoint("TOPLEFT", p.periodDD, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.Refresh = function(self)
    self.charDD:SetOptions(HistoryUI.CharOptions())
    HistoryUI.Paint()
  end
  p.Layout = function(self) self.list:Paint() end
  HistoryUI.Paint()
  return p
end

UI.builders.history = HistoryUI.Build
