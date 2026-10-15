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

-- Progress goes to the status strip only; say also prints one line to chat.
local function setStatus(text, token)
  Mailbox.status = { text = text, token = token or "text" }
  changed()
end

local function say(text, token)
  U.msg(text)
  setStatus(text, token)
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

-- Who a mail is, for following it across our own takes (which change money and attachments): sender, subject
-- and the hour it expires.
local function sigOf(h, daysLeft)
  return (h.sender or "") .. "|" .. (h.subject or "") .. "|" .. math.floor((time() + (daysLeft or 0) * 86400) / 3600)
end

-- The header of mail i as the planner reads it.
local function header(i)
  local _, _, sender, subject, m, cod, daysLeft, hasItem, _, wasReturned, textCreated, _, isGM = GetInboxHeaderInfo(i)
  local h = { sender = sender, subject = subject, money = m or 0, cod = cod or 0, hasItem = hasItem and true or false,
              wasReturned = wasReturned, textCreated = textCreated, isGM = isGM }
  h.sig, h.daysLeft = sigOf(h, daysLeft), daysLeft
  return h
end

local function holds(h) return h.money > 0 or h.hasItem end

-- ---------- finishing ----------

local function release(text, token)
  Mailbox.busy = false
  if Mailbox.progress then Mailbox.progress.kind = false end
  say(text, token)
end

local function collectSummary(b)
  local text
  if b.mails == 0 and b.gold == 0 then
    text = "Nothing to collect"
  else
    text = "Collected " .. money(b.gold) .. " from " .. b.mails .. (b.mails == 1 and " mail" or " mails")
  end
  if (b.left or 0) > 0 then text = text .. ", left " .. b.left .. " for later (item name not known yet)" end
  return text
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
  -- a collect step is confirmed from the headers, never from the event: an update only prompts a re-check
  if e == "MAIL_INBOX_UPDATE" and b.kind == "collect" then b.at = GetTime()
  elseif e == "MAIL_SEND_SUCCESS" and b.kind == "send" then b.evt = true end
end

-- UI_ERROR_MESSAGE (through Core.Safe).
function Mailbox.OnError(msg)
  local b = Mailbox.busy
  if not b or type(msg) ~= "string" then return end
  if b.kind == "collect" then
    if ERR_INV_FULL and msg == ERR_INV_FULL then b.fail = "Bags full"
    elseif ERR_ITEM_MAX_COUNT and msg == ERR_ITEM_MAX_COUNT and b.waiting then b.skipCur = true end
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
           gold = 0, mails = 0, cur = false, tries = 0, total = total, done = 0, counted = false,
           key = false, looked = false, left = 0 }
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
  setStatus("Collecting", "text")
  return true
end

function Mailbox.CollectOne(i)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return refuse("No such mail") end
  A.Mail.Read()
  start(newCollect(i, true))
  setStatus("Collecting", "text")
  return true
end

local function waitFor(b)
  b.waiting, b.evt, b.at = true, false, GetTime()
end

-- Forgets the mail at the index: whatever is there next is looked at afresh.
local function nextMail(b)
  b.cur, b.tries, b.counted, b.key, b.looked = false, 0, false, false, false
end

local function countDone(b)
  b.done = b.done + 1
  if Mailbox.progress then Mailbox.progress.done = b.done end
end

-- Moves past the mail at the index. counts: it was acted on.
local function advance(b, counts)
  if counts then countDone(b) end
  b.idx = b.idx + 1
  nextMail(b)
  return b.single
end

-- Did the call in b.cur land? Read from the header at the index. Returns "yes", "vanished" (a take after
-- which the mail left the inbox: the client removed it, or the list shifted under it) or nil. cur.n is the
-- inbox count from before the call.
local function landed(b)
  local cur = b.cur
  local n = GetInboxNumItems() or 0
  local h = n >= cur.idx and header(cur.idx)
  local gone = n < cur.n or not h or h.sig ~= cur.sig
  if cur.action == "delete" then return gone and "yes" or nil end
  if gone then return "vanished" end
  if cur.action == "money" and h.money <= 0 then return "yes" end
  if cur.action == "item" and not h.hasItem then return "yes" end
  return nil
end

-- First look at the mail at the index, before anything is taken from it. An auction result is collected
-- only once Mail.Read has recorded it; its seenMail key is kept so a delete can forget it. A sale, expiry or
-- cancel Mail.Read deferred (the item name isn't cached yet) is left for a later visit. Returns true when the
-- mail is to be left alone.
local function firstLook(b, h, plan)
  b.looked, b.key = true, false
  if plan == "skip" then return false end
  local Mail = A.Mail
  local outcome = A.Sales.Classify(h.subject)
  if not outcome or not Mail.HasPayload(outcome, h.money, h.hasItem) then return false end
  local n, key = Mail.Recorded(h.subject, h.money, h.daysLeft, time())
  if n > 0 then
    b.key = key
    return false
  end
  if outcome == "won" or outcome == "outbid" then return false end
  b.left = b.left + 1
  return true
end

-- One tick of a collect chain: first settle the call we are waiting on, then make at most one new call.
-- Returns true when the chain ended.
local function collectStep(b, now)
  if b.waiting then
    local cur = b.cur
    if b.skipCur then
      -- ERR_ITEM_MAX_COUNT: this mail is left as it is and does not count
      b.skipCur, b.waiting = false, false
      if advance(b, true) then return finish(b) end
    else
      local how = landed(b)
      if how then
        b.waiting = false
        if cur.action == "delete" then
          -- the later mails shifted down: the index stays
          A.Mail.Forget(b.key)
          countDone(b)
          nextMail(b)
          if b.single then return finish(b) end
        else
          -- a take that vanished the mail still landed: its gold is the header's from before the call
          if cur.action == "money" then
            b.gold = b.gold + cur.money
            Mailbox.collected = Mailbox.collected + cur.money
          end
          if not b.counted then
            b.counted = true
            b.mails = b.mails + 1
          end
          b.cur = false
          if how == "vanished" then
            -- no delete step for a mail that is already gone; the later mails shifted down
            countDone(b)
            nextMail(b)
            if b.single then return finish(b) end
          end
        end
      elseif now - b.at >= Mailbox.TIMEOUT then
        return finish(b, "No reply from the mailbox", "bad")
      else
        return false
      end
    end
  end
  if b.stop then return finish(b, "Stopped", "text") end
  while true do
    local n = GetInboxNumItems() or 0
    if b.idx > n then return finish(b) end
    local i = b.idx
    -- whatever is at the index now is planned afresh; no plan outlives the mail it was made for
    local h = header(i)
    local plan = A.MailRules.Plan(h)
    local leave = false
    if not b.looked then leave = firstLook(b, h, plan) end
    if leave then
      if advance(b, false) then return finish(b) end
    elseif plan == "skip" then
      if advance(b, b.counted) then return finish(b) end
    elseif holds(h) then
      if b.tries >= Mailbox.MAX_TRIES then
        if advance(b, true) then return finish(b) end
      else
        b.tries = b.tries + 1
        setStatus(progressText(b, "Collecting"), "text")
        b.cur = { idx = i, sig = h.sig, n = n, money = h.money, action = h.money > 0 and "money" or "item" }
        waitFor(b)
        b.skipCur = false   -- a unique-item error from before this take must not skip this mail
        if h.money > 0 then TakeInboxMoney(i) else TakeInboxItem(i) end
        return false
      end
    elseif plan == "take+delete" then
      -- auction house mail with nothing left: read first (marks it read, as TurtleMail does before deleting)
      b.cur = { idx = i, sig = h.sig, n = n, action = "delete" }
      waitFor(b)
      GetInboxText(i)
      DeleteInboxItem(i)
      return false
    else
      -- emptied player mail stays; move on
      if advance(b, b.counted) then return finish(b) end
    end
  end
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
  if h.isGM then return refuse("Game master mail can't be touched") end
  if holds(h) then return refuse("That mail still holds money or an item") end
  DeleteInboxItem(i)
  say("Deleted", "text")
  return true
end

function Mailbox.Return(i)
  if Mailbox.busy then return refuse("Busy. Stop the current action first.") end
  if not i or i < 1 or i > (GetInboxNumItems() or 0) then return refuse("No such mail") end
  local h = header(i)
  if h.isGM then return refuse("Game master mail can't be touched") end
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
  if table.getn(attachments) == 0 and (moneyAmount or 0) <= 0 then return refuse("Nothing to send") end
  local total = table.getn(attachments)
  if total == 0 then total = 1 end
  local b = { kind = "send", to = to, subject = subject or "", body = body or "", money = moneyAmount or 0,
              list = attachments, i = 0, sent = 0, skipped = 0, total = total, waiting = false, evt = false,
              at = GetTime(), moneySet = false, bare = table.getn(attachments) == 0 }
  start(b)
  setStatus("Sending", "text")
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
  -- every mail sets its money, so a failed send's money is never carried into this one
  if not b.moneySet then
    b.moneySet = true
    SetSendMailMoney(b.money)
  else
    SetSendMailMoney(0)
  end
  local subject = b.subject
  if subject == "" and name then subject = A.MailRules.Subject(name, a.count) end
  if subject == "" then subject = b.money > 0 and "Money" or "(no subject)" end
  setStatus("Sent " .. b.sent .. " of " .. b.total, "text")
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
  if b.kind == "collect" then
    collectStep(b, now)
    changed()
    return
  end
  if b.waiting then
    if b.evt then
      b.waiting, b.evt = false, false
      b.sent = b.sent + 1
      if Mailbox.progress then Mailbox.progress.done = b.sent end
    elseif now - b.at >= Mailbox.TIMEOUT then
      return finish(b, "No reply from the mailbox", "bad")
    else
      return
    end
  end
  if b.stop then return finish(b, "Stopped", "text") end
  sendStep(b)
  changed()
end
