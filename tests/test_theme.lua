local Th, DB = TaxTheFools.Theme, TaxTheFools.DB

T.test("switching theme re-colours what is already drawn", function()
  local t = Th.Solid(CreateFrame("Frame"), "ARTWORK", "accent")
  T.near(t.color[2], 199 / 255, 0.005, "Pathfinder green")
  Th.Apply("Frost")
  T.near(t.color[1], 91 / 255, 0.005, "Frost blue")
  local fs = Th.Text(CreateFrame("Frame"), "body", 12, "accent")
  T.near(fs.color[3], 214 / 255, 0.005, "text drawn later uses the current theme")
end)

T.test("an unknown theme falls back to Pathfinder", function()
  Th.Apply("Nope")
  T.eq(Th.current, "Pathfinder")
  T.near(Th.color.accent[1], 82 / 255, 0.005)
end)

T.test("chat colour codes come from the tokens", function()
  T.eq(Th.Code("accent"), "|cff52c722")
end)

T.test("bundled fonts are used when the client accepts them", function()
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.ok(string.find(fs.font, "Inter-Regular", 1, true), fs.font)
  Th.SetFont(fs, "display", 14)
  T.ok(string.find(fs.font, "Rajdhani-Bold", 1, true), fs.font)
end)

T.test("a font the client refuses falls back to the standard one", function()
  WoW.rejectFonts = true
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.eq(fs.font, STANDARD_TEXT_FONT)
end)

T.test("fonts switched off in options use the standard font", function()
  DB.S().fonts = false
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.eq(fs.font, STANDARD_TEXT_FONT)
end)

T.test("nine-slice keeps corners at their size and cuts the texture at the corner", function()
  local parts = Th.NineSlice(CreateFrame("Frame"), "panel-fill", "BACKGROUND", "bg", 1, 10)
  local n = 0
  for _ in pairs(parts) do n = n + 1 end
  T.eq(n, 9)
  T.eq(parts.TOPLEFT.width, 10)
  T.eq(parts.TOPLEFT.coords[2], 10 / 32)
  T.eq(parts.CENTER.texture, Th.MEDIA .. "panel-fill")
end)

local function onDisk(path)
  local f = io.open((string.gsub(path, "\\", "/")), "rb")
  if f then f:close() return true end
  return false
end

T.test("every texture the theme names exists in the addon folder", function()
  for _, name in ipairs(Th.TEXTURES) do
    T.ok(onDisk("TaxTheFools/media/" .. name .. ".tga"), name .. ".tga missing: run make media")
  end
end)

T.test("every font the theme names exists in the addon folder", function()
  for _, file in pairs(Th.FONTS) do
    T.ok(onDisk("TaxTheFools/media/" .. file), file .. " missing: run make fonts")
  end
end)
