local A = TaxTheFools
local Mailbox, Mail = A.Mailbox, A.Mail

local function frame()
  WoW.clock = WoW.clock + 0.1
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
end
local function pump(n)
  for _ = 1, n or 60 do
    if not Mailbox.busy then return end
    frame()
  end
end

local function setup()
  WoW.items[100] = { name = "Linen Cloth", stack = 20 }
  WoW.items[200] = { name = "Bolt of Linen", stack = 20 }
  WoW.bags = { [0] = { {}, {}, {}, {} } }
  WoW.money = 1000
end
local function ah(money, item) return { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = money, item = item } end
local function linen(n) return { id = 100, name = "Linen Cloth", count = n or 5 } end

T.test("collect all takes money and items, deletes AH mail, keeps letters, skips COD and GM mail", function()
  setup()
  WoW.mail = { ah(900),
               { sender = "Bob", subject = "gift", money = 50, item = linen(), body = "" },
               { sender = "Ann", subject = "hello", money = 70, body = "Hi there" },
               { sender = "Cod", subject = "pay me", item = linen(), cod = 500 },
               { sender = "GM", subject = "ticket", money = 10, isGM = true, body = "" } }
  T.eq(Mailbox.CollectAll(), true)
  T.eq(Mailbox.busy.kind, "collect")
  T.eq(T.count("TakeInboxMoney"), 0, "nothing happens before the first tick")
  pump()
  T.eq(Mailbox.busy, false, "the lock is released")
  T.eq(WoW.money, 1000 + 900 + 50 + 70)
  T.eq(table.getn(WoW.mail), 3, "AH mail and the empty-bodied gift are gone")
  T.eq(WoW.mail[1].sender, "Ann") T.eq(WoW.mail[1].money, 0)
  T.eq(WoW.mail[2].cod, 500) T.ok(WoW.mail[2].item, "COD item stays")
  T.eq(WoW.mail[3].money, 10, "GM mail untouched")
  T.eq(WoW.bags[0][1].id, 100)
  T.eq(Mailbox.collected, 1020)
  T.eq(T.count("CheckInbox"), 1, "CheckInbox once when finished")
  T.ok(T.calledWith("Collected 10s 20c from 3 mails"), Mailbox.status.text)
  T.eq(Mailbox.status.token, "good")
end)

T.test("a mail still holding money or an item is never deleted by the chain", function()
  setup()
  WoW.mail = { { sender = "Bob", subject = "two things", money = 5, item = linen(), body = "" } }
  Mailbox.CollectAll()
  local deletedWith = false
  local real = DeleteInboxItem
  DeleteInboxItem = function(i)
    local m = WoW.mail[i]
    if m and ((m.money or 0) > 0 or m.item) then deletedWith = true end
    return real(i)
  end
  pump()
  DeleteInboxItem = real
  T.eq(deletedWith, false)
  T.eq(table.getn(WoW.mail), 0, "emptied, then deleted")
  T.eq(T.count("TakeInboxMoney"), 1) T.eq(T.count("TakeInboxItem"), 1)
end)

T.test("non-AH mail is read for its body before the take, AH mail is not", function()
  setup()
  WoW.mail = { { sender = "Ann", subject = "hello", money = 70, body = "Hi" } }
  Mailbox.CollectAll() pump()
  T.eq(T.count("GetInboxText 1"), 1)
  WoW.calls = {}
  WoW.mail = { ah(30) }
  Mailbox.CollectAll() pump()
  T.eq(T.count("GetInboxText"), 0)
end)

T.test("an empty non-AH mail is left alone", function()
  setup()
  WoW.mail = { { sender = "Ann", subject = "hello", body = "" } }
  Mailbox.CollectAll() pump()
  T.eq(table.getn(WoW.mail), 1)
  T.eq(T.count("DeleteInboxItem"), 0)
  T.ok(T.calledWith("Nothing to collect"))
end)

T.test("one server call per tick, each waiting for its event", function()
  setup()
  WoW.mail = { ah(10), ah(20) }
  local real = TakeInboxMoney
  local silent = true
  TakeInboxMoney = function(i) WoW.log("TakeInboxMoney", i) if not silent then real(i) end end
  Mailbox.CollectAll()
  frame() T.eq(T.count("TakeInboxMoney"), 1)
  frame() frame() T.eq(T.count("TakeInboxMoney"), 1, "waits for MAIL_INBOX_UPDATE")
  T.eq(Mailbox.busy.waiting, true)
  TakeInboxMoney = real
  WoW.fire("MAIL_INBOX_UPDATE")
  frame() T.eq(T.count("TakeInboxMoney"), 2, "the event releases the next call")
  Mailbox.Stop() pump()
end)

T.test("Mail.Read runs before the first take", function()
  setup()
  WoW.mail = { ah(10) }
  local real = Mail.Read
  Mail.Read = function() WoW.log("MailRead") real() end
  Mailbox.CollectAll() pump()
  Mail.Read = real
  local read, take
  for i, c in ipairs(WoW.calls) do
    if c == "MailRead" and not read then read = i end
    if string.find(c, "TakeInboxMoney", 1, true) and not take then take = i end
  end
  T.ok(read and take and read < take, "read before take")
end)

T.test("full bags stop the chain and keep the mail", function()
  setup()
  WoW.bags = { [0] = { {} } }
  WoW.mail = { { sender = "Bob", subject = "a", item = linen(), body = "x" }, { sender = "Bob", subject = "b", item = linen(), body = "x" } }
  Mailbox.CollectAll() pump()
  T.eq(Mailbox.busy, false)
  T.eq(table.getn(WoW.mail), 2)
  T.ok(WoW.mail[2].item, "the second item is still in the mail")
  T.ok(string.find(Mailbox.status.text, "Bags full", 1, true))
  T.eq(Mailbox.status.token, "bad")
  Mailbox.CollectAll() pump()
  T.ok(string.find(Mailbox.status.text, "Bags full", 1, true))
end)

T.test("a unique item already owned is skipped and the chain goes on", function()
  setup()
  WoW.bags = { [0] = { { id = 100, name = "Linen Cloth", count = 1 }, {}, {} } }
  WoW.mail = { { sender = "Bob", subject = "u", item = { id = 100, name = "Linen Cloth", count = 1, unique = true }, body = "x" },
               { sender = "Ann", subject = "m", money = 40, body = "x" } }
  Mailbox.CollectAll() pump()
  T.eq(Mailbox.busy, false)
  T.ok(WoW.mail[1].item, "unique mail kept")
  T.eq(WoW.money, 1040, "the next mail was collected")
end)

T.test("10 seconds of silence stops the chain", function()
  setup()
  WoW.mail = { ah(10) }
  local real = TakeInboxMoney
  TakeInboxMoney = function(i) WoW.log("TakeInboxMoney", i) end
  Mailbox.CollectAll()
  for _ = 1, 99 do frame() end
  T.ok(Mailbox.busy, "still waiting after 9.9 s")
  for _ = 1, 3 do frame() end
  TakeInboxMoney = real
  T.eq(Mailbox.busy, false)
  T.ok(string.find(Mailbox.status.text, "No reply", 1, true))
end)

T.test("MAIL_CLOSED stops a chain and releases the lock", function()
  setup()
  WoW.mail = { ah(10), ah(20) }
  Mailbox.CollectAll() frame()
  WoW.fire("MAIL_CLOSED")
  T.eq(Mailbox.busy, false)
  T.ok(string.find(Mailbox.status.text, "Mailbox closed", 1, true))
  local n = T.count("TakeInboxMoney")
  frame() frame()
  T.eq(T.count("TakeInboxMoney"), n, "nothing more is called")
end)

T.test("Stop ends the chain after the current step", function()
  setup()
  WoW.mail = { ah(10), ah(20), ah(30) }
  Mailbox.CollectAll() frame()
  Mailbox.Stop()
  pump()
  T.eq(Mailbox.busy, false)
  T.eq(T.count("TakeInboxMoney"), 1)
  T.eq(T.count("CheckInbox"), 0)
  T.ok(string.find(Mailbox.status.text, "Stopped", 1, true))
end)

T.test("CollectOne takes one mail and never deletes a letter", function()
  setup()
  WoW.mail = { { sender = "Ann", subject = "m", money = 40, body = "dear" }, ah(60) }
  T.eq(Mailbox.CollectOne(1), true) pump()
  T.eq(WoW.money, 1040)
  T.eq(table.getn(WoW.mail), 2)
  T.eq(Mailbox.CollectOne(2), true) pump()
  T.eq(WoW.money, 1100)
  T.eq(table.getn(WoW.mail), 1, "AH mail deleted")
  T.eq(Mailbox.busy, false)
end)

T.test("Delete and Return refuse what they must, and are one call each", function()
  setup()
  WoW.mail = { { sender = "Ann", subject = "m", money = 40 }, { sender = "Ann", subject = "x", body = "hi" },
               ah(0), { sender = "Bob", subject = "r", body = "hi" } }
  T.eq(Mailbox.Delete(1), false) T.eq(T.count("DeleteInboxItem"), 0)
  T.eq(Mailbox.Return(3), false) T.eq(T.count("ReturnInboxItem"), 0)
  T.eq(Mailbox.Return(4), true) T.eq(T.count("ReturnInboxItem"), 1)
  T.eq(Mailbox.Delete(2), true) T.eq(T.count("DeleteInboxItem"), 1)
  T.eq(table.getn(WoW.mail), 2)
  T.eq(Mailbox.Delete(9), false)
end)

T.test("Read returns the body", function()
  setup()
  WoW.mail = { { sender = "Ann", subject = "m", body = "Dear you" } }
  T.eq(Mailbox.Read(1), "Dear you")
  T.eq(Mailbox.Read(5), nil)
end)

T.test("a second action is refused while busy", function()
  setup()
  WoW.mail = { ah(10) }
  Mailbox.CollectAll()
  T.eq(Mailbox.CollectAll(), false)
  T.eq(Mailbox.Delete(1), false)
  T.eq(Mailbox.Send("Bob", "", "", 0, {}), false)
  Mailbox.Stop() pump()
end)

-- ---------- send ----------

local function stacks()
  WoW.items[100] = { name = "Linen Cloth", stack = 20 }
  WoW.items[200] = { name = "Bolt of Linen", stack = 20 }
  WoW.bags = { [0] = { { id = 100, name = "Linen Cloth", count = 20 }, { id = 200, name = "Bolt of Linen", count = 3 },
                       { id = 100, name = "Linen Cloth", count = 7 } } }
  WoW.money = 5000
end
local function att(slot, key, count) return { bag = 0, slot = slot, key = key, count = count } end

T.test("send makes the call sequence per attachment, money on the first mail only", function()
  stacks()
  T.eq(Mailbox.Send("Bob", "", "note", 123, { att(1, "100:0", 20), att(2, "200:0", 3) }), true)
  T.eq(T.count("SendMail"), 0, "nothing before the first tick")
  pump()
  T.eq(Mailbox.busy, false)
  T.eq(table.getn(WoW.sent), 2)
  T.eq(WoW.sent[1].to, "Bob") T.eq(WoW.sent[1].subject, "Linen Cloth (20)") T.eq(WoW.sent[1].body, "note")
  T.eq(WoW.sent[1].money, 123) T.eq(WoW.sent[1].item.count, 20)
  T.eq(WoW.sent[2].subject, "Bolt of Linen (3)") T.eq(WoW.sent[2].money, 0)
  T.eq(T.count("SetSendMailMoney"), 1)
  T.eq(T.count("PickupContainerItem 0 1"), 1) T.eq(T.count("PickupContainerItem 0 2"), 1)
  T.eq(T.count("ClickSendMailItemButton"), 2)
  T.ok(T.calledWith("Sent 2 of 2"), Mailbox.status.text)
  T.eq(Mailbox.progress.done, 2) T.eq(Mailbox.progress.total, 2)
  local order = {}
  for _, c in ipairs(WoW.calls) do
    if c == "ClearCursor" or string.find(c, "PickupContainerItem", 1, true) or c == "ClickSendMailItemButton"
       or string.find(c, "SetSendMailMoney", 1, true) or string.find(c, "SendMail ", 1, true) then
      table.insert(order, (string.gsub(c, " .*", "")))
    end
  end
  T.eq(table.concat(order, ","), "ClearCursor,PickupContainerItem,ClickSendMailItemButton,SetSendMailMoney,SendMail," ..
       "ClearCursor,PickupContainerItem,ClickSendMailItemButton,SendMail")
end)

T.test("a typed subject is used for every mail", function()
  stacks()
  Mailbox.Send("Bob", "Mats", "", 0, { att(1, "100:0", 20), att(3, "100:0", 7) }) pump()
  T.eq(WoW.sent[1].subject, "Mats") T.eq(WoW.sent[2].subject, "Mats")
end)

T.test("a slot that changed is skipped with a note, money goes on the first mail that is sent", function()
  stacks()
  Mailbox.Send("Bob", "", "", 99, { att(1, "100:0", 19), att(2, "200:0", 3) }) pump()
  T.eq(table.getn(WoW.sent), 1)
  T.eq(WoW.sent[1].item.id, 200) T.eq(WoW.sent[1].money, 99)
  T.ok(T.calledWith("Skipped an attachment"))
  T.ok(T.calledWith("Sent 1 of 2, skipped 1"), Mailbox.status.text)
  stacks()
  WoW.calls = {}
  Mailbox.Send("Bob", "", "", 0, { att(1, "200:0", 20) }) pump()
  T.eq(T.count("SendMail "), 0, "wrong item in the slot")
end)

T.test("no attachments sends one mail with the money", function()
  stacks()
  Mailbox.Send("Bob", "Gold", "here", 500, {}) pump()
  T.eq(table.getn(WoW.sent), 1)
  T.eq(WoW.sent[1].money, 500) T.eq(WoW.sent[1].item, nil) T.eq(WoW.sent[1].subject, "Gold")
end)

T.test("sending to yourself is refused before any call", function()
  stacks()
  WoW.calls = {}
  T.eq(Mailbox.Send("bankALT", "", "", 0, { att(1, "100:0", 20) }), false)
  T.eq(Mailbox.busy, false)
  T.eq(table.getn(WoW.calls) > 0, true)    -- only the status message
  for _, name in ipairs({ "PickupContainerItem", "ClickSendMailItemButton", "SendMail", "SetSendMailMoney", "ClearCursor" }) do
    T.eq(T.count(name), 0, name)
  end
  T.eq(Mailbox.Send("", "", "", 0, {}), false)
end)

T.test("each send error stops the chain, keeps the rest, and puts the item back", function()
  for _, name in ipairs({ "ERR_PLAYER_WRONG_FACTION", "ERR_MAIL_TARGET_NOT_FOUND", "ERR_MAIL_REACHED_CAP",
                          "ERR_NOT_ENOUGH_MONEY", "ERR_MAIL_DATABASE_ERROR" }) do
    stacks()
    table.insert(WoW.mailErrors, getglobal(name))
    Mailbox.Send("Bob", "", "", 0, { att(1, "100:0", 20), att(2, "200:0", 3) }) pump()
    T.eq(Mailbox.busy, false, name)
    T.eq(table.getn(WoW.sent), 0, name)
    T.eq(T.count("SendMail "), 1, name .. " stopped at the first")
    T.eq(Mailbox.status.token, "bad")
    T.eq(WoW.sendSlot, nil, name .. " slot cleared")
    T.eq(WoW.bags[0][1].id, 100, name .. " item still in bags")
    WoW.calls = {}
  end
end)

T.test("a failure after the first mail stops the chain with the count", function()
  stacks()
  Mailbox.Send("Bob", "", "", 0, { att(1, "100:0", 20), att(2, "200:0", 3), att(3, "100:0", 7) })
  frame()
  table.insert(WoW.mailErrors, ERR_MAIL_REACHED_CAP)
  pump()
  T.eq(table.getn(WoW.sent), 1)
  T.ok(string.find(Mailbox.status.text, "Sent 1 of 3", 1, true), Mailbox.status.text)
end)

T.test("a send with no confirmation times out, and MAIL_CLOSED ends it", function()
  stacks()
  local real = SendMail
  SendMail = function(to, s, b) WoW.log("SendMail", to, s, b) end
  Mailbox.Send("Bob", "", "", 0, { att(1, "100:0", 20) })
  for _ = 1, 120 do frame() end
  T.eq(Mailbox.busy, false)
  T.ok(string.find(Mailbox.status.text, "No reply", 1, true))
  stacks()
  Mailbox.Send("Bob", "", "", 0, { att(1, "100:0", 20) })
  frame()
  WoW.fire("MAIL_CLOSED")
  SendMail = real
  T.eq(Mailbox.busy, false)
end)

T.test("Stop ends a send after the current step", function()
  stacks()
  Mailbox.Send("Bob", "", "", 0, { att(1, "100:0", 20), att(2, "200:0", 3) })
  frame()
  Mailbox.Stop() pump()
  T.eq(table.getn(WoW.sent), 1)
  T.eq(Mailbox.busy, false)
end)

-- ---------- the automation guard ----------

T.test("opening the mailbox, update bursts, ticks and Mail.Read never call a mail action", function()
  setup()
  WoW.mail = { ah(10), { sender = "Ann", subject = "m", money = 4, body = "x" } }
  WoW.openMailbox()
  for _ = 1, 5 do WoW.fire("MAIL_INBOX_UPDATE") end
  WoW.fire("MAIL_SEND_SUCCESS")
  for _ = 1, 20 do frame() end
  Mail.Read()
  WoW.fire("UI_ERROR_MESSAGE", ERR_INV_FULL)
  WoW.fire("MAIL_CLOSED")
  for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "DeleteInboxItem", "ReturnInboxItem", "GetInboxText",
                          "GetInboxInvoiceInfo", "SendMail", "ClickSendMailItemButton", "SetSendMailMoney", "CheckInbox" }) do
    T.eq(T.count(name), 0, name)
  end
  T.eq(Mailbox.busy, false)
end)

T.test("only a Mailbox action calls them", function()
  setup()
  WoW.mail = { ah(10) }
  WoW.openMailbox()
  for _ = 1, 5 do frame() end
  T.eq(T.count("TakeInboxMoney"), 0)
  Mailbox.CollectAll() pump()
  T.eq(T.count("TakeInboxMoney"), 1)
end)
