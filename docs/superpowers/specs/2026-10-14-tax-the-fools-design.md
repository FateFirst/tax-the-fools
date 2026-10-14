# Tax The Fools — design

Date: 2026-10-14
Status: draft for review

## 1. Purpose

A gold-making addon for the Ravencraft server (unmodified Turtle WoW 1.18.1 client: WoW 1.12.1 build 5875, Interface 11200, Lua 5.0).

The player has two characters on the same account:

- **Bank alt**: does all AH buying and selling, and scans the AH every few days.
- **Main**: Undead Priest with Tailoring and Skinning, who crafts and farms.

Success means:

1. A scan on the bank alt builds a price history that every character on the account can see, with no rescanning per character.
2. The addon suggests buys that should resell (or vendor) for a profit, and shows the profit after the AH cut and deposit.
3. The addon shows, for every learned tailoring recipe, the material cost, the value of the product, and the profit or loss.
4. Over time, the addon learns which items actually sell and at what price, from the player's own AH mail.

### Decisions already made

| Topic | Decision |
|---|---|
| Characters | Same account, so data is shared through account-wide SavedVariables. Data appears on another character after a logout or `/reload`. |
| Self-gathered materials (looted cloth, skinned leather) | Always valued at market price. Recipes also show a second figure: cash profit using materials already in bags or bank. |
| Automation | One hardware click = at most one buy, bid, post or cancel. Scanning is the only automated part: the scan pages through the AH on its own, the way aux does. Nothing ever buys or posts from OnUpdate or from an event. |
| AH window | Our own window replaces Blizzard's AuctionFrame, with a button to switch back. |
| Visual style | Aegis Pathfinder's look (dark flat panels, green accent, Rajdhani and Inter fonts, tinted nine-slice textures), **reimplemented**. Pathfinder is GPLv3, so no code is copied from it. Aegis_Exchange is MIT, so patterns and short snippets from it may be adapted, with credit. |
| Deal types | All four: below market, below vendor, cheap materials, undersupplied. |
| Recipes | Learned recipes only, captured from the tradeskill window. A full recipe database comes later. |
| Skinning | Leather and hides are valued at market price, like any other material. No extra views. |
| Client DLLs | None required. Optional ClassicAPI functions are used if present. AuctionQueryThrottle is **not** recommended: its own README says it has no effect on Ravencraft, which throttles on the server, and a reported bug returns duplicate pages. |

### Out of scope (for now)

- Auto-buying, auto-posting, or any chained server actions after a single click.
- A database of recipes the player hasn't learned, and recipe-payback analysis (phase 5).
- A mailbox tab for bulk collecting mail and sending goods to the bank alt (phase 5).
- Sharing prices with other players. aux's Turtle fork does this through a chat channel, which lets anyone poison the data.
- Crawling every item ID with `GetItemInfo`. This floods the server and can crash the client.

## 2. Build phases

Each phase can be installed and used on its own.

1. **Core and scanning.** Addon skeleton, theme and widget kit, our own AH window (Browse tab plus scan controls), full scan, watchlist scan, price history, market value, tooltips, and the options window.
2. **Crafting.** Capture recipes, then show cost, value and profit: a Crafting tab and its own window, a profit strip on the tradeskill window, and adding all materials and products to the watchlist.
3. **Buying and selling.** Deals tab (all four types, with one-click Buy), Sell tab (suggested price, one click per Post), Auctions tab (undercut status, one click per Cancel), a log of what was posted, and a record of bag and bank contents.
4. **Sales tracking.** Read AH mail headers, match them to what was posted, work out the sell rate per item, add a History tab, and feed the sell rate into "undersupplied" deals and price suggestions.
5. **Later.** A recipe database with payback analysis, and a mailbox tab with bulk collect and send-to-alt rules.

## 3. Repository layout

The layout follows HealMyAss (`/Users/liamnorth/repos/heal-my-ass`).

```
TaxTheFools/            the addon folder that gets installed
  TaxTheFools.toc
  fonts/ textures/      bundled assets (fonts under the OFL licence; textures as 32-bit uncompressed power-of-two TGA)
  *.lua
tests/                  run.lua, wow_stub.lua (fake client), test_*.lua
tools/                  lint.sh, make-textures, install/update script
docs/                   research/, superpowers/specs, superpowers/plans, testing-checklist.md
Makefile                targets: lua, lint, test, install, clean
```

### Conventions carried over from HealMyAss

- Each file begins with `TaxTheFools = TaxTheFools or {}` and attaches its module, for example `TaxTheFools.Price = P`. Files read the modules they depend on into locals at the top.
- A function is never named the same as a module.
- One event frame lives in `core.lua`, which is loaded last. Each module lists the events it wants (`EVENTS`) and handles them in its own `OnEvent`.
- Default settings are merged in recursively. A migration runs once, keyed on `DATA_VERSION`.
- Chat output goes through `U.msg`, prefixed `TTF:`. There is one hidden scanning tooltip. Slash command: `/ttf`.

### Lua 5.0 rules, enforced by `tools/lint.sh`

- None of these: `#`, `%`, `string.match`/`gmatch`, `select`, `hooksecurefunc`, `strsplit`, or `function(self, event`.
- Use `table.getn`, `math.mod` and `string.gfind` instead.
- A function may reference at most 32 upvalues (variables from enclosing scopes). This is checked with `luac -l`.
- Never pass multi-return calls straight into `ipairs(...)`; assign to a local first.

## 4. Modules

Pure logic (no WoW API calls; fully unit-testable):

| Module | Responsibility |
|---|---|
| `util.lua` | Lua 5.0 helpers, money formatting (`12g 34s 56c`, with colours), item-link parsing (`item:ID:enchant:suffix:unique` into an item key), time helpers using `time()` |
| `stats.lua` | Percentiles, weighted median, coefficient of variation |
| `price.lua` | Builds a day summary from raw listings; works out market value and confidence; handles retention and compaction |
| `deals.lua` | Scores listings against the four deal rules; deposit and AH-cut maths |
| `craft.lua` | Recipe cost, value, profit and cash profit; flags recipes with missing prices |
| `sales.lua` | Classifies mail subjects; matches sales to posting records; works out sell rates |
| `layout.lua` | Column widths, text fitting and truncation, row pooling maths |

Glue code that talks to the game:

| Module | Responsibility |
|---|---|
| `data.lua` | Constants, defaults, built-in vendor-price table for common tradeskill materials |
| `db.lua` | SavedVariables setup, defaults, migration, pruning, realm keys |
| `items.lua` | Item cache (name, quality, stack size, vendor price); learns vendor prices at merchants and in the AH sell slot; optional ClassicAPI lookups |
| `scan.lua` | Scan state machine (§6) |
| `auction.lua` | Buy, bid, post and cancel actions, each run from one click (§8) |
| `inventory.lua` | Records the contents of bags and bank per character |
| `tradeskill.lua` | Captures recipes from the tradeskill window; the profit strip |
| `mail.lua` | Reads mail headers when the mailbox opens (phase 4) |
| `tooltip.lua` | Adds the price block to item tooltips |
| `theme.lua` | Colour tokens, fonts, nine-slice panels, widget kit (§9) |
| `ui_*.lua` | AH window and its tabs, Crafting window, options window, minimap button |
| `core.lua` | Event frame, init, slash commands |

## 5. Data model

There is one account-wide SavedVariable, `TaxTheFoolsDB`, plus a small per-character one, `TaxTheFoolsCharDB`, for window state only. Prices are keyed by realm, because the AH is cross-faction on Turtle-derived servers. Item metadata is shared across realms.

```lua
TaxTheFoolsDB = {
  dataVersion = 1,
  settings = { ... },                      -- account-wide options (§9)
  items = {                                -- itemId -> metadata
    [14047] = { n="Runecloth", q=1, st=20, v=400 },   -- v = vendor sell price per unit in copper; nil if unknown
  },
  realms = { ["Medivh"] = {
    history = {                            -- itemKey -> daily rows
      ["14047:0"] = {
        days = { [20375] = { min=..., p25=..., med=..., n=listings, qty=units, sellers=k_or_nil, src="full"|"watch"|"browse" }, ... },
        months = { [202609] = { p25=..., n=..., d=daysSeen } },   -- compacted rows older than 60 days
      },
    },
    market = { ["14047:0"] = { v=..., conf=0..1, low=..., lowDay=..., seen=... } },  -- cache, recomputed after each scan
    scan = { lastFull=time, resume={ page=..., total=..., started=..., partial={...} } or nil },
    chars = { ["Name"] = {
      class=..., professions = { Tailoring = { rank=..., recipes = { [recipeName] = {
          item=itemKey, yieldMin=1, yieldMax=1, color="orange|yellow|green|grey",
          reagents = { { item=itemKey, count=n }, ... } } } } },
      bags = { [itemKey]=count }, bank = { [itemKey]=count }, bagsAt=time, bankAt=time,
      postings = { ... },                  -- phase 3: { item, stack, count, bid, buyout, duration, at }, capped at 500, kept 35 days
      sales = { ... },                     -- phase 4: { item, outcome="sold|expired|cancelled|won", money, qty_or_nil, unit_or_nil, at, mailKey }, capped at 2000, kept 120 days
      seenMail = { [mailKey]=at },         -- de-duplication; pruned with sales
    } },
    watch = { [itemKey]=true },            -- manual watchlist; recipe materials and products are added automatically
  } },
}
```

- **Item key:** `itemId:suffixId`. Random-suffix items get separate prices; enchant and unique ID are ignored, as in aux.
- **Day number:** `floor(time() / 86400)`, which is a UTC day. Day boundaries are UTC, deliberately, so every character agrees on what "today" is. All timestamps use `time()`, never `GetTime()`. aux and TurtleMail both have expiry bugs from using `GetTime()`.
- **Retention:** daily rows are kept for 60 days. Older rows are folded into monthly rows, which are kept for 12 months. Pruning runs at login, a few items per frame.
- **Size:** about 5,000 distinct items × 30 days × ~6 numbers stays within what 1.12 handles comfortably. If file size becomes a problem, day rows switch to aux's compact string form.

## 6. Scan engine (`scan.lua`)

One state machine, driven by an OnUpdate attached to our AH window. It only runs while the AH is open.

### Kinds of scan

- **Full scan:** pages through an empty query until the last page.
- **Watchlist scan:** one exact-name query per watched item, paged until that item's results run out.
- **Browse:** a manual search in the Browse tab. Every page it returns also feeds the history, marked `src="browse"`.

### Step loop

1. Wait until `CanSendAuctionQuery()` is true and a minimum delay has passed since the last query (default 0.3 s; "safe mode" setting: 4 s).
2. Send `QueryAuctionItems(name, "", "", invType, class, subclass, page, usable, quality)`. Name and level are always strings, never nil.
3. On `AUCTION_ITEM_LIST_UPDATE`:
   - Read `GetNumAuctionItems("list")`, then for every row `GetAuctionItemInfo` and `GetAuctionItemLink`.
   - Store the unit buyout (the buyout divided by the stack count; rows with no buyout count toward listings but not toward prices), quantity, and owner if present.
   - Owner names arrive late on 1.12. The scan never waits for them; the seller count only covers rows whose owner was known.
4. **Duplicate-page guard:** compute a signature for the page (each row's name, count and buyout, plus the row count).
   - If it matches the previous page's signature, ask for the page again after the safe delay.
   - After two duplicates, switch the rest of this scan to safe pacing.
5. **Timeouts:** if there's no update within 15 s, resend the same page, up to 3 times. After that, pause the scan and show "server not responding — Resume".
6. **Progress:** show page X of Y, the measured seconds per page, and the estimated time left. Each page's time is split into client wait, server reply time, and our own delay.

### Interruptions

- **AH closed mid-scan:** the page reached and the listings so far (`scan.resume`) are saved. On the next visit, the status strip offers Resume or Discard.
- **Resume on another day:** the scan is discarded instead, so one day's summary never mixes listings from two days.

### Finishing a scan

- The listings are summarised into one `days[today]` row per item.
- A full scan replaces any rows already written today.
- A watchlist scan or browse only replaces the rows for items it actually saw. A browse never overwrites a row written by a full scan or watchlist scan today.
- Market values are then recomputed for the affected items, a few hundred per frame so the game doesn't freeze.

### Hiding Blizzard's AuctionFrame

Hiding AuctionFrame calls `CloseAuctionHouse()`, which kills the AH session. Aegis_Exchange's workaround:

- On `AUCTION_HOUSE_SHOW`, wait one frame, then hide AuctionFrame with its OnHide handler temporarily swapped out, and show our window.
- Our window's close button and Escape call `CloseAuctionHouse()`.
- The "Blizzard UI" button reverses this.

## 7. Pricing and deals

### Day summary (per item, per scan day)

- **`min`:** lowest unit buyout.
- **`p25`:** the 25th-percentile unit buyout, weighted by quantity. This is the "fair price" for that day: one troll listing can't drag it down, and a wall of overpriced stacks can't push it up.
- **`med`:** median unit buyout.
- **`n`:** number of listings. **`qty`:** total units. **`sellers`:** distinct owners, where known.

### Market value

- **Value:** the weighted median of daily `p25` over the last 30 days, with weight `0.9^ageDays`. Monthly rows are only used when the item has no daily rows.
- **Confidence (0 to 1):** `min(1, daysSeen/5) × (1 − clamp(cv, 0, 0.6)/0.6 × 0.5)`, where `cv` is the coefficient of variation of the daily `p25` values.
  - Labels: high ≥ 0.7, medium ≥ 0.4, low below that.
  - With a single day of data the value is still shown, marked low confidence.
- **Lowest now:** the `min` from the newest row, and that row's age.

### Costs

- **AH cut:** 5% of the sale price.
- **Deposit:** Turtle's formula, as used by aux:
  `floor(vendorUnit × stack × (minutes/120) × (1 + (maxStack − stack) × 0.05) × 0.025) × stackCount`.
  - Where the vendor price is unknown, the deposit counts as 0 in the profit maths, and the deal is flagged "deposit unknown".
  - A deposit seen on a real post replaces the estimate for that item and duration.
- **Default duration** for posting and deposit maths: the middle duration, 8 hours (shown as 24h on Turtle). It's a setting.

### Deal rules

Rules are evaluated against the listings from the most recent scan or browse. Every deal shows profit, profit as a percentage, and the rule that triggered it.

| Type | Triggers when | Profit |
|---|---|---|
| **Below market** | unit buyout ≤ `belowMarketPct` (default 70%) × market, confidence ≥ medium, profit ≥ `minProfit` (default 50s) | `qty × market × 0.95 − buyout − deposit` |
| **Below vendor** | vendor price known and buyout < `qty × vendor` | `qty × vendor − buyout` (no AH cut, no deposit) |
| **Cheap materials** | item is a material in a captured recipe; replacing that material's market price with this unit buyout makes the recipe's profit ≥ `minProfit`; and unit buyout ≤ `matPct` (default 85%) × market | the gain in recipe profit per craft, × the number of crafts this listing covers. The deal names the recipe. |
| **Undersupplied** (phase 4) | sell rate ≥ 50% from at least 3 posting outcomes; current listing count ≤ ⅓ of the 30-day median listing count; and any character holds the item in bags or bank | sell suggestion: post at `max(market, lowestNow)` × `premiumPct` (default 110%). This deal type has no Buy button. |

Items with no market value, or only low confidence, never appear as "below market" deals. They can appear under the other rules.

## 8. Actions: one click each (`auction.lua`)

Every action runs from a button's OnClick handler and makes at most one server call: `PlaceAuctionBid`, `StartAuction` or `CancelAuction`. A single lock blocks a second action until the result comes back (`ERR_AUCTION_BID_PLACED` / `ERR_AUCTION_STARTED` / `ERR_AUCTION_REMOVED` or an error via `UI_ERROR_MESSAGE`) or 5 s pass.

### Buy

A deal row stores the auction's signature: item key, stack count, buyout and seller (if known).

- **Click "Buy":**
  - If a matching row is on the AH page currently loaded, buy it now with `PlaceAuctionBid("list", index, buyout)`.
  - Otherwise send one exact-name search for the item (that click's one server call). The row then shows "Searching…" and then "Found — click to buy" or "Gone".
- **Click "Found — click to buy":** check the match again on the current page, then buy it.
- **Never:**
  - buy a different auction than the one shown
  - buy if the buyout has changed
  - buy if you can't afford it
  - place a bid when Bid was meant (Bid refuses any amount ≥ buyout).

### Post (Sell tab)

- Choose an item from the bag grid. The tab shows the competing listings from the latest data, with "% of market" and "You?" columns.
- **Suggested price:** 1c under the cheapest listing that's ≥ `floorPct` (default 80%) of market, never below the floor, and the market value if nothing is listed.
- **Each "Post" click puts up one stack:**
  - pick up that stack (splitting into an empty bag slot first if needed, because the sell slot reliably takes only whole bag stacks)
  - `ClickAuctionSellItemButton()`
  - `StartAuction(bid, buyout, minutes)`.
  - The button stays ready for the next stack. Posting N stacks takes N clicks.
- **Splitting a stack** is its own click, because it changes the bag before posting. The button reads "Split" then "Post".
- Each post is written to `postings`.

### Cancel (Auctions tab)

- One click calls `CancelAuction` once.
- Rows are refreshed from `GetOwnerAuctionItems` after each cancel, because indices shift.
- Rows are red when undercut and green when you're cheapest.
- The tab shows a count of active auctions.

## 9. User interface

### Theme (`theme.lua`)

Reimplemented from the Aegis Pathfinder notes (`docs/research/notes-aegis.md`):

- **Colour tokens:**
  - `bg #202020`, `header #111111`, `strip #3b3b3b`, `border #050505`
  - `accent #52c722`, `gold #ffed71`, `text #e6e6e6`, `dim #c7c7bd`
  - `bad #d9534f`, `good #52c722`, `warn #e0a030`
  - Switching theme re-colours open windows live.
- **Fonts:** Rajdhani for headings (uppercase), Inter for body text. Both are OFL-licensed and bundled.
- **Textures:** one white 32 px rounded rectangle, sliced into nine pieces and tinted with `SetVertexColor`, draws panels, buttons, tabs and fields. An 8×8 white texture stands in for `SetColorTexture`. Small glyph textures are used for ✕, ☰, ✓ and the arrows. No Blizzard frame art.
- **Widgets:** window frame (header bar, close, subtitle), tab strip, pill and panel buttons, switch, checkbox, slider (sets its value on release), dropdown (on its own FULLSCREEN_DIALOG layer so it never gets clipped), edit box, money input (g/s/c), sortable list with pooled rows and a themed scrollbar, progress bar, custom tooltip.
- **Windows:**
  - added to `UISpecialFrames` so Escape closes them
  - draggable, re-anchored at their top-left corner after a drag
  - resizable from a corner grip
  - position and size saved per character
  - scalable (85–150%).

### AH window

Replaces AuctionFrame (§6). The header shows the current gold.

- **Tabs:** Deals · Browse · Sell · Auctions · Crafting · History.
  - Deals and Sell arrive in phase 3, History in phase 4. Tabs from later phases are hidden until those phases ship.
- **Status strip** under the tabs: Full scan, Watchlist scan, progress bar, page count, estimated time left, Resume/Discard, "last full scan 2d ago".
- **Deals:**
  - The left rail has deal-type toggles and minimum-profit and percentage sliders.
  - The table columns are item (icon, quality colour), qty, buyout, market, %, profit, type, and Buy.
  - Columns sort. Hovering a row shows the price history (a sparkline of daily p25 plus the numbers) and the confidence.
- **Browse:** search box, category dropdown, a "usable" toggle, and a results table with % of market. A Buy or Bid button acts on the selected row.
- **Sell:** bag grid on the left. On the right: competing listings, suggested price, stack size, number of stacks, duration, and the deposit preview.
- **Auctions:** your listings with status colours and Cancel.
- **History** (phase 4): per item, sold count, expired count, sell rate, average price, and income; per character totals; date filter.

### Crafting window

Opened with `/ttf craft`, the minimap button, or the AH Crafting tab. It works on any character.

- **Header:** a dropdown for character and profession.
- **Table columns:** recipe, skill colour, cost, value, profit, cash profit, data age.
- **Expanding a row** shows its materials: need, have (bags and bank, all characters), unit price, source (market / vendor / none) and age.
- Prices older than 7 days are shown dim.
- A recipe whose material or product prices are incomplete shows "incomplete" with the missing items named. It never shows a guessed profit.
- **Cash profit** treats materials already held as free, and buys only what's missing at market price.
- "Add materials to watchlist" happens automatically. A toggle turns it off.

### Tradeskill strip

A thin themed bar attached under `TradeSkillFrame`. It shows the selected recipe's cost, value and profit, coloured good or bad, and updates when the selection changes. Recipes are captured every time the window opens or `TRADE_SKILL_UPDATE` fires, using:

- `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillItemLink`
- `GetTradeSkillNumMade` (gives the yield range)
- `GetTradeSkillNumReagents`, `GetTradeSkillReagentInfo`, `GetTradeSkillReagentItemLink`.

Header rows are skipped.

### Tooltip

Hooks `GameTooltip` SetBagItem, SetInventoryItem, SetAuctionItem, SetTradeSkillItem, SetMerchantItem, SetLootItem, SetHyperlink and SetInboxItem by wrapping the originals, as aux does. Adds:

- `Market 1g 20s (high)`, `Low now 1g 05s · 2d`, `Vendor 25s`
- in phase 4, `Sells 72% (18)`.

Each line can be switched off in options. Multiplied by stack size when the Shift key is held.

### Options window

Aegis layout: a category list on the left and a scrolling page of rows on the right. One refresh function pushes saved settings back into the controls.

| Category | Settings |
|---|---|
| General | minimap button, window scale |
| Scanning | minimum delay, safe mode, resume behaviour, browse feeds history |
| Deals | enable per type, `belowMarketPct`, `minProfit`, `matPct`, `premiumPct`, minimum confidence |
| Selling | `floorPct`, default duration, undercut amount |
| Crafting | auto-watch materials, stale-price days |
| Tooltip | per-line toggles |
| Appearance | theme, fonts on/off (falls back to the stock font) |
| Data | prune now, reset with a confirmation dialog, data size readout |

### Minimap button

Left-click opens the Crafting window. Shift-left-click opens Deals, using the last scan's data if the AH is closed: read-only, with Buy disabled. Right-click opens options. Drag to move it around the minimap.

## 10. Sales tracking (`mail.lua`, phase 4)

### Reading the mail

- **When:** on `MAIL_INBOX_UPDATE`, at most once per frame, because the event fires dozens of times on first open. Every header is read with `GetInboxHeaderInfo`. Opening mail text or invoices is avoided, since that marks mail as read.
- **Classifying subjects** uses the client's own format strings, turned into search patterns:
  `AUCTION_SOLD_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT`, `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_OUTBID_MAIL_SUBJECT`.
- **Payout:** comes from the header's `money` field.
- **De-duplication key:** `subject|money|floor(daysLeft × 24)` plus the character.
  - The key is remembered in `seenMail`, which is pruned along with sales.
  - (Aegis_Exchange's mail keys are never pruned. That's a size problem we avoid.)

### Working out quantity

Sold mail never states the quantity, so it's worked out by matching against `postings`:

- **Unambiguous match:** the open postings for that item contain exactly one stack/buyout combination consistent with `money / 0.95`. The sale gets that quantity and unit price.
- **No unambiguous match:** quantity stays nil, and the sale counts toward the item's sell rate but not its average price.
- **Posts made outside the addon:** the posting log is topped up from `GetOwnerAuctionItems` on every AH visit.

### Sell rate and live updates

- **Sell rate:** `sold / (sold + expired + cancelled)` over 30 days, per item, across all characters.
- **Online sale message:** `ERR_AUCTION_SOLD_S` in system chat gives an instant "sold" toast while online. The record itself is created only from the mail.

## 11. Error handling

- **Missing data:**
  - Items not in the client cache show "Unknown item #ID" until `GetItemInfo` resolves. They're looked up again a few at a time when the item is seen, using `SetHyperlink` on the hidden tooltip to prompt the client.
  - With ClassicAPI present, `C_Item.RequestLoadItemDataByID` is used instead.
- **Server errors:** `UI_ERROR_MESSAGE` errors are shown on the status strip and release the action lock. These include:
  - not enough money
  - item not found
  - auction house full
  - can't post that item.
- **Game errors:** every event handler and OnUpdate step runs inside `pcall` when debug is off. An error disables only that module for the session and prints one chat line, instead of throwing an error every frame.
- **Corrupt data:** a SavedVariables table that fails validation is renamed (`TaxTheFoolsDB_broken_<time>`), not deleted, and a fresh one is created.
- **Auction status:** a deal or a posting never claims "bought" or "posted" until the server confirms it.

## 12. Testing

- `make test`:
  - runs real Lua 5.0.3 against a fake client copied from HealMyAss's `wow_stub.lua`
  - adds fakes for the AH, mail, merchant and tradeskill APIs, and a scripted auction house that serves pages from fixtures
  - can simulate delays, duplicate pages and timeouts.
- **Unit tests** cover the pure-logic modules: percentiles and weighted median, market value and confidence on synthetic histories, every deal rule including the edge cases (no vendor price, low confidence, single listing), deposit maths against values seen on Turtle, recipe profit and cash profit, mail subject classification, sale-to-posting matching (unambiguous, ambiguous, none), retention and compaction.
- **State machine tests:**
  - scan state machine: normal run, duplicate page, timeout, AH closed mid-scan and resumed, resume on a new day
  - action lock: one click → one server call, confirmed or timing out.
- **An automation guard test** fails if `PlaceAuctionBid`, `StartAuction` or `CancelAuction` is ever called anywhere other than inside a simulated click.
- **Lint:** Lua 5.1-only constructs, `luac -p`, and the 32-upvalue limit.
- **In game:** a `docs/testing-checklist.md` run after each phase is installed. It covers the AH window opening and closing without killing the session, a short full scan, a watchlist scan, a tooltip, tradeskill capture, and `/reload` keeping positions and data.
- **Probe:** a debug command (`/ttf probe`) dumps API availability and sample return values (AH row, mail header, tradeskill reagent) to a copyable window. Real-client fixtures come from that dump, as in HealMyAss.

## 13. Open questions to settle in game

These don't block the design; the probe answers them.

1. Exact AH page timing on Ravencraft: how long `CanSendAuctionQuery` stays false, and how long the server takes to reply.
2. Whether `GetInboxInvoiceInfo` exists on this client. Assumed absent.
3. Whether the auction duration labels (6h/24h/72h on Turtle) match the `minutes` values 120/480/1440.
4. The real deposit for a few known items, to check the deposit formula.
5. Whether mail between your own characters on one account arrives instantly. This matters for phase 5.

## 14. References

- `docs/research/notes-aux.md`: aux scanning, history, posting, tooltip hooks, deposit formula.
- `docs/research/notes-aegis-exchange.md`: Ravencraft AH behaviour, hiding AuctionFrame, mail matching, crafting capture (MIT).
- `docs/research/notes-aegis.md`: Pathfinder visual language and widget kit (GPLv3, so it is reimplemented, not copied).
- `docs/research/notes-interact-mail.md`: TurtleMail mail APIs and sequencing; Interact (a DLL, not relied on).
- `docs/research/notes-aqt.md`: AuctionQueryThrottle (not recommended on Ravencraft); optional ClassicAPI functions.
- HealMyAss (`/Users/liamnorth/repos/heal-my-ass`): project conventions, test harness, lint, install script.
