TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
local Hooks = { merchant = false, last = false }
A.LedgerHooks = Hooks

-- Recording only (phase 6 spec section 3): these functions add ledger entries and make no game action call.
-- Callers run them through Core.Safe, which passes at most three arguments, so each takes one or two tables.
-- A.Ledger and A.DB are read at call time.

local function add(kind, amount, key, qty, who, at)
  A.Ledger.Add(A.DB.Char(), { kind = kind, amount = amount, key = key, qty = qty, who = who, at = at }, at or time())
end

-- True when name is one of this realm's characters (case-insensitive).
function Hooks.IsAlt(name)
  if not name then return false end
  local low = string.lower(name)
  for n in pairs(A.DB.Realm().chars) do
    if string.lower(n) == low then return true end
  end
  return false
end

-- b: the finished auction.lua busy record of a buy or bid.
function Hooks.Buy(b) add("buy", b.amount, b.key, b.count) end
function Hooks.Bid(b) A.Ledger.PendingBid(A.DB.Char(), b.name, b.amount, time(), b.key) end

-- p: the post record { key, count, at }; amount: the deposit paid.
function Hooks.Deposit(p, amount) add("deposit", amount, p.key, p.count) end

-- A new auction mail Sales.Record just recorded as e (outcome, money, key, qty, at), for item `name`.
function Hooks.Mail(char, e, name)
  local L = A.Ledger
  if e.outcome == "sold" then
    L.Add(char, { kind = "sale", amount = e.money, key = e.key, qty = e.qty, at = e.at }, e.at)
  elseif e.outcome == "won" then L.BidWon(char, name, e.at)
  elseif e.outcome == "outbid" then L.BidLost(char, name) end
end

-- cur: the mailbox's step { sender, subject, money } from before a confirmed TakeInboxMoney.
-- AH mail is covered by its sale entry.
function Hooks.Take(cur)
  local s = cur.sender
  if (s and string.find(s, "Auction House", 1, true)) or A.Sales.Classify(cur.subject) then return end
  add(Hooks.IsAlt(s) and "transferIn" or "mailIn", cur.money, nil, nil, s)
end

-- b: a send chain whose mail was just confirmed (to, mailMoney, postage).
function Hooks.Sent(b)
  add(Hooks.IsAlt(b.to) and "transferOut" or "mailOut", b.mailMoney or 0, nil, nil, b.to)
  add("mailOut", b.postage or 0, nil, nil, b.to)
end

-- ---------- vendor ----------
-- GetMoney() is compared with the last amount seen. The last amount is kept current on every PLAYER_MONEY and
-- whenever another recorder consumes a change, so only a change that happens while a merchant window is open
-- counts. The addon assumes the merchant, the auction house and the mailbox are never open together (the
-- client allows one interaction window), so nothing else moves money while a merchant is open.

function Hooks.Sync() Hooks.last = GetMoney() end

function Hooks.MerchantShow()
  Hooks.Sync()
  Hooks.merchant = true
end

function Hooks.MerchantClosed()
  Hooks.merchant = false
  Hooks.Sync()
end

function Hooks.OnMoney()
  local now, last = GetMoney(), Hooks.last
  Hooks.last = now
  if not Hooks.merchant or not last or now == last or not A.DB.S().ledger.vendor then return end
  if now > last then add("vendorIn", now - last) else add("vendorOut", last - now) end
end
