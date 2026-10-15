TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
local U = A.Util
local Mailbox = { busy = false, progress = false, status = false, collected = 0 }
A.Mailbox = Mailbox

-- The mailbox engine (phase 5b spec section 4). One lock, Mailbox.busy, with kind "collect" or "send".
-- Every action starts from a click (CollectAll, CollectOne, Delete, Return, Read, Send). Opening the mailbox,
-- inbox updates, ticks and Mail.Read never call Take*, Delete, Return, GetInboxText, SendMail or the attachment
-- clicks. Events only set flags; Tick does the work. A chain makes one server call per tick (a take, a delete
-- or a SendMail) and waits for its confirming event; the local steps before a SendMail (clearing the cursor,
-- picking the stack up, clicking the slot) happen in the same tick.
-- Mailbox.OnChange is a callback the UI sets; it runs after every state change.

Mailbox.TIMEOUT = 10
Mailbox.SEND_ERRORS = { "ERR_MAIL_TO_SELF", "ERR_PLAYER_WRONG_FACTION", "ERR_MAIL_TARGET_NOT_FOUND",
                        "ERR_MAIL_REACHED_CAP", "ERR_NOT_ENOUGH_MONEY", "ERR_MAIL_DATABASE_ERROR" }
Mailbox.MAX_TRIES = 4

function Mailbox.ResetState()
  Mailbox.busy, Mailbox.progress, Mailbox.status, Mailbox.collected = false, false, false, 0
end

local function changed() if Mailbox.OnChange then Mailbox.OnChange() end end

local function say(text, token)
  Mailbox.status = { text = text, token = token or "text" }
  U.msg(text)
  changed()
end

local function refuse(text)
  say(text, "bad")
  return false
end

local function money(c) return U.money(c, true) end

local function isAH(sender, subject)
  if sender and string.find(sender, "Auction House", 1, true) then return true end
  return A.Sales.Classify(subject) ~= nil
end

-- The header of mail i as the planner reads it.
local function header(i)
  local _, _, sender, subject, m, cod, _, hasItem, _, wasReturned, textCreated, _, isGM = GetInboxHeaderInfo(i)
  return { sender = sender, subject = subject, money = m or 0, cod = cod or 0, hasItem = hasItem and true or false,
           wasReturned = wasReturned, textCreated = textCreated, isGM = isGM }
end

local function holds(h) return h.money > 0 or h.hasItem end

-- ---------- finishing ----------

local function release(text, token)
  Mailbox.busy = false
  if Mailbox.progress then Mailbox.progress.kind = false end
  say(text, token)
end

local function collectSummary(b)
  if b.mails == 0 and b.gold == 0 then return "Nothing to collect" end
  return "Collected " .. money(b.gold) .. " from " .. b.mails .. (b.mails == 1 and " mail" or " mails")
end

-- Puts the attachment slot back in the bags after a failed send.
local function clearSendSlot()
  ClearCursor()
  if GetSendMailItem() then
    ClickSendMailItemButton()
    ClearCursor()
  end
end

-- why: nil for a normal finish, else the reason the chain stopped.
local function finish(b, why, token)
  if b.kind == "collect" then
    local sum = collectSummary(b)
    if not why then
      CheckInbox()
      release(sum, "good")
    else
      release(why .. ". " .. sum, token or "bad")
    end
  else
    local text = "Sent " .. b.sent .. " of " .. b.total
    if b.skipped > 0 then text = text .. ", skipped " .. b.skipped end
    if why then
      clearSendSlot()
      release(why .. ". " .. text, token or "bad")
    else
      release(text, b.sent > 0 and "good" or "bad")
    end
  end
  return true
end

function Mailbox.Stop()
  local b = Mailbox.busy
  if b then b.stop = true end
end

-- MAIL_CLOSED (through Core.Safe): whatever was running ends, and the lock is released.
function Mailbox.OnClosed()
  local b = Mailbox.busy
  if not b then return end
  if b.kind == "send" then
    -- the window is gone; the client returns the attachment itself
    release("Mailbox closed. Sent " .. b.sent .. " of " .. b.total, "bad")
  else
    release("Mailbox closed. " .. collectSummary(b), "bad")
  end
end

-- MAIL_SHOW, MAIL_INBOX_UPDATE and MAIL_SEND_SUCCESS (through Core.Safe): flags only.
function Mailbox.OnEvent(e)
  if e == "MAIL_SHOW" then
    Mailbox.collected = 0
    return
  end
  local b = Mailbox.busy
  if not b or not b.waiting then return end
  if e == "MAIL_INBOX_UPDATE" and b.kind == "collect" then b.evt = true
  elseif e == "MAIL_SEND_SUCCESS" and b.kind == "send" then b.evt = true end
end

-- UI_ERROR_MESSAGE (through Core.Safe).
function Mailbox.OnError(msg)
  local b = Mailbox.busy
  if not b or type(msg) ~= "string" then return end
  if b.kind == "collect" then
    if ERR_INV_FULL and msg == ERR_INV_FULL then b.fail = "Bags full"
    elseif ERR_ITEM_MAX_COUNT and msg == ERR_ITEM_MAX_COUNT then
      if b.waiting then b.evt = true end
      b.skipCur = true
    end
  else
    for _, name in ipairs(Mailbox.SEND_ERRORS) do
      local text = getglobal(name)
      if text and msg == text then b.fail = msg return end
    end
  end
end

-- ---------- collect ----------

local function newCollect(start, single)
  local total = 0
  local n = GetInboxNumItems() or 0
  for i = start, single and start or n do
    if A.MailRules.Plan(header(i)) ~= "skip" then total = total + 1 end
  end
  return { kind = "collect", idx = start, single = single, waiting = false, evt = false, at = GetTime(),
           gold = 0, mails = 0, cur = false, tries = 0, total = total, done = 0 }
end

local function progressText(b, what)
  return what .. " " .. (b.done + 1) .. " of " .. b.total
end

local function start(b)
  Mailbox.busy = b
  Mailbox.progress = { done = 0, total = b.total, kind = b.kind }
  changed()
end

function Mailbox.CollectAll()
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if (GetInboxNumItems() or 0) < 1 then return refuse("The mailbox is empty") end
  A.Mail.Read()
  start(newCollect(1, false))
  say("Collecting", "text")
  return true
end

function Mailbox.CollectOne(i)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return refuse("No such mail") end
  A.Mail.Read()
  start(newCollect(i, true))
  say("Collecting", "text")
  return true
end

local function mailDone(b)
  b.done = b.done + 1
  if Mailbox.progress then Mailbox.progress.done = b.done end
  b.cur, b.tries, b.skipCur = false, 0, false
end

local function waitFor(b)
  b.waiting, b.evt, b.at = true, false, GetTime()
end

-- One step of a collect chain. Returns true when the chain ended.
local function collectStep(b)
  while true do
    local n = GetInboxNumItems() or 0
    if b.idx > n then return finish(b) end
    local i = b.idx
    local h = header(i)
    local cur = b.cur
    if cur and cur.idx ~= i then cur = false end
    if cur and cur.skip then
      -- ERR_ITEM_MAX_COUNT: leave this mail as it is
      mailDone(b)
      b.idx = i + 1
      if b.single then return finish(b) end
    elseif holds(h) and h.cod <= 0 and not h.isGM then
      if not cur then
        local plan = A.MailRules.Plan(h)
        if plan == "take" and not isAH(h.sender, h.subject) and h.body == nil then
          -- the body decides whether the mail may be deleted afterwards
          local body = GetInboxText(i)
          b.cur = { idx = i, del = (body == "") }
          return false
        end
        b.cur = { idx = i, del = (plan == "take+delete"), counted = false }
        cur = b.cur
      end
      if b.tries >= Mailbox.MAX_TRIES then
        mailDone(b)
        b.idx = i + 1
        if b.single then return finish(b) end
      else
        b.tries = b.tries + 1
        b.cur.gain = h.money
        say(progressText(b, "Collecting"), "text")
        waitFor(b)
        if h.money > 0 then TakeInboxMoney(i) else TakeInboxItem(i) end
        return false
      end
    elseif cur and cur.del and not holds(h) and h.cod <= 0 and not h.isGM then
      -- emptied: the plan said delete
      cur.del = false
      cur.deleting = true
      waitFor(b)
      DeleteInboxItem(i)
      return false
    elseif not cur and A.MailRules.Plan(h) == "take+delete" and not holds(h) then
      -- AH mail with nothing left (a result, an outbid notice): just delete it
      b.cur = { idx = i, deleting = true }
      waitFor(b)
      DeleteInboxItem(i)
      return false
    else
      -- skipped, or emptied and kept
      if cur then mailDone(b) end
      b.idx = i + 1
      b.cur, b.tries = false, 0
      if b.single then return finish(b) end
    end
  end
end

-- What a confirming event settles for a collect chain.
local function collectConfirm(b)
  local cur = b.cur
  if cur and cur.deleting then
    mailDone(b)
    -- the later mails shifted down: stay at this index
    if b.single then return finish(b) end
    return false
  end
  if cur and cur.gain and cur.gain > 0 then
    b.gold = b.gold + cur.gain
    Mailbox.collected = Mailbox.collected + cur.gain
    cur.gain = 0
  end
  if cur and not cur.counted then
    cur.counted = true
    b.mails = b.mails + 1
  end
  return false
end

-- ---------- delete, return, read ----------

function Mailbox.Read(i)
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return nil end
  return GetInboxText(i)
end

function Mailbox.Delete(i)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return refuse("No such mail") end
  local h = header(i)
  if holds(h) then return refuse("That mail still holds money or an item") end
  DeleteInboxItem(i)
  say("Deleted", "text")
  return true
end

function Mailbox.Return(i)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return refuse("No such mail") end
  local h = header(i)
  if isAH(h.sender, h.subject) then return refuse("Auction house mail can't be returned") end
  ReturnInboxItem(i)
  say("Returned", "text")
  return true
end

-- ---------- send ----------

-- attachments = list of { bag, slot, key, count }. subject blank: automatic per mail.
function Mailbox.Send(to, subject, body, moneyAmount, attachments)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  to = U.trim(to or "")
  if to == "" then return refuse("Who is it for?") end
  if string.lower(to) == string.lower(UnitName("player") or "") then return refuse("You can't mail yourself") end
  attachments = attachments or {}
  local total = table.getn(attachments)
  if total == 0 then total = 1 end
  local b = { kind = "send", to = to, subject = subject or "", body = body or "", money = moneyAmount or 0,
              list = attachments, i = 0, sent = 0, skipped = 0, total = total, waiting = false, evt = false,
              at = GetTime(), moneySet = false, bare = table.getn(attachments) == 0 }
  start(b)
  say("Sending", "text")
  return true
end

-- Fills the send slot with the stack of attachment a. Returns the item name, or nil when it is not there.
local function attach(a)
  local link = GetContainerItemLink(a.bag, a.slot)
  local _, count = GetContainerItemInfo(a.bag, a.slot)
  if not link or U.keyFromLink(link) ~= a.key or count ~= a.count then return nil end
  ClearCursor()
  if GetSendMailItem() then
    ClickSendMailItemButton()
    ClearCursor()
  end
  PickupContainerItem(a.bag, a.slot)
  ClickSendMailItemButton()
  local name, _, got = GetSendMailItem()
  if not name or got ~= a.count then
    clearSendSlot()
    return nil
  end
  return name
end

local function sendStep(b)
  local name, a
  if b.bare then
    if b.sent > 0 then return finish(b) end
  else
    while b.i < table.getn(b.list) do
      b.i = b.i + 1
      a = b.list[b.i]
      name = attach(a)
      if name then break end
      b.skipped = b.skipped + 1
      say("Skipped an attachment that changed in your bags", "bad")
    end
    if not name then return finish(b) end
  end
  if not b.moneySet then
    b.moneySet = true
    if b.money > 0 then SetSendMailMoney(b.money) end
  end
  local subject = b.subject
  if subject == "" and name then subject = A.MailRules.Subject(name, a.count) end
  if subject == "" then subject = b.money > 0 and "Money" or "(no subject)" end
  say("Sent " .. b.sent .. " of " .. b.total, "text")
  waitFor(b)
  SendMail(b.to, subject, b.body)
  return false
end

-- ---------- tick ----------

-- Every frame (through Core.Safe).
function Mailbox.Tick(now)
  local b = Mailbox.busy
  if not b then return end
  if b.fail then return finish(b, b.fail) end
  if b.waiting then
    if b.evt then
      b.waiting, b.evt = false, false
      if b.kind == "collect" then
        if b.skipCur and b.cur then b.cur.skip = true end
        b.skipCur = false
        if collectConfirm(b) then return end
      else
        b.sent = b.sent + 1
        if Mailbox.progress then Mailbox.progress.done = b.sent end
      end
    elseif now - b.at >= Mailbox.TIMEOUT then
      return finish(b, "No reply from the mailbox", "bad")
    else
      return
    end
  end
  if b.stop then return finish(b, "Stopped", "text") end
  if b.kind == "collect" then collectStep(b) else sendStep(b) end
  changed()
end
