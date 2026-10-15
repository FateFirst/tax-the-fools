local D = TaxTheFools.RecipeData and TaxTheFools.RecipeData["Tailoring"]

T.test("recipedata: Tailoring has more than 200 well-formed entries", function()
  T.ok(D)
  local n, turtle = 0, 0
  for id, e in pairs(D) do
    n = n + 1
    T.ok(e.n and e.n ~= "")
    T.ok(type(e.skill) == "number")
    T.ok(type(e.item) == "number")
    local rn = table.getn(e.r)
    T.ok(rn > 0)
    T.eq(math.mod(rn, 2), 0)
    T.ok(type(e.src) == "table")
    if e.turtle then turtle = turtle + 1 end
  end
  T.ok(n > 200)
  T.ok(turtle >= 1)
end)

T.test("recipedata: 3854 Azure Silk Gloves", function()
  local e = D[3854]
  T.eq(e.n, "Azure Silk Gloves") T.eq(e.skill, 145) T.eq(e.item, 4319)
  T.eq(e.pat[1], 7114) T.eq(e.src[1], "vendor")
  T.eq(e.turtle, nil)
end)

T.test("recipedata: sources come from the fixed vocabulary", function()
  local ok = { trainer = true, auto = true, vendor = true, drop = true, quest = true, other = true }
  for id, e in pairs(D) do
    for i = 1, table.getn(e.src) do T.ok(ok[e.src[i]]) end
  end
end)
