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

T.test("a tradeskill capture while the Crafting page is open adds the recipe without reopening", function()
  seed()
  DB.Realm().chars[DB.charName], DB.Realm().chars.Tailor = DB.Realm().chars.Tailor, nil   -- the tailor is us
  local p = open()
  T.eq(table.getn(p.list.data), 3)
  WoW.tradeskill = { name = "Tailoring", rank = 225, maxRank = 300, selected = 0, rows = {
    { name = "Linen Bag", type = "easy", id = 4240, made = { 1, 1 },
      reagents = { { id = 2996, name = "Bolt of Linen Cloth", count = 3 } } } } }
  A.TradeSkill.Capture()
  T.eq(table.getn(p.list.data), 4, "the new recipe is listed at once")
end)

T.test("a bag change while the Crafting page is open repaints it", function()
  seed()
  local p = open()
  local before = p.list.data[1].cash
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 10 } }
  A.Inventory.ScanBags()
  T.ok(p.list.data[1].cash ~= before, "cash counts the new silk")
end)

-- ---------- the Not learned view ----------

local function withData(fn)
  local saved = A.RecipeData
  A.RecipeData = { Tailoring = {
    [1] = { n = "Silk Cape", skill = 150, item = 9300, pat = { 7000 }, src = { "vendor" }, r = { 4306, 2 } },
    [2] = { n = "Silk Sash", skill = 160, item = 9400, pat = { 7001 }, src = { "drop" }, r = { 4306, 1 } },
    [3] = { n = "Epic Robe", skill = 290, item = 9500, src = { "trainer" }, r = { 4306, 1 }, turtle = true },
    [4] = { n = "Bolt of Silk Cloth", skill = 125, item = 4305, src = { "trainer" }, r = { 4306, 4 } },
    [5] = { n = "Dud Hat", skill = 100, item = 9600, pat = { 7002 }, src = { "quest" }, r = { 4306, 9 } },
  } }
  A.CraftUI.cache = false
  local ok, err = pcall(fn)
  A.RecipeData = saved
  A.CraftUI.cache = false
  if not ok then error(err, 0) end
end

local function unlearnedPage()
  seed()
  DB.Realm().chars.Tailor.professions.Tailoring.rank = 140
  A.Items.Remember(7000, "Pattern: Silk Cape").vb = 4000
  A.Items.Remember(7001, "Pattern: Silk Sash")
  A.Items.Remember(7002, "Pattern: Dud Hat")
  DB.Realm().market["9300:0"] = { v = 4000, lowDay = 20375 }    -- Silk Cape: 4000 x 0.95 - 600 = 3200
  DB.Realm().market["9400:0"] = { v = 900, lowDay = 20375 }     -- Silk Sash: 855 - 300 = 555
  DB.Realm().market["9600:0"] = { v = 1000, lowDay = 20375 }    -- Dud Hat: 950 - 2700 < 0
  DB.Realm().market["7001:0"] = { v = 1500.5, lowDay = 20375 }  -- the sash pattern on the AH
  local p = open()
  p.ulist:SetHeight(200)
  p.view, p.soon = "unlearned", true
  CraftUI.Paint(p)
  return p
end

T.test("Not learned lists what this character has not learned, quickest payback first", function()
  withData(function()
    local p = unlearnedPage()
    -- Epic Robe (290) is out of reach at rank 140 + 25; Bolt of Silk Cloth is already learned.
    T.eq(names(p.ulist), "Silk Cape, Silk Sash, Dud Hat")
    T.ok(p.ulist:IsShown())
    T.eq(p.list:IsShown(), false)
    local r = p.ulist.data[1]
    T.eq(r.cost, 4000, "vendor price")
    T.eq(r.payback, 2, "ceil(4000 / 3200)")
    T.eq(p.ulist.rows[1].cells[3]:GetText(), TaxTheFools.Util.money(4000) .. " vendor")
    T.eq(p.ulist.rows[1].cells[5]:GetText(), "2 crafts")
    T.eq(p.ulist.data[2].cost, 1500, "AH cost floored")
    T.eq(p.ulist.rows[2].cells[3]:GetText(), TaxTheFools.Util.money(1500) .. " AH")
    T.eq(p.ulist.rows[2].cells[5]:GetText(), "3 crafts")
    T.eq(p.ulist.data[3].payback, nil, "no cost")
    T.eq(p.ulist.rows[3].cells[3]:GetText(), "quest")
    T.eq(p.ulist.rows[3].cells[5]:GetText(), "-")
  end)
end)

T.test("Not learned: never, free, the T tag, Sells and the warning colour", function()
  withData(function()
    local p = unlearnedPage()
    A.Items.Remember(7002, "Pattern: Dud Hat").vb = 50
    DB.Realm().market["7002:0"] = nil
    DB.Char().sales = { { key = "9300:0", outcome = "sold", money = 100, qty = 1, unit = 100, at = time() - 86400 },
      { key = "9300:0", outcome = "expired", at = time() - 86400 } }
    CraftUI.Paint(p)
    local byName = {}
    for i, r in ipairs(p.ulist.data) do byName[r.name] = i end
    T.eq(p.ulist.rows[byName["Dud Hat"]].cells[5]:GetText(), "never")
    T.eq(p.ulist.rows[byName["Silk Cape"]].cells[6]:GetText(), "50%")
    T.eq(p.ulist.rows[byName["Silk Sash"]].cells[6]:GetText(), "-")
    -- a free trainer recipe, not yet reachable: warning colour and the T tag
    TaxTheFoolsDB.recipes = { Tailoring = { trainer = { ["Epic Robe"] = { c = 0, s = 290 } }, seen = {} } }
    p.soon = false
    CraftUI.Paint(p)
    local robe
    for i, r in ipairs(p.ulist.data) do if r.name == "Epic Robe" then robe = i end end
    T.ok(robe, "listed without the filter")
    T.ok(string.find(p.ulist.rows[robe].cells[1]:GetText(), "T|r", 1, true), "Turtle tag")
    T.ok(string.find(p.ulist.rows[robe].cells[1]:GetText(), Th.Code("warn"), 1, true), "beyond rank")
    T.eq(p.ulist.rows[robe].cells[5]:GetText(), "free")
  end)
end)

T.test("Not learned: the Learnable soon filter, sort and selection detail", function()
  withData(function()
    local p = unlearnedPage()
    T.eq(table.getn(p.ulist.data), 3)
    WoW.runScript(p.soonSw, "OnClick")
    T.eq(p.soon, false)
    T.eq(table.getn(p.ulist.data), 4, "Epic Robe appears")
    DB.S().recipes.skillAhead = 0
    CraftUI.SetSoon(p, true)
    T.eq(table.getn(p.ulist.data), 1, "only skill <= 140: Dud Hat")
    DB.S().recipes.skillAhead = 25
    CraftUI.SetSoon(p, true)
    WoW.runScript(p.ulist.headers[2], "OnClick")           -- Skill ascending
    T.eq(p.ulist.data[1].name, "Dud Hat")
    WoW.runScript(p.ulist.rows[2], "OnClick", "LeftButton") -- Silk Cape
    local d = p.detail.lines
    T.eq(d[1]:GetText(), "Silk Cape: Pays back after 2 crafts at 32s each")
    T.eq(d[2]:GetText(), "Source: vendor   Pattern: Pattern: Silk Cape")
    T.ok(string.find(d[3]:GetText(), "2 x Silk Cloth", 1, true), d[3]:GetText())
  end)
end)

T.test("Not learned with no recipe list says so, and Learned is unchanged afterwards", function()
  withData(function()
    local p = unlearnedPage()
    DB.Realm().chars.Zed = { professions = { Leatherworking = { recipes = {} } } }
    CraftUI.SetChar(p, "Zed")
    T.eq(p.empty:GetText(), "No recipe list for Leatherworking yet.")
    T.ok(p.empty:IsShown())
    CraftUI.SetChar(p, "Tailor")
    CraftUI.SetView(p, "learned")
    T.eq(p.empty:GetText(), CraftUI.EMPTY)
    T.ok(p.list:IsShown())
    T.eq(p.ulist:IsShown(), false)
    T.eq(p.soonSw:IsShown(), false)
    T.eq(names(p.list), "Bolt of Silk Cloth, Silk Headband, Spider Silk Robe")
    T.eq(p.list.sortCol, CraftUI.COLUMNS[4])
  end)
end)
