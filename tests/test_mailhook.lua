local MH, DB = TaxTheFools.MailHook, TaxTheFools.DB

local function fakeWindow()
  local w = CreateFrame("Frame", "TTFTestMailWindow", UIParent)
  w:Hide()
  w:SetScript("OnHide", function() MH.OnWindowHidden() end)
  return w
end

local function open()
  WoW.openMailbox()   -- MailFrame shown by Blizzard, then MAIL_SHOW through core
  MH.Tick()
end

local function chats()
  local n = 0
  for _, c in ipairs(WoW.calls) do if string.find(c, "TurtleMail is loaded", 1, true) then n = n + 1 end end
  return n
end

T.test("opening the mailbox swaps in our window on the next frame and keeps the session", function()
  local old = MH.window
  MH.window = fakeWindow()
  WoW.openMailbox()
  T.ok(MailFrame:IsShown(), "nothing happens inside the event itself")
  MH.Tick()
  T.eq(MailFrame:IsShown(), false)
  T.ok(MH.window:IsShown())
  T.ok(not T.calledWith("CloseMail"), "mailbox still open")
  T.ok(T.calledWith("OpenBackpack"))
  T.ok(MH.Active())
  MH.window = old
end)

T.test("closing our window calls CloseMail", function()
  local old = MH.window
  MH.window = fakeWindow()
  open()
  MH.window:Hide()
  T.ok(T.calledWith("CloseMail"))
  MH.window = old
end)

T.test("switching to Blizzard's window and back does not close the mailbox", function()
  local old = MH.window
  MH.window = fakeWindow()
  open()
  MH.ShowBlizzard()
  T.ok(MailFrame:IsShown()) T.eq(MH.window:IsShown(), false)
  T.ok(not MH.Active())
  MH.ShowOurs()
  T.eq(MailFrame:IsShown(), false) T.ok(MH.window:IsShown())
  T.ok(not T.calledWith("CloseMail"))
  MH.window = old
end)

T.test("closing Blizzard's window while it is shown ends the visit", function()
  local old = MH.window
  MH.window = fakeWindow()
  open()
  MH.ShowBlizzard()
  MailFrame:Hide()
  T.ok(T.calledWith("CloseMail"))
  MH.window = old
end)

T.test("MAIL_CLOSED hides our window and resets without calling CloseMail again", function()
  local old = MH.window
  MH.window = fakeWindow()
  open()
  WoW.fire("MAIL_CLOSED")
  T.eq(MH.window:IsShown(), false)
  T.eq(MH.open, false)
  T.eq(MH.keepOpen, false)
  MH.window = old
end)

T.test("with replacing off nothing is swapped, Blizzard's window stays, and the back button exists", function()
  local old = MH.window
  MH.window = fakeWindow()
  DB.S().replaceBlizzardMail = false
  open()
  T.ok(MailFrame:IsShown())
  T.eq(MH.window:IsShown(), false)
  T.ok(not MH.Enabled())
  MH.window = old
end)

T.test("with TurtleMail loaded nothing is replaced and the notice prints once", function()
  local old = MH.window
  MH.window = fakeWindow()
  WoW.addons.TurtleMail = true
  open()
  T.ok(MailFrame:IsShown())
  T.eq(MH.window:IsShown(), false)
  T.ok(not MH.Enabled()) T.ok(not MH.Active())
  WoW.fire("MAIL_CLOSED")
  open()
  T.eq(chats(), 1)
  MH.window = old
end)

T.test("MAIL_CLOSED stops a running engine chain through core routing", function()
  local old = MH.window
  MH.window = fakeWindow()
  open()
  WoW.fire("MAIL_CLOSED")
  T.ok(not TaxTheFools.Mailbox.busy)
  MH.window = old
end)
