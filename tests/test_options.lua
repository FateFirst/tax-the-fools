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

T.test("clicking the minimap button opens options", function()
  Mini.Create()
  Opt.Create():Hide()
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.ok(Opt.frame:IsShown())
end)

T.test("the minimap button shows the goblin coin", function()
  Mini.Create()
  T.eq(Mini.button.icon:GetTexture(), TaxTheFools.Theme.MEDIA .. "minimap")
end)
