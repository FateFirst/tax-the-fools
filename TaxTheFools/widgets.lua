TaxTheFools = TaxTheFools or {}
local Th, DB, U = TaxTheFools.Theme, TaxTheFools.DB, TaxTheFools.Util
local W = { windows = {} }
TaxTheFools.Widgets = W

function W.Tip(f, title, body)
  f.tip = { title = title, body = body }
  return f
end

function W.ShowTip(f)
  if type(f.tip) ~= "table" then return end
  GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
  GameTooltip:SetText(f.tip.title, 1, 1, 1)
  if f.tip.body then GameTooltip:AddLine(f.tip.body, 0.78, 0.78, 0.74, 1) end
  GameTooltip:Show()
end

function W.HideTip() GameTooltip:Hide() end

function W.Button(parent, label, width, height, onClick, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width)
  b:SetHeight(height or 22)
  local base = (style == "accent") and "accentDeep" or "strip"
  local over = (style == "accent") and "accent" or "subtle"
  b.fill = Th.NineSlice(b, "tab-fill", "BACKGROUND", base, 1, 6)
  b.edge = Th.NineSlice(b, "tab-border", "BORDER", "border", 1, 6)
  b.label = Th.Text(b, "display", 11, "white")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetJustifyH("CENTER")
  b.enabled = true
  b.SetLabel = function(self, t) self.label:SetText(string.upper(t or "")) end
  b.SetEnabled = function(self, on)
    self.enabled = on and true or false
    self:SetAlpha(on and 1 or 0.45)
  end
  b:SetLabel(label)
  b:SetScript("OnEnter", function()
    if this.enabled then Th.TintSlice(this.fill, over, 1) end
    W.ShowTip(this)
  end)
  b:SetScript("OnLeave", function()
    Th.TintSlice(this.fill, base, 1)
    W.HideTip()
  end)
  b:SetScript("OnClick", function()
    if this.enabled and onClick then onClick(this) end
  end)
  return b
end

function W.IconButton(parent, icon, size, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size)
  b:SetHeight(size)
  b.fill = Th.NineSlice(b, "tab-fill", "BACKGROUND", "white", 0.04, 6)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(Th.MEDIA .. icon)
  b.icon:SetWidth(size * 0.6)
  b.icon:SetHeight(size * 0.6)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  Th.Tint(b.icon, "dim")
  b:SetScript("OnEnter", function()
    Th.TintSlice(this.fill, "white", 0.1)
    Th.Tint(this.icon, "white")
    W.ShowTip(this)
  end)
  b:SetScript("OnLeave", function()
    Th.TintSlice(this.fill, "white", 0.04)
    Th.Tint(this.icon, "dim")
    W.HideTip()
  end)
  b:SetScript("OnClick", function() onClick(this) end)
  return b
end

function W.Switch(parent, label, get, set, hint)
  local f = CreateFrame("Button", nil, parent)
  f:SetWidth(320)
  f:SetHeight(24)
  f.locked, f.on = false, false
  f.track = CreateFrame("Frame", nil, f)
  f.track:SetWidth(30)
  f.track:SetHeight(16)
  f.track:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.trackFill = Th.NineSlice(f.track, "tab-fill", "BACKGROUND", "strip", 1, 6)
  f.knob = f.track:CreateTexture(nil, "ARTWORK")
  f.knob:SetTexture(Th.MEDIA .. "circle")
  f.knob:SetWidth(12)
  f.knob:SetHeight(12)
  Th.Tint(f.knob, "white")
  f.text = Th.Text(f, "body", 13, "text")
  f.text:SetPoint("LEFT", f.track, "RIGHT", 8, 0)
  f.text:SetText(label)
  f.Refresh = function(self)
    self.on = get() and true or false
    Th.TintSlice(self.trackFill, self.on and "accentDeep" or "strip", 1)
    self.knob:ClearAllPoints()
    if self.on then self.knob:SetPoint("RIGHT", self.track, "RIGHT", -2, 0)
    else self.knob:SetPoint("LEFT", self.track, "LEFT", 2, 0) end
  end
  f:SetScript("OnClick", function()
    if this.locked then return end
    set(not this.on)
    this:Refresh()
  end)
  if hint then
    W.Tip(f, label, hint)
    f:SetScript("OnEnter", function() W.ShowTip(this) end)
    f:SetScript("OnLeave", function() W.HideTip() end)
  end
  f:Refresh()
  return f
end

function W.Slider(parent, label, min, max, step, get, set, fmt)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(320)
  f:SetHeight(38)
  f.text = Th.Text(f, "body", 13, "text")
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.text:SetText(label)
  f.value = Th.Text(f, "body2", 12, "gold")
  f.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.value:SetJustifyH("RIGHT")
  local s = CreateFrame("Slider", nil, f)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(12)
  s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
  s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
  s.track = Th.NineSlice(s, "tab-fill", "BACKGROUND", "strip", 1, 6)
  s:SetThumbTexture(Th.MEDIA .. "circle")
  local thumb = s:GetThumbTexture()
  thumb:SetWidth(14)
  thumb:SetHeight(14)
  Th.Tint(thumb, "accent")
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  local function snap(v) return math.floor(v / step + 0.5) * step end
  local function show(v) f.value:SetText(fmt and fmt(snap(v)) or tostring(snap(v))) end
  s:SetScript("OnValueChanged", function() show(this:GetValue()) end)
  -- Saving on release, not on every step of a drag, keeps the scan and the
  -- windows from reacting to values the player is only passing through.
  s:SetScript("OnMouseUp", function() set(snap(this:GetValue())) end)
  f.slider = s
  f.Refresh = function(self)
    local v = get()
    s:SetValue(v)
    show(v)
  end
  f:Refresh()
  return f
end

function W.Dropdown(parent, width, options, get, set)
  local menu
  local b = W.Button(parent, "", width, 22, function(self)
    if menu:IsShown() then menu:Hide() return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end)
  Th.SetFont(b.label, "body", 12)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.label:SetJustifyH("LEFT")
  b.SetLabel = function(self, t) self.label:SetText(t or "") end
  b.caret = b:CreateTexture(nil, "OVERLAY")
  b.caret:SetTexture(Th.MEDIA .. "icon-caret-down")
  b.caret:SetWidth(12)
  b.caret:SetHeight(12)
  b.caret:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  Th.Tint(b.caret, "dim")
  -- The list sits on the top layer of UIParent so no scroll frame can clip it.
  menu = CreateFrame("Frame", nil, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetWidth(width)
  Th.Panel(menu, "header")
  menu.items = {}
  menu:Hide()
  b.menu = menu
  local function choose(value)
    set(value)
    menu:Hide()
    b:Refresh()
  end
  b:SetScript("OnHide", function() menu:Hide() end)
  -- Replaces the choices; menu items are reused, spare ones hidden.
  b.SetOptions = function(self, opts)
    self.options = opts
    for i, o in ipairs(opts) do
      local item = menu.items[i]
      if item then
        item.text:SetText(o.label)
        item.value = o.value
      else
        item = W.MenuItem(menu, i, o, choose)
        menu.items[i] = item
      end
      item:Show()
    end
    for i = table.getn(opts) + 1, table.getn(menu.items) do menu.items[i]:Hide() end
    menu:SetHeight(8 + table.getn(opts) * 20)
    self:Refresh()
  end
  b.Refresh = function(self)
    local v = get()
    self:SetLabel("")
    for _, o in ipairs(self.options) do
      if o.value == v then self:SetLabel(o.label) end
    end
  end
  b:SetOptions(options)
  return b
end

function W.MenuItem(menu, i, option, choose)
  local item = CreateFrame("Button", nil, menu)
  item:SetHeight(20)
  item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
  item:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
  local hl = item:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(item)
  hl:SetVertexColor(1, 1, 1, 0.06)
  item.text = Th.Text(item, "body", 12, "text")
  item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
  item.text:SetText(option.label)
  item.value = option.value
  item:SetScript("OnClick", function() choose(this.value) end)
  return item
end

function W.EditBox(parent, width, onEnter)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetWidth(width)
  e:SetHeight(22)
  e:SetAutoFocus(false)
  e.fill = Th.NineSlice(e, "tab-fill", "BACKGROUND", "header", 1, 6)
  e.edge = Th.NineSlice(e, "tab-border", "BORDER", "subtle", 1, 6)
  Th.SetFont(e, "body", 12)
  Th.Color(e, "text")
  e:SetTextInsets(6, 6, 0, 0)
  e:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    if onEnter then onEnter(this:GetText()) end
  end)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  return e
end

-- Gold, silver and copper boxes standing for one copper amount. onChange(copper) runs on every
-- edit the user makes; SetValue (copper or nil to blank) never calls it. GetValue is nil when blank.
function W.MoneyInput(parent, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(22)
  f.updating = false
  local parts = { { "gold", 54, "g" }, { "silver", 34, "s" }, { "copper", 34, "c" } }
  local x = 0
  for _, d in ipairs(parts) do
    local e = W.EditBox(f, d[2], nil)
    e:SetNumeric(true)
    e:SetMaxLetters(d[1] == "gold" and 7 or 2)
    e:SetPoint("LEFT", f, "LEFT", x, 0)
    e:SetScript("OnTextChanged", function()
      if not f.updating and onChange then onChange(f:GetValue()) end
    end)
    f[d[1]] = e
    local t = Th.Text(f, "body", 11, "dim")
    t:SetPoint("LEFT", e, "RIGHT", 2, 0)
    t:SetText(d[3])
    x = x + d[2] + 14
  end
  f:SetWidth(x)
  f.GetValue = function(self)
    local g, s, c = self.gold:GetText(), self.silver:GetText(), self.copper:GetText()
    if g == "" and s == "" and c == "" then return nil end
    return (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
  end
  f.SetValue = function(self, v)
    self.updating = true
    if v == nil then
      self.gold:SetText("") self.silver:SetText("") self.copper:SetText("")
    else
      v = math.floor(v + 0.5)
      local g = math.floor(v / 10000)
      self.gold:SetText(g > 0 and tostring(g) or "")
      self.silver:SetText(tostring(math.floor(math.mod(v, 10000) / 100)))
      self.copper:SetText(tostring(math.mod(v, 100)))
    end
    self.updating = false
  end
  return f
end

-- A 30-day bar chart: one bar per day that has a price, today at the right, scaled from 0 to the
-- highest bar or marker. `marker` is drawn as a horizontal line (the market value).
W.CHART_DAYS = 30

function W.Chart(parent, w, h)
  local c = CreateFrame("Frame", nil, parent)
  c:SetWidth(w)
  c:SetHeight(h)
  c.bg = Th.Solid(c, "BACKGROUND", "panel3")
  c.bg:SetAllPoints(c)
  c.bars, c.hits, c.series, c.markerValue = {}, {}, false, false
  for i = 1, W.CHART_DAYS do
    c.bars[i] = Th.Solid(c, "ARTWORK", "accent")
    c.bars[i]:Hide()
    local b = CreateFrame("Button", nil, c)
    b.day, b.price = false, false
    b:Hide()
    b:SetScript("OnEnter", function()
      if not this.day then return end
      GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
      GameTooltip:SetText(date("%d %b", this.day * 86400), 1, 1, 1)
      GameTooltip:AddLine(U.money(this.price), 0.78, 0.78, 0.74)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.hits[i] = b
  end
  c.marker = Th.Solid(c, "OVERLAY", "gold")
  c.marker:Hide()
  c.empty = Th.Text(c, "body", 11, "dim")
  c.empty:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.empty:SetText("No price history yet")
  c.empty:Hide()
  c.SetSize = function(self, nw, nh)
    self:SetWidth(nw)
    self:SetHeight(nh)
    if self.series then self:SetSeries(self.series, self.markerValue) end
  end
  c.SetSeries = function(self, series, marker)
    self.series, self.markerValue = series, marker
    local cw, ch = self:GetWidth(), self:GetHeight()
    local slot = (cw - 2) / W.CHART_DAYS
    local today = U.day()
    local top = marker or 0
    local shown = 0
    for _, pt in ipairs(series or {}) do
      if pt.p25 > top then top = pt.p25 end
    end
    for i = 1, W.CHART_DAYS do
      self.bars[i]:Hide()
      self.hits[i].day = false
      self.hits[i]:Hide()
    end
    for _, pt in ipairs(series or {}) do
      local i = W.CHART_DAYS - (today - pt.day)
      if i >= 1 and i <= W.CHART_DAYS and top > 0 then
        local bh = math.max(1, (ch - 2) * pt.p25 / top)
        local x = 1 + (i - 1) * slot
        local bar = self.bars[i]
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 1)
        bar:SetWidth(math.max(1, slot - 1))
        bar:SetHeight(bh)
        bar:Show()
        local hit = self.hits[i]
        hit:ClearAllPoints()
        hit:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 1)
        hit:SetWidth(slot)
        hit:SetHeight(ch - 2)
        hit.day, hit.price = pt.day, pt.p25
        hit:Show()
        shown = shown + 1
      end
    end
    if shown == 0 then
      self.marker:Hide()
      self.empty:Show()
      return
    end
    self.empty:Hide()
    if marker and marker > 0 and top > 0 then
      self.marker:ClearAllPoints()
      self.marker:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 1, 1 + (ch - 2) * marker / top)
      self.marker:SetWidth(cw - 2)
      self.marker:SetHeight(1)
      self.marker:Show()
    else
      self.marker:Hide()
    end
  end
  return c
end

function W.Progress(parent, height)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(height or 8)
  f.track = Th.Solid(f, "BACKGROUND", "panel3")
  f.track:SetAllPoints(f)
  f.bar = Th.Solid(f, "ARTWORK", "accent")
  f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  f.fraction = 0
  f.SetFraction = function(self, x)
    x = math.max(0, math.min(1, x or 0))
    self.fraction = x
    local w = (self:GetWidth() - 2) * x
    if w < 1 then self.bar:Hide()
    else
      self.bar:Show()
      self.bar:SetWidth(w)
    end
  end
  f:SetFraction(0)
  return f
end

function W.TabStrip(parent, tabs, onSelect)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(28)
  strip.bg = Th.Solid(strip, "BACKGROUND", "panel3")
  strip.bg:SetAllPoints(strip)
  strip.buttons, strip.selected = {}, false
  local x = 8
  for _, t in ipairs(tabs) do
    local b = W.Tab(strip, t)
    b:SetPoint("LEFT", strip, "LEFT", x, 0)
    x = x + b:GetWidth()
    strip.buttons[t.key] = b
  end
  strip.Select = function(self, key)
    self.selected = key
    for k, b in pairs(self.buttons) do
      Th.Color(b.text, (k == key) and "white" or "dim")
      if k == key then b.line:Show() else b.line:Hide() end
    end
    onSelect(key)
  end
  return strip
end

function W.Tab(strip, t)
  local b = CreateFrame("Button", nil, strip)
  b:SetHeight(28)
  b.text = Th.Text(b, "display", 13, "dim")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text:SetText(string.upper(t.label))
  b:SetWidth(b.text:GetStringWidth() + 24)
  b.line = Th.Solid(b, "ARTWORK", "accent")
  b.line:SetHeight(2)
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 0)
  b.line:Hide()
  b.key = t.key
  b:SetScript("OnClick", function() strip:Select(this.key) end)
  return b
end

-- Windows are re-pinned by their top-left corner after a drag: left to itself
-- the client re-anchors by whichever corner it likes, and the saved spot drifts.
function W.SavePosition(f)
  local x, y = f:GetLeft(), f:GetTop()
  if not x or not y then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  local p = TaxTheFoolsCharDB.windows[f.windowKey] or {}
  p.x, p.y, p.w, p.h = x, y, f:GetWidth(), f:GetHeight()
  TaxTheFoolsCharDB.windows[f.windowKey] = p
end

function W.RestorePosition(f)
  local p = TaxTheFoolsCharDB.windows[f.windowKey]
  f:ClearAllPoints()
  if p and p.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    if p.w and p.h then
      f:SetWidth(p.w)
      f:SetHeight(p.h)
    end
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

function W.ApplyScale()
  local s = DB.S().scale or 1
  for _, f in ipairs(W.windows) do f:SetScale(s) end
end

function W.Grip(f, minW, minH)
  f:SetResizable(true)
  f:SetMinResize(minW, minH)
  local g = CreateFrame("Button", nil, f)
  g:SetWidth(16)
  g:SetHeight(16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  local t = g:CreateTexture(nil, "OVERLAY")
  t:SetTexture(Th.MEDIA .. "icon-grip")
  t:SetAllPoints(g)
  Th.Tint(t, "subtle")
  g:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  -- 1.12 has no size-changed event: lay out again once the drag ends.
  g:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    W.SavePosition(f)
    if type(f.onResize) == "function" then f.onResize() end
  end)
  f.grip = g
end

function W.Window(name, width, height, title, opts)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetWidth(width)
  f:SetHeight(height)
  f:SetMovable(true)
  f:EnableMouse(true)
  f.windowKey = name
  Th.Panel(f, "bg")
  local h = CreateFrame("Frame", nil, f)
  h:SetHeight(30)
  h:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  h.fill = Th.NineSlice(h, "panel-fill", "BACKGROUND", "header", 1, 10)
  -- squares off the header's bottom corners so it meets the body cleanly
  h.square = Th.Solid(h, "BACKGROUND", "header")
  h.square:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
  h.square:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
  h.square:SetHeight(12)
  h.title = Th.Text(h, "display", 14, "white")
  h.title:SetText(string.upper(title))
  -- The logo is full colour artwork, so it is never tinted.
  if opts and opts.logo then
    h.logo = h:CreateTexture(nil, "ARTWORK")
    h.logo:SetTexture(Th.MEDIA .. "logo")
    h.logo:SetWidth(24)
    h.logo:SetHeight(24)
    h.logo:SetPoint("LEFT", h, "LEFT", 8, 0)
    h.title:SetPoint("LEFT", h.logo, "RIGHT", 6, 0)
  else
    h.logo = false
    h.title:SetPoint("LEFT", h, "LEFT", 12, 0)
  end
  h:EnableMouse(true)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() f:StartMoving() end)
  h:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    W.SavePosition(f)
  end)
  f.header = h
  f.close = W.IconButton(h, "icon-close", 20, function() f:Hide() end)
  f.close:SetPoint("RIGHT", h, "RIGHT", -6, 0)
  local line = Th.Solid(f, "ARTWORK", "border")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, 0)
  table.insert(UISpecialFrames, name)
  table.insert(W.windows, f)
  f:SetScale(DB.S().scale or 1)
  W.RestorePosition(f)
  if opts and opts.resizable then W.Grip(f, opts.minW or width, opts.minH or height) end
  f:Hide()
  return f
end
