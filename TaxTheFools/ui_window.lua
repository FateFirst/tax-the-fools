TaxTheFools = TaxTheFools or {}
local U, Th, W, DB, Scan, AH = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB,
  TaxTheFools.Scan, TaxTheFools.AH
local UI = { pages = {}, builders = {}, ah = nil }
TaxTheFools.UI = UI

-- Later phases add Deals, Sell, Auctions and History here.
UI.TABS = { { key = "browse", label = "Browse" }, { key = "craft", label = "Crafting" } }

local SEP = "  -  "

function UI.Duration(s)
  s = math.floor((s or 0) + 0.5)
  if s < 60 then return s .. "s" end
  local m = math.floor(s / 60)
  if m < 60 then return m .. "m" end
  local h = math.floor(m / 60)
  if h < 24 then return h .. "h " .. math.mod(m, 60) .. "m" end
  return math.floor(h / 24) .. "d " .. math.mod(h, 24) .. "h"
end

-- What the status strip says and offers, from the scan's state alone.
function UI.Describe(p, resume, lastFull, now)
  local d = { text = "", fraction = 0, pause = false, discard = false, canStart = true }
  if p then
    d.canStart = false
    if p.kind == "browse" then
      d.text = "Searching..."
      return d
    end
    local label = (p.kind == "full") and "Full scan" or "Watchlist"
    if p.state == "stalled" then
      d.text = label .. " stopped: server not responding. Press Resume to try again."
      d.pause = "Resume"
      return d
    end
    local parts = { label }
    if p.kind == "full" then
      if p.totalPages and p.totalPages > 0 then
        table.insert(parts, "page " .. (p.page + 1) .. "/" .. p.totalPages)
        d.fraction = p.page / p.totalPages
      else
        table.insert(parts, "starting")
      end
    else
      table.insert(parts, "item " .. p.qi .. "/" .. p.nq)
      d.fraction = (p.qi - 1) / p.nq
    end
    if p.secsPerPage then table.insert(parts, string.format("%.1fs/page", p.secsPerPage)) end
    if p.eta then table.insert(parts, "~" .. UI.Duration(p.eta) .. " left") end
    if p.safe then table.insert(parts, "safe pace") end
    d.text = table.concat(parts, SEP)
    d.pause = "Pause"
    return d
  end
  if resume then
    d.text = "Paused " .. ((resume.kind == "full") and "full scan" or "watchlist scan") .. " at page " .. (resume.page + 1)
      .. " with " .. table.getn(resume.rows) .. " listings. Resume or discard it."
    d.pause, d.discard, d.canStart = "Resume", true, false
    return d
  end
  if lastFull then
    d.text = "Last full scan " .. UI.Duration(now - lastFull) .. " ago"
    d.fraction = 1
  else
    d.text = "No full scan yet. It takes a while; you can close the AH and resume later today."
  end
  return d
end

function UI.CreateStatusStrip(f)
  local s = CreateFrame("Frame", nil, f)
  s:SetHeight(38)
  local bg = Th.Solid(s, "BACKGROUND", "header")
  bg:SetAllPoints(s)
  s.full = W.Button(s, "Full scan", 92, 22, function() UI.StartScan("full") end, "accent")
  s.full:SetPoint("LEFT", s, "LEFT", 10, 0)
  W.Tip(s.full, "Full scan", "Pages through the whole auction house. Expect many minutes; it pauses if you leave and resumes later the same day.")
  s.watch = W.Button(s, "Watchlist", 92, 22, function() UI.StartScan("watch") end)
  s.watch:SetPoint("LEFT", s.full, "RIGHT", 6, 0)
  W.Tip(s.watch, "Watchlist scan", "Looks up only the items you watch. Quick.")
  s.pause = W.Button(s, "Pause", 76, 22, function() UI.PauseOrResume() end)
  s.pause:SetPoint("LEFT", s.watch, "RIGHT", 6, 0)
  s.discard = W.Button(s, "Discard", 76, 22, function() Scan.Discard() end)
  s.discard:SetPoint("LEFT", s.pause, "RIGHT", 6, 0)
  s.bar = W.Progress(s, 8)
  s.bar:SetPoint("TOPLEFT", s.discard, "TOPRIGHT", 12, -2)
  s.bar:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  s.text = Th.Text(s, "body", 11, "dim")
  s.text:SetPoint("TOPLEFT", s.bar, "BOTTOMLEFT", 0, -4)
  s.text:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  return s
end

function UI.CreateAH()
  if UI.ah then return UI.ah end
  local f = W.Window("TaxTheFoolsAH", 780, 500, "Tax the Fools", { resizable = true, minW = 660, minH = 380 })
  f.gold = Th.Text(f.header, "body2", 12, "gold")
  f.gold:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
  f.gold:SetJustifyH("RIGHT")
  f.blizzard = W.Button(f.header, "Blizzard UI", 96, 20, function() AH.ShowBlizzard() end)
  f.blizzard:SetPoint("RIGHT", f.gold, "LEFT", -12, 0)
  W.Tip(f.blizzard, "Blizzard UI", "Switch to the standard auction window. Its Tax the Fools button brings you back.")
  f.tabs = W.TabStrip(f, UI.TABS, function(key) UI.ShowPage(key) end)
  f.tabs:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -1)
  f.tabs:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -1)
  f.status = UI.CreateStatusStrip(f)
  f.status:SetPoint("TOPLEFT", f.tabs, "BOTTOMLEFT", 0, 0)
  f.status:SetPoint("TOPRIGHT", f.tabs, "BOTTOMRIGHT", 0, 0)
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 10, -8)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f:SetScript("OnShow", function()
    UI.RefreshGold()
    UI.RefreshStatus()
    if not f.tabs.selected then f.tabs:Select("browse") end
  end)
  f:SetScript("OnHide", function() AH.OnWindowHidden() end)
  f.onResize = function()
    for _, page in pairs(UI.pages) do
      if type(page.Layout) == "function" then page:Layout() end
    end
  end
  UI.ah = f
  AH.window = f
  Scan.OnChange(function() UI.RefreshStatus() end)
  return f
end

function UI.ShowPage(key)
  local f = UI.ah
  for _, page in pairs(UI.pages) do page:Hide() end
  local page = UI.pages[key]
  if not page then
    page = UI.builders[key](f.body)
    page:SetAllPoints(f.body)
    UI.pages[key] = page
  end
  page:Show()
  if type(page.Refresh) == "function" then page:Refresh() end
end

function UI.RefreshGold()
  if UI.ah then UI.ah.gold:SetText(U.money(GetMoney())) end
end

function UI.RefreshStatus()
  local f = UI.ah
  if not f or not f:IsShown() then return end
  local s = f.status
  local d = UI.Describe(Scan.Progress(GetTime()), Scan.Resumable(), DB.Realm().scan.lastFull, time())
  s.text:SetText(d.text)
  s.bar:SetFraction(d.fraction)
  if d.pause then
    s.pause:SetLabel(d.pause)
    s.pause:Show()
  else
    s.pause:Hide()
  end
  if d.discard then s.discard:Show() else s.discard:Hide() end
  s.full:SetEnabled(d.canStart)
  s.watch:SetEnabled(d.canStart)
end

function UI.StartScan(kind)
  local ok, why
  if kind == "full" then ok, why = Scan.StartFull(GetTime()) else ok, why = Scan.StartWatch(GetTime()) end
  if not ok and why == "empty" then
    U.msg("Your watchlist is empty. Select an item in Browse and press Watch, or type /ttf watch <item name>.")
  elseif not ok and why == "busy" then
    U.msg("A scan is already running.")
  end
  UI.RefreshStatus()
end

function UI.PauseOrResume()
  local p = Scan.Progress(GetTime())
  if p and p.state == "stalled" then Scan.Continue()
  elseif p then Scan.Pause("user")
  else Scan.Resume(GetTime()) end
  UI.RefreshStatus()
end

function UI.Tick(now)
  if UI.ah and UI.ah:IsShown() then UI.RefreshStatus() end
end
