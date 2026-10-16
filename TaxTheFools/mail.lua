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

-- The dedup key of a mail: its subject, money and the hour it expires. Mail lives a fixed time, so
-- now + daysLeft*86400 is the same moment on every visit and relog. Spec section 2 writes
-- now - daysLeft*86400, which drifts two hours per hour of play (daysLeft falls as now rises) and would
-- count every mail again on the next visit.
function Mail.Key(subject, money, daysLeft, now, hourShift)
  return subject .. "|" .. money .. "|" .. (math.floor((now + (daysLeft or 0) * 86400) / 3600) + (hourShift or 0))
end

-- Mail.BOUNDARY: an expiry this close (seconds) to an hour boundary may fall on either side of it on
-- another read, because daysLeft is a rounded float.
Mail.BOUNDARY = 5

-- seenMail[key] is { at = when last changed, n = how many such mails are recorded }; n = 0 reads as unseen.
-- The old format was a bare timestamp, which reads as one recorded mail.
local function seenCount(seen, key)
  local v = seen[key]
  if type(v) == "table" then return v.n or 1 end
  if v then return 1 end
  return 0
end

-- The key of the hour on the other side of a nearby boundary, or nil when the expiry is not near one.
local function adjacentShift(daysLeft, now)
  local e = now + (daysLeft or 0) * 86400
  local frac = e - math.floor(e / 3600) * 3600
  if frac < Mail.BOUNDARY then return -1 end
  if frac > 3600 - Mail.BOUNDARY then return 1 end
  return nil
end

-- Deposit of a posting for Sales.Record: the learned figure, else Turtle's formula from the vendor price
-- (estimated), else 0. Returns deposit, estimated.
function Mail.Deposit(key, p)
  local U = A.Util
  local id = U.keyId(key)
  if not id then return 0, false end
  local items = TaxTheFoolsDB.items
  local minutes = p.minutes or 480
  local rec = items[id]
  local maxStack = rec and rec.st or p.stack
  local learned = A.Sell.Deposit(items, id, minutes, p.stack, maxStack)
  if learned then return learned, false end
  local vendor = A.Items and A.Items.Vendor(id)
  if vendor then return A.Craft.Deposit(vendor, maxStack, p.stack, minutes, 1), true end
  return 0, false
end

-- True while an auction mail still holds what it was sent with: the gold of a sale or a refunded bid, the
-- item of a win, expiry or cancel. Once collected it is the same result seen again, never a new one.
function Mail.HasPayload(outcome, money, hasItem)
  if outcome == "sold" or outcome == "outbid" then return (money or 0) > 0 end
  return hasItem and true or false
end

-- How many mails Mail.Read has recorded under this mail's key (the adjacent hour too, near a boundary),
-- and the key that holds that count.
function Mail.Recorded(subject, money, daysLeft, now)
  local key = Mail.Key(subject, money, daysLeft, now)
  local seen = A.DB.Char().seenMail
  if not seen then return 0, key end
  local done = seenCount(seen, key)
  local shift = adjacentShift(daysLeft, now)
  if shift then
    local adj = Mail.Key(subject, money, daysLeft, now, shift)
    local other = seenCount(seen, adj)
    if other > done then done, key = other, adj end
  end
  return done, key
end

-- A recorded mail has left the inbox (Collect all deleted it): one fewer under its key, so a later identical
-- mail is counted as new. The entry stays at n = 0 with a fresh `at`, so device sync sees the newer count
-- instead of bringing the old one back; the 120-day prune removes it.
function Mail.Forget(key)
  if not key then return end
  local seen = A.DB.Char().seenMail
  local v = seen and seen[key]
  if not v then return end
  local n = seenCount(seen, key)
  if n <= 0 then return end
  seen[key] = { at = time(), n = n - 1 }
end

-- Reads every mail header and records each new auction mail that still holds its payload. Identical mails
-- (same subject, money and expiry hour) share a key, so each key counts its mails in this read and records
-- only those beyond the number already recorded.
function Mail.Read()
  local char = A.DB.Char()
  local now = time()
  local n = GetInboxNumItems() or 0
  local order, groups = {}, {}
  for i = 1, n do
    local _, _, _, subject, money, _, daysLeft, hasItem = GetInboxHeaderInfo(i)
    local outcome, name = Sales.Classify(subject)
    if outcome and Mail.HasPayload(outcome, money, hasItem) then
      money = money or 0
      local key = Mail.Key(subject, money, daysLeft, now)
      local g = groups[key]
      if not g then
        g = { count = 0, outcome = outcome, name = name, money = money, adj = nil }
        local shift = adjacentShift(daysLeft, now)
        if shift then g.adj = Mail.Key(subject, money, daysLeft, now, shift) end
        groups[key] = g
        table.insert(order, key)
      end
      g.count = g.count + 1
    end
  end
  char.seenMail = char.seenMail or {}
  local seen = char.seenMail
  Sales.ResolveNames(char, TaxTheFoolsDB.items)
  for _, key in ipairs(order) do
    local g = groups[key]
    -- Every result is recorded now, even for an item the cache can't name yet: it is kept by name and
    -- given its key later (Sales.ResolveNames). Holding it back would leave the mail uncollectable for good
    -- when the item is never seen.
    do
      local done = seenCount(seen, key)
      if g.adj then
        local other = seenCount(seen, g.adj)
        if other > done then done = other end
      end
      local fresh = g.count - done
      if fresh > 0 then
        for _ = 1, fresh do
          local e = Sales.Record(char, g.outcome, g.name, g.money, now, TaxTheFoolsDB.items, Mail.Deposit)
          A.Core.Safe("ledger", A.LedgerHooks.Mail, char, e, g.name)
        end
        seen[key] = { at = now, n = done + fresh }
      elseif done > seenCount(seen, key) then
        seen[key] = { at = now, n = done }
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
