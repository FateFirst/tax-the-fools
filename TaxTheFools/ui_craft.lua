TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Craft, TS, UI, Scan = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets,
  TaxTheFools.List, TaxTheFools.DB, TaxTheFools.Craft, TaxTheFools.TradeSkill, TaxTheFools.UI, TaxTheFools.Scan
local CraftUI = { pages = {}, window = nil }
TaxTheFools.CraftUI = CraftUI

CraftUI.EMPTY = "Open your Tailoring window once on this character to load its recipes."
-- The client's own recipe colours (TradeSkillTypeColor).
CraftUI.SKILL_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40bf40", trivial = "|cff808080" }
CraftUI.SOURCE = { ah = "AH", vendor = "vendor", craft = "craft" }
CraftUI.DETAIL_LINES = 9      -- a heading and up to eight materials, the most a 1.12 recipe has
CraftUI.DETAIL_H = 10 + 9 * 14

local function money(v)
  if v then return U.money(v) end
  return "-"
end

local function signed(v)
  if not v then return "-", "dim" end
  if v >= 0 then return U.money(v, true), "good" end
  return U.money(v, true), "bad"
end

CraftUI.COLUMNS = {
  { label = "Recipe", width = 220, sort = "name",
    fmt = function(r) return (CraftUI.SKILL_COLOR[r.color] or "|cffffffff") .. r.name .. "|r" end },
  { label = "Cost", width = 90, align = "RIGHT", sort = "cost", fmt = function(r) return money(r.cost) end },
  { label = "Value", width = 100, align = "RIGHT", sort = "value",
    fmt = function(r) return money(r.value) .. (r.vendorValue and " (v)" or "") end },
  { label = "Profit", width = 90, align = "RIGHT", sort = "profit", desc = true, fmt = function(r)
    if not r.profit then return "incomplete", "warn" end
    return signed(r.profit)
  end },
  { label = "Cash", width = 90, align = "RIGHT", sort = "cash", desc = true, fmt = function(r) return signed(r.cash) end },
  { label = "Age", width = 60, align = "RIGHT", sort = "age",
    fmt = function(r) return r.age and U.daysAgo(r.age) or "-", r.stale and "dim" or "text" end },
}

-- One row per recipe. A recipe with any price missing has profit nil, and
-- the list sorts nil last whichever way a column is sorted.
function CraftUI.Rows(prof, ctx, staleDays)
  local rows = {}
  for name, recipe in pairs(prof.recipes or {}) do
    local ev = Craft.Evaluate(recipe, ctx)
    local age = ev.oldest and (ctx.today - ev.oldest) or nil
    table.insert(rows, { name = name, color = recipe.color, recipe = recipe, ev = ev,
      cost = ev.cost, value = ev.value, profit = ev.profit, cash = ev.cash,
      vendorValue = (ev.valueSource == "vendor"), age = age, stale = (age ~= nil and age > staleDays) })
  end
  return rows
end

-- Characters on this realm with at least one captured profession, sorted.
function CraftUI.Characters(realm)
  local names = {}
  for name, c in pairs(realm.chars or {}) do
    if c.professions and next(c.professions) then table.insert(names, name) end
  end
  table.sort(names)
  return names
end

function CraftUI.Professions(c)
  local names = {}
  for name in pairs((c and c.professions) or {}) do table.insert(names, name) end
  table.sort(names)
  return names
end

local function options(names)
  local t = {}
  for _, n in ipairs(names) do table.insert(t, { value = n, label = n }) end
  return t
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- The detail pane's lines for one row, as { text, token } pairs.
function CraftUI.DetailLines(row, today, staleDays)
  if not row then return { { "Select a recipe to see its materials.", "dim" } } end
  local ev = row.ev
  local out = {}
  if ev.profit then
    local head = row.name .. ": profit " .. U.money(ev.profit, true) .. ", cash " .. U.money(ev.cash, true)
    if ev.valueSource == "vendor" then head = head .. " (valued at the vendor price)" end
    if ev.depositUnknown then head = head .. " (deposit unknown)" end
    local _, token = signed(ev.profit)
    table.insert(out, { head, token })
  else
    table.insert(out, { row.name .. ": incomplete: " .. table.concat(ev.missing, ", "), "warn" })
  end
  for _, l in ipairs(ev.lines) do
    local age = l.day and (today - l.day) or nil
    local src = (l.source and CraftUI.SOURCE[l.source]) or "no price"
    if l.limited then src = src .. ", limited stock" end
    local unit = l.unit and (U.money(l.unit, true) .. " each") or "-"
    local text = l.need .. " x " .. l.name .. "   have " .. l.have .. "   " .. unit .. "   " .. src
    if age then text = text .. "   " .. U.daysAgo(age) end
    table.insert(out, { text, (age and age > staleDays) and "dim" or "text" })
  end
  return out
end

function CraftUI.Detail(p)
  local d = CreateFrame("Frame", nil, p)
  d:SetHeight(CraftUI.DETAIL_H)
  d:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  d:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  local bg = Th.Solid(d, "BACKGROUND", "panel3")
  bg:SetAllPoints(d)
  d.lines = {}
  for i = 1, CraftUI.DETAIL_LINES do
    local fs = Th.Text(d, "body", 11, "text")
    fs:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -6 - (i - 1) * 14)
    fs:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.lines[i] = fs
  end
  return d
end

function CraftUI.ShowDetail(p, row)
  local lines = CraftUI.DetailLines(row, U.day(time()), DB.S().craft.staleDays)
  for i, fs in ipairs(p.detail.lines) do
    local l = lines[i]
    if l then
      fs:SetText(l[1])
      Th.Color(fs, l[2])
    else
      fs:SetText("")
    end
  end
end

function CraftUI.SetChar(p, name)
  p.char, p.prof = name, false
  CraftUI.Paint(p)
end

function CraftUI.SetProf(p, name)
  p.prof = name
  CraftUI.Paint(p)
end

-- One builder for both places the page appears: the Crafting window and the AH tab.
function CraftUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.char, p.prof = false, false
  p.charDD = W.Dropdown(p, 150, {}, function() return p.char end, function(v) CraftUI.SetChar(p, v) end)
  p.charDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.profDD = W.Dropdown(p, 150, {}, function() return p.prof end, function(v) CraftUI.SetProf(p, v) end)
  p.profDD:SetPoint("LEFT", p.charDD, "RIGHT", 6, 0)
  p.list = L.New(p, CraftUI.COLUMNS, 18, function(item) CraftUI.ShowDetail(p, item) end)
  p.list:SetPoint("TOPLEFT", p.charDD, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, CraftUI.DETAIL_H + 6)
  p.list.sortCol, p.list.sortDesc = CraftUI.COLUMNS[4], true     -- Profit, highest first
  p.detail = CraftUI.Detail(p)
  p.empty = Th.Text(p, "body", 13, "dim")
  p.empty:SetPoint("CENTER", p, "CENTER", 0, 0)
  p.empty:SetText(CraftUI.EMPTY)
  p.empty:Hide()
  p.Refresh = function(self) CraftUI.Paint(self) end
  p.Layout = function(self) self.list:Paint() end
  table.insert(CraftUI.pages, p)
  return p
end

-- Starts on this character when it has recipes, else the first that does.
function CraftUI.Paint(p)
  local realm = DB.Realm()
  local names = CraftUI.Characters(realm)
  if not p.char or not contains(names, p.char) then
    if contains(names, DB.charName) then p.char = DB.charName else p.char = names[1] or false end
  end
  p.charDD:SetOptions(options(names))
  local c = p.char and realm.chars[p.char]
  local profs = CraftUI.Professions(c)
  if not p.prof or not contains(profs, p.prof) then p.prof = profs[1] or false end
  p.profDD:SetOptions(options(profs))
  local prof = p.prof and c.professions[p.prof]
  if not prof then
    p.empty:Show()
    p.list:Hide()
    p.detail:Hide()
    return
  end
  p.empty:Hide()
  p.list:Show()
  p.detail:Show()
  local keep = p.list.selected and p.list.selected.name
  p.list:SetData(CraftUI.Rows(prof, TS.Context(), DB.S().craft.staleDays))
  for _, r in ipairs(p.list.data) do
    if r.name == keep then p.list.selected = r end
  end
  p.list:Paint()
  CraftUI.ShowDetail(p, p.list.selected or nil)
end

function CraftUI.RefreshAll()
  for _, p in ipairs(CraftUI.pages) do
    if p:IsVisible() then CraftUI.Paint(p) end
  end
end

function CraftUI.Window()
  if CraftUI.window then return CraftUI.window end
  local f = W.Window("TaxTheFoolsCraft", 720, 480, "Tax the Fools  -  Crafting",
    { resizable = true, minW = 700, minH = 360 })
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 10, -10)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f.page = CraftUI.Build(f.body)
  f.page:SetAllPoints(f.body)
  f:SetScript("OnShow", function() CraftUI.Paint(f.page) end)
  f.onResize = function() f.page:Layout() end
  CraftUI.window = f
  return f
end

function CraftUI.Toggle()
  local f = CraftUI.Window()
  if f:IsShown() then f:Hide() else f:Show() end
end

UI.builders.craft = CraftUI.Build
-- New market values change every profit on the page.
Scan.OnChange(function() CraftUI.RefreshAll() end)
