local A = TaxTheFools
local Auction, Scan, DB, Mailbox, LH = A.Auction, A.Scan, A.DB, A.Mailbox, A.LedgerHooks

-- Phase 6 spec section 3: the recording hooks. They only record; they make no game action call.

local function frame()
  WoW.clock = WoW.clock + 0.1
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
end
local function pump()
  for _ = 1, 60 do
    if not Mailbox.busy then return end
    frame()
  end
end
local function fresh()
  DB.Char().ledger = nil
  DB.Char().pendingBids = {}
  DB.Char().sales = {}
  DB.Char().seenMail = {}
  DB.S().ledger.vendor = true
  WoW.fire("MERCHANT_CLOSED")
end
local function led() return DB.Char().ledger or {} end
local function kinds()
  local t = {}
  for _, e in ipairs(led()) do table.insert(t, e.kind .. ":" .. e.amount) end
  return table.concat(t, ",")
end
local function page(listings)
  for _, l in ipairs(listings) do table.insert(WoW.ah.listings, l) end
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
end
local function sig(i) return Auction.Sig(Scan.ReadRow(i)) end
local function stock()
  WoW.items[14047] = { name = "Runecloth", stack = 20, vendor = 100 }
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20, vendor = 100 }, {}, {} }
  TaxTheFoolsDB.items[14047] = { v = 100, n = "Runecloth" }
end

T.test("the hooks table is loaded and MERCHANT_CLOSED is registered", function()
  T.ok(LH) T.ok(TaxTheFoolsCore.events.MERCHANT_CLOSED)
end)

-- ---------- auction ----------

T.test("a buy adds a buy entry with the buyout, key and count", function()
  fresh()
  WoW.money = 10000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, owner = "Sel" } })
  T.eq(Auction.Buy(1, sig(1)), true)
  T.eq(table.getn(led()), 0, "nothing until the reply")
  WoW.bidRespond()
  T.eq(kinds(), "buy:4000")
  T.eq(led()[1].key, "14047:0") T.eq(led()[1].qty, 20)
end)

T.test("a failed buy records nothing", function()
  fresh()
  WoW.money = 10000
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 4000, owner = "Sel" } })
  WoW.ah.bidReply = "money"
  Auction.Buy(1, sig(1))
  WoW.bidRespond()
  T.eq(table.getn(led()), 0)
  WoW.ah.bidReply = "auto"
end)

T.test("a bid is pending, then a won mail makes the bid entry; an outbid mail removes it", function()
  fresh()
  WoW.money = 10000
  TaxTheFoolsDB.items[14047] = { n = "Runecloth" }
  page({ { id = 14047, name = "Runecloth", count = 20, buyout = 9000, minBid = 3000, owner = "Sel" } })
  T.eq(Auction.Bid(1, sig(1)), true)
  WoW.bidRespond()
  T.eq(table.getn(led()), 0, "a bid is not spending")
  T.eq(table.getn(DB.Char().pendingBids), 1)
  T.eq(DB.Char().pendingBids[1].name, "Runecloth") T.eq(DB.Char().pendingBids[1].amount, 3000)
  WoW.mail = { { subject = "Auction won: Runecloth", money = 0, daysLeft = 29.5, hasItem = 1 } }
  WoW.now = WoW.now + 1800
  WoW.fire("MAIL_SHOW") frame()
  T.eq(kinds(), "bid:3000")
  T.eq(led()[1].key, "14047:0")
  T.eq(table.getn(DB.Char().pendingBids), 0)
  -- outbid
  A.Ledger.PendingBid(DB.Char(), "Runecloth", 500, WoW.now, "14047:0")
  WoW.mail = { { subject = "Outbid on Runecloth", money = 500, daysLeft = 28.5 } }
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().pendingBids), 0)
  T.eq(kinds(), "bid:3000", "no spending for an outbid")
end)

T.test("a post's deposit is the money actually paid", function()
  fresh() stock() WoW.money = 100000
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  T.eq(kinds(), "deposit:720")
  T.eq(led()[1].key, "14047:0") T.eq(led()[1].qty, 20)
end)

T.test("a late money change records the actual deposit once", function()
  fresh() stock() WoW.money = 100000
  WoW.ah.moneyLate = true
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  T.eq(table.getn(led()), 0, "unknown at the reply")
  WoW.clock = WoW.clock + 1
  WoW.moneyArrive()
  T.eq(kinds(), "deposit:720")
  WoW.money = WoW.money - 5000
  WoW.fire("PLAYER_MONEY")
  frame()
  T.eq(kinds(), "deposit:720", "never twice")
  WoW.ah.moneyLate = false
end)

T.test("a money change that never comes falls back to the preview deposit, once", function()
  fresh() stock() WoW.money = 100000
  WoW.ah.moneyLate = true
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  WoW.clock = WoW.clock + 3.5
  frame()
  T.eq(kinds(), "deposit:1200", "the client's figure")
  WoW.moneyArrive()
  frame()
  T.eq(kinds(), "deposit:1200")
  WoW.ah.moneyLate = false
end)

T.test("a post replaced before its money change records the preview, not nothing", function()
  fresh() stock() WoW.money = 100000
  WoW.ah.moneyLate = true
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  stock() WoW.ah.moneyLate = false
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  T.eq(kinds(), "deposit:1200")
  WoW.postRespond()
  T.eq(kinds(), "deposit:1200,deposit:720")
end)

T.test("a deposit the learner can't believe falls back to the preview", function()
  fresh() stock() WoW.money = 100000
  TaxTheFoolsDB.items[14047] = { v = 100, n = "Runecloth" }
  WoW.ah.depositFactor = 0.01                      -- 12 copper: outside the plausible band
  Auction.Post(0, 1, 20, 100, 200, 480, "14047:0", true)
  WoW.postRespond()
  T.eq(kinds(), "deposit:1200")
  WoW.ah.depositFactor = 0.6
end)

-- ---------- mail ----------

T.test("a sold mail adds a sale entry with the sales entry's money, key and qty", function()
  fresh()
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  DB.Char().postings = { { key = "100:0", stack = 5, buyout = 1000, bid = 900, minutes = 480, at = WoW.now - 3600, deposit = 20 } }
  WoW.now = WoW.now + 1800
  WoW.mail = { { subject = "Auction successful: Linen Cloth", money = 950, daysLeft = 29.5 } }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(kinds(), "sale:950")
  local s = DB.Char().sales[1]
  T.eq(led()[1].key, "100:0") T.eq(led()[1].qty, s.qty) T.eq(led()[1].at, s.at)
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(led()), 1, "the same mail is not recorded again")
end)

T.test("expired and cancelled mail record no ledger entry", function()
  fresh()
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  WoW.now = WoW.now + 1800
  WoW.mail = { { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20, hasItem = 1 } }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(led()), 0)
end)

-- ---------- vendor ----------

T.test("merchant money in and out is recorded while the window is open", function()
  fresh()
  WoW.money = 1000 WoW.fire("PLAYER_MONEY")
  WoW.fire("MERCHANT_SHOW")
  WoW.money = 1300 WoW.fire("PLAYER_MONEY")
  WoW.money = 1100 WoW.fire("PLAYER_MONEY")
  T.eq(kinds(), "vendorIn:300,vendorOut:200")
  WoW.fire("MERCHANT_CLOSED")
  WoW.money = 5000 WoW.fire("PLAYER_MONEY")
  T.eq(kinds(), "vendorIn:300,vendorOut:200", "closed: nothing")
end)

T.test("with settings.ledger.vendor off nothing is recorded", function()
  fresh()
  DB.S().ledger.vendor = false
  WoW.money = 1000 WoW.fire("PLAYER_MONEY")
  WoW.fire("MERCHANT_SHOW")
  WoW.money = 1300 WoW.fire("PLAYER_MONEY")
  T.eq(table.getn(led()), 0)
  DB.S().ledger.vendor = true
end)

T.test("money changed before the merchant opened is not counted when it opens", function()
  fresh()
  WoW.money = 1000 WoW.fire("PLAYER_MONEY")
  WoW.money = 4000                                  -- no PLAYER_MONEY seen
  WoW.fire("MERCHANT_SHOW")
  WoW.money = 4100 WoW.fire("PLAYER_MONEY")
  T.eq(kinds(), "vendorIn:100")
end)

-- ---------- mailbox ----------

local function setup()
  fresh()
  WoW.items[100] = { name = "Linen Cloth", stack = 20 }
  WoW.bags = { [0] = { {}, {}, {}, {} } }
  WoW.money = 1000
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  DB.Realm().chars["Annalt"] = DB.Realm().chars["Annalt"] or {}
  WoW.fire("PLAYER_MONEY")
end

T.test("collected mail money: an alt is a transfer, a stranger is mailIn, AH mail is skipped", function()
  setup()
  WoW.mail = { { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 900, body = "" },
               { sender = "annalt", subject = "gold", money = 70, body = "Hi" },
               { sender = "Stranger", subject = "thanks", money = 50, body = "Hi" } }
  Mailbox.CollectAll()
  pump()
  T.eq(WoW.money, 1000 + 900 + 70 + 50)
  local got = {}
  for _, e in ipairs(led()) do table.insert(got, e.kind .. ":" .. e.amount .. ":" .. (e.who or "")) end
  T.eq(table.concat(got, ","), "sale:900:,transferIn:70:annalt,mailIn:50:Stranger", "AH money is the sale from Mail.Read, not mail")
end)

T.test("a send with money to an alt is a transfer plus postage as mailOut", function()
  setup()
  Mailbox.Send("Annalt", "", "", 500, {})
  pump()
  T.eq(table.getn(WoW.sent), 1)
  T.eq(kinds(), "transferOut:500,mailOut:30")
  T.eq(led()[1].who, "Annalt")
end)

T.test("a send with money to a stranger is mailOut", function()
  setup()
  Mailbox.Send("Stranger", "", "", 200, {})
  pump()
  T.eq(kinds(), "mailOut:200,mailOut:30")
end)

T.test("a send with an item records postage only, and a failed send records nothing", function()
  setup()
  WoW.bags[0][1] = { id = 100, name = "Linen Cloth", count = 5 }
  Mailbox.Send("Stranger", "", "", 0, { { bag = 0, slot = 1, key = "100:0", count = 5 } })
  pump()
  T.eq(kinds(), "mailOut:30")
  setup()
  table.insert(WoW.mailErrors, ERR_MAIL_TARGET_NOT_FOUND)
  Mailbox.Send("Nobody", "", "", 100, {})
  pump()
  T.eq(table.getn(led()), 0)
end)

-- ---------- login ----------

T.test("login prunes old entries and backfills the sold mail once", function()
  fresh()
  local c = DB.Char()
  c.ledgerBackfilled = nil
  c.ledger = { { at = WoW.now - 200 * 86400, kind = "sale", amount = 9 } }
  c.sales = { { outcome = "sold", money = 400, key = "100:0", qty = 2, at = WoW.now - 86400 },
              { outcome = "expired", money = 0, at = WoW.now } }
  A.Core.Init()
  T.eq(kinds(), "sale:400")
  A.Core.Init()
  T.eq(kinds(), "sale:400", "once")
end)

-- ---------- automation guard ----------

T.test("the hooks make no game action call", function()
  setup()
  WoW.calls = {}
  LH.Buy({ amount = 5, key = "1:0", count = 1 })
  LH.Deposit({ key = "1:0", count = 1 }, 5)
  LH.Take({ sender = "x", subject = "y", money = 5 })
  LH.Sent({ to = "x", mailMoney = 5, postage = 1 })
  LH.MerchantShow() LH.OnMoney() LH.MerchantClosed()
  T.eq(table.getn(WoW.calls), 0)
end)
