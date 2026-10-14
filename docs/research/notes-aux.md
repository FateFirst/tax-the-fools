# aux (vanilla 1.12 / Turtle WoW) — study notes

## 0. Source selection
- Upstream: github.com/shirsig/aux-addon-vanilla (last push 2023-12-21, effectively unmaintained). 41 stars.
- Turtle forks found (GitHub fork graph + search, 2026-10-14):
  - **OldManAlpha/aux-addon** — 23 stars, 14 forks, last push 2026-01-15; merges PRs from Turtle community
    (Otari98 data-sharer rewrite, MarcelineVQ stack-size saving, isfir deposit fix). **Most maintained → cloned.**
    Its README is titled "aux Turtle". It is the successor to gwetchen's Turtle fork (deleted; archived at ERitzman/aux-addon).
  - MarcelineVQ/aux-addon (2026-02) = OldManAlpha + README pointer to upstream. Nelethor/Aux-Revamped (2025-06, UI tweaks).
  - T-imothy/Aux (2026-08, standalone, "maintained for 1.12.1"), elboaf/aux-addon (inventory scan), not evaluated.
  - shirsig/aux_merchant_prices — separate vendor-price DB addon (see §6).
- Clone: `refs/aux` = OldManAlpha/aux-addon @ c25ad2b ("Fix LFT showing up as first channel"). ~10.2k lines Lua.
- Core history/scan logic is identical to upstream (verified history.lua schema/weights and scan.lua timeout via gh api);
  Turtle fork adds: LFT-channel price sharing, Turtle durations (6/24/72h), deposit formula, ShaguTweaks vendor-price
  fallback, autopricing heuristic, purchase summary, blizzard theme, Nordanaar faction-key hack.

Paths below are relative to `refs/aux/`.

## 1. AH scanning (core/scan.lua)

### Load order / globals
- `aux-addon.toc:1-6` — `## Interface: 11200`, single `## SavedVariables: aux` (no SavedVariablesPerCharacter).
- Coroutine-free "threads": `control.lua` runs continuation closures each OnUpdate. `aux.thread(f, ...)`,
  `aux.when(cond, k, ...)` re-schedules until `cond()` true (`control.lua:120-128`), `aux.later(t, t0)` returns a
  timeout predicate (`util.lua:175-178`), `aux.signal()` returns (send, received) pair (`util.lua:180-187`),
  `aux.event_listener(event, cb)` / `on_next_event` (`control.lua:79-92`). OnUpdate is removed when no threads live
  (`control.lua:41-45`, `107-109`).

### scan.start params (core/scan.lua:17-29)
`{type='list'|'owner'|'bidder', queries={ {blizzard_query=..., validator=fn}, ...}, on_scan_start, on_start_query,
on_page_loaded(page, last_page, total_pages), on_page_scanned, on_auction(record), on_complete, on_abort,
auto_buy_validator, auto_bid_validator, ignore_owner}`. One active scan per `type`; starting a new one aborts the old.
Aborted on AUCTION_HOUSE_CLOSED (`scan.lua:10-12`).

### QueryAuctionItems (scan.lua:96-125)
```lua
QueryAuctionItems(bq.name, bq.min_level, bq.max_level, bq.slot, bq.class, bq.subclass,
                  get_state().page, bq.usable, bq.quality)
```
- 9 args in 1.12: name, minLevel, maxLevel, invTypeIndex, classIndex, subclassIndex, page(0-based), isUsable, qualityIndex.
- **No getAll** arg in 1.12 (introduced in 2.3). No code in aux/Turtle fork references getAll (grep: none). Turtle fork
  README: "The rate at which the client receives auction data is intentionally limited by the server, there is nothing
  addons can do here." → full scans must page 50 at a time.
- Throttle: only 'list' queries are gated: `return aux.when(CanSendAuctionQuery, submit)` (scan.lua:123). Owner/bidder use
  `GetOwnerAuctionItems(page)` / `GetBidderAuctionItems(page)` ungated (scan.lua:97-100).
- PAGE_SIZE = 50 (scan.lua:8); `total_pages = ceil(total/50)`; `last_page` clamps to `blizzard_query.last_page` (68-76).
- Query construction: `util/filter.lua:539-561`. For `name/exact` it looks the name up in its item DB and fills
  min/max level = item level, class/subclass/slot indices (via `GetAuctionItemClasses/SubClasses/InvTypes` name matching,
  `util/info.lua:389-411`), quality. Otherwise filters map directly. Exact-name validation is done client-side by
  validator (`filter.lua:571-574`) since server name match is substring.

### Result handling: AUCTION_ITEM_LIST_UPDATE (scan.lua:203-231)
```lua
local listener_id = aux.event_listener('AUCTION_ITEM_LIST_UPDATE', function() last_update = GetTime(); updated = true end)
local timeout = aux.later(5, get_state().last_list_query)
return aux.when(function()
    if not last_update and timeout() then return true end          -- no event within 5s of query
    if last_update and GetTime() - last_update > 5 then return true end  -- events stopped but owners missing
    if updated and (ignore_owner or owner_data_complete()) then return true end
    updated = false
end, function()
    aux.kill_listener(listener_id)
    if not last_update and timeout() then return submit_query()   -- RETRY same page
    else return accept_results() end
end)
```
- Retry: if no AUCTION_ITEM_LIST_UPDATE within 5 s, re-submits the same page (re-gated by CanSendAuctionQuery). Infinite retries.
- Owner names arrive lazily in 1.12 (extra AUCTION_ITEM_LIST_UPDATE events). `owner_data_complete()` (233-241) loops 1..50
  checking `owner` non-nil; waits up to 5 s after last event. Default `account_data.ignore_owner = true`
  (`aux-addon.lua:66`) skips this wait — big speedup.
- `accept_results()` (181-191): `_, total = GetNumAuctionItems(type)` then `scan_page()`.
- `scan_page(i)` (128-169) iterates i=1..50 recursively: `info.auction(i, type)`; records with nil owner are skipped
  unless ignore_owner. Calls `history.process_auction(record, pages)` for EVERY scanned auction (all scan types, incl.
  post-tab scans) → history is a side-effect of any scan. Then auto-buy/auto-bid validators (sniping), then query
  validator → `on_auction`. After 50 → next page or next query.
- Owner list: waits for AUCTION_OWNED_LIST_UPDATE, tracking requested page via hooked `GetOwnerAuctionItems`
  (`aux-addon.lua:241-250`, scan.lua:193-201). Bidder: waits for AUCTION_BIDDER_LIST_UPDATE flag.
- Real-time/snipe mode (`tabs/search/results.lua:139-200`): repeatedly queries only the last page; dedups by
  `sniping_signature`; caps table at 2000 records.
- Scan duration: not measured in code. Rate = server response + CanSendAuctionQuery gate per page; on Turtle it is
  server-throttled (README). Plan for full-AH scans taking many minutes; prefer targeted (name/exact, class) queries.

### GetAuctionItemInfo / Link (util/info.lua:100-162)
```lua
local link = GetAuctionItemLink(query_type, index)
local name, texture, count, quality, usable, level, start_price, min_increment, buyout_price,
      high_bid, high_bidder, owner, sale_status = GetAuctionItemInfo(query_type, index)
local duration = GetAuctionItemTimeLeft(query_type, index)   -- 1..4 (30m/2h/8h/72h on Turtle; auction_listing.lua:24-29)
local blizzard_bid = high_bid > 0 and high_bid or start_price
local bid_price   = high_bid > 0 and (high_bid + min_increment) or start_price
```
- Note: `sale_status` (13th return) is read; `level` is the 6th return. `buyout_price == 0` → no buyout.
- `aux_quantity = charges or count` — charge items (wizard oils, etc.) priced per charge via tooltip parse; hardcoded
  table `max_item_charges` (info.lua:313-342).
- Unit prices: `unit_buyout_price = buyout_price/aux_quantity` etc. `search_signature` = item_id:suffix:enchant:start:
  buyout:bid:qty:duration:bidderflag:owner — used to re-identify an auction after the page shifts (util/scan.lua:9-12).
- Tooltip scraped for every auction (`tooltip('auction', type, i)`) — expensive but used for charges/auctionability.
- `parse_link` (info.lua:364-367): `|Hitem:(%d*):(%d*):(%d*):(%d*)` = item_id, enchant_id, suffix_id, unique_id (1.12 order).

## 2. Price history model (core/history.lua)

- Stored per item_key = `item_id .. ':' .. suffix_id` (info.lua:126). Enchant and unique id are ignored; random-suffix
  items ("of the Bear") are distinct keys.
- Storage: `aux.faction[realm|faction].history[item_key] = "<string>"` (aux-addon.lua:107-117; history.lua:26).
  **Per realm+faction, shared across all characters on the account** (one SavedVariables `aux`).
  Turtle hack: realm 'Nordanaar' always keyed as Horde (aux-addon.lua:109-111) — presumably shared AH there.
- Serialized string schema (history.lua:21):
```lua
{'tuple', '#', {next_push='number'}, {daily_min_buyout='number'},
  {data_points={'list', ';', {'tuple', '@', {value='number'}, {time='number'}}}}}
-- e.g. "1734912000#1250#1300@1734825600;1400@1734739200"
```
  Serializer: `util/persistence.lua` (tuple/list with separator chars). Compact string per item = efficient SV.
- Collection (history.lua:99-116): for each scanned auction, `unit = ceil(buyout/aux_quantity)`; if
  `unit > 0 and unit < daily_min_buyout` → update. **Only the daily minimum unit buyout is kept** — no bids, no volume,
  no median of listings, no count.
- Day rollover: `next_push` = next local midnight (`date('*t')` with hour=24) (history.lua:44-54). On read, if
  `next_push <= time()`, `push_record` (170-179) prepends `{value=daily_min_buyout, time=next_push}` to data_points,
  **keeps at most 11 data points**, resets daily_min. So max ~11 days of history (only days with scans count).
- Value ("historical value") (history.lua:132-153):
```lua
local weight = .99 ^ aux.round((data_points[1].time - data_point.time) / 86400)
-- normalize weights; value = weighted_median(weighted_values)  (sort by value, first with cum weight >= .5)
-- if no data points yet → value = today's daily_min_buyout
```
  Effectively a median of the last 11 daily minimums (0.99 decay is near-uniform). Cached in `value_cache` until next_push.
- `market_value(item_key)` = today's `daily_min_buyout` (shown as "Today" in tooltip) (155-157).
- Pruning: no item expiry; bounded by 11 points/item. Item count unbounded (one string per item ever seen).
- Turtle data sharing (history.lua:25-42, 77-116): joins channel "LFT"; on a new daily min, sends
  `"AuxData,<item_key>,<unit_price>"` via ChatThrottleLib BULK to LFT, only if scan had <15 pages (avoid full scans).
  Receiver applies lower daily_min. No validation → trust issue (anyone can poison prices). Toggle `/aux sharing`.

## 3. Item info caching (core/cache.lua — note it declares `module 'aux.util.info'`)

- 1.12 `GetItemInfo(id|"item:id")` returns nil unless the item is in the client cache (WDB/itemcache.wdb). Returns
  (1.12): name, link(itemstring), quality, level(min level? — aux treats as 'level'), class, subclass, max_stack,
  equip_slot, texture. **No vendor price, no item level distinction in 1.12.**
- aux item DB (account-wide): `aux.account.items[item_id] = "name#quality#level#class#subclass#slot#max_stack#texture"`
  and `aux.account.item_ids[strlower(name)] = item_id`, plus sorted `auctionable_items` (name list for autocompletion)
  (cache.lua:10, 165-198).
- `scan_wdb()` on LOAD: iterates item ids 1..99999, 100 new items per batch, then `aux.when(aux.later(.5), scan_wdb, id)`
  → background crawl of whatever is in the local WDB. For each new item it scrapes a tooltip via
  `SetHyperlink` to decide auctionability (BoP/quest/soulbound/conjured) (`info.lua:262-271`).
- `populate_wdb` (`/aux populate wdb`, cache.lua:200-211): for every id not cached, `AuxTooltip:SetHyperlink('item:'..id)`
  one per frame — forces server item queries to fill the WDB (risky on some servers: disconnects for unknown ids).
- `info.item(id, suffix)` (info.lua:373-387): GetItemInfo first, falls back to the saved DB.
- Tooltip scanning: hidden `AuxTooltip` (GameTooltipTemplate) created at info.lua:6; `OnTooltipAddMoney` script captures
  the vendor sell money line (`this.money = arg1`) (info.lua:7-9). `info.tooltip(setter, a, b)` (273-295) reads
  AuxTooltipTextLeft/Right N into a table of {left_text,left_color,right_text,right_color}.
- Character list for "is it me" detection: `aux.realm[realm].characters[name] = GetTime()` (cache.lua:34-48) — note it
  uses GetTime() (session uptime), so the 30-day expiry check is broken.

## 4. Posting / buying / bidding

### Buy/bid (aux-addon.lua:158-187)
```lua
function M.place_bid(type, index, amount, on_success)
    if locked then return end
    PlaceAuctionBid(type, index, amount)            -- buyout = bid of buyout_price
    if money >= amount then locked = true
        ... wait for CHAT_MSG_SYSTEM arg1 == ERR_AUCTION_BID_PLACED, or 5 s timeout, then unlock + on_success
```
- Single in-flight bid lock. Purchases recorded in purchase summary when amount >= buyout.
- Buy flow from search (`tabs/search/results.lua:371-420`): click a row → `scan_util.find(record)` re-queries the record's
  page, then page-1, then an exact-name query (`util/scan.lua:14-72`), matching `search_signature`; once found the
  Bid/Buyout buttons get OnClick that calls place_bid with the found index. PlaceAuctionBid must be from a hardware
  event (button click) — aux respects this: scan finds, user clicks.
- Auto-buy/auto-bid validators in scan_page (scan.lua:155-162) call place_bid from inside the scan thread (OnUpdate) —
  so aux assumes PlaceAuctionBid needs no hardware event in 1.12 (verify on Turtle).
- Cancel: `CancelAuction(index)`, confirm via ERR_AUCTION_REMOVED (aux-addon.lua:189-209).

### Posting (core/post.lua)
- `post.start(item_key, stack_size, duration, unit_start, unit_buyout, count, cb)` (189-201). Loop: `stack.start` (core/stack.lua)
  splits/merges bag stacks to exact size, then `post_auction(slot)` (36-172):
```lua
ClearCursor(); ClickAuctionSellItemButton(); ClearCursor()
PickupContainerItem(bag, slot); ClickAuctionSellItemButton(); ClearCursor()
StartAuction(max(1, round(start_price*qty)), round(buyout_price*qty), state.duration)  -- duration in minutes 120/480/1440
-- confirm: CHAT_MSG_SYSTEM arg1 == ERR_AUCTION_STARTED
```
- Durations: `DURATION_2, DURATION_8, DURATION_24 = 120, 480, 1440` (tabs/post/core.lua:23) but labelled
  6h/24h/72h for Turtle (post/core.lua:630-644). Turtle's AH durations differ from vanilla; StartAuction still takes the
  vanilla minute codes.
- Vendor price for deposit obtained by placing item in sell slot and reading `GetAuctionSellItemInfo()` 6th return
  (`vendor_price`, whole stack) (post/core.lua:411-430, info.lua:87-98).
- Deposit (Turtle fix, post/core.lua:365-372):
```lua
local deposit_factor = 0.025
local duration_factor = duration_minutes / 120          -- 1, 4, 12
local amount = floor(unit_vendor_price * stack_size * duration_factor
                     * (1 + (max_stack - stack_size) * 0.05) * deposit_factor) * stack_count
```
  (Previous: `UnitFactionGroup'npc' and .05 or .25` i.e. 5% faction / 25% neutral of vendor×stack, ×0.6 fudge; Turtle formula penalizes partial stacks: +5% per missing unit.)
- Undercut (post/core.lua:390-398): `price = ceil(unit_price * stack_size) - 1` (1 copper per stack) unless own auction;
  toggle `/aux uc`. Existing auctions gathered by an exact-name scan grouped by (unit price, stack size, duration, own)
  (post/core.lua:533-610).
- Per-item post settings: `aux.faction[...].post[item_key] = "duration#start#buyout#hidden#stack_size"` (post/core.lua:19-43).
- Turtle "autopricing" when start price = 0 (post.lua:50-151): heuristic mixing daily min-1c, 0.5–0.95×value,
  vendor buy ×1.1/1.15, vendor sell ×(1.35+3.65·e^(-v/4000)), 0.85×disenchant value; aborts with
  "recommends disenchanting/vendoring" when DE or vendor beats AH.

## 5. Tooltip hooks (core/tooltip.lua)
- Hooks GameTooltip methods by replacing them on the object (aux.hook(name, GameTooltip, fn); aux-addon.lua:143-156):
  SetHyperlink, SetAuctionItem, SetLootItem, SetQuestItem, SetQuestLogItem, SetBagItem, SetInboxItem,
  SetInventoryItem, SetMerchantItem, SetCraftItem, SetCraftSpell, SetTradeSkillItem, SetAuctionSellItem (110-224).
```lua
aux.hook(name, GameTooltip, T.vararg-function(arg)
    game_tooltip_money = 0; inside_hook = true
    local tmp = T.list(aux.orig[GameTooltip][name](unpack(arg)))
    inside_hook = false
    f(unpack(arg)); return T.unpack(tmp) end)
```
- Captures/defers `SetTooltipMoney` during the original call (vendor money frame) then re-adds it after aux's lines so the
  money frame stays at the bottom (tooltip.lua:28-35, 104-106).
- Also wraps global `SetItemRef` for ItemRefTooltip (chat links) (36-46).
- SetBagItem → `GetContainerItemLink(bag,slot)` + count from `GetContainerItemInfo` (147-152). SetInboxItem resolves by
  name via item_ids DB (154-165). Shift held = multiply by stack quantity (49).
- Lines added (`extend_tooltip`, 47-108): disenchant distribution & value, Vendor Buy, Vendor (sell), Value (historical),
  Today (daily min + % of value). Per-character toggles in `aux.character[realm|name].tooltip`.

## 6. Vendor / disenchant data
- No 1.12 API for vendor sell price. aux learns it:
  - At merchant: `merchant_sell_scan` iterates bags, scrapes tooltip money (the OnTooltipAddMoney trick) /
    quantity → `aux.account.merchant_sell[item_id]` (cache.lua:155-163, triggered MERCHANT_SHOW/BAG_UPDATE).
  - At AH: NEW_AUCTION_UPDATE → `GetAuctionSellItemInfo()` vendor_price/count (cache.lua:23-31).
  - Vendor *buy* prices: `GetMerchantItemInfo(i)` price/count + `limited` (stock >= 0) →
    `aux.account.merchant_buy[item_id] = "unit_price#limited"` (cache.lua:117-153).
  - Fallback: `ShaguTweaks.SellValueDB[item_id]` if ShaguTweaks loaded (tooltip.lua:80-86; post.lua:95-101;
    filter.lua:209-218). Also standalone `shirsig/aux_merchant_prices` addon provides a prebuilt table.
  - Known bug: filter.lua:214 assigns `info.charges=` instead of local `charges`.
- Disenchant (core/disenchant.lua): hardcoded vanilla DE tables by slot class (armor/weapon), quality (2/3/4), level
  bands → list of {item_id, min_qty, max_qty, probability} (52-172). `value()` = Σ p·avg_qty·min(value, today_min)
  of the dust/essence/shard (36-50). Exclusions for non-DE items (55-60). Not updated for Turtle custom items.

## 7. UI architecture / module system
- Module system `libs/package.lua` (37 lines): `module 'name'` sets the file's function env to a per-module table
  (fallback `__index=_G`), so all non-local functions are module-private globals; assigning `M.x = ...` exports.
  `require 'name'` returns a read-only interface proxy (works before the module file loads → no load-order issues).
  Multiple files can share one module (e.g. core/cache.lua + util/info.lua both `aux.util.info`).
- `libs/T.lua`: table pool (`T.acquire/release/temp/static`, `T.map/list/set`, `T.vararg-function`) to minimize
  garbage in Lua 5.0. `T.temp-x` auto-releases next frame via AuxGCFrame OnUpdate.
- Lifecycle hooks (aux-addon.lua:23-54): `function aux.handle.LOAD()` / `LOAD2()` / `INIT_UI()` / `CLOSE()` — assigning
  appends a handler (metatable __newindex), so many modules each register LOAD. LOAD on VARIABLES_LOADED, LOAD2 on
  PLAYER_LOGIN (faction known), CLOSE on AUCTION_HOUSE_CLOSED.
- SavedVariables init via `assign(defaults)` into `aux.account`, `aux.realm[realm]`, `aux.faction[realm|faction]`,
  `aux.character[realm|name]` (aux-addon.lua:56-117). Good pattern for our account-wide data.
- Replaces Blizzard AH: on Blizzard_AuctionUI load, unregisters AuctionFrame's AUCTION_HOUSE_SHOW, hooks ShowUIPanel;
  on AUCTION_HOUSE_SHOW hides AuctionFrame and shows `aux_frame` (aux-addon.lua:215-260). Tabs via `aux.tab(name)`
  with OPEN/CLOSE/USE_ITEM/CLICK_LINK events (119-141); tabs: search, post, auctions, bids.
- Widgets: `gui/core.lua` factory functions (panel, button, editbox, dropdown, slider, checkbox, item, label,
  percentage_historical coloring) with two themes (modern TSM-like / blizzard). Tables: `gui/listing.lua` (generic
  scroll table, SetData/SetColInfo/SetHandler) and `gui/auction_listing.lua` (grouped auction rows, column defs
  search/auctions/bids, sort by % of value, RemoveAuctionRecord). `gui/purchase_summary.lua` session spend window.
- Search language `util/filter.lua`: slash-separated filter strings with boolean operators and validators, e.g.
  `percent/60`, `profit/1g`, `disenchant-profit`, `vendor-profit`, `seller`, `left`, `tooltip` (filter.lua:24-230).
  `percent` = unit_buyout / history.value ×100 ≤ N (124-133); `profit` = value×qty − buyout ≥ amount (155-162).
  These are the flip-suggestion primitives.

## 8. Crafting cost (core/crafting.lua)
- Option `aux.account.crafting_cost` (default true). On Blizzard_TradeSkillUI / Blizzard_CraftUI load, hooks
  `TradeSkillFrame_SetSelection` / `CraftFrame_SetSelection` (41-97):
```lua
for i = 1, GetTradeSkillNumReagents(id) do
    local link = GetTradeSkillReagentItemLink(id, i)       -- nil if reagent not cached → total nil
    local count = aux.select(3, GetTradeSkillReagentInfo(id, i))
    local _, price, limited = info.merchant_info(item_id)  -- vendor buy price if unlimited vendor item
    local value = price and not limited and price or history.value(item_id..':'..suffix_id)
    total_cost = total_cost + value * count
end
TradeSkillReagentLabel:SetText(SPELL_REAGENTS .. ' (Total Cost: ...)')   -- also ATSWReagentLabel if ATSW present
```
- Only reagent cost of the selected recipe; no product value, no profit, no yield (GetTradeSkillNumMade), no recipe DB,
  no cross-character recipe storage. Right-click reagent → search it in aux (hook_quest_item, 30-40).
- Tooltip hook on SetTradeSkillItem shows value of product/reagents (tooltip.lua:201-211).

## Takeaways for our addon
- Reuse: paging/timeout/retry state machine, ignore_owner default, signature re-find before buying, string-serialized
  per-item records, GameTooltip method hooks + SetTooltipMoney deferral, hidden-tooltip vendor price capture,
  merchant buy capture, package.lua module system + handle.LOAD pattern.
- Improve: history keeps only daily min (no volume/median/listing count); 11-day cap; no pruning of stale items;
  sharing unauthenticated; characters list expiry bug; crafting has no profit/yield; DE tables vanilla-only.
