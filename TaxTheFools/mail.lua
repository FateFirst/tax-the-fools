TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
-- db.lua and auction.lua load after this file, so A.DB and A.Auction are read at call time.
local Sales = A.Sales
local Mail = { dirty = false }
A.Mail = Mail

-- Auction mail, read from the inbox headers only (phase 4 spec section 2). Opening a mail, reading its
-- invoice, or taking its money or items marks it read or shortens its expiry, so none of that is ever
-- called here: GetInboxNumItems and GetInboxHeaderInfo are the only mail calls this addon makes.

function Mail.ResetState() Mail.dirty = false end

-- MAIL_SHOW and MAIL_INBOX_UPDATE (through Core.Safe): the update fires many times on first open, so the
-- events only mark the inbox dirty and Tick reads it once.
function Mail.OnEvent(e)
  Mail.dirty = true
end

-- The dedup key of a mail: its subject, money and the hour it arrived. Mail lives a fixed time, so
-- now + daysLeft*86400 is the same moment on every visit and relog and (less that fixed lifetime) fixes the
-- arrival hour. Spec section 2 writes now - daysLeft*86400, which drifts two hours per hour of play
-- (daysLeft falls as now rises) and would count every mail again on the next visit.
function Mail.Key(subject, money, daysLeft, now)
  return subject .. "|" .. money .. "|" .. math.floor((now + (daysLeft or 0) * 86400) / 3600)
end

-- Reads every mail header and records each new auction mail once.
function Mail.Read()
  local char = A.DB.Char()
  local now = time()
  local n = GetInboxNumItems() or 0
  for i = 1, n do
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    local outcome, name = Sales.Classify(subject)
    if outcome then
      money = money or 0
      local key = Mail.Key(subject, money, daysLeft, now)
      char.seenMail = char.seenMail or {}
      if not char.seenMail[key] then
        char.seenMail[key] = now
        Sales.Record(char, outcome, name, money, now, TaxTheFoolsDB.items)
      end
    end
  end
end

-- Every frame (through Core.Safe): at most one read, however many events came in.
function Mail.Tick()
  if not Mail.dirty then return end
  Mail.dirty = false
  Mail.Read()
end

-- CHAT_MSG_SYSTEM (through Core.Safe): "Your auction of X sold." is a note only; the mail records the sale.
function Mail.OnMessage(msg)
  local fmt = ERR_AUCTION_SOLD_S
  if type(msg) ~= "string" or not fmt then return end
  local i, j = string.find(fmt, "%s", 1, true)
  if not i then return end
  local pre, post = string.sub(fmt, 1, i - 1), string.sub(fmt, j + 1)
  local lp, lm, lq = string.len(pre), string.len(msg), string.len(post)
  if lm <= lp + lq then return end
  if string.sub(msg, 1, lp) ~= pre or string.sub(msg, lm - lq + 1) ~= post then return end
  A.Auction.Say("Sold: " .. string.sub(msg, lp + 1, lm - lq))
end
