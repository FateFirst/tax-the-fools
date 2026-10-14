TaxTheFools = TaxTheFools or {}
local Th, DB = TaxTheFools.Theme, TaxTheFools.DB
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
  menu:SetHeight(8 + table.getn(options) * 20)
  Th.Panel(menu, "header")
  menu.items = {}
  for i, o in ipairs(options) do
    menu.items[i] = W.MenuItem(menu, i, o, function(value)
      set(value)
      menu:Hide()
      b:Refresh()
    end)
  end
  menu:Hide()
  b.menu = menu
  b:SetScript("OnHide", function() menu:Hide() end)
  b.Refresh = function(self)
    local v = get()
    for _, o in ipairs(options) do
      if o.value == v then self:SetLabel(o.label) end
    end
  end
  b:Refresh()
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
  h.title:SetPoint("LEFT", h, "LEFT", 12, 0)
  h.title:SetText(string.upper(title))
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
