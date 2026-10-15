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

T.test("cells are one line high, so long text is cut short instead of wrapping over the next row", function()
  local l = L.New(UIParent, COLS, 18)
  l:SetHeight(20 + 18 * 2)
  l:SetData({ { name = "Stormwind Auction House, a sender far wider than its column" } })
  T.eq(l.rows[1].cells[1]:GetHeight(), 14)
end)

T.test("widths: the first column takes the spare width unless columns are marked flex", function()
  local cols = { { width = 100 }, { width = 50 }, { width = 50 } }
  local w = L.Widths(cols, 300)
  T.eq(w[1], 200) T.eq(w[2], 50) T.eq(w[3], 50)
  w = L.Widths(cols, 150)
  T.eq(w[1], 100, "never below the minimum")
  local flex = { { width = 40 }, { width = 90, flex = 1 }, { width = 130, flex = 2 }, { width = 60 } }
  w = L.Widths(flex, 320 + 100)
  T.eq(w[1], 40) T.eq(w[2], 90 + 33) T.eq(w[3], 130 + 67) T.eq(w[4], 60)
end)

T.test("a wider list widens its flexible columns' headers and cells", function()
  local cols = { { label = "Name", width = 100, fmt = function(r) return r.name end },
                 { label = "Qty", width = 40, fmt = function(r) return "1" end } }
  local l = L.New(UIParent, cols, 18)
  l:SetHeight(20 + 18 * 2)
  l:SetWidth(152)
  l:SetData({ { name = "a" } })
  T.eq(l.headers[1]:GetWidth(), 100) T.eq(l.rows[1].cells[1]:GetWidth(), 88)
  l:SetWidth(352)
  l:Paint()
  T.eq(l.headers[1]:GetWidth(), 300) T.eq(l.rows[1].cells[1]:GetWidth(), 288)
  T.eq(l.headers[2]:GetWidth(), 40)
end)
