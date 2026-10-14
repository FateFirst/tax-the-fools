TaxTheFools = TaxTheFools or {}
local Th = { color = {}, current = "Pathfinder" }
TaxTheFools.Theme = Th

-- The look of Aegis Pathfinder, rebuilt from scratch (its code is GPLv3):
-- flat dark panels, one accent colour, white-mask textures tinted at run time.
Th.MEDIA = "Interface\\AddOns\\TaxTheFools\\media\\"
Th.TEXTURES = { "solid", "panel-fill", "panel-border", "tab-fill", "tab-border", "circle",
  "icon-close", "icon-check", "icon-caret-down", "icon-caret-up", "icon-arrow-left", "icon-arrow-right", "icon-grip" }
Th.FONTS = {
  display = "fonts\\Rajdhani-Bold.ttf",
  display2 = "fonts\\Rajdhani-SemiBold.ttf",
  body = "fonts\\Inter-Regular.ttf",
  body2 = "fonts\\Inter-SemiBold.ttf",
}

Th.BASE = {
  bg = "202020", header = "111111", panel3 = "1a1a1a", strip = "3b3b3b", border = "050505", subtle = "545454",
  accent = "52c722", accentDeep = "2e850e", accentGlow = "8fe066",
  gold = "ffed71", text = "e6e6e6", white = "ffffff", dim = "c7c7bd",
  bad = "d9534f", good = "52c722", warn = "e0a030",
}
-- A theme only overrides the accent family; meaning colours (good/bad) stay put.
Th.THEMES = {
  Pathfinder = {},
  Frost = { accent = "5b9fd6", accentDeep = "2f6ea8", accentGlow = "9cc8ef" },
  Ember = { accent = "e0a030", accentDeep = "a8701a", accentGlow = "f2c46e" },
}
Th.ORDER = { "Pathfinder", "Frost", "Ember" }

-- Every tinted region, weakly held, so a theme change re-colours what is on screen.
Th.registry = setmetatable({}, { __mode = "k" })

local function hex(s)
  return { tonumber(string.sub(s, 1, 2), 16) / 255, tonumber(string.sub(s, 3, 4), 16) / 255,
           tonumber(string.sub(s, 5, 6), 16) / 255 }
end

function Th.paint(region, r)
  local c = Th.color[r.token] or Th.color.text
  if r.kind == "text" then region:SetTextColor(c[1], c[2], c[3], r.alpha)
  else region:SetVertexColor(c[1], c[2], c[3], r.alpha) end
end

function Th.Apply(name)
  if not Th.THEMES[name] then name = "Pathfinder" end
  local over = Th.THEMES[name]
  for k, v in pairs(Th.BASE) do Th.color[k] = hex(over[k] or v) end
  Th.current = name
  for region, r in pairs(Th.registry) do Th.paint(region, r) end
end

function Th.ResetState() Th.Apply("Pathfinder") end

function Th.Tint(tex, token, alpha)
  local r = { token = token, alpha = alpha or 1, kind = "tex" }
  Th.registry[tex] = r
  Th.paint(tex, r)
  return tex
end

function Th.Color(fs, token, alpha)
  local r = { token = token, alpha = alpha or 1, kind = "text" }
  Th.registry[fs] = r
  Th.paint(fs, r)
  return fs
end

function Th.Code(token)
  local c = Th.color[token] or Th.color.text
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
    math.floor(c[3] * 255 + 0.5))
end

-- SetFont returns nil when the client refuses a file; the stock font is the fallback.
function Th.SetFont(fs, role, size, flags)
  local s = TaxTheFoolsDB and TaxTheFoolsDB.settings
  local own = not s or s.fonts ~= false
  if own and fs:SetFont(Th.MEDIA .. (Th.FONTS[role] or Th.FONTS.body), size, flags) then return end
  fs:SetFont(STANDARD_TEXT_FONT, size, flags)
end

function Th.Text(parent, role, size, token, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  Th.SetFont(fs, role, size)
  Th.Color(fs, token or "text")
  fs:SetJustifyH("LEFT")
  return fs
end

function Th.Solid(parent, layer, token, alpha)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(Th.MEDIA .. "solid")
  return Th.Tint(t, token, alpha)
end

-- Nine pieces from one 32px mask: corners keep their size, edges and middle stretch.
local function pieces(c)
  return {
    { "TOPLEFT", 0, c, 0, c }, { "TOP", c, 1 - c, 0, c }, { "TOPRIGHT", 1 - c, 1, 0, c },
    { "LEFT", 0, c, c, 1 - c }, { "CENTER", c, 1 - c, c, 1 - c }, { "RIGHT", 1 - c, 1, c, 1 - c },
    { "BOTTOMLEFT", 0, c, 1 - c, 1 }, { "BOTTOM", c, 1 - c, 1 - c, 1 }, { "BOTTOMRIGHT", 1 - c, 1, 1 - c, 1 },
  }
end

function Th.NineSlice(frame, file, layer, token, alpha, corner)
  corner = corner or 10
  local parts = {}
  for _, p in ipairs(pieces(corner / 32)) do
    local t = frame:CreateTexture(nil, layer)
    t:SetTexture(Th.MEDIA .. file)
    t:SetTexCoord(p[2], p[3], p[4], p[5])
    Th.Tint(t, token, alpha)
    parts[p[1]] = t
  end
  local tl, tr, bl, br = parts.TOPLEFT, parts.TOPRIGHT, parts.BOTTOMLEFT, parts.BOTTOMRIGHT
  for _, c in ipairs({ tl, tr, bl, br }) do
    c:SetWidth(corner)
    c:SetHeight(corner)
  end
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT")
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
  parts.TOP:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  parts.TOP:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  parts.BOTTOM:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  parts.BOTTOM:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  parts.LEFT:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  parts.LEFT:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  parts.RIGHT:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  parts.RIGHT:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  parts.CENTER:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
  parts.CENTER:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  return parts
end

function Th.TintSlice(parts, token, alpha)
  for _, t in pairs(parts) do Th.Tint(t, token, alpha) end
end

function Th.Panel(frame, token)
  frame.fill = Th.NineSlice(frame, "panel-fill", "BACKGROUND", token or "bg", 1, 10)
  frame.edge = Th.NineSlice(frame, "panel-border", "BORDER", "border", 1, 10)
end

Th.Apply("Pathfinder")
