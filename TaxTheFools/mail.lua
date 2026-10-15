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

-- seenMail[key] is { at = when first recorded, n = how many such mails are recorded }; the old format was
-- a bare timestamp, which reads as one recorded mail.
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

-- Reads every mail header and records each new auction mail. Identical mails (same subject, money and
-- expiry hour) share a key, so each key counts its mails in this read and records only those beyond the
-- number already recorded.
function Mail.Read()
  local char = A.DB.Char()
  local now = time()
  local n = GetInboxNumItems() or 0
  local order, groups = {}, {}
  for i = 1, n do
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    local outcome, name = Sales.Classify(subject)
    if outcome then
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
  for _, key in ipairs(order) do
    local g = groups[key]
    -- A sale, expiry or cancel of an item the cache cannot name yet is left for the next visit.
    if g.outcome == "won" or g.outcome == "outbid" or Sales.KeyByName(TaxTheFoolsDB.items, g.name) then
      local done = seenCount(seen, key)
      if g.adj then
        local other = seenCount(seen, g.adj)
        if other > done then done = other end
      end
      local fresh = g.count - done
      if fresh > 0 then
        for _ = 1, fresh do
          Sales.Record(char, g.outcome, g.name, g.money, now, TaxTheFoolsDB.items, Mail.Deposit)
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
