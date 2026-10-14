# Aegis: Exchange — study notes (delta vs notes-aux.md / notes-aegis.md)

- Repo: github.com/Torchlite-bit/Aegis_Exchange, cloned --depth 1 to `refs/aegis-exchange/`. v1.55.1 (`Aegis_Exchange.toc:4`).
- **License: MIT**, "Copyright (c) 2026 Torchlite" (`LICENSE:1-3`). Code can be copied with attribution.
- Targets 1.18.1 servers incl. **RavenCraft**, Octo WoW, CapyCraft, Turtle (`README.md:5-8`, `:23-25`). It's the same
  author family as Aegis_Pathfinder, but this addon uses its own palette and `C` table (`ui/frame.lua:29-60`), not Pathfinder's `Theme.lua`.
- Size: ~35k Lua lines; `ui/frame.lua` alone is 20.8k (one file for every tab). Core: init/util/db/disenchant/scan/sell/buy.
- The **best docs are `CLAUDE.md` (hard rules), `ROADMAP.md` (6.1k lines of design decisions and post-mortems) and `CHANGELOG.md`.**
  `design/` holds PNG mockups plus a Claude Design export (`design/README.md`, `design/Design readme.md`). `tests/` has a Lua 5.1
  harness, a WoW API mock (`tests/support/wow.lua`), lints (upvalues, palette, scoping, definitions) and a "sabotage" layer.
  Paths below are relative to `refs/aegis-exchange/`.

---

## 1. AH query rules and throttling on Turtle/1.18.1

The repo documents **no server-side rate limit**. The limit it describes is on the client (`CanSendAuctionQuery`).
- `CLAUDE.md:155-181` (hard rules 9-11):
  - `QueryAuctionItems` takes 9 args with a 0-based page. Pass **strings** for name/minLevel/maxLevel (`""`, never nil),
    because "servers may silently ignore a query with nils in those slots". Index args stay nil. There's no getAll.
  - **Poll `CanSendAuctionQuery()` before every query.** The vanilla client keeps the gate shut **~5 s after each query**.
    That's the source of the old "4 s between pages" folklore.
  - The **AuctionQueryThrottle DLL** (github.com/brues-code/AuctionQueryThrottle, needs the VanillaFixes loader) clears that
    timer as soon as the reply arrives. Because it's a DLL you can't detect it with IsAddOnLoaded. **The gate's own behaviour tells you
    whether it's installed.**
  - Page size is 50.
- What this means for scan pacing (`core/scan.lua:26-59`):
  - `scan.PAGE_DELAY = 4` is the "safe" floor. `scan.FAST_DELAY = 0.05` is the "auto" floor and the default.
  - `scan.FAST_GATE = 1.5`: if the gate opens within 1.5 s, the throttle is assumed lifted. This only changes the readout.
  - `scan.REPLY_TIMEOUT = 15` s, after which the same page is re-sent (`:327-339`, retry cooldown 1 s).
  - The setting `queryThrottle = "auto"|"safe"` lives at `core/db.lua:209-214`.
- **Measured speed** (README, not code): "Octo WoW is dramatically faster, Capy WoW lands around 2×" with the DLL (`README.md:27-35`).
  The readout shows `fast — gate 0.02s, server 0.61s` (`CHANGELOG.md:6409`), so on Capy the server round trip is about 0.6 s per page.
  - On a stock client, expect about 5 s per page. A comment mentions "a realm with 294 pages" and "you would page for half an hour" (`core/scan.lua:152-153`).
  - The mockup shows 1832 pages and "~38 min remaining" (`design/1b`). That's an illustration, not a measurement.
  - **Nothing measures RavenCraft specifically.**
- Per-page cost is broken into three parts: `lastGate` (client throttle), `lastReply` (server round trip) and our own floor (`core/scan.lua:89-95`, `:435-441`).
  The ETA uses the measured seconds per page (`:557-600`). **This instrumentation is worth copying.**
- Rate stats tracked: `rate = scanned/elapsed`, `sent`, `retries`, and `waitOk` (time blocked on the gate, with a debug trace every 5 s, `:315-325`).
- Debug toggle: `/aex debug` traces every state transition, so you can tell which leg of a stall you're on: gate never opens, or query sent and no reply (`:112-120`).
- **Session-killing gotchas (new; aux notes don't have these):**
  - Hiding `AuctionFrame` runs its XML OnHide → `CloseAuctionHouse()`. After that, every query is a silent no-op (`CLAUDE.md:183-203`).
  - `AuctionFrame_Show()` closes the AH if the frame isn't visible right after `ShowUIPanel`. So a **synchronous hide from OnShow kills the session**,
    and the hide has to be deferred one OnUpdate tick (`ui/frame.lua:19113-19141`).
  - Seed `AuctionFrameAuctions.page = 0`, or Blizzard's own `AUCTION_OWNED_LIST_UPDATE` handler throws (`ui/frame.lua:19158-19166`).
- Single query channel: the Buy engine won't send while a scan or post holds the channel (`buy.IsBusy`, `core/buy.lua:1898-1913`).
  The Buy engine uses `QUERY_DELAY 0.5`, `TIMEOUT 8` (`core/buy.lua:24-26`).
- Scans auto-pause on `AUCTION_HOUSE_CLOSED`. `scan.Continue()` resumes from `lastCompleted + 1` within the session (`core/scan.lua:512-535`, `:649-654`).

## 2. Scan strategies

- One state machine walks a **list of queries** (`core/scan.lua:65-99`, `:468-510`):
  - `scan.Start({})` is a full scan.
  - `scan.Start({class=5, subclass=1})` scans one category.
  - A list of such tables scans several categories (the category picker; `scan.GetCategories()` at `:620-639` builds the class/subclass tree).
  - `scan.Start({name=itemName})` is a **targeted single-item scan**, used by the Sell tab (`core/sell.lua:1400-1420`).
  - `IsFullRun` distinguishes full from targeted runs for the "last full scan" stamp (`:352-357`, `db.SetLastScan` at `core/db.lua:3003`).
  - Item scans pass `stampLast=false` so they don't reset the "last full scan" marker (`:381-385`).
- **Passive feed:** *every* `AUCTION_ITEM_LIST_UPDATE` records the visible page into the price DB, including manual browsing and Buy searches
  (`core/scan.lua:417-426`, `RecordVisiblePage :202-258`).
  - An `ours` flag stops per-run callbacks from receiving pages they didn't request. That callback leak once froze clients (`:131-145`, ROADMAP "scan callback leak v1.51.1").
- **Bag scan** ("Scan All") walks auctionable bag items and runs one targeted scan each.
  - Results are cached per item for 1 h (`sell.cache`, `CACHE_TTL 3600`, `core/sell.lua:1222-1260`). The cache is cleared when the AH closes (`ui/frame.lua:19470-19474`).
- **Buy search "gather":** a one-term search or category browse reads up to `GATHER_MAX=20` pages into one grouped list (`core/buy.lua:2121-2285`).
- **Buy "sweep":** a client-side post-filter (vendor-profit, percent, tooltip) keeps paging until a page has matches, up to `SWEEP_MAX=25` pages
  (`core/buy.lua:1714-1860`, setting `sweepEmptyPages` at `core/db.lua:233-243`).
- No watchlist or snipe mode. "**No Auto Buy**" is a recorded decision (`ROADMAP.md:312-314`).
  - Saved/favorite searches and recent searches are stored account-wide (`core/db.lua:113-122`, `core/buy.lua:175-222`).
- **Vendor-flip detection during scans:** each row of *our* pages is compared with the vendor sell price.
  - The list is session-only and never saved ("live listings… gone within the hour") and capped at 300 (`core/scan.lua:147-200`).
  - The profit maths is `db.VendorFlip`: no AH cut on either side, per-unit margin × stack (`core/db.lua:1228-1250`).
- Owner sweep: every AH visit walks your own auctions with `GetOwnerAuctionItems`, at most 6 pages (`core/sell.lua:470-580`). It yields if the player pages manually.

## 3. Price model and stored statistics

The model is aux-like, with different parameters (`core/db.lua:1-80`):
- Per item, per realm: `daily[dayNumber] = minUnitBuyout` plus `seen = count of auctions ever recorded`. That's all.
  - **No volume per day, no listing counts, no median of listings, no bids.**
  - `day = floor(time()/86400)` is a UTC day, not local midnight (`:81-84`).
- **KEEP_DAYS = 30, DECAY = 0.85.** The header explains why aux's 11 days at about 0.99 decay was "a flat 11-day median wearing a decay curve's name" (`:44-79`).
  - Age weights: today 100%, 3 days 61%, 7 days 32%, 14 days 10%, 30 days 1%. A step change is tracked in about 5 days.
  - The audit write-up is ROADMAP §0.3 (`ROADMAP.md:163`).
- `RecordAuction(itemId, unitBuyout, name)` folds into today's minimum and calls `PruneDaily` (`:1052-1089`). Bid-only auctions are ignored.
  - Charge items are normalized to item units (`util.ItemUnits`; count is *negative* for charge items, `CLAUDE.md:147-154`, `core/scan.lua:209-217`).
- Accessors:
  - `MinBuyout` returns the newest daily minimum (`:1091`).
  - `MarketValue` is the weighted median (`:1149-1180`).
  - `DayCount` is the number of distinct days, used as a confidence figure (`:1124`).
  - `SeenCount` is the number of sightings (`:1110`).
  - `BestUnit` returns the newest daily minimum, falling back to market (`:1135`).
  - `PriceSpread` returns (days, low, high). It's unused (`:2855`).
- **Keyed per realm** (`realms[GetRealmName()]`), not per faction, because the AH is cross-faction (`:22-35`, `db.Items :579-590`; migration v2→v3 `MigrateToRealms :979`).
  - Account-wide game facts are shared across realms: vendor sell, vendor buy, names→id, item facts, max stacks (`:86-160`).
- Vendor **buy** prices (what a merchant charges) use aux's merge rule: "limited stock outranks price" (`:1252-1300`).
- Deposits: the vanilla formula is about 2× off on these servers. The addon learns the formula→client ratio and the client→charged ratio
  from real posts (`CLAUDE.md:335-350`, `core/sell.lua:40-110`, `:2114-2170`). It always labels deposits "approx".
- **Gap for our flip engine:** there's no listing-count or volume history and no sell-through rate. We'd need to add those ourselves.

## 4. SavedVariables layout and pruning

- `## SavedVariables: AegisExchangeDB` (account) and `## SavedVariablesPerCharacter: AegisExchangeCharDB` (`Aegis_Exchange.toc:5-6`).
- Account DB shape (`core/db.lua:86-163`), `DB_VERSION = 3` (`:43`):
  ```
  version, realms[realm] = { items[id]={daily={},seen}, inventory[char]={bags,bank,ah,mail + timestamps},
                              cooldowns[char], crafts[char] (cap 100), money/purse history ... },
  vendors[id], vendorBuy[id]={p,l}, deposit={ratio,ratioN,charge,chargeN}, names[name]=id,
  facts[id]={q,r,e}, stacks[id], shopping={lists,recent,favorites}, crafting={projects},
  settings, ledger[] (cap 500), ledgerSeen{key=true}, vendorMarks, groups, operations, cdRecipes
  ```
- Char DB holds `ui` (window position, tab, widths), `lastScan`, and `posted` (the posting book) (`:539-549`).
- Pruning:
  - Prices: 30 days per item (`PruneDaily :1052-1064`). Item count is unbounded.
  - Ledger: `LEDGER_MAX = 500`, oldest dropped first (`:164`, `:1447-1450`).
  - Posting book: 33 days and 500 entries (`:305-341`).
  - Money history: 96 hourly samples, then compacted to daily, 900 samples max (about 2 years) (`:1490-1580`).
  - Crafts: 100 per character (`:685`).
  - `ledgerSeen` dedup keys are **never pruned**. That's a small leak; avoid it in our design.
- Defaults are filled with `ApplyDefaults` (one level deep, `:552-566`). Settings read through `db.Setting` with a `SETTING_DEFAULTS` fallback, so no migration is needed (`:167-282`).
- **Demo mode** swaps in generated readers, never writers (`db.LedgerSource`, `db.CooldownSource`). That lets screenshots work without touching real data (`:1453-1470`). This is a neat pattern.
- Integration contract for the companion "Aegis: Courier" mail addon: `A.INTEGRATION_VERSION`, `A.RecordExternalTxn`, `A.MailTxnKey`,
  `A.ClaimMailScanning` (`core/db.lua:1900-2018`). It's a good model if we ever split mail tracking into its own addon.

## 5. Buy / post flows: how "click-driven" are they?

**This is not strictly one hardware click per server action.** 1.12 doesn't require a hardware event for these calls.
- **Single buyout or bid** (`core/buy.lua:2933-3014`): one click → `buy.Verify(row)` → one `PlaceAuctionBid`.
  - Verify re-reads the client row and compares name, count and buyout.
  - `buy.Bid` **refuses** any amount at or above the buyout, because on 1.12 such a bid buys the item. That bug shipped once (ROADMAP "Pressing Bid bought the item v1.53.6").
- **Batch buyout** (multi-select, `core/buy.lua:2452-2931`): **one click, then N purchases chained from the `AUCTION_ITEM_LIST_UPDATE` handler** (`:2076-2083`).
  - The safety model: a **multiset of fingerprints (name, client count, buyout)**. Each step re-finds an index on the live page and buys it.
  - Gold is re-checked before every purchase.
  - The batch aborts if an owed fingerprint is missing (after re-reading candidate pages and the page before each).
  - It never substitutes another auction (ROADMAP `:830-847`).
  - **If we want strictly one click per buy, keep the fingerprint/verify logic and make each step wait for a click.**
- **Posting** (`core/sell.lua:2460-2690`): one click → `sell.StartPosting(itemId, stackSize, numStacks, ...)`.
  - An OnUpdate job then runs assemble → carve (SplitContainerItem into an empty slot) → settle → place (`ClickAuctionSellItemButton`) → verify → `StartAuction`
    for **every stack**. Timings: `ASSEMBLE_DELAY 0.25`, `POST_DELAY 0.45`, `CURSOR_TIMEOUT 2.0`, `MAX_RETRIES 4` (`:2213-2220`).
  - Its key learning: the sell slot reliably accepts only a *whole* bag stack. Never hand it a floating split; carve the split into a bag slot first (`:2511-2522`).
  - The job caps itself at the 120-auction cap (`sell.CAP`).
  - It records a posting-book entry per `StartAuction` with buyout, start bid and deposit (`:2645-2656`).
- **Post All / bag walk** *is* click-per-item: the first item goes into the slot automatically, and the user presses Post or Skip for each one (`ui/frame.lua:18466-18500`).
  - Stack plans: as-is, full, singles, fixed, or Smart (`sell.PlanStacks`, `sell.SmartStacks` at `core/sell.lua:1791-1972`).
  - A vendor gate skips items that would net less than vendor price after the cut.
  - The blacklist is `db.GROUP_NO_POST` (`core/db.lua:2679-2760`).
- **Cancel** is one click per row, with an optional confirmation (`confirmCancel`).
  - **Cancel All** loops rounds (max 6) and walks indices *downwards*, because cancelling shifts indices. It always confirms (ROADMAP `:3723-3755`, `sell.CancelOrder :742`).
- `confirmPost` / `confirmCancel` settings: `core/db.lua:215-222`.

## 6. Sales and mail tracking (much richer than aux)

- `MAIL_INBOX_UPDATE` only **shows a driver frame**. Its OnUpdate hides itself first, then scans, so it runs at most once per frame (`ui/frame.lua:19529-19542`).
  - Rationale: the mailbox storm, where the first open fires dozens of times as the item cache fills. Courier froze the client because of it (`CLAUDE.md:253-323`, hard rule 16). **Must copy.**
- `ui.ScanMailSales` (`ui/frame.lua:14223-14300`) reads **headers only** (`GetInboxHeaderInfo`).
  - It never calls `GetInboxInvoiceInfo`, because that **marks the mail read** and shortens its expiry.
  - Subjects are parsed with the localized globals `AUCTION_SOLD_MAIL_SUBJECT` / `AUCTION_EXPIRED_MAIL_SUBJECT`, with English fallbacks (`:13497-13511`).
- Dedup key: `subject|money|floor((time() - daysLeft*86400)/3600)`, an arrival hour that survives relogs (`core/db.lua:1930-1933`).
- **Quantity problem:** a sold mail doesn't carry the stack size (not in the invoice, the subject, or attachments). Aegis's answer is the **posting book** (`core/db.lua:284-537`):
  - `RecordPosting` stores name, id, qty and the {buyout, start, deposit} window at post time.
  - `MatchPosting(name, now, money)` consumes one entry only when unambiguous: all stacks the same size, or the mail money fits exactly one size's
    `[start*(1-cut)-1, buyout*(1-cut)+1+deposit]` window.
  - Expired-auction mail consumes a posting too.
  - `ReconcilePostings` tops the book up (additively) from the owner sweep, so auctions posted outside the addon still get quantities.
- Ledger entries: `{t, kind="sale"|"buy", item, amount (net copper), id, qty|nil (nil = unknown, never 1), who}` (`core/db.lua:1427-1451`).
  - Buys are booked at purchase time (`core/buy.lua:2948-2960`).
  - Sales to a vendor are booked as "Vendor sale (…)" income.
- History tab and Ledger window (`ui/frame.lua:13514-15860`):
  - Account gold chart over 24h/7d/30d/3m/all, with a per-character filter.
  - Stats: High/Low/Sold/Bought/Top sale/Top buy. Sales, Expenses and Profit blocks with per-day figures and the top item.
  - Ledger "Items" view: Sold / Avg Sell / Bought / Avg Buy / Avg Profit. Averages only use sales with a known quantity (`db.LedgerItems :2515`, `db.AvgUnit :2478`).
- **The posting book and its matching window are exactly what our mail-sales tracker needs.**

## 7. Crafting / profession features

- An **"Add to Aegis"** button is attached to TradeSkillFrame/CraftFrame on `TRADE_SKILL_SHOW`/`CRAFT_SHOW` (`ui/frame.lua:19476-19490`, `:11590-11637`).
  - It captures the recipe: name, product itemId, `GetTradeSkillNumMade` yield, and reagents {name, count, itemId} (`core/buy.lua:3312-3345`).
  - Stored account-wide in `crafting.projects`.
- Profit maths (`core/buy.lua:3348-3430`):
  - `craft.MarketUnit` = newest daily minimum, else market (`:3184`).
  - `CostOf` returns total, complete and missing names, and only answers when every reagent is priced ("a crafting cost that reads low is the direction that loses money").
  - `ValueOf` = unit × made.
  - `NetOf` = value × (1 − 0.05) − cost.
  - `CostForItem` gives the cheapest per-unit craft cost across captured recipes and feeds the tooltip's "Crafting Cost" line.
- A **live profit line on the profession window** works with the AH closed. It shows "Aegis: Profit Xg" in green or red, plus "mats … sells …".
  If prices are missing it says "price the mats in the AH" (`ui/frame.lua:11640-11720`, setting `profLine`). A poller hides it when the window closes.
- **Crafting tab:**
  - Want-quantity stepper (`craft.Want`, `CraftsFor` handles yield rounding at `:3439-3519`).
  - **Aggregated shopping list** across tracked recipes, expanding sub-reagents up to depth 4 (`craft.ShoppingList :3568`).
  - `CheaperSource` compares vendor and AH prices; a tie goes to the vendor (`:3528`).
  - "Price all" fires real AH searches for every reagent you're short of.
  - Bags and bank are counted; there's a "Spent X of Y" tracker.
  - `/aex shop` opens the list in a standalone window that pops up at merchants.
- Profession **cooldowns** across alts (`/aex cd`, `core/db.lua:615-680`, `core/buy.lua:3805-3940`). Ready times are stored as epoch values, and a ready-now line is printed at login.
- Crafts made are detected from "You create" chat (`craft.ParseCreate :3731`, behind a dirty flag).
- **Tailoring-relevant:** cloth → bolt chains expand as sub-reagents, and Mooncloth cooldown tracking is included.

## 8. AuctionFrame integration: REPLACE, not tab

- Aegis is a **standalone top-level frame under UIParent that replaces the Blizzard AH** (aux-style, `ui/frame.lua:1-22`).
- On `AUCTION_HOUSE_SHOW` → `ui.OpenWindow()`, which hooks, hides Blizzard **with a session-preserving OnHide**, and shows its own frame (`:19396-19458`).
- How the hook works (`ui.HookAuctionFrame :19150-19218`):
  - Save and replace AuctionFrame's OnShow so it *queues* a hide for the next tick (`AegisExchangeHider`).
  - Save and replace OnHide so it returns early while `ui.keepSessionOpen` is set (`ui.HideBlizzardAH :19221-19226`).
- The way back: an "Aegis UI" button is parented to AuctionFrame next to its close button. It's the only frame parented to Blizzard's.
  - A title-bar "Blizzard UI" button calls `ui.ShowBlizzardUI()`, using the `showBlizzard` flag (`:19413-19430`).
- Closing Aegis's own window ends the session via its OnHide (it calls CloseAuctionHouse).
- `AUCTION_HOUSE_CLOSED` hides the window, cancels queues and clears caches (`:19460-19474`).
- It also hooks bag right-click (send the item to the Sell tab only while Sell is visible) and shift-click (put the item name in the search box) (`:19230-19395`).
- The design folder's earlier concept ("Aegis tab docked in the AH frame", `design/README.md`) was abandoned in favour of the standalone window.
  CLAUDE.md still documents `AuctionTabTemplate` as the correct template if you add tabs (`CLAUDE.md:243-246`).

## 9. UI screens worth copying

Sub-tabs: Buy, Sell, Auctions, Crafting, History, Scan/"Aegis" (`ui/frame.lua:185`). Resizable, with list rows that re-fit and window scale from 70–150%.
- **Scan strip / console** (`design/1b`, `1c`, `01-scan-strip.png`, `02-aegis-scan-console.png`):
  - Full Scan / Pause / Resume, one StatusBar, and "Page x / y · ~N min remaining · N auctions/sec".
  - A stale-scan idle warning, and a gate/server timing readout.
- **Sell tab** (`design/2a`, `06-sell-tab.png`):
  - Bag grid grouped by category on the left.
  - Header with unit and stack price, stack size × count, duration radios, Deposit (approx), Total, After-cut, and "Listings 87/120".
  - Competitor listings table: Unit, Available ("2 stacks of 20"), Stack price, **% Mkt** coloured green or red, and a "You?" column.
  - Clicking a row takes that price.
  - A low-price warning modal (`design/1g`) and a below-vendor / worth-more-disenchanted notice.
- **Auctions tab** (`design/1h`): your auctions with Stack / Your price / Cheapest / Status rows, tinted red for Undercut and green for Lowest.
  - Per-row Cancel and "Cancel all N".
  - Bids section below. The book value is "at most X after the cut".
  - Note: undercut status compares against `db.MinBuyout` (today's daily minimum) (`ui/frame.lua` ≈`:12257`, `:12604`).
- **Buy tab** (`design/1d`, `1e`, `07-buy-tab.png`):
  - Results grouped by item ("8 auctions, 129 items"). Expand a row for the individual auctions; right-click to search all of an item.
  - Unit and % Mkt columns. Category tree. Advanced query box, Saved searches and Builder.
  - A session **Receipt** of purchases. Empty states.
- **Crafting tab** (`design/1i`): recipe list, reagent rows with ×count and price, BoP reagents greyed, and a Cost / Value / Profit bar
  (green/red) with "Find reagents on AH". The shipped version merges recipes into one shopping list.
- **History**: gold-over-time chart plus a Ledger window with Items and Transactions views (no mockup; see README `:290-321`).
- **Tooltip block** (`README.md:322+`, `design/1j`, `ui/tooltip.lua:376-615`):
  - Seen N times, Aegis Buyout, Market, vendor sell and buy, Crafting Cost, disenchant breakdown, and inventory per character and location.
  - Hooks are set on the GameTooltip *object*, never the metatable, so private scan tooltips don't re-enter.
- Optional pfUI skin, every call pcall-guarded (`ui/skin.lua`).

## 10. Lua 5.0 / 1.12 gotchas not already in our notes

- **32-upvalue limit per function.** Lua 5.0 refuses to load the file; 5.1 tooling won't catch it. Group constants into tables (`CLAUDE.md:205-226`).
- File-scope local read above its declaration resolves to a nil global (`CLAUDE.md:610-615`).
- `FauxScrollFrame_OnVerticalScroll(itemHeight, updateFn)` takes 2 args on 1.12 (`CLAUDE.md:247-251`).
- **Stormable events** (MAIL_INBOX_UPDATE, BAG_UPDATE, AUCTION_ITEM_LIST_UPDATE, TRADE_SKILL_UPDATE) need O(1), state-gated, or dirty-flag-per-frame handlers (`CLAUDE.md:253-323`).
- A full id sweep with `GetItemInfo` (1..120000) floods the server with item queries (~25/s `GET_ITEM_INFO_RECEIVED`) and grows the C-side cache in a 32-bit
  process until it crashes to desktop. That's why it's **off by default** (`core/db.lua:170-188`).
- `GetAuctionItemTimeLeft("list", i)` exists on 1.12 and returns 1..4 (`ROADMAP.md:801-808`).
- Durations: 120/480/1440 minutes become 6h/24h/72h on Turtle-family servers. 120-auction cap, 5% cut, deposit about 0.6× of the client figure (`core/sell.lua:27-63`).
- Optional DLLs used: ClassicAPI `C_Item` (exact item level and vendor price, always guarded) and AuctionQueryThrottle. SuperWoW is used for an optional "live file" export (`core/db.lua:3100-3400`).
