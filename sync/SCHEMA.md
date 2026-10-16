# TaxTheFoolsDB schema and merge rules

Every key the addon (0.11.0) stores under `TaxTheFoolsDB`, read from the code in `TaxTheFools/`, with the
rule `sync/merge` applies to it. The rules are the policy of the phase 9 spec, section 5. A path not listed
here is merged as **local wins** (the remote value fills in only when the local side has none) and is
reported in `Report.Unknown` so the tool can log it.

`*` stands for a dynamic key. "Newer `at`" means the table with the larger `at` field wins and the local
side wins a tie. Times are `time()` seconds; days are `floor(time / 86400)`.

Not synced at all: `TaxTheFoolsCharDB` (per-character window positions and `sellView`, `widgets.lua`,
`ui_stock.lua`) and `TaxTheFoolsDB_broken` (`db.lua`, a set-aside unreadable copy).

## Top level

| Path | Shape | Written by | Rule |
|---|---|---|---|
| `dataVersion` | number | `db.lua` `DB.Init` | Max. |
| `version` | string, addon version | `core.lua` at login | Local only. |
| `settingsAt` | number | `db.lua` `DB.Touch` (every settings writer, Task 1) | Max. |
| `settings` | table, defaults in `data.lua` | see below | The side with the newer `settingsAt` wins (local on a tie), except `settings.mail.keep` and `settings.mail.keepRemoved`. |
| `items` | `[id] = item` | `items.lua`, `sell.lua`, `scan.lua`, `tradeskill.lua` | Per item, see below. |
| `realms` | `[realmName] = realm` | `db.lua` `DB.Realm` | Per realm, see below. A realm only one side has goes through the same rules. |
| `recipes` | `[profession] = { trainer, seen }` | `recipes_learn.lua` | See below. |
| `sync` | `{ at, device, version }` | the TTF Sync tool only (`core.lua` reads it) | Local only; the tool sets it after merging. |
| `probe` | list of strings | `probe.lua` (`/ttf probe` debug dump) | Local only. |

## `settings`

Shape (`data.lua` `D.DEFAULTS.settings`): `debug`, `replaceBlizzardAH`, `replaceBlizzardMail`, `minimap`,
`minimapAngle`, `scale`, `theme`, `fonts`, `scanDelay`, `safeMode`, `browseFeedsHistory`, `bagClick`,
`tooltip{market,low,vendor}`, `craft{autoWatch,staleDays}`, `deals{...}`, `buy{confirmAbove}`,
`sell{bidPct,floorPct,undercut,duration,repostDays}`, `sales{days,warnPct,tooltip}`, `ledger{vendor}`,
`trend{tooltip}`, `alerts{...}`, `recipes{tooltip,skillAhead}`,
`mail{bankAlt,rules{...},keep,keepRemoved}`.

Writers: `options.lua` `Opt.Set` (every Options row), `ui_deals.lua` rail switches and sliders,
`minimap.lua` drag, `core.lua` `/ttf debug`, `ui_mail.lua` and `options.lua` keep list through
`DB.KeepSet`. All call `DB.Touch`.

| Path | Shape | Rule |
|---|---|---|
| `settings` (everything else) | as above | Whole table from the newer `settingsAt`. |
| `settings.mail.keep` | `[key] = time added` (old saves: `true`, counted as time 0) | Union with removal records: an entry survives when it was added after its key's removal time. When both sides list it, the later add. |
| `settings.mail.keepRemoved` | `[key] = time removed` | Union, keeping the latest time; pruned after 90 days; a key whose entry survives loses its record (the addon clears it on a re-add). |

## `items[id]`

Writers: `items.lua` `I.Remember` (`n` name, `q` quality, `st` stack size, `t` texture), `I.Vendor` and
`I.LearnVendorPrices` (`v` vendor sell price), `I.LearnMerchantPrices` (`vb` vendor buy price, `vbLimited`),
`sell.lua` `Sell.LearnDeposit` (`dep = { [minutes] = base }`).

Rule: union by field, the non-nil value. When both sides have a field, the local value for the facts
(`n`, `q`, `st`, `t`, `v` and anything else) and the remote value for the learned fields: `vb` together
with `vbLimited` (taken as a pair from the remote side whenever it has `vb`), and each `dep[minutes]`.
The addon keeps no stamp on these fields, so the spec's "newer stamp" case never applies.

## `realms[r]`

Defaults (`data.lua` `D.REALM_DEFAULTS`): `history`, `market`, `scan`, `chars`, `watch`, `snipe`,
`removed{watch,snipe}`.

| Path | Shape | Written by | Rule |
|---|---|---|---|
| `history[key].days[day]` | `{ n, qty, min, p25, med, sellers, src }` | `price.lua` `P.Record` (scans and browse) | Union by day. When both sides have a day, the rule follows `P.Record`: a scan row (`full`, `watch`, `mats`, `snipe`) beats a `browse` row, and within the same class the larger `n` wins, local on a tie. Days at or below the merged `foldedTo` are dropped. |
| `history[key].foldedTo` | number, the newest day ever folded | `price.lua` `P.Compact` (only moves forward) | Max. Day rows at or below it have already been counted in a month on some device, so they are dropped and never folded twice. Unfolded days stay, whatever their age, for the addon to fold. |
| `history[key].months[month]` | `{ p25, n, d }`, month `yyyymm` | `price.lua` `P.Compact` | Union by month, the larger `n`, local on a tie. |
| `market[key]` | `{ v, conf, low, lowDay, seen, n }` | `scan.lua` `Scan.MarketStep`, `Scan.RecomputeMarket` (at login, Task 1) | Union by key; when both have it, the side whose `history[key].days` has the newest day, local on a tie. Recomputed at login anyway. |
| `scan.lastFull` | number | `scan.lua` after a full scan | Max. |
| `scan.resume` | saved scan job | `scan.lua` | Local only: never taken from the remote side. |
| `snapshot` | `{ at, day, changedAt, rows = { [key] = { "count\|buyout\|minBid\|owner", ... } } }` | `scan.lua` `Scan.SaveSnapshot` (full and partial scans), `Scan.SnapshotRemove` (bought listings from `auction.lua`, `ui_deals.lua`); each stamps `changedAt` | The newer `changedAt` (falling back to `at`), local on a tie. |
| `watch[key]` | time added (old saves `true`) | `db.lua` `DB.WatchSet` from `core.lua`, `ui_browse.lua`, `tradeskill.lua` | Union with removal records, as `settings.mail.keep`. |
| `removed.watch[key]` | time removed | `DB.WatchSet` | Union, latest time, 90-day prune, cleared by a surviving entry. |
| `snipe[key]` | `{ max, name, at }` | `snipe.lua` `Snipe.Set`/`SetMax` from `core.lua` `/ttf snipe`, `ui_browse.lua`, `ui_craft.lua` | Union with removal records; the added time is `at`; when both sides list it, the newer `at`. |
| `removed.snipe[key]` | time removed | `Snipe.Remove` from `ui_deals.lua` | As `removed.watch`. |
| `chars[name]` | character record | `db.lua` `DB.Char` | Per character, below. |

## `realms[r].chars[name]`

| Path | Shape | Written by | Rule |
|---|---|---|---|
| `class` | string | `DB.Char` | Local, else remote. |
| `bags`, `bagsAt` | `[key] = count`, time | `inventory.lua` | Both from the side with the newer `bagsAt` (local on a tie). |
| `bank`, `bankAt` | `[key] = count`, time | `inventory.lua` | Both from the side with the newer `bankAt`. |
| `professions[prof]` | `{ rank, maxRank, at, recipes }` | `tradeskill.lua` `TS.Capture` | Newer `at`. |
| `sales` | list `{ key, name, outcome, money, at, qty, unit, secs }` | `sales.lua` `Sales.Record`, `ResolveNames` | Union, de-duplicated by `(at, outcome, money, name or key)`. Cap 2000, 120 days. |
| `postings` | list `{ key, stack, bid, buyout, minutes, deposit, at, done, reconciled }` | `sell.lua` `Sell.Log`, `sales.lua` `Reconcile`, `Record` sets `done` | Union, de-duplicated by `(at, key, stack, buyout)`; `done` set on either side stays set. Cap 500, 35 days. |
| `ledger` | list `{ at, kind, amount, key, qty, who }` | `ledger.lua` `Ledger.Add`, `Backfill`, `BidWon`; `ledger_hooks.lua` | Union, de-duplicated by `(at, kind, amount, key)`. `vendorIn`, `vendorOut` and `mailOut` grow in place (one per merchant visit, one postage entry per send chain): matched by `(at, kind, who)`, the larger amount kept. Cap 5000, 180 days. |
| `pendingBids` | list `{ name, amount, at, key, used }` | `Ledger.PendingBid`; `BidWon` and `BidLost` set `used` (they don't remove the entry) | Union, de-duplicated by `(name, amount, at)`; `used` is the larger of both sides. 7 days. |
| `pendingBuys` | list `{ name, at, used }` | `Ledger.PendingBuy`; `BidWon` sets `used` | The same, with no amount in the identity. |
| `seenMail[key]` | `{ at, n }`, `at` = last change (old saves: a bare time, one mail) | `mail.lua` `Mail.Read`, `Mail.Forget` (lowers `n` to at least 0 and stamps `at`, never deletes) | The newer `at`; on a tie the larger `n`, then local. `n = 0` reads as unseen. Keys older than 120 days go, as in `Sales.Prune`. |
| `ledgerBackfilled` | boolean | `Ledger.Backfill` | Logical OR. |

List details, all in `sync/merge/lists.go`:

- **Duplicates.** A list is merged as a multiset: an identity appears as many times as on the side
  that has it most often. Two identical sold mails read in one second are two sales, and two identical
  auctions reconciled in one second are two postings.
- **Paired entries.** Paired entries take the union of their fields, local first. This is how
  `done` and a key added later by `Sales.ResolveNames` survive. Postings pair finished entries first.
- **Order.** When the result holds exactly one side's entries, that side's order is kept. Otherwise
  entries are sorted by `at`, and ties are broken by content.
- **Age limits.** The addon's login prunes (`Sell.Prune`, `Sales.Prune`, `Ledger.Prune`, the bid
  expiry) run again with the injected clock.
- **Caps.** Caps are re-applied after that, dropping the oldest `at` first.

## `recipes[prof]`

| Path | Shape | Written by | Rule |
|---|---|---|---|
| `trainer[name]` | `{ c, s, at }` | `recipes_learn.lua` `RL.ReadTrainer` | Newer `at`. |
| `seen[id]` | `{ n, skill, r, at }` | `recipes_learn.lua` `RL.FromTooltip` | Newer `at`. |

## Not covered by section 5, and the rule chosen

- `dataVersion`: max, so a device that already migrated isn't migrated again.
- `version`, `probe`: local only (per install, or debug output).
- `scan.resume`: local only. The spec says resume and job state stay local, so a remote resume is never taken.
- `class`: local, else remote.
- History months: larger `n`, as the spec says. `d` (days folded) isn't compared.
- History day rows: the source class is compared first (scan beats browse, as in `P.Record`), then `n`.
- Legacy watch and keep `true` values, and snipe entries with no `at`: `DB.StampLegacy` stamps them with
  `DB.LEGACY_AT` (1) at login, never with the current time, so a removal made on another device always
  beats them. The merge reads `true` as time 0.
- Unknown paths: local wins, and the remote value fills in only when the local side has none, so that
  nothing a newer addon writes is lost. Every such path is reported.
