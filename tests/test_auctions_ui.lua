local A = TaxTheFools
local UI, AH, Scan, DB, Auction, AU, Confirm = A.UI, A.AH, A.Scan, A.DB, A.Auction, A.AuctionsUI, A.Confirm

local function tok(_, b) return b end
local function page()
  UI.CreateAH()
  local p = AU.frame
  if not p then p = AU.Build(UI.ah.body) end
  p.list:SetHeight(300)
  return p
end

-- Your auctions on the server; the page asks and the fake server answers.
local function owned(listings)
  for _, l in ipairs(listings) do
    l.owner = WoW.player
    table.insert(WoW.ah.listings, l)
  end
  local p = page()
  p:Refresh()
  WoW.ownerRespond()
  return p
end

local function theirs(id, name, count, buyout, owner)
  table.insert(WoW.ah.listings, { id = id, name = name, count = count, buyout = buyout, owner = owner or "Rival" })
end

local function snapshot(rows)
  DB.Realm().snapshot = { at = time(), day = A.Util.day(time()), rows = rows }
end

T.test("the builder is registered", function()
  T.ok(UI.builders.auctions)
end)

T.test("opening the page requests the owner list, and the update event fills the rows", function()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, owner = WoW.player })
  local p = page()
  p:Refresh()
  T.eq(T.count("GetOwnerAuctionItems"), 1)
  T.ok(T.calledWith("GetOwnerAuctionItems 0"))
  WoW.ownerRespond()
  T.eq(table.getn(p.list.data), 1)
  local r = p.list.data[1]
  T.eq(r.name, "Runecloth") T.eq(r.count, 20) T.eq(r.buyout, 4000) T.eq(r.minBid, 3600)
  T.eq(r.timeText, "long")
  T.eq(p.summary:GetText(), "1 active auction")
end)

T.test("the owner update event goes through Core.Safe", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  T.eq(table.getn(p.list.data), 1)
  A.Core.disabled = {}
  local was = AU.Read
  AU.Read = function() error("boom") end
  WoW.fire("AUCTION_OWNED_LIST_UPDATE")
  AU.Read = was
  T.ok(A.Core.disabled["auctions"], "an error stops only the auctions part")
  A.Core.disabled = {}
end)

T.test("summary counts active auctions", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 },
                    { id = 14047, name = "Runecloth", count = 10, buyout = 2500 } })
  T.eq(p.summary:GetText(), "2 active auctions")
end)

T.test("time left 1 to 4 reads short, medium, long, very long", function()
  T.eq(AU.TimeText(1), "short") T.eq(AU.TimeText(2), "medium")
  T.eq(AU.TimeText(3), "long") T.eq(AU.TimeText(4), "very long")
end)

T.test("status: undercut shows the cheaper price in red", function()
  -- mine: 20 for 4000 = 200 each; theirs: 10 for 1500 = 150 each (browse rows).
  theirs(14047, "Runecloth", 10, 1500)
  Scan.Browse("Runecloth", 0, WoW.clock)
  for _ = 1, 40 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then break end
  end
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  local r = p.list.data[1]
  T.eq(r.status, "undercut")
  T.near(r.rival, 150, 0.001)
  T.ok(string.find(AU.COLUMNS[6].fmt(r), A.Util.money(150), 1, true), "shows their price")
  T.eq(tok(AU.COLUMNS[6].fmt(r)), "bad")
end)

T.test("status: cheapest reads green, from the snapshot", function()
  snapshot({ ["14047:0"] = { "10|3000|0|Rival" } })      -- 300 each
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  local r = p.list.data[1]
  T.eq(r.status, "cheapest")
  T.eq(tok(AU.COLUMNS[6].fmt(r)), "good")
end)

T.test("status: no competition reads dim, and your own listings do not count", function()
  snapshot({ ["14047:0"] = { "20|1000|0|" .. WoW.player } })
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  local r = p.list.data[1]
  T.eq(r.status, "none")
  T.eq(tok(AU.COLUMNS[6].fmt(r)), "dim")
end)

T.test("the Cancel button cancels the selected row once when there is no bid", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  T.eq(p.cancelBtn.enabled, false, "nothing selected")
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.cancelBtn.enabled, true)
  WoW.runScript(p.cancelBtn, "OnClick")
  T.eq(T.count("CancelAuction"), 1)
  T.ok(T.calledWith("CancelAuction 1"))
  WoW.runScript(p.cancelBtn, "OnClick")
  T.eq(T.count("CancelAuction"), 1, "locked while waiting")
end)

T.test("Cancel with a bid confirms first", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, bid = 3700 } })
  WoW.runScript(p.list.rows[1], "OnClick")
  WoW.runScript(p.cancelBtn, "OnClick")
  T.eq(T.count("CancelAuction"), 0)
  T.ok(Confirm.frame:IsShown())
  WoW.runScript(Confirm.frame.buy, "OnClick")
  T.eq(T.count("CancelAuction"), 1)
end)

T.test("the list is re-requested after a cancel and the row goes", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  WoW.runScript(p.list.rows[1], "OnClick")
  WoW.runScript(p.cancelBtn, "OnClick")
  local before = T.count("GetOwnerAuctionItems")
  WoW.cancelRespond()
  T.eq(T.count("GetOwnerAuctionItems"), before + 1)
  WoW.ownerRespond()
  T.eq(table.getn(p.list.data), 0)
  T.eq(p.summary:GetText(), "0 active auctions")
end)

T.test("opening the tab and selecting rows never cancels", function()
  local p = owned({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000 } })
  p:Refresh()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(T.count("CancelAuction"), 0)
end)
