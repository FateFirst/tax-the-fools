local Sn = TaxTheFools.Snipe
local Dl = TaxTheFools.Deals

local function parse(t, name, copper)
  local n, c = Sn.Parse(t)
  T.eq(n, name) T.eq(c, copper)
end

T.test("Snipe.Parse reads gold, silver and copper forms", function()
  parse("Silk Cloth 20s", "Silk Cloth", 2000)
  parse("Silk Cloth 1g 5s", "Silk Cloth", 10500)
  parse("Silk Cloth 1g5s", "Silk Cloth", 10500)
  parse("Silk Cloth 2g 50s 3c", "Silk Cloth", 25003)
  parse("Silk Cloth 2050", "Silk Cloth", 2050)
  parse("  Silk   Cloth  5G  ", "Silk Cloth", 50000)
end)

T.test("Snipe.Parse keeps digits in names and takes a trailing bare number as copper", function()
  parse("Recipe: Elixir of Agility 2 1g", "Recipe: Elixir of Agility 2", 10000)
  parse("Recipe: Elixir of Agility 2", "Recipe: Elixir of Agility", 2)
  parse("Rune 7 50s", "Rune 7", 5000)
end)

T.test("Snipe.Parse rejects no name, no price or zero", function()
  T.eq(Sn.Parse("Silk Cloth"), nil)
  T.eq(Sn.Parse("20s"), nil)
  T.eq(Sn.Parse("1g 5s"), nil)
  T.eq(Sn.Parse("Silk Cloth 0"), nil)
  T.eq(Sn.Parse(""), nil)
  T.eq(Sn.Parse(nil), nil)
end)

T.test("Snipe.Set keeps the higher max, Remove deletes, Match is at or below", function()
  local l = {}
  Sn.Set(l, "1:0", "A", 500, 10)
  T.eq(l["1:0"].max, 500) T.eq(l["1:0"].name, "A") T.eq(l["1:0"].at, 10)
  Sn.Set(l, "1:0", "A", 300, 11)
  T.eq(l["1:0"].max, 500)
  Sn.Set(l, "1:0", "A", 800, 12)
  T.eq(l["1:0"].max, 800)
  T.ok(Sn.Match(l, "1:0", 800)) T.ok(Sn.Match(l, "1:0", 1))
  T.ok(not Sn.Match(l, "1:0", 801)) T.ok(not Sn.Match(l, "2:0", 1))
  T.ok(Sn.Remove(l, "1:0")) T.ok(not Sn.Remove(l, "1:0")) T.eq(l["1:0"], nil)
end)

T.test("Deals.FindSnipes matches by unit price, skips own and sorts by profit", function()
  local snapshot = { rows = {
    ["1:0"] = { "1|900||Bob", "5|2500||Cy", "1|100||Me", "1|0||Bob", "2|1100|0|Dee" },
    ["2:0"] = { "1|10||Bob" },
  } }
  local list = { ["1:0"] = { max = 500 } }
  local d = Dl.FindSnipes(snapshot, list, "Me")
  T.eq(table.getn(d), 1)
  T.eq(d[1].type, "snipe") T.eq(d[1].count, 5) T.eq(d[1].buyout, 2500) T.eq(d[1].unit, 500)
  T.eq(d[1].max, 500) T.eq(d[1].owner, "Cy") T.eq(d[1].profit, 0)
  list["1:0"].max = 600
  d = Dl.FindSnipes(snapshot, list, "Me")
  T.eq(table.getn(d), 2)
  T.eq(d[1].count, 5) T.eq(d[1].profit, 500)
  T.eq(d[2].unit, 550) T.eq(d[2].profit, 100)
  T.eq(table.getn(Dl.FindSnipes(snapshot, list, nil)), 3)
  T.eq(table.getn(Dl.FindSnipes(nil, list, "Me")), 0)
  T.eq(table.getn(Dl.FindSnipes(snapshot, {}, "Me")), 0)
end)

T.test("Deals.MergeOnce appends only listings primary lacks", function()
  local a = { { key = "1:0", count = 1, buyout = 100, owner = "Bob", type = "market" } }
  local b = { { key = "1:0", count = 1, buyout = 100, owner = "Bob", type = "snipe" },
              { key = "1:0", count = 1, buyout = 100, owner = "Cy", type = "snipe" },
              { key = "1:0", count = 2, buyout = 100, owner = "Bob", type = "snipe" },
              { key = "1:0", count = 2, buyout = 100, owner = "Bob", type = "snipe" } }
  local r = Dl.MergeOnce(a, b)
  T.eq(r, a)
  T.eq(table.getn(a), 4)
  T.eq(a[1].type, "market") T.eq(a[2].owner, "Cy") T.eq(a[3].count, 2)
  T.eq(table.getn(Dl.MergeOnce({}, nil)), 0)
end)
