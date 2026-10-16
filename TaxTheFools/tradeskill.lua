TaxTheFools = TaxTheFools or {}
local U, DB, I, Th, Craft, Inv = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Theme,
  TaxTheFools.Craft, TaxTheFools.Inventory
local TS = { open = false, dirty = false, capturedAt = -1000, strip = nil }
TaxTheFools.TradeSkill = TS

TS.THROTTLE = 0.5    -- seconds between captures; TRADE_SKILL_UPDATE fires in bursts
-- TradeSkillFrame is 384x512 but its art leaves the bottom 75px and right 34px
-- transparent (its HitRectInsets): the strip sits just under the visible panel.
TS.STRIP_X, TS.STRIP_Y, TS.STRIP_W = 14, 73, 330

function TS.ResetState() TS.open, TS.dirty, TS.capturedAt = false, false, -1000 end

-- Every item seen in the window is remembered account-wide, so its name is
-- known to the watchlist scan and the Crafting page on every character.
local function remember(link, name, texture)
  local key, id = U.keyFromLink(link)
  if not key then return nil end
  I.Remember(id, name, nil, nil, texture)
  return key, id
end

-- One recipe row. A reagent whose link is not cached yet is kept by name
-- with no item key; the next capture fills it in.
function TS.ReadRecipe(i)
  local link = GetTradeSkillItemLink(i)
  local key, id = remember(link, U.linkName(link))
  if id then
    I.Resolve(id)                      -- max stack size, for the deposit
    I.Vendor(id)
  end          -- ClassicAPI supplies the sell price the deposit needs
  local lo, hi = GetTradeSkillNumMade(i)
  if not lo or lo < 1 then lo = 1 end
  if not hi or hi < lo then hi = lo end
  local r = { item = key, yieldMin = lo, yieldMax = hi, reagents = {} }
  for n = 1, GetTradeSkillNumReagents(i) do
    local name, texture, count = GetTradeSkillReagentInfo(i, n)
    local rkey = remember(GetTradeSkillReagentItemLink(i, n), name, texture)
    table.insert(r.reagents, { item = rkey, name = name, count = count or 1 })
  end
  return r
end

-- A product or reagent whose link is not cached this time keeps the item key
-- it had (same name, same position) rather than losing it.
function TS.KeepKeys(r, old)
  if not old then return end
  if not r.item then r.item = old.item end
  if not old.reagents then return end
  for n, g in ipairs(r.reagents) do
    local o = old.reagents[n]
    if not g.item and o and o.name == g.name then g.item = o.item end
  end
end

-- Reads the open window into this character's professions. Capture only
-- merges: the window's filters ("have materials", slot filters) hide learned
-- recipes, so a recipe is never removed. A recipe the window lists is updated
-- in place. A list that reads empty (the client has not sent it yet) changes
-- nothing.
function TS.Capture()
  local line, rank, maxRank = GetTradeSkillLine()
  if not line or line == "UNKNOWN" then return nil end
  local recipes, found = {}, 0
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if kind ~= "header" and name then
      local r = TS.ReadRecipe(i)
      r.color = kind
      recipes[name] = r
      found = found + 1
    end
  end
  if found == 0 then return nil end
  local c = DB.Char()
  c.professions = c.professions or {}
  local prof = c.professions[line]
  if not prof then
    prof = {}
    c.professions[line] = prof
  end
  local stored = prof.recipes or {}
  for name, r in pairs(recipes) do
    TS.KeepKeys(r, stored[name])
    stored[name] = r
  end
  prof.rank, prof.maxRank, prof.at, prof.recipes = rank, maxRank, time(), stored
  if DB.S().craft.autoWatch then TS.Watch(recipes) end
  TS.RefreshStrip(true)
  -- ui_craft.lua loads after this file: look it up at call time.
  if TaxTheFools.CraftUI then TaxTheFools.CraftUI.RefreshAll() end
  return prof
end

function TS.Watch(recipes)
  local watch = DB.Realm().watch
  for _, r in pairs(recipes) do
    if r.item and not watch[r.item] then DB.WatchSet(r.item, true) end
    for _, g in ipairs(r.reagents) do
      if g.item and not watch[g.item] then DB.WatchSet(g.item, true) end
    end
  end
end

function TS.OnEvent(e, now)
  if e == "TRADE_SKILL_SHOW" then
    TS.open, TS.dirty = true, true
    TS.CreateStrip()
    if TS.strip then TS.strip.sel = false end
    TS.Tick(now)
    TS.RefreshStrip(true)
  elseif e == "TRADE_SKILL_UPDATE" then
    TS.dirty = true
  elseif e == "TRADE_SKILL_CLOSE" then
    TS.open, TS.dirty = false, false
    if TS.strip then TS.strip.sel = false end
  end
end

function TS.Tick(now)
  if not TS.open or not TS.dirty then return end
  if now - TS.capturedAt < TS.THROTTLE then return end
  TS.dirty, TS.capturedAt = false, now
  TS.Capture()
end

-- ---------- the profit strip under the tradeskill window ----------

-- Prices, every character's recipes and everything held, as of now.
function TS.Context()
  local realm = DB.Realm()
  return Craft.Context(realm, TaxTheFoolsDB.items, Inv.Held(realm), U.day(time()))
end

-- Wide enough for its line (8 px padding each side), never narrower than
-- STRIP_W nor wider than STRIP_MAX.
TS.STRIP_MAX = 600
function TS.StripWidth(textWidth)
  local w = textWidth + 16
  if w < TS.STRIP_W then w = TS.STRIP_W end
  if w > TS.STRIP_MAX then w = TS.STRIP_MAX end
  return w
end

-- Sets the line and resizes the strip to fit it.
function TS.SetStripText(text, token)
  local s = TS.strip
  s.text:SetText(text)
  Th.Color(s.text, token or "text")
  s:SetWidth(TS.StripWidth(s.text:GetStringWidth()))
end

-- Made the first time a tradeskill window opens: TradeSkillFrame is
-- load-on-demand and does not exist before that.
function TS.CreateStrip()
  if TS.strip then return TS.strip end
  if not TradeSkillFrame then return nil end
  local s = CreateFrame("Frame", "TaxTheFoolsStrip", TradeSkillFrame)
  s:SetWidth(TS.StripWidth(0))
  s:SetHeight(22)
  s:SetPoint("TOPLEFT", TradeSkillFrame, "BOTTOMLEFT", TS.STRIP_X, TS.STRIP_Y)
  Th.Panel(s, "header")
  s.text = Th.Text(s, "body", 11, "text")
  s.text:SetPoint("LEFT", s, "LEFT", 8, 0)
  s.text:SetPoint("RIGHT", s, "RIGHT", -8, 0)
  s.sel = false
  TS.strip = s
  return s
end

-- Text and colour token for one evaluation (nil: nothing selected).
-- Plain money, so the whole line takes the good or bad colour.
function TS.StripText(ev)
  if not ev then return "Select a recipe to see its profit.", "dim" end
  if not ev.profit then return "incomplete: " .. table.concat(ev.missing, ", "), "warn" end
  local value = U.money(ev.value, true)
  if ev.valueSource == "vendor" then value = value .. " (vendor)" end
  local text = "Cost " .. U.money(ev.cost, true) .. "   Value " .. value .. "   Profit " .. U.money(ev.profit, true)
  if ev.profit >= 0 then return text, "good" end
  return text, "bad"
end

-- The recipe the window has selected, from this character's captured list.
function TS.Selected()
  local i = GetTradeSkillSelectionIndex()
  if not i or i < 1 then return nil end
  local name, kind = GetTradeSkillInfo(i)
  if not name or kind == "header" then return nil end
  local profs = DB.Char().professions
  local prof = profs and profs[GetTradeSkillLine()]
  return prof and prof.recipes[name]
end

-- Selecting a recipe fires no event, so this runs on a poll as well; it only
-- repaints when the selection moved, unless forced (after a capture).
function TS.RefreshStrip(force)
  local s = TS.strip
  if not s or not s:IsVisible() then return end
  local i = GetTradeSkillSelectionIndex()
  if not force and i == s.sel then return end
  s.sel = i
  local recipe = TS.Selected()
  local ev = recipe and Craft.Evaluate(recipe, TS.Context())
  local text, token = TS.StripText(ev)
  TS.SetStripText(text, token)
end

function TS.Poll(now)
  -- TradeSkillFrame may have loaded after the show event that found it absent.
  if TS.open and not TS.strip and TradeSkillFrame then TS.CreateStrip() end
  TS.RefreshStrip(false)
end
