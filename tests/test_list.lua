local L = TaxTheFools.List

local COLS = { { label = "Name", width = 100, sort = "name", fmt = function(r) return r.name end } }

T.test("clamp keeps the visible window inside the data", function()
  T.eq(L.Clamp(10, 4, 8), 6)
  T.eq(L.Clamp(3, 4, 2), 0)
  T.eq(L.Clamp(10, 4, -1), 0)
end)

T.test("sorting puts missing values last whichever way", function()
  local rows = { { v = 2 }, {}, { v = 1 } }
  L.Sort(rows, "v", false)
  T.eq(rows[1].v, 1) T.eq(rows[3].v, nil)
  L.Sort(rows, "v", true)
  T.eq(rows[1].v, 2) T.eq(rows[3].v, nil)
end)

T.test("a list draws only the rows that fit and scrolls", function()
  local l = L.New(UIParent, COLS, 18)
  l:SetHeight(20 + 18 * 3)
  l:SetData({ { name = "a" }, { name = "b" }, { name = "c" }, { name = "d" }, { name = "e" } })
  T.eq(l.rows[1].cells[1]:GetText(), "a")
  T.eq(l.rows[4], nil, "only three rows built")
  l:Scroll(5)
  T.eq(l.offset, 2)
  T.eq(l.rows[1].cells[1]:GetText(), "c")
end)

T.test("clicking a header sorts, and clicking again reverses", function()
  local l = L.New(UIParent, COLS, 18)
  l:SetHeight(20 + 18 * 3)
  l:SetData({ { name = "b" }, { name = "a" }, { name = "c" } })
  WoW.runScript(l.headers[1], "OnClick")
  T.eq(l.rows[1].cells[1]:GetText(), "a")
  WoW.runScript(l.headers[1], "OnClick")
  T.eq(l.rows[1].cells[1]:GetText(), "c")
end)
