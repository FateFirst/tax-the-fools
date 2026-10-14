local A = TaxTheFools
local Inv, DB, C = A.Inventory, A.DB, A.Craft

local function tick() WoW.runScript(TaxTheFoolsCore, "OnUpdate") end

T.test("bags 0 to 4 are counted per item key, stacks added together", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20 }, {}, { id = 4306, name = "Silk Cloth", count = 17 } }
  WoW.bags[4] = { { id = 2321, name = "Fine Thread", count = 5 } }
  WoW.fire("BAG_UPDATE", 0)
  tick()
  local c = DB.Char()
  T.eq(c.bags["4306:0"], 37, "20 + 17")
  T.eq(c.bags["2321:0"], 5)
  T.eq(c.bagsAt, WoW.now)
end)

T.test("a burst of bag updates is counted at most once a second", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20 } }
  WoW.fire("BAG_UPDATE", 0)
  tick()
  T.eq(DB.Char().bags["4306:0"], 20)
  WoW.bags[0][1].count = 10
  WoW.fire("BAG_UPDATE", 0)
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(DB.Char().bags["4306:0"], 20, "half a second later: not yet")
  WoW.clock = WoW.clock + 0.5
  tick()
  T.eq(DB.Char().bags["4306:0"], 10, "a second later: counted")
end)

T.test("the bank is recorded only while it is open", function()
  WoW.bags[-1] = { { id = 4306, name = "Silk Cloth", count = 100 } }
  WoW.bags[5] = { { id = 4306, name = "Silk Cloth", count = 20 }, { id = 4339, name = "Bolt of Mageweave", count = 3 } }
  Inv.ScanBank()
  T.eq(DB.Char().bank, nil, "closed: nothing read")
  WoW.bankOpen = true
  WoW.fire("BANKFRAME_OPENED")
  T.eq(DB.Char().bank["4306:0"], 120, "100 in the bank slots + 20 in bank bag 5")
  T.eq(DB.Char().bank["4339:0"], 3)
  T.eq(DB.Char().bags, nil, "bank items are not counted as carried")
  WoW.fire("BANKFRAME_CLOSED")
  WoW.bankOpen = false
  WoW.fire("BAG_UPDATE", 0)
  WoW.clock = WoW.clock + 2
  tick()
  T.eq(DB.Char().bank["4306:0"], 120, "a bag update after closing leaves the bank record alone")
end)

T.test("changes while the bank is open are recorded", function()
  WoW.bankOpen = true
  WoW.bags[-1] = { { id = 4306, name = "Silk Cloth", count = 100 } }
  WoW.fire("BANKFRAME_OPENED")
  WoW.bags[-1][1].count = 60
  WoW.fire("PLAYERBANKSLOTS_CHANGED")
  WoW.clock = WoW.clock + 2
  tick()
  T.eq(DB.Char().bank["4306:0"], 60)
end)

T.test("holdings add up bags and bank across every character", function()
  local chars = DB.Realm().chars
  chars.Bankalt = { bags = { ["4306:0"] = 3 }, bank = { ["4306:0"] = 100, ["2321:0"] = 2 } }
  chars.Tailor = { bags = { ["4306:0"] = 7 } }
  chars.Empty = {}
  local held = Inv.Held(DB.Realm())
  T.eq(held["4306:0"], 110, "3 + 100 + 7")
  T.eq(held["2321:0"], 2)
end)

T.test("cash profit counts what two characters hold between them", function()
  local realm = DB.Realm()
  realm.market["4306:0"] = { v = 300 }
  realm.market["4305:0"] = { v = 2000 }
  realm.chars.Bankalt = { bank = { ["4306:0"] = 1 } }
  realm.chars.Tailor = { bags = { ["4306:0"] = 2 }, professions = { Tailoring = { recipes = {} } } }
  local bolt = { item = "4305:0", reagents = { { item = "4306:0", count = 4 } } }
  local ev = C.Evaluate(bolt, C.Context(realm, TaxTheFoolsDB.items, Inv.Held(realm), 20375))
  T.eq(ev.lines[1].have, 3, "1 + 2")
  T.near(ev.cash, 1600, 0.001, "2000 x 0.95 - (4 - 3) x 300")
end)

T.test("bags are counted at login", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 4 } }
  WoW.fire("PLAYER_ENTERING_WORLD")
  tick()
  T.eq(DB.Char().bags["4306:0"], 4)
end)
