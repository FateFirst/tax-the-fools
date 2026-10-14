TaxTheFools = TaxTheFools or {}
local Th = TaxTheFools.Theme
local L = {}
TaxTheFools.List = L

local HEAD = 20
local BAR = 12

-- Which slice of total rows to draw in `shown` slots.
function L.Clamp(total, shown, offset)
  local max = total - shown
  if max < 0 then max = 0 end
  if offset < 0 then offset = 0 end
  if offset > max then offset = max end
  return offset, max
end

-- Missing values sink to the bottom in both directions: "no market price" is
-- never the most interesting row.
function L.Sort(rows, key, desc)
  table.sort(rows, function(a, b)
    local x, y = a[key], b[key]
    if x == nil then return false end
    if y == nil then return true end
    if x == y then return false end
    if desc then return x > y end
    return x < y
  end)
end

local M = {}

function M:SetData(data)
  self.data = data or {}
  self.selected = false
  if self.sortCol then L.Sort(self.data, self.sortCol.sort, self.sortDesc) end
  self:Paint()
end

function M:SortBy(col)
  if not col.sort then return end
  if self.sortCol == col then self.sortDesc = not self.sortDesc
  else self.sortCol, self.sortDesc = col, col.desc or false end
  L.Sort(self.data, col.sort, self.sortDesc)
  self:Paint()
end

function M:Scroll(delta)
  self.offset = self.offset + delta
  self:Paint()
end

function M:Slots()
  return math.max(1, math.floor((self:GetHeight() - HEAD) / self.rowHeight))
end

function M:Row(i)
  if self.rows[i] then return self.rows[i] end
  local list = self
  local r = CreateFrame("Button", nil, self)
  r:SetHeight(self.rowHeight)
  r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -HEAD - (i - 1) * self.rowHeight)
  r:SetPoint("RIGHT", self, "RIGHT", -BAR, 0)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(r)
  hl:SetVertexColor(1, 1, 1, 0.05)
  r.sel = Th.Solid(r, "BACKGROUND", "strip")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.cells = {}
  local x = 0
  for c, col in ipairs(self.columns) do
    local fs = Th.Text(r, "body", 11, "text")
    fs:SetPoint("LEFT", r, "LEFT", x + 6, 0)
    fs:SetWidth(col.width - 12)
    fs:SetJustifyH(col.align or "LEFT")
    r.cells[c] = fs
    x = x + col.width
  end
  r.item = false
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function()
    if not this.item then return end
    list.selected = this.item
    list:Paint()
    if type(list.onClick) == "function" then list.onClick(this.item, arg1) end
  end)
  r:SetScript("OnEnter", function()
    if this.item and type(list.onEnter) == "function" then list.onEnter(this, this.item) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.rows[i] = r
  return r
end

function M:Paint()
  local shown = self:Slots()
  local offset, max = L.Clamp(table.getn(self.data), shown, self.offset)
  self.offset = offset
  self.updating = true
  self.bar:SetMinMaxValues(0, max)
  self.bar:SetValue(offset)
  self.updating = false
  if max == 0 then self.bar:Hide() else self.bar:Show() end
  for i = 1, shown do
    local r = self:Row(i)
    local item = self.data[i + offset]
    if item then
      r.item = item
      for c, col in ipairs(self.columns) do
        local text, token = col.fmt(item)
        r.cells[c]:SetText(text or "")
        Th.Color(r.cells[c], token or "text")
      end
      if item == self.selected then r.sel:Show() else r.sel:Hide() end
      r:Show()
    else
      r.item = false
      r:Hide()
    end
  end
  for i = shown + 1, table.getn(self.rows) do self.rows[i]:Hide() end
end

function L.Header(list, c, col, x)
  local b = CreateFrame("Button", nil, list.head)
  b:SetHeight(HEAD)
  b:SetWidth(col.width)
  b:SetPoint("LEFT", list.head, "LEFT", x, 0)
  b.text = Th.Text(b, "display", 11, "dim")
  b.text:SetText(string.upper(col.label))
  b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.text:SetJustifyH(col.align or "LEFT")
  b.col = col
  b:SetScript("OnClick", function() list:SortBy(this.col) end)
  return b
end

function L.New(parent, columns, rowHeight, onClick)
  local f = CreateFrame("Frame", nil, parent)
  for k, v in pairs(M) do f[k] = v end
  f.columns, f.rowHeight, f.rows, f.data, f.offset = columns, rowHeight or 18, {}, {}, 0
  f.onClick, f.onEnter, f.selected, f.updating = onClick or false, false, false, false
  f.sortCol, f.sortDesc = false, false
  f.head = CreateFrame("Frame", nil, f)
  f.head:SetHeight(HEAD)
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -BAR, 0)
  local hb = Th.Solid(f.head, "BACKGROUND", "strip")
  hb:SetAllPoints(f.head)
  f.headers = {}
  local x = 0
  for c, col in ipairs(columns) do
    f.headers[c] = L.Header(f, c, col, x)
    x = x + col.width
  end
  local bar = CreateFrame("Slider", nil, f)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(10)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local track = Th.Solid(bar, "BACKGROUND", "panel3")
  track:SetAllPoints(bar)
  bar:SetThumbTexture(Th.MEDIA .. "solid")
  local thumb = bar:GetThumbTexture()
  thumb:SetWidth(10)
  thumb:SetHeight(30)
  Th.Tint(thumb, "subtle")
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetScript("OnValueChanged", function()
    if f.updating then return end
    f.offset = math.floor(this:GetValue() + 0.5)
    f:Paint()
  end)
  f.bar = bar
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function() f:Scroll(-arg1 * 3) end)
  return f
end
