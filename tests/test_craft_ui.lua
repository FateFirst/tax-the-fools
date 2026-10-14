local A = TaxTheFools
local CraftUI, DB, UI, AH, Th = A.CraftUI, A.DB, A.UI, A.AH, A.Theme

local function bolt()
  return { item = "4305:0", color = "medium", reagents = { { item = "4306:0", name = "Silk Cloth", count = 4 } } }
end

-- Tailor knows three recipes: one profitable, one at a loss, one with a material nobody has priced.
local function seed()
  local realm = DB.Realm()
  realm.market["4306:0"] = { v = 300, lowDay = 20366 }     -- Silk Cloth, last seen 9 days ago
  realm.market["4305:0"] = { v = 2000, lowDay = 20375 }    -- Bolt of Silk Cloth
  realm.market["9100:0"] = { v = 3000, lowDay = 20375 }    -- Silk Headband
  realm.market["9200:0"] = { v = 5000, lowDay = 20375 }    -- Spider Silk Robe
  A.Items.Remember(4306, "Silk Cloth")
  A.Items.Remember(4305, "Bolt of Silk Cloth")
  A.Items.Remember(2321, "Fine Thread").vb = 100
  realm.chars.Tailor = { bags = { ["4306:0"] = 3 }, professions = { Tailoring = { recipes = {
    ["Bolt of Silk Cloth"] = bolt(),
    ["Silk Headband"] = { item = "9100:0", color = "optimal", reagents = {
      { item = "4305:0", name = "Bolt of Silk Cloth", count = 3 }, { item = "2321:0", name = "Fine Thread", count = 1 } } },
    ["Spider Silk Robe"] = { item = "9200:0", color = "easy", reagents = { { item = "3182:0", name = "Spider's Silk", count = 1 } } },
  } } } }
end

-- The fake client has no layout engine: give the list a height so it draws rows.
local function open()
  local f = CraftUI.Window()
  f:Hide()
  f.page.char, f.page.prof = false, false
  f.page.list:SetHeight(200)
  f:Show()
  return f.page
end

local function names(list)
  local t = {}
  for _, r in ipairs(list.data) do table.insert(t, r.name) end
  return table.concat(t, ", ")
end

T.test("recipes sort by profit, highest first, with incomplete ones last", function()
  seed()
  local p = open()
  T.eq(p.char, "Tailor", "Bankalt has no recipes, so the first character that does")
  T.eq(p.prof, "Tailoring")
  -- Bolt: 2000 x 0.95 - 4 x 300 = 700. Headband: 3000 x 0.95 - (3 x 1200 crafted bolts + 100 thread) = -850.
  T.eq(names(p.list), "Bolt of Silk Cloth, Silk Headband, Spider Silk Robe")
  T.near(p.list.data[1].profit, 700, 0.001)
  T.near(p.list.data[2].profit, -850, 0.001)
  T.eq(p.list.data[3].profit, nil)
  T.eq(p.list.rows[3].cells[4]:GetText(), "incomplete")
end)

T.test("switching character and profession changes the list", function()
  seed()
  DB.Realm().chars.Zed = { professions = {
    Leatherworking = { recipes = { ["Light Armor Kit"] = { item = "2304:0", reagents = { { item = "2318:0", count = 1 } } } } },
    Tailoring = { recipes = { ["Bolt of Silk Cloth"] = bolt() } },
  } }
  local p = open()
  WoW.runScript(p.charDD.menu.items[2], "OnClick")       -- Tailor, Zed
  T.eq(p.char, "Zed")
  T.eq(p.prof, "Leatherworking", "the first of Zed's professions")
  T.eq(names(p.list), "Light Armor Kit")
  WoW.runScript(p.profDD.menu.items[2], "OnClick")       -- Leatherworking, Tailoring
  T.eq(p.prof, "Tailoring")
  T.eq(names(p.list), "Bolt of Silk Cloth")
  DB.Realm().chars.Bankalt = { professions = { Tailoring = { recipes = { ["Bolt of Silk Cloth"] = bolt() } } } }
  p = open()
  T.eq(p.char, "Bankalt", "this character, once it has recipes")
end)

T.test("with nothing captured the page says how to load recipes", function()
  local p = open()
  T.ok(p.empty:IsShown())
  T.eq(p.empty:GetText(), "Open your Tailoring window once on this character to load its recipes.")
  T.eq(p.list:IsShown(), false)
end)

T.test("the detail pane lists each material, dimming prices older than the setting", function()
  seed()
  local p = open()
  WoW.runScript(p.list.rows[1], "OnClick", "LeftButton")    -- Bolt of Silk Cloth
  local d = p.detail.lines
  -- profit 700; cash 1900 - (4 - 3 held) x 300 = 1600
  T.eq(d[1]:GetText(), "Bolt of Silk Cloth: profit 7s, cash 16s (deposit unknown)")
  T.eq(d[2]:GetText(), "4 x Silk Cloth   have 3   3s each   AH   9d ago")
  T.eq(d[2].color[1], Th.color.dim[1], "20375 - 20366 = 9 days > 7")
  DB.S().craft.staleDays = 10
  CraftUI.ShowDetail(p, p.list.selected)
  T.eq(d[2].color[1], Th.color.text[1], "9 days is within 10")
end)

T.test("materials show which source won: crafted, vendor, or nothing", function()
  seed()
  local p = open()
  WoW.runScript(p.list.rows[2], "OnClick", "LeftButton")    -- Silk Headband
  local d = p.detail.lines
  T.eq(d[2]:GetText(), "3 x Bolt of Silk Cloth   have 0   12s each   craft   9d ago", "4 x 300 = 1200 < 2000")
  T.eq(d[3]:GetText(), "1 x Fine Thread   have 0   1s each   vendor")
  WoW.runScript(p.list.rows[3], "OnClick", "LeftButton")    -- Spider Silk Robe
  T.eq(d[1]:GetText(), "Spider Silk Robe: incomplete: Spider's Silk")
  T.eq(d[2]:GetText(), "1 x Spider's Silk   have 0   -   no price")
  T.eq(d[3]:GetText(), "", "unused lines are cleared")
end)

T.test("the auction window's Crafting tab shows the same page", function()
  seed()
  UI.CreateAH()
  AH.switching = true UI.ah:Hide() AH.switching = false
  AH.open = true
  AH.ShowOurs()
  if UI.pages.craft then UI.pages.craft.char, UI.pages.craft.prof = false, false end
  UI.ah.tabs:Select("craft")
  T.ok(UI.pages.craft:IsShown())
  T.eq(UI.pages.browse:IsShown(), false)
  T.eq(names(UI.pages.craft.list), "Bolt of Silk Cloth, Silk Headband, Spider Silk Robe")
  UI.ah.tabs:Select("browse")
end)

T.test("the auction and Crafting windows show the logo before the title", function()
  UI.CreateAH()
  local logo = Th.MEDIA .. "logo"
  T.eq(UI.ah.header.logo:GetTexture(), logo)
  T.eq(UI.ah.header.logo:GetWidth(), 24)
  T.eq(UI.ah.header.title.points[1][2], UI.ah.header.logo, "the title starts after the logo")
  T.eq(CraftUI.Window().header.logo:GetTexture(), logo)
end)
