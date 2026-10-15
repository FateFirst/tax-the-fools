local A = TaxTheFools
local Mail, Sales, DB, Auction = A.Mail, A.Sales, A.DB, A.Auction

local FORBIDDEN = { "GetInboxText", "GetInboxInvoiceInfo", "TakeInboxMoney", "TakeInboxItem", "DeleteInboxItem", "ReturnInboxItem" }
local function noForbidden(why)
  for _, name in ipairs(FORBIDDEN) do T.eq(T.count(name), 0, (why or "") .. " " .. name) end
end

-- One frame: the OnUpdate script runs once.
local function frame()
  WoW.clock = WoW.clock + 0.1
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
end

local function known()
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  WoW.now = WoW.now + 1800          -- mid-hour, so the arrival hour is not on a floor() boundary
end

local function sold(money, daysLeft) return { subject = "Auction successful: Linen Cloth", money = money, daysLeft = daysLeft or 29.5 } end

T.test("the module is loaded and the events are registered", function()
  T.ok(Mail)
  T.ok(TaxTheFoolsCore.events.MAIL_SHOW) T.ok(TaxTheFoolsCore.events.MAIL_INBOX_UPDATE)
end)

T.test("a sold, expired and cancelled mail are recorded; won and outbid are kept for history", function()
  known()
  WoW.mail = { sold(950), { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20 },
               { subject = "Auction cancelled: Linen Cloth", money = 0, daysLeft = 21 },
               { subject = "Auction won: Linen Cloth", money = 0, daysLeft = 22, hasItem = 1 },
               { subject = "Outbid on Linen Cloth", money = 500, daysLeft = 23 },
               { subject = "Hello friend", money = 5, daysLeft = 24 } }
  WoW.fire("MAIL_SHOW")
  frame()
  local c = DB.Char()
  T.eq(table.getn(c.sales), 5, "five auction mails, not the friend's")
  local out = {}
  for _, e in ipairs(c.sales) do out[e.outcome] = e end
  T.eq(out.sold.money, 950) T.eq(out.sold.key, "100:0") T.eq(out.sold.at, WoW.now)
  T.ok(out.expired and out.cancelled and out.won and out.outbid)
  noForbidden("reading")
end)

T.test("a posting matched by a sold mail is consumed with qty and secs", function()
  known()
  local c = DB.Char()
  c.postings = { { key = "100:0", stack = 20, bid = 900, buyout = 1000, at = WoW.now - 3600 } }
  WoW.mail = { sold(950) }
  WoW.fire("MAIL_INBOX_UPDATE")
  frame()
  T.eq(c.sales[1].qty, 20) T.eq(c.sales[1].secs, 3600) T.eq(c.postings[1].done, "sold")
end)

T.test("a burst of update events gives one read per frame (Review Focus 4)", function()
  known()
  WoW.mail = {}
  for i = 1, 50 do table.insert(WoW.mail, { subject = "Auction successful: Linen Cloth", money = 100 + i, daysLeft = 29.5 }) end
  WoW.fire("MAIL_SHOW")
  for _ = 1, 30 do WoW.fire("MAIL_INBOX_UPDATE") end
  T.eq(T.count("GetInboxNumItems"), 0, "nothing is read inside the events")
  frame()
  T.eq(T.count("GetInboxNumItems"), 1, "one read")
  T.eq(T.count("GetInboxHeaderInfo"), 50, "each header once")
  frame() frame()
  T.eq(T.count("GetInboxNumItems"), 1, "no more reads without a new event")
  T.eq(table.getn(DB.Char().sales), 50)
  WoW.fire("MAIL_INBOX_UPDATE") WoW.fire("MAIL_INBOX_UPDATE")
  frame()
  T.eq(T.count("GetInboxNumItems"), 2, "a new burst is one more read")
  T.eq(table.getn(DB.Char().sales), 50, "and records nothing again")
  noForbidden("50 mails")
end)

T.test("the same mail on two visits, and after a relog, is recorded once (Review Focus 1)", function()
  known()
  WoW.mail = { sold(950, 29.5) }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(DB.Char().sales), 1)
  -- closed and reopened an hour later: daysLeft has dropped by an hour, time has moved on
  WoW.now = WoW.now + 3600
  WoW.mail = { sold(950, 29.5 - 1 / 24) }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(DB.Char().sales), 1, "second visit")
  -- a relog: the module state is reset, the saved character stays
  A.Core.ResetState()
  if Mail.ResetState then Mail.ResetState() end
  A.Core.Init()
  WoW.now = WoW.now + 7200
  WoW.mail = { sold(950, 29.5 - 3 / 24) }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(DB.Char().sales), 1, "after a relog")
  -- a different sale of the same item (other money) is new
  WoW.mail = { sold(950, 29.5 - 3 / 24), sold(1900, 29.0) }
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 2)
end)

T.test("the dedup key is subject|money|arrival hour (time + daysLeft, constant while the mail waits) in char.seenMail", function()
  known()
  WoW.mail = { sold(950, 29.5) }
  WoW.fire("MAIL_SHOW") frame()
  local want = "Auction successful: Linen Cloth|950|" .. math.floor((time() + 29.5 * 86400) / 3600)
  T.eq(DB.Char().seenMail[want], time())
end)

T.test("mail does nothing before the first frame and when the inbox is empty", function()
  WoW.fire("MAIL_SHOW") frame()
  T.eq(DB.Char().sales, nil)
  noForbidden("empty")
end)

T.test("the live sold message puts a note on the strip and records nothing", function()
  WoW.fire("CHAT_MSG_SYSTEM", "Your auction of Linen Cloth sold.")
  T.ok(Auction.note, "a note")
  T.eq(Auction.note.text, "Sold: Linen Cloth")
  T.ok(T.calledWith("Sold: Linen Cloth"))
  T.eq(DB.Char().sales, nil)
  Auction.note = nil
  WoW.fire("CHAT_MSG_SYSTEM", "Your auction of Linen Cloth expired.")
  WoW.fire("CHAT_MSG_SYSTEM", "Something else")
  T.eq(Auction.note, nil, "other system messages leave no note")
end)

T.test("the sold note also reaches a sold-format with the name in the middle", function()
  local keep = ERR_AUCTION_SOLD_S
  ERR_AUCTION_SOLD_S = "[Sold] %s (done)."
  WoW.fire("CHAT_MSG_SYSTEM", "[Sold] Potion of (Fire)? (done).")
  ERR_AUCTION_SOLD_S = keep
  T.eq(Auction.note.text, "Sold: Potion of (Fire)?")
end)

T.test("login prunes old sales through Safe", function()
  local c = DB.Char()
  c.sales = { { key = "100:0", outcome = "sold", money = 1, at = WoW.now - 200 * 86400 }, { key = "100:0", outcome = "sold", money = 1, at = WoW.now } }
  c.seenMail = { old = WoW.now - 200 * 86400, new = WoW.now }
  A.Core.Init()
  T.eq(table.getn(c.sales), 1) T.eq(c.seenMail.old, nil) T.eq(c.seenMail.new, WoW.now)
end)

T.test("reading the owner list reconciles your auctions into postings", function()
  local c = DB.Char()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 4000, minBid = 3600, owner = WoW.player })
  A.UI.CreateAH()
  local p = A.AuctionsUI.frame or A.AuctionsUI.Build(A.UI.ah.body)
  p:Refresh()
  WoW.ownerRespond()
  T.eq(table.getn(c.postings), 1)
  T.eq(c.postings[1].stack, 20) T.eq(c.postings[1].buyout, 4000) T.eq(c.postings[1].reconciled, true)
  p:Refresh()
  WoW.ownerRespond()
  T.eq(table.getn(c.postings), 1, "a second read adds nothing")
end)

T.test("a mail error switches mail off without throwing", function()
  local keep = GetInboxNumItems
  GetInboxNumItems = function() error("boom") end
  WoW.fire("MAIL_SHOW")
  frame()
  GetInboxNumItems = keep
  T.ok(T.calledWith("mail stopped after an error"))
  frame()
end)
