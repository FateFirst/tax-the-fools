local Probe = TaxTheFools.Probe

T.test("the probe reports which API functions this client has", function()
  local all = table.concat(Probe.Lines(), "\n")
  T.ok(string.find(all, "fn QueryAuctionItems yes", 1, true), all)
  T.ok(string.find(all, "fn GetInboxItem MISSING", 1, true), all)
  T.ok(string.find(all, "realm Medivh", 1, true), all)
end)

T.test("with an auction page loaded it samples a real row", function()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 8000, owner = "Bob" })
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
  local all = table.concat(Probe.Lines(), "\n")
  T.ok(string.find(all, "auction row 1: Runecloth", 1, true), all)
  T.ok(string.find(all, "Bob", 1, true))
end)

T.test("the probe window holds copyable text and the dump is saved", function()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 8000 })
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
  Probe.Show()
  T.ok(table.getn(TaxTheFoolsDB.probe) > 5)
  T.ok(Probe.frame:IsShown())
  T.ok(string.find(Probe.frame.edit:GetText(), "||Hitem:14047", 1, true), "links shown as text, not as links")
end)

T.test("the probe reports the mail API, ATTACHMENTS_MAX_SEND and MailFrame's OnHide", function()
  local all = table.concat(Probe.Lines(), "\n")
  for _, n in ipairs({ "GetSendMailItem", "ClickSendMailItemButton", "SendMail", "TakeInboxItem", "CheckInbox" }) do
    T.ok(string.find(all, "fn " .. n .. " yes", 1, true), n)
  end
  T.ok(string.find(all, "ATTACHMENTS_MAX_SEND = nil", 1, true), all)
  T.ok(string.find(all, "MailFrame OnHide script yes", 1, true), all)
end)
