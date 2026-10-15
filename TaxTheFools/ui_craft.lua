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
CraftUI.EMPTY_UNLEARNED = "No recipe list for %s yet."
CraftUI.GET_SOURCE = { ah = "AH", vendor = "vendor", trainer = "trainer" }

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

-- ---------- the "Not learned" view ----------

local function sortedKeys(t)
  local names = {}
  for k in pairs(t or {}) do table.insert(names, k) end
  table.sort(names)
  return names
end

-- A cheap stamp of everything the catalogue is built from that changes without the tables being
-- replaced: a capture sets prof.at, the trainer and pattern learning set an `at` per entry.
local function stamp(realm)
  local n = 0
  for _, c in pairs(realm.chars or {}) do
    for _, p in pairs(c.professions or {}) do n = n + 1 + (p.at or 0) end
  end
  for _, b in pairs((TaxTheFoolsDB and TaxTheFoolsDB.recipes) or {}) do
    for _, t in pairs(b.trainer or {}) do n = n + 1 + (t.c or 0) + (t.at or 0) end
    for _, t in pairs(b.seen or {}) do n = n + 1 + (t.at or 0) end
  end
  return n
end

CraftUI.cache = false

-- Every profession's catalogue and the pattern index, built once and rebuilt only when the saved
-- recipes change. Entries carry .prof.
function CraftUI.Realm()
  local realm = DB.Realm()
  local db = TaxTheFoolsDB and TaxTheFoolsDB.recipes
  local st = stamp(realm)
  local c = CraftUI.cache
  if c and c.chars == realm.chars and c.db == db and c.items == TaxTheFoolsDB.items and c.stamp == st then return c end
  local profs = {}
  for k in pairs(TaxTheFools.RecipeData or {}) do profs[k] = true end
  for k in pairs(db or {}) do profs[k] = true end
  for _, ch in pairs(realm.chars or {}) do
    for k in pairs(ch.professions or {}) do profs[k] = true end
  end
  c = { chars = realm.chars, db = db, items = TaxTheFoolsDB.items, stamp = st, cat = {}, index = {} }
  for _, prof in ipairs(sortedKeys(profs)) do
    local cat = TaxTheFools.Recipes.Catalogue(prof, TaxTheFools.RecipeData, db, realm.chars, TaxTheFoolsDB.items)
    for _, e in ipairs(cat) do e.prof = prof end
    c.cat[prof] = cat
    for key, e in pairs(TaxTheFools.Recipes.PatternIndex(cat)) do c.index[key] = e end
  end
  CraftUI.cache = c
  return c
end

function CraftUI.Catalogue(prof) return CraftUI.Realm().cat[prof] or {} end

-- The catalogue entry a pattern item teaches, or nil.
function CraftUI.PatternEntry(key) return CraftUI.Realm().index[key] end

local function has(list, v)
  for _, x in ipairs(list or {}) do
    if x == v then return true end
  end
  return false
end

-- "Get" text and its token. A cost shows with where it comes from; an unknown one says what is known.
function CraftUI.GetText(r)
  if r.cost then
    local label = CraftUI.GET_SOURCE[r.source] or ""
    if r.source == "vendor" and r.limited then label = "vendor (limited)" end
    if r.cost == 0 then return "free " .. label end
    return U.money(r.cost) .. " " .. label
  end
  local src = r.entry.src
  if has(src, "trainer") then return "trainer ?", "dim" end
  if has(src, "drop") then return "drop", "dim" end
  if has(src, "quest") then return "quest", "dim" end
  return "-", "dim"
end

function CraftUI.PaybackText(pb)
  if pb == nil then return "-", "dim" end
  if pb == "never" then return "never", "bad" end
  if pb == 0 then return "free", "good" end
  if pb == 1 then return "1 craft" end
  return pb .. " crafts"
end

CraftUI.UNLEARNED_COLUMNS = {
  { label = "Recipe", width = 200, sort = "name", fmt = function(r)
    local code = r.ready and "|cffffffff" or Th.Code("warn")
    return code .. r.name .. "|r" .. (r.turtle and (" " .. Th.Code("dim") .. "T|r") or "")
  end },
  { label = "Skill", width = 50, align = "RIGHT", sort = "skill", fmt = function(r) return tostring(r.skill or "-") end },
  { label = "Get", width = 130, align = "RIGHT", sort = "cost", fmt = function(r) return CraftUI.GetText(r) end },
  { label = "Profit", width = 90, align = "RIGHT", sort = "profit", desc = true, fmt = function(r) return signed(r.profit) end },
  { label = "Payback", width = 80, align = "RIGHT", sort = "pbSort", fmt = function(r) return CraftUI.PaybackText(r.payback) end },
  { label = "Sells", width = 60, align = "RIGHT", sort = "rate", desc = true, fmt = function(r)
    if not r.rate then return "-", "dim" end
    return math.floor(r.rate * 100 + 0.5) .. "%"
  end },
}

-- One row per unlearned recipe. Costs are floored (an AH figure can be fractional copper). With
-- `soon`, only recipes up to `ahead` skill points past `rank` are kept.
function CraftUI.UnlearnedRows(entries, rank, ahead, soon, ctx, snapshot, stats)
  local rows = {}
  for _, e in ipairs(entries) do
    if not soon or (e.skill or 0) <= rank + ahead then
      local ev = TaxTheFools.Craft.Evaluate(e, ctx)
      local cost, source, limited = TaxTheFools.Recipes.Cost(e, ctx, snapshot)
      if cost then cost = math.floor(cost) end
      local pb = TaxTheFools.Recipes.Payback(cost, ev.profit)
      local st = e.item and stats[e.item]
      table.insert(rows, { name = e.name, skill = e.skill, entry = e, ev = ev, cost = cost, source = source,
        limited = limited, profit = ev.profit, payback = pb, pbSort = (type(pb) == "number") and pb or nil,
        ready = (e.skill or 0) <= rank, turtle = e.turtle, rate = st and st.rate or nil })
    end
  end
  return rows
end

-- The detail pane for one Not learned row: how it pays back, where to get it, then the materials.
function CraftUI.UnlearnedDetail(row, today, staleDays)
  if not row then return { { "Select a recipe to see how it pays back.", "dim" } } end
  local pb = row.payback
  local head
  local token = "text"
  if type(pb) == "number" and pb > 0 then
    head = "Pays back after " .. pb .. (pb == 1 and " craft" or " crafts") .. " at +" .. U.money(row.profit, true) .. " each"
    token = "good"
  elseif pb == 0 then
    head = "Free to learn" .. (row.profit and (", " .. U.money(row.profit, true) .. " each craft") or "")
    token = "good"
  elseif pb == "never" then
    head, token = "No profit per craft: never pays back", "bad"
  elseif row.cost then
    head, token = "Profit unknown: a price is missing", "dim"
  else
    head, token = "No cost known for this recipe", "dim"
  end
  local out = { { row.name .. ": " .. head, token } }
  local mats = CraftUI.DetailLines(row, today, staleDays)
  table.remove(mats, 1)
  if table.getn(mats) <= CraftUI.DETAIL_LINES - 2 then
    local e = row.entry
    local text = "Source: " .. ((e.src and table.getn(e.src) > 0) and table.concat(e.src, ", ") or "unknown")
    if e.pats and table.getn(e.pats) > 0 then
      local names = {}
      for _, id in ipairs(e.pats) do
        local rec = TaxTheFoolsDB.items[id]
        table.insert(names, rec and rec.n or ("item " .. id))
      end
      text = text .. "   Pattern: " .. table.concat(names, ", ")
    end
    table.insert(out, { text, "dim" })
  end
  for _, l in ipairs(mats) do
    if table.getn(out) < CraftUI.DETAIL_LINES then table.insert(out, l) end
  end
  return out
end

function CraftUI.ShowUnlearnedDetail(p, row)
  local lines = CraftUI.UnlearnedDetail(row, U.day(time()), DB.S().craft.staleDays)
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

function CraftUI.SetView(p, view)
  p.view = view
  CraftUI.Paint(p)
end

function CraftUI.SetSoon(p, on)
  p.soon = on and true or false
  CraftUI.Paint(p)
end

local function paintViewButtons(p)
  Th.Color(p.learnedBtn.label, p.view == "learned" and "gold" or "white")
  Th.Color(p.unlearnedBtn.label, p.view == "unlearned" and "gold" or "white")
  if p.view == "unlearned" then p.soonSw:Show() else p.soonSw:Hide() end
end

function CraftUI.PaintUnlearned(p, c)
  p.list:Hide()
  local cat = CraftUI.Catalogue(p.prof)
  if table.getn(cat) == 0 then
    p.empty:SetText(string.format(CraftUI.EMPTY_UNLEARNED, p.prof))
    p.empty:Show()
    p.ulist:Hide()
    p.detail:Hide()
    return
  end
  p.empty:Hide()
  p.ulist:Show()
  p.detail:Show()
  local R = TaxTheFools.Recipes
  local rs = DB.S().recipes
  local now = time()
  local realm = DB.Realm()
  local stats = TaxTheFools.Sales.StatsAll(realm.chars, DB.S().sales.days or 30, now)
  local rank = c.professions[p.prof].rank or 0
  local keep = p.ulist.selected and p.ulist.selected.name
  p.ulist:SetData(CraftUI.UnlearnedRows(R.Unlearned(cat, c, p.prof), rank, rs.skillAhead or 0, p.soon,
    TS.Context(), realm.snapshot, stats))
  for _, r in ipairs(p.ulist.data) do
    if r.name == keep then p.ulist.selected = r end
  end
  p.ulist:Paint()
  CraftUI.ShowUnlearnedDetail(p, p.ulist.selected or nil)
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
  p.view, p.soon = "learned", true
  p.charDD = W.Dropdown(p, 150, {}, function() return p.char end, function(v) CraftUI.SetChar(p, v) end)
  p.charDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.profDD = W.Dropdown(p, 150, {}, function() return p.prof end, function(v) CraftUI.SetProf(p, v) end)
  p.profDD:SetPoint("LEFT", p.charDD, "RIGHT", 6, 0)
  p.learnedBtn = W.Button(p, "Learned", 70, 22, function() CraftUI.SetView(p, "learned") end)
  p.learnedBtn:SetPoint("LEFT", p.profDD, "RIGHT", 10, 0)
  p.unlearnedBtn = W.Button(p, "Not learned", 90, 22, function() CraftUI.SetView(p, "unlearned") end)
  p.unlearnedBtn:SetPoint("LEFT", p.learnedBtn, "RIGHT", 2, 0)
  p.soonSw = W.Switch(p, "Learnable soon", function() return p.soon end, function(v) CraftUI.SetSoon(p, v) end,
    "Only recipes up to the skill-ahead setting past this character's rank.")
  p.soonSw:SetWidth(150)
  p.soonSw:SetPoint("LEFT", p.unlearnedBtn, "RIGHT", 10, 0)
  p.soonSw:Hide()
  p.list = L.New(p, CraftUI.COLUMNS, 18, function(item) CraftUI.ShowDetail(p, item) end)
  p.list:SetPoint("TOPLEFT", p.charDD, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, CraftUI.DETAIL_H + 6)
  p.list.sortCol, p.list.sortDesc = CraftUI.COLUMNS[4], true     -- Profit, highest first
  p.ulist = L.New(p, CraftUI.UNLEARNED_COLUMNS, 18, function(item) CraftUI.ShowUnlearnedDetail(p, item) end)
  p.ulist:SetPoint("TOPLEFT", p.charDD, "BOTTOMLEFT", 0, -8)
  p.ulist:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, CraftUI.DETAIL_H + 6)
  p.ulist.sortCol, p.ulist.sortDesc = CraftUI.UNLEARNED_COLUMNS[5], false     -- Payback, quickest first
  p.ulist:Hide()
  p.detail = CraftUI.Detail(p)
  p.empty = Th.Text(p, "body", 13, "dim")
  p.empty:SetPoint("CENTER", p, "CENTER", 0, 0)
  p.empty:SetText(CraftUI.EMPTY)
  p.empty:Hide()
  p.Refresh = function(self) CraftUI.Paint(self) end
  p.Layout = function(self) self.list:Paint() self.ulist:Paint() end
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
  paintViewButtons(p)
  if not prof then
    p.empty:SetText(CraftUI.EMPTY)
    p.empty:Show()
    p.list:Hide()
    p.ulist:Hide()
    p.detail:Hide()
    return
  end
  if p.view == "unlearned" then return CraftUI.PaintUnlearned(p, c) end
  p.empty:SetText(CraftUI.EMPTY)
  p.empty:Hide()
  p.ulist:Hide()
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
    { resizable = true, minW = 700, minH = 360, logo = true })
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
