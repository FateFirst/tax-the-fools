TaxTheFools = TaxTheFools or {}
local U, D, DB, Scan = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.DB, TaxTheFools.Scan
local Auction = { busy = false, note = false, listeners = {} }
TaxTheFools.Auction = Auction

-- PlaceAuctionBid is called in exactly one place, place() below, and only from
-- Auction.Buy and Auction.Bid, which run from a button's OnClick (phase 3a
-- spec section 2). One pending action at a time: Auction.busy.

-- Replies that end a pending buy or bid as a failure. Matched only where the
-- client defines the global.
Auction.FAILURES = { "ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_HIGHER_BID", "ERR_AUCTION_BID_OWN",
                     "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_RESTRICTED_ACCOUNT" }
Auction.NO_REPLY = "No reply from the auction house. Search again to see whether it went through."

function Auction.ResetState() Auction.busy, Auction.note = false, false end

function Auction.OnChange(fn) table.insert(Auction.listeners, fn) end
function Auction.Changed() for _, fn in ipairs(Auction.listeners) do fn() end end

-- A message for chat and, for D.NOTE_SECS, the status strip.
function Auction.Say(text, token)
  Auction.note = { text = text, token = token or "text", at = GetTime() }
  U.msg(text)
  Auction.Changed()
end

function Auction.Note(now)
  local n = Auction.note
  if n and now - n.at < D.NOTE_SECS then return n end
  return nil
end

local function refuse(text)
  Auction.Say(text, "bad")
  return false
end

-- What identifies one auction: item key, stack count, buyout, owner (may be nil).
function Auction.Sig(r) return { key = r.key, count = r.count, buyout = r.buyout, owner = r.owner } end

-- Row index of the current "list" page, re-read now, if it is still the auction
-- sig describes. The owner is compared only when both sides know it.
function Auction.Match(index, sig)
  if not index or not sig then return nil end
  local r = Scan.ReadRow(index)
  if not r then return nil end
  if r.key ~= sig.key or r.count ~= sig.count or r.buyout ~= sig.buyout then return nil end
  if r.owner and sig.owner and r.owner ~= sig.owner then return nil end
  return r
end

-- The next acceptable bid: the current bid plus the increment, or the minimum bid.
function Auction.BidAmount(r)
  if (r.bid or 0) > 0 then return r.bid + (r.minInc or 0) end
  return r.minBid or 0
end

function Auction.NeedsConfirm(amount)
  local limit = DB.S().buy.confirmAbove or 0
  return limit > 0 and amount >= limit
end

function Auction.Own(r) return r.owner ~= nil and r.owner == DB.charName end

local function place(kind, index, r, amount, after)
  Auction.busy = { kind = kind, key = r.key, count = r.count, amount = amount, at = GetTime(),
                   sig = Auction.Sig(r), name = r.name, after = after or false }
  PlaceAuctionBid("list", index, amount)
  Auction.Changed()
  return true
end

-- Buy listing `index` if it is still `sig`. A buyout at or above the
-- confirmation amount opens the confirmation window instead; confirmed is
-- set only by that window's Buy button. after(busy) runs on success.
function Auction.Buy(index, sig, after, confirmed)
  if Auction.busy then return refuse("Wait for the auction house to answer the last bid.") end
  local r = Auction.Match(index, sig)
  if not r then return refuse("Listing changed. Search again.") end
  if r.buyout <= 0 then return refuse("That listing has no buyout. Bid instead.") end
  if Auction.Own(r) then return refuse("That is your own auction.") end
  if r.buyout > GetMoney() then return refuse("You can't afford " .. U.money(r.buyout, true) .. ".") end
  if not confirmed and Auction.NeedsConfirm(r.buyout) then
    TaxTheFools.Confirm.Open(index, sig, r, after)
    return "confirm"
  end
  return place("buy", index, r, r.buyout, after)
end

-- Bids are never confirmed: a bid is not a purchase until the auction ends.
function Auction.Bid(index, sig, after)
  if Auction.busy then return refuse("Wait for the auction house to answer the last bid.") end
  local r = Auction.Match(index, sig)
  if not r then return refuse("Listing changed. Search again.") end
  if Auction.Own(r) then return refuse("That is your own auction.") end
  local amount = Auction.BidAmount(r)
  -- On 1.12 a bid at or above the buyout buys the item.
  if r.buyout > 0 and amount >= r.buyout then return refuse("The next bid would reach the buyout. Use Buy.") end
  if r.high then return refuse("You are already the high bidder.") end
  if amount > GetMoney() then return refuse("You can't afford " .. U.money(amount, true) .. ".") end
  return place("bid", index, r, amount, after)
end

local function finish(ok, text)
  local b = Auction.busy
  Auction.busy = false
  if not ok then return Auction.Say(text, "bad") end
  if b.kind == "buy" then
    Scan.SnapshotRemove(b.sig)
    Auction.Say("Bought " .. b.name .. " x" .. b.count .. " for " .. U.money(b.amount, true) .. ".", "good")
  else
    Auction.Say("Bid " .. U.money(b.amount, true) .. " on " .. b.name .. " x" .. b.count .. ".", "good")
  end
  if b.after then b.after(b) end
end

-- CHAT_MSG_SYSTEM and UI_ERROR_MESSAGE: arg1 is the message text.
function Auction.OnMessage(msg)
  if not Auction.busy or type(msg) ~= "string" then return end
  if ERR_AUCTION_BID_PLACED and msg == ERR_AUCTION_BID_PLACED then return finish(true) end
  for _, name in ipairs(Auction.FAILURES) do
    local text = getglobal(name)
    if text and msg == text then return finish(false, msg) end
  end
end

function Auction.Tick(now)
  local b = Auction.busy
  if b and now - b.at >= D.ACTION_TIMEOUT then finish(false, Auction.NO_REPLY) end
end
