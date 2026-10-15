TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local Sales = {}
TaxTheFools.Sales = Sales

-- Pure: the character record, mail details, owner rows and the items table arrive as arguments.
-- Storage: char.sales (a list, oldest first), char.seenMail (key -> { at, n }), char.postings (phase 3b).

Sales.KEEP_DAYS = 120
Sales.MAX_SALES = 2000
Sales.POSTING_DAYS = 35
Sales.CUT = 0.95            -- the house keeps 5% of a sale; mirrors 1 - D.AH_CUT (data.lua, loaded after this file)

-- Global holding each mail subject format, and the outcome it means.
Sales.SUBJECTS = {
  { "AUCTION_SOLD_MAIL_SUBJECT", "sold" },
  { "AUCTION_EXPIRED_MAIL_SUBJECT", "expired" },
  { "AUCTION_REMOVED_MAIL_SUBJECT", "cancelled" },
  { "AUCTION_WON_MAIL_SUBJECT", "won" },
  { "AUCTION_OUTBID_MAIL_SUBJECT", "outbid" },
}

-- Escapes the Lua pattern magic characters of a client format, then turns its %s into a capture.
local function toPattern(fmt)
  local p = string.gsub(fmt, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = string.gsub(p, "%%%%s", "(.+)")
  return "^" .. p .. "$"
end

-- subject -> outcome, itemName, or nil when it is not an auction mail.
function Sales.Classify(subject)
  if not subject then return nil end
  for _, s in ipairs(Sales.SUBJECTS) do
    local fmt = getglobal(s[1])
    if fmt then
      local _, _, name = string.find(subject, toPattern(fmt))
      if name then return s[2], name end
    end
  end
  return nil
end

-- The key of the item with this name in the items table (id -> { n = name }), or nil.
local function keyByName(items, name)
  local want = string.lower(name or "")
  for id, rec in pairs(items or {}) do
    if rec.n and string.lower(rec.n) == want then return U.key(id) end
  end
  return nil
end

function Sales.KeyByName(items, name) return keyByName(items, name) end

-- The oldest open posting of a key (and of a stack/buyout when given).
local function oldestOpen(list, key, stack, buyout)
  local best = nil
  for _, p in ipairs(list or {}) do
    if not p.done and p.key == key and (not stack or (p.stack == stack and p.buyout == buyout))
       and (not best or (p.at or 0) < (best.at or 0)) then
      best = p
    end
  end
  return best
end

-- The one posting a sale of `money` belongs to, or nil when none or several stack/buyout combinations fit.
-- On 1.12 the sold mail pays buyout less the 5% cut, plus the deposit back. A posting's own deposit is
-- exact; without one, depositFn(key, posting) -> deposit, estimated gives a figure, and an estimated one
-- is trusted to +-50%.
local function soldMatch(list, key, money, depositFn)
  local combos, fits = {}, 0
  local hit = nil
  for _, p in ipairs(list or {}) do
    if not p.done and p.key == key and p.buyout and p.stack then
      local id = p.stack .. "/" .. p.buyout
      if not combos[id] then
        combos[id] = true
        local dep, estimated = p.deposit, false
        if not dep then
          dep, estimated = 0, false
          if depositFn then
            local d, e = depositFn(key, p)
            if d then dep, estimated = d, e end
          end
        end
        local slack = 1
        if estimated then slack = slack + math.floor(dep * 0.5) end
        if math.abs(money - math.floor(p.buyout * Sales.CUT) - dep) <= slack then
          fits = fits + 1
          hit = oldestOpen(list, key, p.stack, p.buyout)
        end
      end
    end
  end
  if fits == 1 then return hit end
  return nil
end

-- Records one auction mail. Returns the sales entry.
-- depositFn (optional) estimates the deposit of a posting that has none, see soldMatch.
function Sales.Record(char, outcome, itemName, money, now, items, depositFn)
  char.sales = char.sales or {}
  money = money or 0
  local key = keyByName(items, itemName)
  -- `at` of a posting added by Reconcile is the reconcile time, not the real posting time, so secs from it is approximate.
  local e = { key = key, outcome = outcome, money = money, at = now }
  if key and outcome == "sold" then
    local p = soldMatch(char.postings, key, money, depositFn)
    if p then
      p.done = outcome
      e.qty = p.stack
      e.unit = p.buyout / p.stack
      e.secs = now - (p.at or now)
    end
  elseif key and (outcome == "expired" or outcome == "cancelled") then
    local p = oldestOpen(char.postings, key)
    if p then p.done = outcome end
  end
  table.insert(char.sales, e)
  return e
end

-- The running totals of one key: { r = result table, unitSum, secsSum, secsN }.
local function newAcc()
  return { r = { sold = 0, expired = 0, cancelled = 0, n = 0, nKnown = 0, income = 0 }, unitSum = 0, secsSum = 0, secsN = 0 }
end

local function add(acc, e)
  local r = acc.r
  r[e.outcome] = r[e.outcome] + 1
  if e.outcome == "sold" then
    r.income = r.income + (e.money or 0)
    if e.qty and e.unit then
      r.nKnown = r.nKnown + 1
      acc.unitSum = acc.unitSum + e.unit
      if e.secs then acc.secsSum = acc.secsSum + e.secs acc.secsN = acc.secsN + 1 end
    end
  end
end

local function finish(acc)
  local r = acc.r
  local total = r.sold + r.expired + r.cancelled
  r.n = total
  if total > 0 then r.rate = r.sold / total end
  if r.nKnown > 0 then r.avgUnit = acc.unitSum / r.nKnown end
  if acc.secsN > 0 then r.avgSecs = acc.secsSum / acc.secsN end
  return r
end

local function counts(e, cutoff)
  return e.at >= cutoff and (e.outcome == "sold" or e.outcome == "expired" or e.outcome == "cancelled")
end

-- Totals for an item across chars (any table of character records) over the last `days` days.
-- { sold, expired, cancelled, rate, n, avgUnit, avgSecs, income }
-- n = sold + expired + cancelled (the rate denominator); nKnown = sold mails whose quantity is known,
-- the sample avgUnit and avgSecs average over.
function Sales.Stats(chars, key, days, now)
  local acc = newAcc()
  local cutoff = now - days * 86400
  for _, char in pairs(chars or {}) do
    for _, e in ipairs(char.sales or {}) do
      if e.key == key and counts(e, cutoff) then add(acc, e) end
    end
  end
  return finish(acc)
end

-- Sales.Stats for every key at once, in one pass over the sales: { [key] = stats }. Keys with no
-- sold, expired or cancelled result in the window are absent.
function Sales.StatsAll(chars, days, now)
  local accs = {}
  local cutoff = now - days * 86400
  for _, char in pairs(chars or {}) do
    for _, e in ipairs(char.sales or {}) do
      if e.key and counts(e, cutoff) then
        local acc = accs[e.key]
        if not acc then acc = newAcc() accs[e.key] = acc end
        add(acc, e)
      end
    end
  end
  local out = {}
  for key, acc in pairs(accs) do out[key] = finish(acc) end
  return out
end

-- Adds a posting for each of your current auctions (owner rows { key, count, buyout, minBid }) that has
-- no open posting of the same key, stack and buyout. Entries are added, never removed.
function Sales.Reconcile(char, ownerRows, now)
  char.postings = char.postings or {}
  local need, order = {}, {}
  for _, r in ipairs(ownerRows or {}) do
    if r.key and r.count and r.buyout and r.buyout > 0 then
      local id = r.key .. "/" .. r.count .. "/" .. r.buyout
      if not need[id] then need[id] = { row = r, rows = 0, open = 0 } table.insert(order, id) end
      need[id].rows = need[id].rows + 1
    end
  end
  for _, p in ipairs(char.postings) do
    if not p.done and p.key and p.stack and p.buyout then
      local n = need[p.key .. "/" .. p.stack .. "/" .. p.buyout]
      if n then n.open = n.open + 1 end
    end
  end
  for _, id in ipairs(order) do
    local n = need[id]
    for _ = 1, n.rows - n.open do
      table.insert(char.postings, { key = n.row.key, stack = n.row.count, bid = n.row.minBid,
                                    buyout = n.row.buyout, at = now, reconciled = true })
    end
  end
end

-- Drops sales and seenMail older than 120 days, keeps at most 2000 sales, and removes consumed
-- postings older than 35 days.
function Sales.Prune(char, now)
  local cutoff = now - Sales.KEEP_DAYS * 86400
  if char.sales then
    local kept = {}
    for _, e in ipairs(char.sales) do
      if (e.at or 0) >= cutoff then table.insert(kept, e) end
    end
    while table.getn(kept) > Sales.MAX_SALES do table.remove(kept, 1) end
    char.sales = kept
  end
  if char.seenMail then
    for k, v in pairs(char.seenMail) do
      local at = type(v) == "table" and v.at or v
      if type(at) ~= "number" or at < cutoff then char.seenMail[k] = nil end
    end
  end
  if char.postings then
    local pc = now - Sales.POSTING_DAYS * 86400
    local kept = {}
    for _, p in ipairs(char.postings) do
      if not (p.done and (p.at or 0) < pc) then table.insert(kept, p) end
    end
    char.postings = kept
  end
end
