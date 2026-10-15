local A = TaxTheFools
local MU, MB, MH = A.MailUI, A.Mailbox, A.MailHook

local function frame()
  WoW.clock = WoW.clock + 0.1
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
end
local function pump(n)
  for _ = 1, n or 60 do
    if not MB.busy then return end
    frame()
  end
end
local function setup()
  WoW.items[100] = { name = "Linen Cloth", stack = 20 }
  WoW.bags = { [0] = { {}, {}, {}, {} } }
  WoW.money = 1000
end
local function ah(subject, money, item, extra)
  local m = { sender = "Auction House", subject = subject, money = money or 0, item = item }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function linen(n) return { id = 100, name = "Linen Cloth", count = n or 5 } end
local function open(mails)
  setup()
  WoW.mail = mails
  WoW.openMailbox()
  frame()
  frame()
  return MU.frame
end
local function click(b) WoW.runScript(b, "OnClick") end
local function cell(p, row, col) return p.list.rows[row].cells[col]:GetText() end

T.test("the window is built at init, registered with the hook, with Inbox first", function()
  T.ok(MU.win)
  T.eq(MU.win:GetName(), "TaxTheFoolsMail")
  T.eq(MH.window, MU.win)
  T.ok(MU.builders.inbox)
  T.eq(table.getn(MU.VisibleTabs()), 2)
  T.eq(MU.VisibleTabs()[1].key, "inbox")
  T.eq(MU.VisibleTabs()[2].key, "send")
end)

T.test("opening the mailbox shows our window on the Inbox tab with rows, tags and the footer", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900), { sender = "Bob", subject = "gift", money = 50, item = linen() },
                   ah("Auction expired: Linen Cloth", 0, linen()), { sender = "Ann", subject = "back", returned = true } })
  T.ok(MU.win:IsShown())
  T.eq(MU.win.tabs.selected, "inbox")
  p.list:SetHeight(300)
  p.list:Paint()
  T.eq(table.getn(p.list.data), 4)
  T.eq(cell(p, 1, 2), "Auction House")
  T.eq(cell(p, 1, 3), "Auction successful: Linen Cloth")
  T.eq(cell(p, 1, 7), "Sold")
  T.eq(cell(p, 2, 7), "")
  T.eq(cell(p, 3, 7), "Expired")
  T.eq(cell(p, 3, 1), "Item")
  T.eq(cell(p, 4, 7), "Returned")
  T.eq(cell(p, 1, 4), A.Util.money(900))
  T.eq(p.footer:GetText(), "4 mails  -  " .. A.Util.money(950) .. " waiting  -  collected " .. A.Util.money(0))
  T.eq(MU.win.status.collect.label:GetText(), "COLLECT ALL (3)", "bob, two AH mails; the plain letter is skipped")
  T.eq(MU.win.status.stop:IsShown(), false)
end)

T.test("a COD mail is orange-flagged and left out of the collect count", function()
  local p = open({ { sender = "Cod", subject = "pay", item = linen(), cod = 500 } })
  p.list:SetHeight(300)
  p.list:Paint()
  T.eq(cell(p, 1, 5), A.Util.money(500))
  T.eq(MU.win.status.collect.label:GetText(), "COLLECT ALL (0)")
  T.eq(MU.win.status.collect.enabled, false)
end)

T.test("Collect all starts the chain on one click, and Stop ends it", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900), ah("Auction successful: Linen Cloth", 100) })
  click(MU.win.status.collect)
  T.ok(MB.busy)
  T.eq(T.count("TakeInboxMoney"), 0, "the click only starts it")
  frame()
  MU.Tick()
  T.eq(MU.win.status.stop:IsShown(), true)
  T.eq(MU.win.status.collect.enabled, false)
  click(MU.win.status.stop)
  pump()
  T.eq(MB.busy, false)
  T.eq(MU.win.status.stop:IsShown(), false)
  T.ok(string.find(MU.win.status.text:GetText(), "Stopped", 1, true), MU.win.status.text:GetText())
end)

T.test("Collect all runs to the end and the footer counts what was collected", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900), ah("Auction successful: Linen Cloth", 100) })
  click(MU.win.status.collect)
  pump()
  frame()
  T.eq(WoW.money, 2000)
  T.eq(table.getn(WoW.mail), 0)
  T.ok(string.find(p.footer:GetText(), "collected " .. A.Util.money(1000), 1, true), p.footer:GetText())
  T.eq(MU.win.status.text:GetText(), MB.status.text)
end)

T.test("Collect, Delete and Return act on the selected mail only", function()
  local p = open({ { sender = "Bob", subject = "gift", money = 50 }, { sender = "Ann", subject = "empty" },
                   { sender = "Cy", subject = "stuff", item = linen() } })
  p.list:SetHeight(300)
  p.list:Paint()
  T.eq(p.collectBtn.enabled, false, "nothing selected")
  T.eq(p.deleteBtn.enabled, false)
  click(p.collectBtn)
  T.eq(T.count("TakeInboxMoney"), 0)
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.collectBtn.enabled, true)
  T.eq(p.deleteBtn.enabled, false, "it still holds money")
  click(p.deleteBtn)
  T.eq(T.count("DeleteInboxItem"), 0)
  click(p.collectBtn)
  pump()
  T.eq(WoW.money, 1050)
  T.eq(T.count("TakeInboxMoney"), 1)
  T.eq(T.count("TakeInboxItem"), 0, "only the selected mail")
  MU.Tick()
  WoW.runScript(p.list.rows[2], "OnClick")
  T.eq(p.deleteBtn.enabled, true)
  click(p.deleteBtn)
  T.eq(T.count("DeleteInboxItem"), 1)
  T.eq(table.getn(WoW.mail), 2)
  frame()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.returnBtn.enabled, true)
  click(p.returnBtn)
  T.eq(T.count("ReturnInboxItem"), 1)
  T.eq(table.getn(WoW.returned), 1)
end)

T.test("Return is off for auction house mail", function()
  local p = open({ ah("Auction successful: Linen Cloth", 5) })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.returnBtn.enabled, false)
  T.eq(p.collectBtn.enabled, true)
end)

T.test("Read shows the body in the detail pane; selecting alone reads nothing", function()
  local p = open({ { sender = "Ann", subject = "hello", body = "Hi there, friend." } })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(T.count("GetInboxText"), 0, "selecting doesn't open it")
  T.eq(p.detail:GetText(), MU.HINT)
  click(p.readBtn)
  T.eq(T.count("GetInboxText"), 1)
  T.eq(p.detail:GetText(), "Hi there, friend.")
  T.eq(WoW.mail[1].wasRead, 1)
end)

T.test("buttons are off while a chain is busy", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900), { sender = "Ann", subject = "x", money = 5 } })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[2], "OnClick")
  T.eq(p.readBtn.enabled, true)
  click(MU.win.status.collect)
  MU.UpdateBar()
  T.eq(p.readBtn.enabled, false)
  T.eq(p.collectBtn.enabled, false)
  T.eq(p.deleteBtn.enabled, false)
  T.eq(p.returnBtn.enabled, false)
  MB.Stop()
  pump()
end)

T.test("hovering a row with an item uses SetInboxItem, and nothing else on the mailbox", function()
  local p = open({ ah("Auction expired: Linen Cloth", 0, linen()), { sender = "Ann", subject = "plain" } })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnEnter")
  T.eq(T.count("SetInboxItem"), 1)
  T.ok(T.calledWith("SetInboxItem GameTooltip 1"))
  WoW.runScript(p.list.rows[2], "OnEnter")
  T.eq(T.count("SetInboxItem"), 1, "no item, no tooltip call")
  T.eq(T.count("GetInboxText"), 0)
end)

T.test("an inbox burst repaints once per frame, and a change repaints too", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900) })
  WoW.calls = {}
  for _ = 1, 20 do WoW.fire("MAIL_INBOX_UPDATE") end
  T.eq(T.count("GetInboxHeaderInfo"), 0, "nothing is read inside the events")
  frame()
  -- Mail.Tick reads once and MailUI once
  T.eq(T.count("GetInboxNumItems"), 2)
  frame() frame()
  T.eq(T.count("GetInboxNumItems"), 2, "quiet without new events")
  WoW.mail[1].money = 5
  WoW.fire("MAIL_INBOX_UPDATE")
  frame()
  T.eq(p.list.data[1].money, 5)
end)

T.test("the Blizzard button switches windows and Collect all labels follow the inbox", function()
  open({ ah("Auction successful: Linen Cloth", 900) })
  click(MU.win.blizzard)
  T.eq(MU.win:IsShown(), false)
  T.ok(MailFrame:IsShown())
  T.ok(not T.calledWith("CloseMail"))
end)

T.test("Collect all's label follows the inbox", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900), { sender = "Ann", subject = "letter" } })
  T.eq(MU.win.status.collect.label:GetText(), "COLLECT ALL (1)")
  table.insert(WoW.mail, { sender = "Bob", subject = "gift", money = 5 })
  WoW.fire("MAIL_INBOX_UPDATE")
  frame()
  T.eq(MU.win.status.collect.label:GetText(), "COLLECT ALL (2)")
end)

T.test("the columns fit the list at the minimum window size", function()
  local sum = 0
  for _, c in ipairs(MU.COLUMNS) do sum = sum + c.width end
  T.ok(sum <= 560 - 20 - 12, "columns total " .. sum)
end)

T.test("Return is off for returned and GM mail", function()
  local p = open({ { sender = "Ann", subject = "back", returned = true, money = 0, item = linen() },
                   { sender = "GM", subject = "t", isGM = true, money = 5 } })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.returnBtn.enabled, false)
  WoW.runScript(p.list.rows[2], "OnClick")
  T.eq(p.returnBtn.enabled, false)
end)

T.test("an engine change alone refreshes the status, not the list", function()
  open({ ah("Auction successful: Linen Cloth", 900) })
  WoW.calls = {}
  MB.status = { text = "Collecting 1 of 1", token = "text" }
  MB.OnChange()
  frame()
  T.eq(T.count("GetInboxNumItems"), 0, "no header read")
  T.eq(MU.win.status.text:GetText(), "Collecting 1 of 1")
end)

T.test("a chain still ends with the list repainted", function()
  local mails = {}
  for i = 1, 6 do table.insert(mails, ah("Auction successful: Linen Cloth", 10 + i)) end
  local p = open(mails)
  click(MU.win.status.collect)
  pump()
  frame() frame()
  T.eq(table.getn(p.list.data), 0)
  T.eq(MU.win.status.stop:IsShown(), false)
  T.eq(WoW.money, 1000 + 10 * 6 + 21)
end)

-- ---------- Send tab ----------
local DB = A.DB
local function sendSetup(alt)
  setup()
  A.BagClick.Install()
  WoW.items[100] = { name = "Linen Cloth", stack = 20, type = "Trade Goods" }
  WoW.items[200] = { name = "Iron Sword", stack = 1, type = "Weapon" }
  WoW.items[300] = { name = "Wool Cloth", stack = 20, type = "Trade Goods" }
  WoW.bags = { [0] = { { id = 100, name = "Linen Cloth", count = 20 }, { id = 200, name = "Iron Sword", count = 1 },
                       { id = 300, name = "Wool Cloth", count = 7 }, {} } }
  WoW.addons.TurtleMail = nil
  MU.send.rows = {}
  local m = DB.S().mail
  m.bankAlt, m.keep, m.rules = alt, {}, { crafted = true, tradeGoods = true, patterns = false, auctionable = false }
  DB.Realm().chars["Banker"] = DB.Realm().chars["Banker"] or {}
  WoW.mail = {}
  WoW.openMailbox()
  frame() frame()
  MU.win.tabs:Select("send")
  return MU.pages.send
end
local function bag(slot) return WoW.bagButton(0, slot) end
local function rclick(slot) WoW.clickBag(bag(slot), "RightButton") end
local function keys() local o = {} for _, r in ipairs(MU.send.rows) do table.insert(o, r.key) end return o end

T.test("the Send page fits the minimum window", function()
  local p = sendSetup("Banker")
  local w = 560 - 20
  T.ok(p.money:GetWidth() + 372 <= w, "money input ends inside the body")
  local cols = 0
  for _, c in ipairs(MU.SEND_COLUMNS) do cols = cols + c.width end
  T.ok(cols <= w - 12, "columns " .. cols)
  -- buttons along the bottom: Fill 120, Clear 60, Remove 70, Keep 60 (+6 gaps) leave room for Send 80
  T.ok(120 + 60 + 70 + 60 + 18 + 80 <= w)
  -- height: body is 380 - 31 - 28 - 38 - 8 - 22 = 253; the list sits between 88 and 54
  T.ok(253 - 88 - 54 - 20 >= 3 * 18, "at least three list rows")
end)

T.test("Fill for bank alt attaches matching stacks, addresses the mail, and sends nothing", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  T.eq(p.to:GetText(), "Banker")
  T.eq(table.getn(MU.send.rows), 2, "linen and wool, not the sword")
  T.eq(MU.send.rows[1].key, "100:0")
  T.eq(MU.send.rows[1].count, 20)
  T.eq(MU.send.rows[2].key, "300:0")
  for _, n in ipairs({ "SendMail", "ClickSendMailItemButton", "SetSendMailMoney", "PickupContainerItem" }) do
    T.eq(T.count(n), 0, n)
  end
end)

T.test("Fill skips kept items and stacks already attached", function()
  local p = sendSetup("Banker")
  DB.S().mail.keep["300:0"] = true
  click(p.fillBtn)
  T.eq(table.getn(MU.send.rows), 1)
  click(p.fillBtn)
  T.eq(table.getn(MU.send.rows), 1, "not added twice")
end)

T.test("Fill is hidden for the bank alt itself and with no bank alt", function()
  local p = sendSetup(nil)
  T.eq(p.fillBtn:IsShown(), false)
  p = sendSetup(WoW.player)
  T.eq(p.fillBtn:IsShown(), false)
  p = sendSetup("Banker")
  T.eq(p.fillBtn:IsShown(), true)
end)

T.test("Remove drops the selected row; Keep drops it and remembers the item", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  p.list:SetHeight(300)
  p.list:Paint()
  T.eq(p.removeBtn.enabled, false, "nothing selected")
  WoW.runScript(p.list.rows[1], "OnClick")
  T.eq(p.removeBtn.enabled, true)
  click(p.removeBtn)
  T.eq(table.getn(MU.send.rows), 1)
  T.eq(MU.send.rows[1].key, "300:0")
  T.ok(not DB.S().mail.keep["100:0"], "remove does not keep")
  WoW.runScript(p.list.rows[1], "OnClick")
  click(p.keepBtn)
  T.eq(table.getn(MU.send.rows), 0)
  T.ok(DB.S().mail.keep["300:0"])
end)

T.test("right-click on the Send tab attaches, once, and consumes the click", function()
  sendSetup("Banker")
  rclick(1)
  T.eq(table.getn(MU.send.rows), 1)
  T.eq(MU.send.rows[1].key, "100:0")
  rclick(1)
  T.eq(table.getn(MU.send.rows), 1, "same slot not added twice")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 0)
  T.eq(T.count("SendMail"), 0)
end)

T.test("right-click on an unmailable item says so and still consumes the click", function()
  local p = sendSetup("Banker")
  local keep, soul = A.Sell.TipLines, getglobal("ITEM_SOULBOUND")
  setglobal("ITEM_SOULBOUND", "Soulbound")
  A.Sell.TipLines = function() return { "Iron Sword", "Soulbound" } end
  rclick(2)
  A.Sell.TipLines = keep
  setglobal("ITEM_SOULBOUND", soul)
  T.eq(table.getn(MU.send.rows), 0)
  T.eq(p.note:GetText(), "Can't mail that")
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 0)
end)

T.test("right-click passes through on the Inbox tab, with a modifier, and with TurtleMail loaded", function()
  sendSetup("Banker")
  MU.win.tabs:Select("inbox")
  rclick(1)
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 1, "inbox")
  T.eq(table.getn(MU.send.rows), 0)
  MU.win.tabs:Select("send")
  WoW.shift = true rclick(1) WoW.shift = false
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 2, "shift")
  WoW.addons.TurtleMail = true
  rclick(1)
  T.eq(T.count("ContainerFrameItemButton_OnClick"), 3, "TurtleMail")
  WoW.addons.TurtleMail = nil
  T.eq(table.getn(MU.send.rows), 0)
end)

T.test("the footer shows the mail count and postage", function()
  local p = sendSetup("Banker")
  T.eq(p.footer:GetText(), "0 mails  -  postage " .. A.Util.money(0))
  click(p.fillBtn)
  T.eq(p.footer:GetText(), "2 mails  -  postage " .. A.Util.money(60))
  p.list:SetHeight(300) p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnClick")
  click(p.removeBtn)
  T.eq(p.footer:GetText(), "1 mail  -  postage " .. A.Util.money(30))
end)

T.test("Send goes through the engine with the attachments, and the sent rows clear", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  p.subject:SetText("")
  p.money:SetValue(500)
  click(p.sendBtn)
  T.ok(MB.busy)
  T.eq(p.sendBtn.enabled, true, "enabled state is refreshed on the next paint")
  pump()
  frame() frame()
  T.eq(table.getn(WoW.sent), 2)
  T.eq(WoW.sent[1].to, "Banker")
  T.eq(WoW.sent[1].item.id, 100)
  T.eq(WoW.sent[1].item.count, 20)
  T.eq(WoW.sent[1].subject, "Linen Cloth (20)")
  T.eq(WoW.sent[1].money, 500)
  T.eq(WoW.sent[2].item.id, 300)
  T.eq(table.getn(MU.send.rows), 0, "sent stacks are gone from the list")
  T.eq(p.money:GetValue(), nil)
end)

T.test("Send is disabled while a chain runs", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  click(p.sendBtn)
  MB.OnChange()
  frame()
  T.eq(p.sendBtn.enabled, false)
  pump()
  frame() frame()
  T.eq(p.sendBtn.enabled, true)
end)

T.test("a row whose stack changed in the bags is dropped after BAG_UPDATE", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  WoW.bags[0][3] = {}
  WoW.fire("BAG_UPDATE")
  frame()
  T.eq(table.getn(MU.send.rows), 1)
  T.eq(MU.send.rows[1].key, "100:0")
end)

T.test("sending to yourself is refused", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  p.to:SetText(WoW.player)
  click(p.sendBtn)
  T.eq(MB.busy, false)
  T.eq(T.count("SendMail"), 0)
  T.eq(T.count("ClickSendMailItemButton"), 0)
  T.eq(MB.status.text, "You can't mail yourself")
  T.eq(table.getn(MU.send.rows), 2, "attachments stay")
end)

T.test("opening, painting, Fill and right-click never reach a send call", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  rclick(2)
  p:Refresh()
  frame() frame()
  for _, n in ipairs({ "SendMail", "ClickSendMailItemButton", "SetSendMailMoney" }) do T.eq(T.count(n), 0, n) end
end)

T.test("Clear empties the form and restores the default recipient", function()
  local p = sendSetup("Banker")
  click(p.fillBtn)
  p.to:SetText("Someone")
  p.subject:SetText("x")
  click(p.clearBtn)
  T.eq(table.getn(MU.send.rows), 0)
  T.eq(p.to:GetText(), "Banker")
  T.eq(p.subject:GetText(), "")
end)
