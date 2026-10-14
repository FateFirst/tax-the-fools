local I = TaxTheFools.Items

T.test("resolve fills a record from what the client knows", function()
  WoW.items[4306] = { name = "Silk Cloth", quality = 1, stack = 20 }
  local rec = I.Resolve(4306)
  T.eq(rec.n, "Silk Cloth") T.eq(rec.st, 20) T.eq(rec.q, 1)
  T.eq(TaxTheFoolsDB.items[4306], rec, "kept account-wide")
end)

T.test("an uncached item is asked for once through the scan tooltip", function()
  T.eq(I.Resolve(5000), nil)
  I.Resolve(5000)
  T.eq(T.count("SetHyperlink TaxTheFoolsScanTip item:5000:0:0:0"), 1)
  T.eq(I.Name(5000), "Unknown item #5000")
end)

T.test("with ClassicAPI the request goes through it instead", function()
  WoW.classicAPI(true)
  I.Resolve(5001)
  T.ok(T.calledWith("RequestLoadItemDataByID 5001"))
  T.ok(not T.calledWith("SetHyperlink"), "no tooltip trick needed")
end)

T.test("vendor prices learned at a merchant are stored per unit", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 }, {}, { id = 14047, name = "Runecloth", count = 1, vendor = 100 } }
  WoW.merchantOpen = true
  I.LearnVendorPrices()
  T.eq(I.Vendor(4306), 37)
  T.eq(I.Vendor(14047), 100)
end)

T.test("without a merchant nothing is learned", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 } }
  I.LearnVendorPrices()
  T.eq(I.Vendor(4306), nil)
end)

T.test("ClassicAPI supplies vendor prices never seen at a merchant", function()
  WoW.classicAPI(true)
  WoW.items[2589] = { name = "Linen Cloth", vendor = 13 }
  T.eq(I.Vendor(2589), 13)
  T.eq(TaxTheFoolsDB.items[2589].v, 13, "remembered")
end)

T.test("find by name ignores case", function()
  I.Remember(4306, "Silk Cloth")
  T.eq(I.FindByName("silk cloth"), 4306)
  T.eq(I.FindByName("Mageweave"), nil)
end)
