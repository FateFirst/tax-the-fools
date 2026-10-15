local A = TaxTheFools
local Mail, Sales, DB, Auction = A.Mail, A.Sales, A.DB, A.Auction

-- Phase 5b spec section 1: these are never called without a click on a Mailbox action. Header reading,
-- events and ticks (everything in this file) never call them; GetInboxInvoiceInfo is never called at all.
local FORBIDDEN = { "GetInboxText", "GetInboxInvoiceInfo", "TakeInboxMoney", "TakeInboxItem", "DeleteInboxItem", "ReturnInboxItem",
                    "SendMail", "ClickSendMailItemButton", "SetSendMailMoney", "CheckInbox" }
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
  WoW.mail = { sold(950), { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20, hasItem = 1 },
               { subject = "Auction cancelled: Linen Cloth", money = 0, daysLeft = 21, hasItem = 1 },
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

T.test("an AH mail is recorded only while it holds its payload; an emptied one never is", function()
  known()
  WoW.mail = { sold(0), { subject = "Outbid on Linen Cloth", money = 0, daysLeft = 23 },
               { subject = "Auction won: Linen Cloth", money = 0, daysLeft = 22 },
               { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20 },
               { subject = "Auction cancelled: Linen Cloth", money = 0, daysLeft = 21 } }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(DB.Char().sales, nil, "nothing recorded")
  T.eq(next(DB.Char().seenMail or {}), nil, "nothing marked seen")
  WoW.mail = { sold(950), { subject = "Outbid on Linen Cloth", money = 500, daysLeft = 23 },
               { subject = "Auction won: Linen Cloth", money = 0, daysLeft = 22, hasItem = 1 },
               { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20, hasItem = 1 },
               { subject = "Auction cancelled: Linen Cloth", money = 0, daysLeft = 21, hasItem = 1 } }
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 5)
  -- the same mails once emptied (money taken, item taken) record nothing more
  WoW.mail = { sold(0), { subject = "Outbid on Linen Cloth", money = 0, daysLeft = 23 },
               { subject = "Auction won: Linen Cloth", money = 0, daysLeft = 22 },
               { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20 },
               { subject = "Auction cancelled: Linen Cloth", money = 0, daysLeft = 21 } }
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 5)
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
  local oldWindow = TaxTheFools.MailHook.window
  TaxTheFools.MailHook.window = nil   -- our mail window paints too (test_mail_ui counts that), so keep it closed
  TaxTheFools.MailUI.win.shown = false
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
  TaxTheFools.MailHook.window = oldWindow
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
  -- seenMail[key] is { at = time first recorded, n = how many such mails are recorded } (C1)
  T.eq(DB.Char().seenMail[want].at, time()) T.eq(DB.Char().seenMail[want].n, 1)
end)

local function expired() return { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20, hasItem = 1 } end

T.test("identical mails are each recorded: 5 expired and 3 sold, once, and a later identical one adds one (C1)", function()
  known()
  WoW.mail = {}
  for _ = 1, 5 do table.insert(WoW.mail, expired()) end
  for _ = 1, 3 do table.insert(WoW.mail, sold(950)) end
  WoW.fire("MAIL_SHOW") frame()
  local c = DB.Char()
  local nE, nS = 0, 0
  for _, e in ipairs(c.sales) do
    if e.outcome == "expired" then nE = nE + 1 elseif e.outcome == "sold" then nS = nS + 1 end
  end
  T.eq(nE, 5, "five expired") T.eq(nS, 3, "three sold") T.eq(table.getn(c.sales), 8)
  -- a second visit (an hour on, daysLeft an hour lower) records nothing
  WoW.now = WoW.now + 3600
  WoW.mail = {}
  for _ = 1, 5 do table.insert(WoW.mail, { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 20 - 1 / 24, hasItem = 1 }) end
  for _ = 1, 3 do table.insert(WoW.mail, sold(950, 29.5 - 1 / 24)) end
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 8, "second visit")
  -- one more identical sold mail arrives: one more is recorded
  table.insert(WoW.mail, sold(950, 29.5 - 1 / 24))
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 9, "the fourth sold mail")
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 9)
end)

T.test("identical sold mails each consume a posting (C1)", function()
  known()
  local c = DB.Char()
  c.postings = { { key = "100:0", stack = 20, bid = 900, buyout = 1000, at = WoW.now - 3600 },
                 { key = "100:0", stack = 20, bid = 900, buyout = 1000, at = WoW.now - 1800 } }
  WoW.mail = { sold(950), sold(950) }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(c.sales), 2) T.eq(c.postings[1].done, "sold") T.eq(c.postings[2].done, "sold")
end)

T.test("old-format seenMail entries (a number) read as one recorded mail (C1)", function()
  known()
  WoW.mail = { sold(950, 29.5), sold(950, 29.5) }
  local key = "Auction successful: Linen Cloth|950|" .. math.floor((time() + 29.5 * 86400) / 3600)
  DB.Char().seenMail = { [key] = time() - 100 }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(DB.Char().sales), 1, "two mails, one already recorded")
  T.eq(DB.Char().seenMail[key].n, 2)
end)

T.test("an expiry within 5 s of an hour boundary does not count twice when the hour flips (C1)", function()
  -- WoW.now + daysLeft*86400 lands 2 s before a boundary on the first read and 2 s after on the second.
  local H = 3600
  local boundary = (math.floor(WoW.now / H) + 1000) * H
  WoW.now = boundary - 2 - 29 * 86400
  WoW.mail = { { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 29, hasItem = 1 }, { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 29, hasItem = 1 } }
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(table.getn(DB.Char().sales), 2, "recorded in hour h-1")
  WoW.now = WoW.now + 4              -- the same mails, now keyed to hour h
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 2, "no double count")
  WoW.now = WoW.now - 4              -- and back again
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 2, "still none")
  table.insert(WoW.mail, { subject = "Auction expired: Linen Cloth", money = 0, daysLeft = 29, hasItem = 1 })
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(DB.Char().sales), 3, "a genuinely new one still counts")
end)

T.test("a reconciled posting matches a sold mail through the learned, then the estimated deposit (I1)", function()
  known()
  local c = DB.Char()
  -- Learned: minutes 480 deposit 50 for a stack of 20 (maxStack 20, no surcharge): money = floor(2000 * 0.95) + 50 = 1950.
  A.Sell.LearnDeposit(TaxTheFoolsDB.items, 100, 480, 50, 20, 20)
  TaxTheFoolsDB.items[100].st = 20
  c.postings = { { key = "100:0", stack = 20, buyout = 2000, bid = 1800, at = WoW.now - 100, reconciled = true } }
  WoW.mail = { sold(1950) }
  WoW.fire("MAIL_SHOW") frame()
  T.eq(c.sales[1].qty, 20, "learned deposit")
  -- Estimated: vendor 40 per unit, stack 20 of 20, 480 minutes: floor(40 * 20 * 4 * 1 * 0.025) = 80, so 1900 + 80 = 1980.
  -- Money 2010 is 30 off, within 1 + floor(80 * 0.5) = 41.
  TaxTheFoolsDB.items[100].dep = nil
  TaxTheFoolsDB.items[100].v = 40
  c.postings = { { key = "100:0", stack = 20, buyout = 2000, bid = 1800, at = WoW.now - 100, reconciled = true } }
  WoW.mail = { sold(1950), sold(2010) }          -- the 1950 mail is already recorded
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 2) T.eq(c.sales[2].money, 2010) T.eq(c.sales[2].qty, 20, "estimated deposit")
end)

T.test("a sale whose item name is not cached is not marked seen and is retried once it is (M1)", function()
  WoW.now = WoW.now + 1800
  WoW.mail = { sold(950), { subject = "Auction won: Mystery", money = 0, daysLeft = 22, hasItem = 1 } }
  WoW.fire("MAIL_SHOW") frame()
  local c = DB.Char()
  T.eq(table.getn(c.sales), 1, "only the won mail")
  T.eq(c.sales[1].outcome, "won")
  T.eq(c.seenMail["Auction successful: Linen Cloth|950|" .. math.floor((time() + 29.5 * 86400) / 3600)], nil, "not marked seen")
  TaxTheFoolsDB.items[100] = { n = "Linen Cloth" }
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 2) T.eq(c.sales[2].outcome, "sold") T.eq(c.sales[2].key, "100:0")
  WoW.fire("MAIL_INBOX_UPDATE") frame()
  T.eq(table.getn(c.sales), 2, "and then once")
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
