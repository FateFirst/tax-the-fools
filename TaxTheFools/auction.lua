TaxTheFools = TaxTheFools or {}
local U, D, DB, Scan, Sell = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.Sell
local Auction = { busy = false, note = false, listeners = {} }
TaxTheFools.Auction = Auction

-- PlaceAuctionBid is called in exactly one place, place() below, and only from
-- Auction.Buy and Auction.Bid, which run from a button's OnClick (phase 3a
-- spec section 2). StartAuction, CancelAuction and SplitContainerItem are each
-- called in exactly one place too: Auction.Post, Auction.Cancel (via place-like
-- code below) and Auction.Split, from a click or a confirmation window's button
-- (phase 3b spec section 2). One pending action at a time: Auction.busy.

-- Replies that end a pending buy or bid as a failure. Matched only where the
-- client defines the global.
Auction.FAILURES = { "ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_HIGHER_BID", "ERR_AUCTION_BID_OWN",
                     "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_RESTRICTED_ACCOUNT",
                     "ERR_AUCTION_LIMITED_DURATION_ITEM", "ERR_AUCTION_REPAIR_ITEM", "ERR_AUCTION_USED_CHARGES" }
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
local function matchRow(r, sig)
  if not r then return nil end
  if r.key ~= sig.key or r.count ~= sig.count or r.buyout ~= sig.buyout then return nil end
  if r.owner and sig.owner and r.owner ~= sig.owner then return nil end
  return r
end

function Auction.Match(index, sig)
  if not index or not sig then return nil end
  return matchRow(Scan.ReadRow(index), sig)
end

-- Row i of your own auctions (the "owner" list), in the shape of Scan.ReadRow.
function Auction.OwnerRow(i) return Scan.ReadRow(i, "owner") end

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

local function place(kind, index, r, amount, after, onFail)
  Auction.busy = { kind = kind, key = r.key, count = r.count, amount = amount, at = GetTime(),
                   sig = Auction.Sig(r), name = r.name, after = after or false, onFail = onFail or false }
  PlaceAuctionBid("list", index, amount)
  Auction.Changed()
  return true
end

local function clearSellSlot()
  ClearCursor()
  if GetAuctionSellItemInfo() then
    ClickAuctionSellItemButton()
    ClearCursor()
  end
end

-- Post one stack of `stack` units of `key` from bag slot (bag, slot) for the given
-- starting bid and buyout (both totals, as StartAuction takes them) and duration in
-- minutes. Refuses, with no StartAuction, when the slot no longer holds key x stack,
-- the bid is above the buyout, the buyout is under the price floor (unless
-- allowBelowFloor) or the deposit can't be paid. after(busy) runs on success;
-- onFail(text) when the reply (or its absence) says it failed.
function Auction.Post(bag, slot, stack, bid, buyout, minutes, key, allowBelowFloor, after, onFail)
  bid, buyout = math.floor(bid), math.floor(buyout)          -- whole copper only
  if Auction.busy then return refuse("Wait for the auction house to answer the last action.") end
  local k, id = U.keyFromLink(GetContainerItemLink(bag, slot))
  local _, have = GetContainerItemInfo(bag, slot)
  if not k or k ~= key or have ~= stack then return refuse("Your bags changed. Pick the item again.") end
  if bid > buyout then return refuse("The starting bid is above the buyout.") end
  local m = DB.Realm().market[key]
  local s = DB.S().sell
  if m and m.v and not allowBelowFloor then
    local floor = math.ceil(m.v * s.floorPct / 100)
    if buyout < floor * stack then return refuse("That is below your floor. Tick Allow below floor to post it.") end
  end
  -- Get the stack into the sell slot, then check the deposit: the learned figure, or the client's.
  local learned = Sell.Deposit(TaxTheFoolsDB.items, id, minutes, stack)
  if learned and learned > GetMoney() then
    return refuse("You can't afford the deposit of " .. U.money(learned, true) .. ".")
  end
  clearSellSlot()
  PickupContainerItem(bag, slot)
  ClickAuctionSellItemButton()
  local deposit = learned or CalculateAuctionDeposit(minutes)
  if deposit > GetMoney() then
    clearSellSlot()
    return refuse("You can't afford the deposit of " .. U.money(deposit, true) .. ".")
  end
  local name = GetItemInfo(id) or key
  Auction.busy = { kind = "post", key = key, id = id, count = stack, bid = bid, buyout = buyout, minutes = minutes,
                   before = GetMoney(), at = GetTime(), name = name, after = after or false, onFail = onFail or false }
  StartAuction(bid, buyout, minutes)
  Auction.Changed()
  return true
end

-- True when bag can hold any item: the backpack, or a bag whose item is a plain "Bag". Quivers, ammo
-- pouches and soul/herb/enchanting bags refuse other items. Unknown (an API or link missing) counts as general.
local function generalBag(bag)
  if bag == 0 then return true end
  if not (GetInventoryItemLink and ContainerIDToInventoryID and GetItemInfo) then return true end
  local link = GetInventoryItemLink("player", ContainerIDToInventoryID(bag))
  if not link then return true end
  -- 1.12's GetItemInfo takes an id or an "item:..." string, not a coloured hyperlink.
  local id = U.parseLink(link)
  if not id then return true end
  local _, _, _, _, itemType, subType = GetItemInfo(id)
  if not subType then return true end
  return subType == "Bag" and (itemType == nil or itemType == "Container")
end

-- Split `size` units off the stack at (bag, slot) into an empty bag slot. No server reply
-- and no lock: the new stack shows on the next BAG_UPDATE. Returns true, or nil and why.
function Auction.Split(bag, slot, size)
  local function no(text) refuse(text) return nil, text end
  if Auction.busy then return no("Wait for the auction house to answer the last action.") end
  local _, have = GetContainerItemInfo(bag, slot)
  if not have or not size or size < 1 or size >= have then return no("Nothing to split.") end
  local eb, es = nil, nil
  for b = 0, 4 do
    if not eb and generalBag(b) then
      for sl = 1, GetContainerNumSlots(b) do
        if not eb and not GetContainerItemInfo(b, sl) then eb, es = b, sl end
      end
    end
  end
  if not eb then return no("No empty slot in a normal bag to split into.") end
  ClearCursor()
  SplitContainerItem(bag, slot, size)
  PickupContainerItem(eb, es)
  return true
end

-- Cancel your auction at owner-list row `index` if it is still `sig`. One with a bid asks first
-- (the deposit is lost and the bidder refunded); confirmed is set only by that window's button.
function Auction.Cancel(index, sig, after, onFail, confirmed)
  if Auction.busy then return refuse("Wait for the auction house to answer the last action.") end
  if not index or not sig then return refuse("Auction changed. Check the Auctions tab.") end
  local r = matchRow(Auction.OwnerRow(index), sig)
  if not r then return refuse("Auction changed. Check the Auctions tab.") end
  if r.bid > 0 and not confirmed then
    TaxTheFools.Confirm.OpenCancel(index, sig, r, after, onFail)
    return "confirm"
  end
  Auction.busy = { kind = "cancel", key = r.key, count = r.count, at = GetTime(), sig = Auction.Sig(r),
                   name = r.name, after = after or false, onFail = onFail or false }
  CancelAuction(index)
  Auction.Changed()
  return true
end

-- Buy listing `index` if it is still `sig`. A buyout at or above the
-- confirmation amount opens the confirmation window instead; confirmed is
-- set only by that window's Buy button. after(busy) runs on success;
-- onFail(text) runs when the reply (or its absence) says the buy failed.
function Auction.Buy(index, sig, after, confirmed, onFail)
  if Auction.busy then return refuse("Wait for the auction house to answer the last bid.") end
  local r = Auction.Match(index, sig)
  if not r then return refuse("Listing changed. Search again.") end
  if r.buyout <= 0 then return refuse("That listing has no buyout. Bid instead.") end
  if Auction.Own(r) then return refuse("That is your own auction.") end
  if r.buyout > GetMoney() then return refuse("You can't afford " .. U.money(r.buyout, true) .. ".") end
  if not confirmed and Auction.NeedsConfirm(r.buyout) then
    TaxTheFools.Confirm.Open(index, sig, r, after, onFail)
    return "confirm"
  end
  return place("buy", index, r, r.buyout, after, onFail)
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
  if not ok then
    Auction.Say(text, "bad")
    if b.onFail then b.onFail(text) end
    return
  end
  if b.kind == "buy" then
    Scan.SnapshotRemove(b.sig)
    Auction.Say("Bought " .. b.name .. " x" .. b.count .. " for " .. U.money(b.amount, true) .. ".", "good")
  elseif b.kind == "post" then
    -- The deposit is what the server took: money before the post less money now.
    local deposit = b.before - GetMoney()
    if deposit <= 0 then deposit = nil end
    Sell.Log(DB.Char(), { key = b.key, stack = b.count, bid = b.bid, buyout = b.buyout, minutes = b.minutes,
                          deposit = deposit }, time())
    if deposit and b.id then Sell.LearnDeposit(TaxTheFoolsDB.items, b.id, b.minutes, deposit / b.count) end
    Auction.Say("Posted " .. b.name .. " x" .. b.count .. " for " .. U.money(b.buyout, true) .. ".", "good")
  elseif b.kind == "cancel" then
    GetOwnerAuctionItems(0)
    Auction.Say("Cancelled " .. b.name .. " x" .. b.count .. ".", "good")
  else
    Auction.Say("Bid " .. U.money(b.amount, true) .. " on " .. b.name .. " x" .. b.count .. ".", "good")
  end
  if b.after then b.after(b) end
end

-- CHAT_MSG_SYSTEM and UI_ERROR_MESSAGE: arg1 is the message text.
function Auction.OnMessage(msg)
  if not Auction.busy or type(msg) ~= "string" then return end
  local b = Auction.busy
  local okText = ERR_AUCTION_BID_PLACED
  if b.kind == "post" then okText = ERR_AUCTION_STARTED elseif b.kind == "cancel" then okText = ERR_AUCTION_REMOVED end
  if okText and msg == okText then return finish(true) end
  for _, name in ipairs(Auction.FAILURES) do
    local text = getglobal(name)
    if text and msg == text then return finish(false, msg) end
  end
end

function Auction.Tick(now)
  local b = Auction.busy
  if b and now - b.at >= D.ACTION_TIMEOUT then finish(false, Auction.NO_REPLY) end
end
