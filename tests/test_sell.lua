local S = TaxTheFools.Sell
local function opts(o)
  local s = { floorPct = 80, undercut = 1, bidPct = 90 }
  for k, v in pairs(o or {}) do s[k] = v end
  return s
end
local function L(unit, owner, count) return { unit = unit, count = count or 1, owner = owner or "Other" } end

T.test("settings.sell defaults", function()
  local d = TaxTheFools.Data.DEFAULTS.settings.sell
  T.eq(d.bidPct, 90) T.eq(d.floorPct, 80) T.eq(d.undercut, 1) T.eq(d.duration, 480)
end)

T.test("suggest undercuts the cheapest listing at or above the floor", function()
  -- market 1000, floor 80% = 800. Listings 700 (below floor), 800 (exactly at it), 900.
  -- cheapest eligible = 800, undercut 1 -> 799, clamped up to the floor 800. bid = floor(800*0.9) = 720.
  local r = S.Suggest({ L(900), L(700), L(800) }, 1000, 50, opts())
  T.eq(r.source, "undercut") T.eq(r.buyout, 800) T.eq(r.bid, 720) T.eq(r.floor, 800)
  -- 799 is not enough: the 800 listing is the only one that counts.
  T.eq(S.Suggest({ L(799), L(1200) }, 1000, 50, opts()).buyout, 1199, "799 < floor 800 is skipped")
end)

T.test("suggest returns whole copper (Review I3)", function()
  -- market 1000, floor 800. Cheapest 900.7, undercut 1 -> 899.7 -> floor 899. bid = floor(899*0.9) = floor(809.1) = 809.
  local r = S.Suggest({ L(900.7) }, 1000, nil, opts())
  T.eq(r.buyout, 899) T.eq(r.bid, 809)
  -- undercut 0.5: 900.7 - 0.5 = 900.2 -> 900.
  T.eq(S.Suggest({ L(900.7) }, 1000, nil, opts({ undercut = 0.5 })).buyout, 900)
  -- a fractional market value: 1000.6 -> 1000, and its floor is rounded up (ceil(800.48) = 801), not under it.
  local m = S.Suggest({}, 1000.6, nil, opts())
  T.eq(m.buyout, 1000) T.eq(m.floor, 801)
  -- vendor 33.3 x 3 = 99.9 -> 99. bid = floor(99*0.9) = floor(89.1) = 89.
  local v = S.Suggest({}, nil, 33.3, opts())
  T.eq(v.buyout, 99) T.eq(v.bid, 89)
end)

T.test("suggest never goes below the floor", function()
  -- market 1000, floor 800. Listing at 850, undercut 5 -> 845 (above the floor, kept).
  T.eq(S.Suggest({ L(850) }, 1000, nil, opts({ undercut = 5 })).buyout, 845)
  -- undercut 60 -> 790, clamped to 800.
  T.eq(S.Suggest({ L(850) }, 1000, nil, opts({ undercut = 60 })).buyout, 800)
  -- listing at exactly 800, undercut 1 -> 799, clamped to 800.
  T.eq(S.Suggest({ L(800) }, 1000, nil, opts()).buyout, 800)
end)

T.test("suggest ignores your own listings", function()
  -- market 1000, floor 800. Mine at 850 is skipped by owner, another flagged own at 820 too; 900 counts -> 899.
  local mine = L(850, "Me")
  local flagged = L(820) flagged.own = true
  local r = S.Suggest({ mine, flagged, L(900) }, 1000, nil, opts({ me = "Me" }))
  T.eq(r.buyout, 899) T.eq(r.source, "undercut")
  -- only my listing: falls through to the market value.
  T.eq(S.Suggest({ mine }, 1000, nil, opts({ me = "Me" })).source, "market")
end)

T.test("suggest uses the market value when every listing is below the floor", function()
  -- market 1000, floor 800, listings 500 and 799 -> market 1000. bid = 900.
  local r = S.Suggest({ L(500), L(799) }, 1000, 50, opts())
  T.eq(r.source, "market") T.eq(r.buyout, 1000) T.eq(r.bid, 900)
  T.eq(S.Suggest({}, 1000, 50, opts()).source, "market", "no listings at all")
end)

T.test("suggest falls back to vendor x 3, then to nothing", function()
  -- no market: vendor 50 x 3 = 150. bid = floor(150*0.9) = 135.
  local r = S.Suggest({}, nil, 50, opts())
  T.eq(r.source, "vendor") T.eq(r.buyout, 150) T.eq(r.bid, 135) T.eq(r.floor, nil)
  local none = S.Suggest({}, nil, nil, opts())
  T.eq(none.source, nil) T.eq(none.buyout, nil) T.eq(none.bid, nil)
end)

T.test("suggest without a market value undercuts the cheapest listing", function()
  -- no market, so no floor: 40 - 1 = 39. bid = floor(39*0.9) = floor(35.1) = 35.
  local r = S.Suggest({ L(40), L(90) }, nil, 50, opts())
  T.eq(r.source, "undercut") T.eq(r.buyout, 39) T.eq(r.bid, 35)
end)

T.test("starting bid is bidPct of the buyout, at least 1 copper", function()
  -- bidPct 50, buyout 1000 (market) -> 500.
  T.eq(S.Suggest({}, 1000, nil, opts({ bidPct = 50 })).bid, 500)
  -- buyout 1 (vendor 0.34 is nonsense, so use a listing of 2 undercut by 1 with no market) -> bid floor(0.9) = 0 -> 1.
  local r = S.Suggest({ L(2) }, nil, nil, opts())
  T.eq(r.buyout, 1) T.eq(r.bid, 1)
  -- undercut below zero clamps the buyout to 1: listing 1, undercut 5 -> -4 -> 1.
  T.eq(S.Suggest({ L(1) }, nil, nil, opts({ undercut = 5 })).buyout, 1)
end)

T.test("suggest takes its defaults from settings.sell when s is empty", function()
  -- market 1000, floor 800, listing 900: 900 - 1 = 899, bid floor(899*0.9) = floor(809.1) = 809.
  local r = S.Suggest({ L(900) }, 1000, nil, {})
  T.eq(r.buyout, 899) T.eq(r.bid, 809)
end)

T.test("stacks counts whole stacks and clamps to the maximum", function()
  T.eq(S.Stacks(100, 20, 20), 5)        -- 100 / 20
  T.eq(S.Stacks(99, 20, 20), 4)         -- floor(4.95)
  T.eq(S.Stacks(100, 50, 20), 5)        -- 50 clamped to 20: 100 / 20
  T.eq(S.Stacks(7, 20, 20), 0)          -- not enough for one
  T.eq(S.Stacks(7, 1, 1), 7)
  T.eq(S.Stacks(0, 5, 20), 0)
  T.eq(S.Stacks(10, nil, 20), 0, "no stack size")
  T.eq(S.Stacks(10, 5, nil), 2, "no maximum")
end)

T.test("net is the buyout less the 5% cut and the deposit", function()
  -- 5000 * 0.95 = 4750, - 37 = 4713.
  T.eq(S.Net(5000, 37), 4713)
  -- 1000 * 0.95 = 950, no deposit.
  T.eq(S.Net(1000, 0), 950)
  T.eq(S.Net(1000), 950)
end)

T.test("auctionable rejects soulbound, quest and conjured items", function()
  local keep = { getglobal("ITEM_SOULBOUND"), getglobal("ITEM_BIND_QUEST"), getglobal("ITEM_CONJURED") }
  setglobal("ITEM_SOULBOUND", "Soulbound") setglobal("ITEM_BIND_QUEST", "Quest Item") setglobal("ITEM_CONJURED", "Conjured Item")
  T.ok(S.Auctionable({ "Linen Cloth", "Vendor sells" }))
  T.ok(not S.Auctionable({ "Sword", "Soulbound" }), "soulbound")
  T.ok(not S.Auctionable({ "Letter", "Quest Item" }), "quest")
  T.ok(not S.Auctionable({ "Conjured Water", "Conjured Item" }), "conjured")
  T.ok(S.Auctionable({}), "no lines")
  -- a check whose global is missing is skipped.
  setglobal("ITEM_SOULBOUND", nil)
  T.ok(S.Auctionable({ "Sword", "Soulbound" }), "no global, no check")
  setglobal("ITEM_SOULBOUND", keep[1]) setglobal("ITEM_BIND_QUEST", keep[2]) setglobal("ITEM_CONJURED", keep[3])
end)

-- Vanilla 1.12 has no global _G (Lua 5.0 itself defines one, which the real client does not expose).
T.test("the fake client has no global _G, as 1.12 has none", function()
  T.eq(rawget(getfenv(0), "_G"), nil)
end)

T.test("Auctionable and TipLines work with no global _G (Review C1)", function()
  local saved = rawget(getfenv(0), "_G")
  rawset(getfenv(0), "_G", nil)
  setglobal("ITEM_SOULBOUND", "Soulbound")
  local ok1, a = pcall(S.Auctionable, { "Sword", "Soulbound" })
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 1 } }
  local ok2, lines = pcall(S.TipLines, 0, 1)
  setglobal("ITEM_SOULBOUND", nil)
  rawset(getfenv(0), "_G", saved)
  T.ok(ok1, "Auctionable raised: " .. tostring(a))
  T.eq(a, false)
  T.ok(ok2, "TipLines raised: " .. tostring(lines))
  T.eq(type(lines), "table")
end)

local DAY = 86400
T.test("log appends and caps at 500, dropping the oldest", function()
  local c = {}
  local now = 100 * DAY
  for i = 1, 502 do S.Log(c, { key = "1:0", stack = i, bid = 1, buyout = 2, minutes = 480, deposit = 3 }, now) end
  T.eq(table.getn(c.postings), 500)
  T.eq(c.postings[1].stack, 3, "entries 1 and 2 were dropped")
  T.eq(c.postings[500].stack, 502)
  T.eq(c.postings[1].at, now, "at defaults to now")
end)

T.test("log prunes entries older than 35 days", function()
  local now = 100 * DAY
  local c = { postings = {
    { key = "a", at = now - 36 * DAY },              -- 36 days: gone
    { key = "b", at = now - 35 * DAY },              -- exactly 35 days: kept
    { key = "c", at = now - 1 * DAY },
  } }
  S.Log(c, { key = "d" }, now)
  T.eq(table.getn(c.postings), 3)
  T.eq(c.postings[1].key, "b") T.eq(c.postings[3].key, "d")
  S.Prune(c, now + 2 * DAY)                           -- b is now 37 days old, c 3, d 2
  T.eq(table.getn(c.postings), 2) T.eq(c.postings[1].key, "c")
  S.Prune({}, now)                                    -- no log: nothing to do
end)

T.test("learned deposits are per item and duration, per unit", function()
  local items = {}
  T.eq(S.Deposit(items, 100, 480, 5), nil, "nothing learned")
  -- 20 units cost 30 copper to post: 1.5 each. A stack of 5 then costs 7.5 -> 8.
  S.LearnDeposit(items, 100, 480, 30 / 20)
  T.eq(items[100].dep[480], 1.5)
  T.eq(S.Deposit(items, 100, 480, 20), 30)
  T.eq(S.Deposit(items, 100, 480, 5), 8)
  T.eq(S.Deposit(items, 100, 1440, 5), nil, "another duration is unknown")
  T.eq(S.Deposit(items, 101, 480, 5), nil, "another item is unknown")
  S.LearnDeposit(items, 100, 480, 2)
  T.eq(S.Deposit(items, 100, 480, 5), 10, "a later post replaces it")
  items[102] = { n = "Name" }
  S.LearnDeposit(items, 102, 120, 1)
  T.eq(items[102].n, "Name", "other fields are kept")
end)
