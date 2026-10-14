local W, DB = TaxTheFools.Widgets, TaxTheFools.DB

T.test("a switch flips its setting and shows the new state", function()
  local v = false
  local s = W.Switch(UIParent, "Thing", function() return v end, function(n) v = n end)
  T.eq(s.on, false)
  WoW.runScript(s, "OnClick")
  T.eq(v, true) T.eq(s.on, true)
end)

T.test("a slider only saves when the mouse is released, snapped to its step", function()
  local v = 0.3
  local s = W.Slider(UIParent, "Delay", 0, 2, 0.1, function() return v end, function(n) v = n end,
    function(x) return string.format("%.1fs", x) end)
  T.eq(s.value:GetText(), "0.3s")
  s.slider:SetValue(1.23)
  T.eq(v, 0.3, "dragging doesn't save")
  T.eq(s.value:GetText(), "1.2s", "but the label follows")
  WoW.runScript(s.slider, "OnMouseUp")
  T.near(v, 1.2, 0.0001)
end)

T.test("a dropdown sets the chosen value and shows its label", function()
  local v = "a"
  local d = W.Dropdown(UIParent, 120, { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
    function() return v end, function(n) v = n end)
  T.eq(d.label:GetText(), "Alpha")
  WoW.runScript(d, "OnClick")
  T.ok(d.menu:IsShown(), "menu opens")
  WoW.runScript(d.menu.items[2], "OnClick")
  T.eq(v, "b") T.eq(d.label:GetText(), "Beta") T.eq(d.menu:IsShown(), false)
end)

T.test("windows remember where they were left and close on Escape", function()
  local f = W.Window("TTFTestWinA", 300, 200, "Test")
  local listed = false
  for _, n in ipairs(UISpecialFrames) do if n == "TTFTestWinA" then listed = true end end
  T.ok(listed, "Escape closes it")
  T.eq(f:IsShown(), false, "starts hidden")
  f.left, f.top = 300, 400
  W.SavePosition(f)
  T.eq(TaxTheFoolsCharDB.windows.TTFTestWinA.x, 300)
  W.RestorePosition(f)
  local p = f.points[1]
  T.eq(p[1], "TOPLEFT") T.eq(p[3], "BOTTOMLEFT") T.eq(p[4], 300) T.eq(p[5], 400)
end)

T.test("the close button hides the window", function()
  local f = W.Window("TTFTestWinB", 300, 200, "Test")
  f:Show()
  WoW.runScript(f.close, "OnClick")
  T.eq(f:IsShown(), false)
end)

T.test("a disabled button ignores clicks and dims", function()
  local clicks = 0
  local b = W.Button(UIParent, "Go", 80, 22, function() clicks = clicks + 1 end)
  b:SetEnabled(false)
  WoW.runScript(b, "OnClick")
  T.eq(clicks, 0) T.eq(b.alpha, 0.45)
  b:SetEnabled(true)
  WoW.runScript(b, "OnClick")
  T.eq(clicks, 1)
end)

T.test("tabs mark the selected one and report it", function()
  local picked
  local s = W.TabStrip(UIParent, { { key = "a", label = "One" }, { key = "b", label = "Two" } },
    function(k) picked = k end)
  WoW.runScript(s.buttons.b, "OnClick")
  T.eq(picked, "b") T.eq(s.selected, "b")
  T.eq(s.buttons.b.line:IsShown(), true)
  T.eq(s.buttons.a.line:IsShown(), false)
end)

T.test("the progress bar's width follows the fraction", function()
  local p = W.Progress(UIParent, 8)
  p:SetWidth(102)
  p:SetFraction(0.5)
  T.eq(p.bar:GetWidth(), 50)
  p:SetFraction(0)
  T.eq(p.bar:IsShown(), false)
  p:SetFraction(3)
  T.eq(p.fraction, 1)
end)

T.test("window scale follows the setting", function()
  local f = W.Window("TTFTestWinC", 300, 200, "Test")
  DB.S().scale = 1.2
  W.ApplyScale()
  T.eq(f:GetScale(), 1.2)
end)
