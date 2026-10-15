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
  T.eq(table.getn(MU.VisibleTabs()), 1, "Send joins in task 5")
  T.eq(MU.VisibleTabs()[1].key, "inbox")
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
  MB.OnChange()
  frame()
  T.eq(p.list.data[1].money, 5)
end)

T.test("the Blizzard button switches windows and Collect all labels follow the inbox", function()
  open({ ah("Auction successful: Linen Cloth", 900) })
  click(MU.win.blizzard)
  T.eq(MU.win:IsShown(), false)
  T.ok(MailFrame:IsShown())
  T.ok(not T.calledWith("CloseMail"))
  T.ok(MU.win.gold:GetText() ~= nil)
end)

T.test("closing the window ends the visit", function()
  open({})
  MU.win:Hide()
  T.ok(T.calledWith("CloseMail"))
end)

T.test("opening and painting call no engine action", function()
  local p = open({ ah("Auction successful: Linen Cloth", 900, linen()), { sender = "Ann", subject = "x", body = "hi", money = 5 } })
  p.list:SetHeight(300)
  p.list:Paint()
  WoW.runScript(p.list.rows[1], "OnEnter")
  WoW.runScript(p.list.rows[1], "OnClick")
  for _ = 1, 5 do WoW.fire("MAIL_INBOX_UPDATE") frame() end
  for _, name in ipairs({ "GetInboxText", "GetInboxInvoiceInfo", "TakeInboxMoney", "TakeInboxItem", "DeleteInboxItem",
                          "ReturnInboxItem", "SendMail", "ClickSendMailItemButton", "SetSendMailMoney", "CheckInbox" }) do
    T.eq(T.count(name), 0, name)
  end
end)
