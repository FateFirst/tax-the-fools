local Opt, Mini, DB = TaxTheFools.Options, TaxTheFools.Minimap, TaxTheFools.DB

T.test("options read and write nested settings, then run the follow-up", function()
  local row = { kind = "switch", path = { "tooltip", "vendor" } }
  T.eq(Opt.Get(row), true)
  Opt.Set(row, false)
  T.eq(DB.S().tooltip.vendor, false)
  local hit
  Opt.Set({ key = "safeMode", after = function(v) hit = v end }, true)
  T.eq(DB.S().safeMode, true) T.eq(hit, true)
end)

T.test("the options window opens on its first page with one control per row", function()
  local f = Opt.Create()
  f:Hide()
  f.selected = false
  Opt.Toggle()
  T.ok(f:IsShown())
  T.eq(f.selected, "general")
  T.eq(table.getn(f.pages.general.controls), table.getn(Opt.CATEGORIES[1].rows))
end)

T.test("choosing a category shows only that page", function()
  local f = Opt.Create()
  Opt.Select("general")
  Opt.Select("scanning")
  T.ok(f.pages.scanning:IsShown())
  T.eq(f.pages.general:IsShown(), false)
  T.ok(f.navRows.scanning.bar:IsShown())
end)

T.test("a switch in options changes the setting", function()
  Opt.Create()
  Opt.Select("scanning")
  WoW.runScript(Opt.frame.pages.scanning.controls[2], "OnClick")
  T.eq(DB.S().safeMode, true)
end)

T.test("reset asks first, then wipes and reloads", function()
  Opt.Create()
  Opt.Select("data")
  WoW.runScript(Opt.frame.pages.data.controls[3], "OnClick")
  T.ok(T.calledWith("StaticPopup_Show TAXTHEFOOLS_RESET"))
  DB.S().scanDelay = 2
  StaticPopupDialogs.TAXTHEFOOLS_RESET.OnAccept()
  T.eq(DB.S().scanDelay, 0.3)
  T.ok(T.calledWith("ReloadUI"))
end)

T.test("the minimap button sits on a circle at the saved angle", function()
  local x, y = Mini.Position(0)
  T.near(x, 80, 0.01) T.near(y, 0, 0.01)
  x, y = Mini.Position(90)
  T.near(x, 0, 0.01) T.near(y, 80, 0.01)
end)

T.test("dragging the minimap button saves the angle under the cursor", function()
  Mini.Create()
  WoW.cursorX, WoW.cursorY = 100, 200     -- straight above the minimap centre (100, 100)
  Mini.DragUpdate()
  T.near(DB.S().minimapAngle, 90, 0.01)
end)

T.test("the minimap button hides when switched off", function()
  Mini.Create()
  DB.S().minimap = false
  Mini.Refresh()
  T.eq(Mini.button:IsShown(), false)
  DB.S().minimap = true
  Mini.Refresh()
  T.ok(Mini.button:IsShown())
end)

T.test("right-clicking the minimap button opens options", function()
  Mini.Create()
  Opt.Create():Hide()
  WoW.runScript(Mini.button, "OnClick", "RightButton")
  T.ok(Opt.frame:IsShown())
end)

T.test("left-clicking the minimap button opens the Crafting window", function()
  Mini.Create()
  local f = TaxTheFools.CraftUI.Window()
  f:Hide()
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.ok(f:IsShown())
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.eq(f:IsShown(), false, "and closes it again")
end)

T.test("the minimap button shows the goblin coin and says what each click does", function()
  Mini.Create()
  T.eq(Mini.button.icon:GetTexture(), TaxTheFools.Theme.MEDIA .. "minimap")
  T.ok(string.find(Mini.button.tip.body, "Left-click: crafting profit", 1, true), Mini.button.tip.body)
end)

T.test("the Crafting options switch auto-watch and set the stale-price days", function()
  local f = Opt.Create()
  Opt.Select("crafting")
  local c = f.pages.crafting.controls
  WoW.runScript(c[1], "OnClick")
  T.eq(DB.S().craft.autoWatch, false)
  c[2].slider:SetValue(12)
  T.eq(c[2].value:GetText(), "12 days")
  WoW.runScript(c[2].slider, "OnMouseUp")
  T.eq(DB.S().craft.staleDays, 12)
end)

T.test("Deals & buying options are bound to the same settings.deals the Deals rail uses", function()
  local f = Opt.Create()
  Opt.Select("deals")
  local c = f.pages.deals.controls
  WoW.runScript(c[1], "OnClick")
  T.eq(DB.S().deals.market, false)
  c[4].slider:SetValue(60)
  WoW.runScript(c[4].slider, "OnMouseUp")
  T.eq(DB.S().deals.belowMarketPct, 60)
  c[5].slider:SetValue(20000)
  T.eq(c[5].value:GetText(), TaxTheFools.Util.money(20000))
  WoW.runScript(c[5].slider, "OnMouseUp")
  T.eq(DB.S().deals.minProfit, 20000)
  -- the rail paints from the same table
  local UI = TaxTheFools.UI
  UI.CreateAH()
  UI.ah:Show()
  UI.ah.tabs:Select("deals")
  local p = UI.pages.deals
  p:Refresh()
  T.eq(p.profitSl.slider:GetValue(), 20000)
  T.eq(p.belowSl.slider:GetValue(), 60)
  -- and the other way round
  WoW.runScript(p.marketSw, "OnClick")
  T.eq(DB.S().deals.market, true)
  Opt.Select("deals")
  T.ok(Opt.Get({ path = { "deals", "market" } }))
  UI.ah.tabs:Select("browse")
  UI.ah:Hide()
end)

T.test("Confirm buys at or above: 0 to 500000 in steps of 10000, shown as money, bound to settings.buy", function()
  local f = Opt.Create()
  Opt.Select("deals")
  local c = f.pages.deals.controls[table.getn(f.pages.deals.controls)]
  local lo, hi = c.slider:GetMinMaxValues()
  T.eq(lo, 0) T.eq(hi, 500000)
  T.ok(string.find(f.pages.deals.controls[table.getn(f.pages.deals.controls)].text:GetText(), "Confirm buys", 1, true))
  c.slider:SetValue(100000)
  T.eq(c.value:GetText(), TaxTheFools.Util.money(100000))
  WoW.runScript(c.slider, "OnMouseUp")
  T.eq(DB.S().buy.confirmAbove, 100000)
  c.slider:SetValue(0)
  T.eq(c.value:GetText(), "never")
  WoW.runScript(c.slider, "OnMouseUp")
  T.eq(DB.S().buy.confirmAbove, 0)
end)

T.test("Selling options: percentages, undercut as money, and the default duration, bound to settings.sell", function()
  local f = Opt.Create()
  Opt.Select("selling")
  local c = f.pages.selling.controls
  T.eq(table.getn(c), 4)
  local lo, hi = c[1].slider:GetMinMaxValues()
  T.eq(lo, 50) T.eq(hi, 100)
  c[1].slider:SetValue(75)
  T.eq(c[1].value:GetText(), "75%")
  WoW.runScript(c[1].slider, "OnMouseUp")
  T.eq(DB.S().sell.bidPct, 75)
  lo, hi = c[2].slider:GetMinMaxValues()
  T.eq(lo, 50) T.eq(hi, 100)
  c[2].slider:SetValue(70)
  WoW.runScript(c[2].slider, "OnMouseUp")
  T.eq(DB.S().sell.floorPct, 70)
  lo, hi = c[3].slider:GetMinMaxValues()
  T.eq(lo, 1) T.eq(hi, 10000)
  c[3].slider:SetValue(250)
  T.eq(c[3].value:GetText(), TaxTheFools.Util.money(250))
  WoW.runScript(c[3].slider, "OnMouseUp")
  T.eq(DB.S().sell.undercut, 250)
  T.eq(c[4].dd.label:GetText(), "24h")
  WoW.runScript(c[4].dd.menu.items[3], "OnClick")
  T.eq(DB.S().sell.duration, 1440)
  WoW.runScript(c[4].dd.menu.items[1], "OnClick")
  T.eq(DB.S().sell.duration, 120)
  T.eq(c[4].dd.label:GetText(), "6h")
end)

T.test("Sales options are bound to settings.sales", function()
  local f = Opt.Create()
  Opt.Select("sales")
  local c = f.pages.sales.controls
  T.eq(table.getn(c), 3)
  c[1].slider:SetValue(60)
  WoW.runScript(c[1].slider, "OnMouseUp")
  T.eq(DB.S().sales.days, 60)
  c[2].slider:SetValue(150)
  WoW.runScript(c[2].slider, "OnMouseUp")
  T.eq(DB.S().sales.warnPct, 150)
  WoW.runScript(c[3], "OnClick")
  T.eq(DB.S().sales.tooltip, false)
  DB.S().sales.tooltip = true
end)

T.test("the undersupplied options are bound to settings.deals, with their ranges", function()
  local f = Opt.Create()
  Opt.Select("deals")
  local c = f.pages.deals.controls
  local n = table.getn(c)
  WoW.runScript(c[n - 3], "OnClick")
  T.eq(DB.S().deals.under, false)
  c[n - 2].slider:SetValue(50)
  WoW.runScript(c[n - 2].slider, "OnMouseUp")
  T.eq(DB.S().deals.underPct, 50)
  c[n - 1].slider:SetValue(125)
  WoW.runScript(c[n - 1].slider, "OnMouseUp")
  T.eq(DB.S().deals.premiumPct, 125)
  local r = Opt.CATEGORIES
  for _, cat in ipairs(r) do
    if cat.key == "deals" then
      local k = table.getn(cat.rows) - 1
      T.eq(cat.rows[k - 1].min, 10) T.eq(cat.rows[k - 1].max, 90) T.eq(cat.rows[k - 1].step, 5)
      T.eq(cat.rows[k].min, 100) T.eq(cat.rows[k].max, 150) T.eq(cat.rows[k].step, 5)
    end
    if cat.key == "sales" then
      T.eq(cat.rows[1].min, 7) T.eq(cat.rows[1].max, 90)
      T.eq(cat.rows[2].min, 100) T.eq(cat.rows[2].max, 200) T.eq(cat.rows[2].step, 10)
    end
  end
  DB.S().deals.under, DB.S().deals.underPct, DB.S().deals.premiumPct = true, 33, 110
end)

T.test("the General page binds the bag right-click switch to settings.bagClick", function()
  local f = Opt.Create()
  Opt.Select("general")
  local rows = Opt.CATEGORIES[1].rows
  local idx
  for i, row in ipairs(rows) do if row.key == "bagClick" then idx = i end end
  T.ok(idx, "row exists")
  T.eq(rows[idx].label, "Right-click bag items to search or sell")
  WoW.runScript(f.pages.general.controls[idx], "OnClick")
  T.eq(DB.S().bagClick, false)
  DB.S().bagClick = true
end)

T.test("the recipe options are bound to settings.deals and settings.recipes, with their ranges", function()
  local f = Opt.Create()
  local function find(catKey, path2)
    for _, cat in ipairs(Opt.CATEGORIES) do
      if cat.key == catKey then
        for i, row in ipairs(cat.rows) do
          if row.path and row.path[2] == path2 then return i, row end
        end
      end
    end
  end
  Opt.Select("deals")
  local i, row = find("deals", "recipe")
  T.ok(i, "Recipe switch") T.eq(row.label, "Recipe")
  WoW.runScript(f.pages.deals.controls[i], "OnClick")
  T.eq(DB.S().deals.recipe, false)
  DB.S().deals.recipe = true
  i, row = find("deals", "paybackCrafts")
  T.eq(row.label, "Pays back within") T.eq(row.min, 1) T.eq(row.max, 50)
  f.pages.deals.controls[i].slider:SetValue(20)
  WoW.runScript(f.pages.deals.controls[i].slider, "OnMouseUp")
  T.eq(DB.S().deals.paybackCrafts, 20)
  DB.S().deals.paybackCrafts = 10
  Opt.Select("crafting")
  i, row = find("crafting", "tooltip")
  T.eq(row.label, "Pattern payback tooltip line") T.eq(row.path[1], "recipes")
  WoW.runScript(f.pages.crafting.controls[i], "OnClick")
  T.eq(DB.S().recipes.tooltip, false)
  DB.S().recipes.tooltip = true
  i, row = find("crafting", "skillAhead")
  T.eq(row.label, "Learnable soon: skill ahead") T.eq(row.min, 0) T.eq(row.max, 75) T.eq(row.step, 5)
  f.pages.crafting.controls[i].slider:SetValue(50)
  WoW.runScript(f.pages.crafting.controls[i].slider, "OnMouseUp")
  T.eq(DB.S().recipes.skillAhead, 50)
  DB.S().recipes.skillAhead = 25
end)

T.test("the Mail page sets the replace switch, rules, bank alt and keep list", function()
  Opt.Create()
  Opt.Select("mail")
  local page = Opt.frame.pages.mail
  T.eq(table.getn(page.controls), table.getn(Opt.CATEGORIES[table.getn(Opt.CATEGORIES) - 1].rows))
  local m = DB.S().mail
  WoW.runScript(page.controls[1], "OnClick")
  T.eq(DB.S().replaceBlizzardMail, false)
  WoW.runScript(page.controls[6], "OnClick")
  T.eq(m.rules.auctionable, true)
  local row = Opt.CATEGORIES[table.getn(Opt.CATEGORIES) - 1].rows[2]
  Opt.Set(row, "Banker")
  T.eq(m.bankAlt, "Banker")
  T.eq(Opt.Get(row), "Banker")
  Opt.Set(row, "")
  T.eq(m.bankAlt, nil)
  local opts = Opt.BankAltOptions()
  T.eq(opts[1].label, "None")
end)

T.test("the keep list shows names, removes on click, and caps at eight", function()
  Opt.Create()
  local m = DB.S().mail
  m.keep = { ["100:0"] = true }
  Opt.Select("mail")
  local kl = Opt.frame.pages.mail.controls[7]
  kl:Refresh()
  T.ok(kl.lines[1]:IsShown())
  T.eq(kl.lines[1].text:GetText(), TaxTheFools.Items.Name(100))
  WoW.runScript(kl.lines[1], "OnClick")
  T.eq(m.keep["100:0"], nil)
  T.eq(kl.lines[1]:IsShown(), false)
  for i = 1, 11 do m.keep[(100 + i) .. ":0"] = true end
  kl:Refresh()
  T.eq(kl.lines[9].text:GetText(), "+3 more")
  m.keep = {}
end)

T.test("the Ledger and trend options are bound to their settings", function()
  local f = Opt.Create()
  Opt.Select("ledger")
  local c = f.pages.ledger.controls
  T.eq(table.getn(c), 1)
  T.eq(DB.S().ledger.vendor, true)
  WoW.runScript(c[1], "OnClick")
  T.eq(DB.S().ledger.vendor, false)
  DB.S().ledger.vendor = true
  Opt.Select("tooltip")
  local tc = f.pages.tooltip.controls
  T.eq(table.getn(tc), 4)
  WoW.runScript(tc[4], "OnClick")
  T.eq(DB.S().trend.tooltip, false)
  DB.S().trend.tooltip = true
end)
