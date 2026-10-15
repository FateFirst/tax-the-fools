TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local Ledger = {}
TaxTheFools.Ledger = Ledger

-- Pure: characters, the clock and every amount arrive as arguments.
-- Storage: char.ledger (list, oldest first, { at, kind, amount, key, qty, who }),
-- char.pendingBids (list, oldest first, { name, amount, at, key }), char.ledgerBackfilled.

Ledger.MAX_ENTRIES = 5000
Ledger.KEEP_DAYS = 180
Ledger.BID_DAYS = 7

local SIGN = { sale = 1, vendorIn = 1, mailIn = 1, buy = -1, bid = -1, deposit = -1, vendorOut = -1, mailOut = -1,
  transferIn = 0, transferOut = 0 }

function Ledger.Sign(kind) return SIGN[kind] or 0 end

-- Appends an entry; amounts <= 0 are ignored. Returns the entry, or nil.
function Ledger.Add(char, entry, now)
  if not char or not entry or not entry.amount or entry.amount <= 0 or not SIGN[entry.kind] then return nil end
  char.ledger = char.ledger or {}
  local e = { at = entry.at or now or time(), kind = entry.kind, amount = entry.amount, key = entry.key, qty = entry.qty, who = entry.who }
  table.insert(char.ledger, e)
  while table.getn(char.ledger) > Ledger.MAX_ENTRIES do table.remove(char.ledger, 1) end
  return e
end

function Ledger.Prune(char, now)
  if not char or not char.ledger then return end
  local cutoff = (now or time()) - Ledger.KEEP_DAYS * 86400
  local kept = {}
  for _, e in ipairs(char.ledger) do
    if e.at >= cutoff then table.insert(kept, e) end
  end
  char.ledger = kept
end

-- Calls fn(entry, charName) for each entry in the window, for the realm's characters or only `who`.
local function each(chars, days, now, who, fn)
  local first = U.day(now) - (days or 30) + 1
  for name, char in pairs(chars or {}) do
    if (not who or who == name) and char.ledger then
      for _, e in ipairs(char.ledger) do
        if U.day(e.at) >= first then fn(e, name) end
      end
    end
  end
end

function Ledger.Totals(chars, days, now, who)
  local t = { inn = 0, out = 0, net = 0, perDay = 0, transferIn = 0, transferOut = 0, byKind = {} }
  each(chars, days, now, who, function(e)
    t.byKind[e.kind] = (t.byKind[e.kind] or 0) + e.amount
    local s = Ledger.Sign(e.kind)
    if s > 0 then t.inn = t.inn + e.amount
    elseif s < 0 then t.out = t.out + e.amount
    elseif e.kind == "transferIn" then t.transferIn = t.transferIn + e.amount
    else t.transferOut = t.transferOut + e.amount end
  end)
  t.net = t.inn - t.out
  t.perDay = t.net / (days or 30)
  return t
end

-- One row per calendar day with entries, newest first. sale/buy/deposit are positive totals;
-- vendor, mail and net are signed. Transfers count nowhere.
function Ledger.Days(chars, days, now, who)
  local byDay = {}
  each(chars, days, now, who, function(e)
    local d = U.day(e.at)
    local r = byDay[d]
    if not r then r = { day = d, sale = 0, buy = 0, deposit = 0, vendor = 0, mail = 0, net = 0 } byDay[d] = r end
    local k, a = e.kind, e.amount
    if k == "sale" then r.sale = r.sale + a
    elseif k == "buy" or k == "bid" then r.buy = r.buy + a
    elseif k == "deposit" then r.deposit = r.deposit + a
    elseif k == "vendorIn" then r.vendor = r.vendor + a
    elseif k == "vendorOut" then r.vendor = r.vendor - a
    elseif k == "mailIn" then r.mail = r.mail + a
    elseif k == "mailOut" then r.mail = r.mail - a end
    r.net = r.net + Ledger.Sign(k) * a
  end)
  local rows = {}
  for _, r in pairs(byDay) do table.insert(rows, r) end
  table.sort(rows, function(a, b) return a.day > b.day end)
  return rows
end

-- One row per item key: { key, income, spend, net, sold, bought }, best net first.
function Ledger.ByItem(chars, days, now, who)
  local by = {}
  each(chars, days, now, who, function(e)
    local k = e.key
    if k then
      local r = by[k]
      if not r then r = { key = k, income = 0, spend = 0, net = 0, sold = 0, bought = 0 } by[k] = r end
      local q = e.qty or 0
      if e.kind == "sale" then r.income = r.income + e.amount r.sold = r.sold + q
      elseif e.kind == "buy" or e.kind == "bid" then r.spend = r.spend + e.amount r.bought = r.bought + q
      elseif e.kind == "deposit" then r.spend = r.spend + e.amount end
    end
  end)
  local rows = {}
  for _, r in pairs(by) do r.net = r.income - r.spend table.insert(rows, r) end
  table.sort(rows, function(a, b)
    if a.net ~= b.net then return a.net > b.net end
    return a.key < b.key
  end)
  return rows
end

-- Once per character: each sold entry in char.sales becomes a sale entry. Returns true when it ran.
function Ledger.Backfill(char)
  if not char or char.ledgerBackfilled then return false end
  for _, s in ipairs(char.sales or {}) do
    if s.outcome == "sold" then
      Ledger.Add(char, { at = s.at, kind = "sale", amount = s.money, key = s.key, qty = s.qty }, s.at)
    end
  end
  char.ledgerBackfilled = true
  return true
end

local function dropOldBids(char, now)
  local cutoff = (now or time()) - Ledger.BID_DAYS * 86400
  local kept = {}
  for _, b in ipairs(char.pendingBids or {}) do
    if b.at >= cutoff then table.insert(kept, b) end
  end
  char.pendingBids = kept
end

-- Remembers a bid (not spending yet); bids older than 7 days are dropped.
function Ledger.PendingBid(char, name, amount, now, key)
  if not char or not name or not amount or amount <= 0 then return end
  now = now or time()
  dropOldBids(char, now)
  table.insert(char.pendingBids, { name = name, amount = amount, at = now, key = key })
end

-- The newest pending bid for this name becomes a bid entry. Returns the entry, or nil.
function Ledger.BidWon(char, name, now)
  if not char then return nil end
  now = now or time()
  dropOldBids(char, now)
  for i = table.getn(char.pendingBids), 1, -1 do
    local b = char.pendingBids[i]
    if b.name == name then
      table.remove(char.pendingBids, i)
      return Ledger.Add(char, { at = now, kind = "bid", amount = b.amount, key = b.key }, now)
    end
  end
  return nil
end

-- An outbid removes the newest pending bid for the name (no spending). Returns true when one was removed.
function Ledger.BidLost(char, name)
  if not char or not char.pendingBids then return false end
  for i = table.getn(char.pendingBids), 1, -1 do
    if char.pendingBids[i].name == name then table.remove(char.pendingBids, i) return true end
  end
  return false
end
