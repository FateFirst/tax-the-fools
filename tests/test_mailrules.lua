local A = TaxTheFools
local R = A.MailRules

local function h(t) return t end

T.test("Plan skips COD and GM mail even when it holds money", function()
  T.eq(R.Plan(h{ sender = "Bob", subject = "x", money = 5, cod = 100, hasItem = true }), "skip")
  T.eq(R.Plan(h{ sender = "GM", subject = "x", money = 5, isGM = true }), "skip")
  T.eq(R.Plan(h{ sender = "Auction House", subject = "Auction successful: Linen", money = 5, cod = 1 }), "skip")
end)

T.test("Plan skips a mail with nothing to take unless it is AH mail", function()
  T.eq(R.Plan(h{ sender = "Bob", subject = "hi", money = 0, body = "text" }), "skip")
  T.eq(R.Plan(h{ sender = "Auction House", subject = "Outbid on Linen", money = 0 }), "take+delete")
  T.eq(R.Plan(h{ sender = "Bob", subject = "Auction expired: Linen", money = 0 }), "take+delete")
end)

T.test("Plan takes and deletes AH mail and mail with an empty body", function()
  T.eq(R.Plan(h{ sender = "Auction House", subject = "Auction successful: Linen", money = 900, body = "Sold." }), "take+delete")
  T.eq(R.Plan(h{ sender = "Bob", subject = "gift", hasItem = true, body = "" }), "take+delete")
  T.eq(R.Plan(h{ sender = "Bob", subject = "gift", money = 10 }), "take+delete")   -- body not read yet
end)

T.test("Plan only takes a player's letter, which keeps its text", function()
  T.eq(R.Plan(h{ sender = "Bob", subject = "hello", money = 10, hasItem = true, body = "Hi there" }), "take")
end)

local function item(key, name, ty, auc) return { key = key, name = name, type = ty, auctionable = auc } end
local ON = { crafted = true, tradeGoods = true, patterns = true, auctionable = true }
local ctx = { products = { ["id:1"] = true } }

T.test("Matches: each rule on its own", function()
  T.ok(R.Matches(item("id:1", "Bolt", "Cloth", true), { crafted = true }, {}, ctx), "crafted")
  T.ok(not R.Matches(item("id:2", "Bolt", "Cloth", true), { crafted = true }, {}, ctx), "not a product")
  T.ok(R.Matches(item("id:2", "Linen", "Trade Goods", true), { tradeGoods = true }, {}, ctx), "trade goods")
  T.ok(not R.Matches(item("id:2", "Sword", "Weapon", true), { tradeGoods = true }, {}, ctx), "weapon")
  T.ok(R.Matches(item("id:3", "Pattern: Cape", "Recipe", true), { patterns = true }, {}, ctx), "pattern")
  T.ok(R.Matches(item("id:4", "Sword", "Weapon", true), { auctionable = true }, {}, ctx), "anything")
  T.ok(not R.Matches(item("id:4", "Sword", "Weapon", true), {}, {}, ctx), "no rule ticked")
end)

T.test("Matches: keep list and unauctionable always win", function()
  T.ok(not R.Matches(item("id:1", "Bolt", "Trade Goods", true), ON, { ["id:1"] = true }, ctx), "kept")
  T.ok(not R.Matches(item("id:5", "Soulbound", "Trade Goods", false), ON, {}, ctx), "unauctionable")
end)

T.test("Matches tolerates a missing ctx and keep", function()
  T.ok(R.Matches(item("id:2", "Linen", "Trade Goods", true), { tradeGoods = true }, nil, nil))
  T.ok(not R.Matches(item("id:1", "Bolt", "Cloth", true), { crafted = true }, nil, nil))
end)

T.test("Subject and Postage", function()
  T.eq(R.Subject("Bolt of Linen", 1), "Bolt of Linen")
  T.eq(R.Subject("Bolt of Linen", 20), "Bolt of Linen (20)")
  T.eq(R.Postage(30, 3), 90)
  T.eq(R.Postage(30, 0), 30)
end)

T.test("mail defaults exist", function()
  local s = TaxTheFoolsDB.settings
  T.eq(s.replaceBlizzardMail, true)
  T.eq(s.mail.rules.crafted, true)
  T.eq(s.mail.rules.auctionable, false)
  T.ok(type(s.mail.keep) == "table")
end)

-- ---------- fake client mailbox smoke tests ----------
local function bagsWithRoom(free)
  WoW.bags = { [0] = {} }
  for i = 1, free do WoW.bags[0][i] = {} end
end

T.test("stub: take money fires an update and pays the player", function()
  WoW.inbox = { { subject = "s", money = 500 } }
  local n = 0
  local f = CreateFrame("Frame")
  f:RegisterEvent("MAIL_INBOX_UPDATE")
  f:SetScript("OnEvent", function() n = n + 1 end)
  TakeInboxMoney(1)
  T.eq(WoW.money, 500)
  T.eq(WoW.mail[1].money, 0)
  T.eq(n, 1)
  T.eq(T.count("TakeInboxMoney"), 1)
end)

T.test("stub: take item goes to the first free slot, then bags full keeps it", function()
  bagsWithRoom(1)
  WoW.items[7] = { name = "Linen", tex = "T" }
  WoW.inbox = { { subject = "a", item = { id = 7, name = "Linen", count = 5 } }, { subject = "b", item = { id = 8, name = "Silk", count = 1 } } }
  T.eq((GetInboxHeaderInfo(1)) ~= nil, true)
  local _, _, _, _, _, _, _, hasItem = GetInboxHeaderInfo(1)
  T.eq(hasItem, 1)
  TakeInboxItem(1)
  T.eq(WoW.bags[0][1].id, 7)
  T.eq(WoW.bags[0][1].count, 5)
  T.eq(WoW.mail[1].item, nil)
  local err
  local f = CreateFrame("Frame")
  f:RegisterEvent("UI_ERROR_MESSAGE")
  f:SetScript("OnEvent", function() err = arg1 end)
  TakeInboxItem(2)
  T.eq(err, ERR_INV_FULL)
  T.ok(WoW.mail[2].item ~= nil, "kept")
end)

T.test("stub: a unique item already carried is refused", function()
  bagsWithRoom(2)
  WoW.bags[0][1] = { id = 9, name = "Idol", count = 1 }
  WoW.inbox = { { subject = "a", item = { id = 9, name = "Idol", count = 1, unique = true } } }
  local err
  local f = CreateFrame("Frame")
  f:RegisterEvent("UI_ERROR_MESSAGE")
  f:SetScript("OnEvent", function() err = arg1 end)
  TakeInboxItem(1)
  T.eq(err, ERR_ITEM_MAX_COUNT)
end)

T.test("stub: delete shifts later mails down, return logs the mail, GetInboxText marks read", function()
  WoW.inbox = { { subject = "a", body = "hello" }, { subject = "b" }, { subject = "c" } }
  T.eq(GetInboxText(1), "hello")
  T.eq(WoW.mail[1].wasRead, 1)
  DeleteInboxItem(1)
  T.eq(GetInboxNumItems(), 2)
  T.eq(WoW.mail[1].subject, "b")
  ReturnInboxItem(1)
  T.eq(WoW.returned[1].subject, "b")
  T.eq(WoW.mail[1].subject, "c")
  CheckInbox()
  T.eq(T.count("CheckInbox"), 1)
end)

local function stack(id, count)
  WoW.items[id] = { name = "Item" .. id, tex = "T" }
  return { id = id, name = "Item" .. id, count = count }
end

T.test("stub: send slot, SendMail records, clears and charges postage", function()
  WoW.money = 1000
  WoW.bags = { [0] = { stack(1, 20) } }
  local got
  local f = CreateFrame("Frame")
  f:RegisterEvent("MAIL_SEND_SUCCESS")
  f:SetScript("OnEvent", function() got = true end)
  ClearCursor()
  PickupContainerItem(0, 1)
  ClickSendMailItemButton()
  local name, _, count = GetSendMailItem()
  T.eq(name, "Item1")
  T.eq(count, 20)
  SetSendMailMoney(100)
  T.eq(GetSendMailPrice(), 30)
  SendMail("Banker", "Subj", "Body")
  T.ok(got, "MAIL_SEND_SUCCESS")
  T.eq(WoW.sent[1].to, "Banker")
  T.eq(WoW.sent[1].money, 100)
  T.eq(WoW.sent[1].item.count, 20)
  T.eq(GetSendMailItem(), nil)
  T.eq(WoW.bags[0][1].id, nil)
  T.eq(WoW.money, 1000 - 30 - 100)
  SendMail("Banker", "Again", "")
  T.eq(WoW.sent[2].money, 0, "money cleared")
  T.eq(WoW.sent[2].item, nil)
end)

T.test("stub: a queued mail error fires instead of sending and changes nothing", function()
  WoW.money = 1000
  WoW.bags = { [0] = { stack(1, 5) } }
  PickupContainerItem(0, 1)
  ClickSendMailItemButton()
  table.insert(WoW.mailErrors, ERR_MAIL_TARGET_NOT_FOUND)
  local err, ok
  local f = CreateFrame("Frame")
  f:RegisterEvent("UI_ERROR_MESSAGE")
  f:RegisterEvent("MAIL_SEND_SUCCESS")
  f:SetScript("OnEvent", function() if event == "MAIL_SEND_SUCCESS" then ok = true else err = arg1 end end)
  SendMail("Nobody", "s", "b")
  T.eq(err, ERR_MAIL_TARGET_NOT_FOUND)
  T.eq(ok, nil)
  T.eq(table.getn(WoW.sent), 0)
  T.eq(WoW.money, 1000)
  T.ok(GetSendMailItem() ~= nil, "slot kept")
  T.eq(table.getn(WoW.mailErrors), 0)
end)

T.test("stub: mailing yourself is an error", function()
  local err
  local f = CreateFrame("Frame")
  f:RegisterEvent("UI_ERROR_MESSAGE")
  f:SetScript("OnEvent", function() err = arg1 end)
  SendMail(WoW.player, "s", "b")
  T.eq(err, ERR_MAIL_TO_SELF)
end)

T.test("stub: ClickSendMailItemButton swaps hand and slot", function()
  WoW.bags = { [0] = { stack(1, 5), stack(2, 3) } }
  PickupContainerItem(0, 1)
  ClickSendMailItemButton()
  PickupContainerItem(0, 2)
  ClickSendMailItemButton()          -- swap: slot holds item 2, hand holds item 1
  T.eq(GetSendMailItem(), "Item2")
  T.eq(WoW.cursor.item.id, 1)
  ClearCursor()
  ClickSendMailItemButton()          -- slot to hand
  T.eq(GetSendMailItem(), nil)
  T.eq(WoW.cursor.item.id, 2)
end)

T.test("stub: hiding MailFrame calls CloseMail, which fires MAIL_CLOSED; IsAddOnLoaded reads WoW.addons", function()
  local closed
  local f = CreateFrame("Frame")
  f:RegisterEvent("MAIL_CLOSED")
  f:SetScript("OnEvent", function() closed = true end)
  WoW.openMailbox()
  T.ok(MailFrame:IsShown(), "shown")
  T.ok(WoW.mailOpen)
  MailFrame:Hide()
  T.eq(T.count("CloseMail"), 1)
  T.ok(closed, "MAIL_CLOSED")
  T.eq(IsAddOnLoaded("TurtleMail"), nil)
  WoW.addons.TurtleMail = true
  T.eq(IsAddOnLoaded("TurtleMail"), 1)
  OpenBackpack()
  T.eq(T.count("OpenBackpack"), 1)
end)
