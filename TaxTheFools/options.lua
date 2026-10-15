TaxTheFools = TaxTheFools or {}
local U, D, Th, W, DB = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB
local Opt = { frame = nil }
TaxTheFools.Options = Opt

local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function secs(v) return string.format("%.1fs", v) end
local function days(v)
  if v == 1 then return "1 day" end
  return v .. " days"
end
local function themes()
  local t = {}
  for _, n in ipairs(Th.ORDER) do table.insert(t, { value = n, label = n }) end
  return t
end

-- The Deals rows read and write the same settings.deals table as the Deals
-- page's rail, so a change in one shows in the other the next time it paints.
local function money(v) return U.money(v) end

-- Phase 3b adds the Selling page.
Opt.CATEGORIES = {
  { key = "general", label = "General", rows = {
    { kind = "switch", key = "replaceBlizzardAH", label = "Replace the Blizzard auction window",
      hint = "Takes effect next time you open the auction house. The Blizzard UI button switches back any time." },
    { kind = "switch", key = "minimap", label = "Minimap button", after = function() TaxTheFools.Minimap.Refresh() end },
    { kind = "slider", key = "scale", label = "Window scale", min = 0.8, max = 1.5, step = 0.05, fmt = pct,
      after = function() W.ApplyScale() end },
    { kind = "switch", key = "debug", label = "Debug messages",
      hint = "Prints extra detail, and shows Lua errors instead of quietly switching the failing part off." },
  } },
  { key = "scanning", label = "Scanning", rows = {
    { kind = "slider", key = "scanDelay", label = "Minimum time between pages", min = 0, max = 2, step = 0.1, fmt = secs },
    { kind = "switch", key = "safeMode", label = "Safe pace (4s between pages)",
      hint = "Use this if scans keep repeating pages or stalling." },
    { kind = "switch", key = "browseFeedsHistory", label = "Searches add to price history" },
  } },
  { key = "crafting", label = "Crafting", rows = {
    { kind = "switch", path = { "craft", "autoWatch" }, label = "Watch recipe materials automatically",
      hint = "Each time a tradeskill window opens, its products and materials join the Watchlist scan." },
    { kind = "slider", path = { "craft", "staleDays" }, label = "Dim prices older than", min = 1, max = 30, step = 1,
      fmt = days, after = function() TaxTheFools.CraftUI.RefreshAll() end },
  } },
  { key = "deals", label = "Deals & buying", rows = {
    { kind = "switch", path = { "deals", "market" }, label = "Below market" },
    { kind = "switch", path = { "deals", "vendor" }, label = "Below vendor" },
    { kind = "switch", path = { "deals", "mats" }, label = "Cheap materials" },
    { kind = "slider", path = { "deals", "belowMarketPct" }, label = "Below market", min = 50, max = 95, step = 5,
      fmt = function(v) return v .. "%" end },
    { kind = "slider", path = { "deals", "minProfit" }, label = "Minimum profit", min = 0, max = 100000, step = 1000,
      fmt = money },
    { kind = "slider", path = { "deals", "matPct" }, label = "Materials", min = 50, max = 100, step = 5,
      fmt = function(v) return v .. "%" end },
    { kind = "dropdown", path = { "deals", "minConfidence" }, label = "Minimum confidence",
      options = TaxTheFools.DealsUI.CONFIDENCE },
    { kind = "slider", path = { "buy", "confirmAbove" }, label = "Confirm buys at or above", min = 0, max = 500000,
      step = 10000, fmt = money },
  } },
  { key = "tooltip", label = "Tooltip", rows = {
    { kind = "switch", path = { "tooltip", "market" }, label = "Market value" },
    { kind = "switch", path = { "tooltip", "low" }, label = "Lowest price in the latest scan" },
    { kind = "switch", path = { "tooltip", "vendor" }, label = "Vendor price" },
  } },
  { key = "appearance", label = "Appearance", rows = {
    { kind = "dropdown", key = "theme", label = "Theme", options = themes(), after = function(v) Th.Apply(v) end },
    { kind = "switch", key = "fonts", label = "Bundled fonts (needs /reload)" },
  } },
  { key = "data", label = "Data", rows = {
    { kind = "info", text = function() return DB.SizeText() end },
    { kind = "button", label = "Prune old data now", onClick = function()
      DB.StartPrune()
      TaxTheFools.Core.pruned = false
      U.msg("Pruning old price history.")
    end },
    { kind = "button", label = "Reset all data", onClick = function() StaticPopup_Show("TAXTHEFOOLS_RESET") end },
  } },
}

StaticPopupDialogs["TAXTHEFOOLS_RESET"] = {
  text = "Delete all Tax the Fools price history, items and settings for every character, then reload?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    DB.Wipe()
    ReloadUI()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local function path(row) return row.path or { row.key } end

function Opt.Get(row)
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  return t[p[table.getn(p)]]
end

function Opt.Set(row, v)
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  t[p[table.getn(p)]] = v
  if row.after then row.after(v) end
end

-- One control for one row. row arrives as a parameter, so the closures below
-- each keep their own (a loop variable would be shared in Lua 5.0).
function Opt.Control(parent, row)
  local get = function() return Opt.Get(row) end
  local set = function(v) Opt.Set(row, v) end
  if row.kind == "switch" then return W.Switch(parent, row.label, get, set, row.hint) end
  if row.kind == "slider" then return W.Slider(parent, row.label, row.min, row.max, row.step, get, set, row.fmt) end
  if row.kind == "dropdown" then
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(320)
    f:SetHeight(26)
    f.text = Th.Text(f, "body", 13, "text")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetText(row.label)
    f.dd = W.Dropdown(f, 140, row.options, get, set)
    f.dd:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.Refresh = function(self) self.dd:Refresh() end
    return f
  end
  if row.kind == "button" then
    local b = W.Button(parent, row.label, 180, 24, row.onClick)
    b.Refresh = function() end
    return b
  end
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(320)
  f:SetHeight(32)
  f.text = Th.Text(f, "body", 12, "dim")
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.text:SetWidth(320)
  f.Refresh = function(self) self.text:SetText(row.text()) end
  return f
end

function Opt.Page(f, cat)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 16, -14)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  p.controls = {}
  local y = 0
  for _, row in ipairs(cat.rows) do
    local c = Opt.Control(p, row)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
    y = y + c:GetHeight() + 10
    table.insert(p.controls, c)
  end
  return p
end

function Opt.NavRow(f, i, cat)
  local b = CreateFrame("Button", nil, f.nav)
  b:SetHeight(30)
  b:SetPoint("TOPLEFT", f.nav, "TOPLEFT", 0, -8 - (i - 1) * 30)
  b:SetPoint("RIGHT", f.nav, "RIGHT", 0, 0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(b)
  hl:SetVertexColor(1, 1, 1, 0.04)
  b.bar = Th.Solid(b, "ARTWORK", "accent")
  b.bar:SetWidth(3)
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.bar:Hide()
  b.text = Th.Text(b, "body", 13, "dim")
  b.text:SetPoint("LEFT", b, "LEFT", 14, 0)
  b.text:SetText(cat.label)
  b.key = cat.key
  b:SetScript("OnClick", function() Opt.Select(this.key) end)
  return b
end

function Opt.Create()
  if Opt.frame then return Opt.frame end
  local f = W.Window("TaxTheFoolsOptions", 540, 400, "Tax the Fools  -  Options")
  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetWidth(150)
  f.nav:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -1)
  f.nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  local bg = Th.Solid(f.nav, "BACKGROUND", "panel3")
  bg:SetAllPoints(f.nav)
  f.version = Th.Text(f.nav, "body", 10, "subtle")
  f.version:SetPoint("BOTTOMLEFT", f.nav, "BOTTOMLEFT", 14, 10)
  f.version:SetText("v" .. D.VERSION)
  f.pages, f.navRows, f.selected = {}, {}, false
  for i, cat in ipairs(Opt.CATEGORIES) do f.navRows[cat.key] = Opt.NavRow(f, i, cat) end
  f:SetScript("OnShow", function() Opt.Select(f.selected or Opt.CATEGORIES[1].key) end)
  Opt.frame = f
  return f
end

function Opt.Select(key)
  local f = Opt.Create()
  f.selected = key
  for _, cat in ipairs(Opt.CATEGORIES) do
    local on = (cat.key == key)
    local nav = f.navRows[cat.key]
    Th.Color(nav.text, on and "white" or "dim")
    if on then nav.bar:Show() else nav.bar:Hide() end
    local page = f.pages[cat.key]
    if on and not page then
      page = Opt.Page(f, cat)
      f.pages[cat.key] = page
    end
    if page then
      if on then page:Show() else page:Hide() end
    end
  end
  for _, c in ipairs(f.pages[key].controls) do c:Refresh() end
end

function Opt.Toggle()
  local f = Opt.Create()
  if f:IsShown() then f:Hide() else f:Show() end
end
