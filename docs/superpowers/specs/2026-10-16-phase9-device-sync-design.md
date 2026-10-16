# Tax The Fools: Phase 9, device sync

Date: 2026-10-16
Status: approved in conversation, written for review

## 0. Goal

The user plays on a Windows PC, a Windows laptop and a Steam Deck (Linux, WoW through Proton). TTF data on each device (scans, prices, sales, ledger, snipe list, settings, character data) has to reconcile across all three, without the user doing anything by hand.

A 1.12 addon can't reach the network. The only thing it can do is write its SavedVariables file on logout or `/reload`. So sync is done by a companion program, **TTF Sync**, with a small private backend on **Supabase**.

A website is out of scope (a possible later bonus). Sync is the priority.

## 1. Decisions

| Topic | Decision |
|---|---|
| Companion | `ttf-sync`, a single Go binary per platform: `ttf-sync-windows-amd64.exe` and `ttf-sync-linux-amd64` (Steam Deck). The source lives in `sync/` in this repo, and binaries ship as GitHub release assets. |
| Backend | One Supabase project owned by the user. One table holds the merged state, plus a device log. All access goes through Postgres RPC functions (`SECURITY DEFINER`) that check a sync key. Tables have RLS on with no policies, so the anon key alone can read nothing. |
| Auth | No login. `ttf-sync init` creates an account row and prints a long random **sync key**; only its SHA-256 is stored. Each other device runs `ttf-sync join <key>` once. The Supabase URL and anon key go in the local config. |
| Where merging happens | In the client. The server stores the latest merged blob and a version number, and accepts a write only when the expected version matches (compare-and-swap). On a conflict the client pulls, merges again and retries, up to 3 times. |
| Blob | The parsed `TaxTheFoolsDB`, as JSON, gzip-compressed and base64-encoded. Expected size is a few MB. |
| When | `ttf-sync run -- <command...>` syncs, starts the game command, waits for it to exit, then syncs again. On Windows a shortcut runs `ttf-sync run -- "C:\...\WoW.exe"`. On the Deck, WoW's Steam launch options are `ttf-sync run -- %command%`. `ttf-sync sync` runs one sync by hand. |
| Safety | The tool never writes the file while WoW is running (process check: `WoW.exe` / `Wow.exe`, case-insensitive, including under Wine/Proton). Before every write it keeps the last 5 copies in a `backups/` folder beside the config. A file it can't parse is never overwritten, and it says why. |
| Per-character file | `TaxTheFoolsCharDB` only holds window state, so it isn't synced. `TaxTheFoolsDB_broken` isn't synced either. |
| Free tier | Supabase pauses free projects after about a week with no activity; regular syncs count as activity. If a sync finds the project paused, the tool reports "Your Supabase project is paused: open the dashboard and resume it", and the game still starts. |

## 2. Addon changes (version 0.11.0)

- **Settings timestamp.** Every settings change (`Opt.Set`, the Deals rail switches, and any other code that writes `DB.S()`) sets `TaxTheFoolsDB.settingsAt = time()`.
- **Removal records.** These tables now record what was removed:
  - the watchlist (`realm.watch`)
  - the snipe list (`realm.snipe`)
  - the mail keep list (`settings.mail.keep`).

  Removing an entry also records `realm.removed[kind][key] = time()`, or `settings.mail.keepRemoved[key]` for the keep list. Adding an entry records its time too: `watch[key] = time()` instead of `true`, which is backwards-compatible because every check for `true` still holds; snipe entries already have `at`; `keep[key] = time()`. Re-adding an entry clears its removal record.
- **Sync status.** `TaxTheFoolsDB.sync` is written only by the tool: `{ at, device, version }`. `/ttf sync` prints "Last synced 2h ago from Laptop (TTF Sync 1.0.0)", or "Not synced yet: see docs/sync.md".
- **Device-local data is kept out of sync.** Scan resume state and anything per-session stays local. The merge rules (§5) list exactly what is synced and what isn't.

## 3. Backend (`sync/supabase/001_init.sql`)

```sql
create table accounts (id uuid primary key default gen_random_uuid(), key_hash text unique not null,
                       created_at timestamptz default now());
create table state (account uuid primary key references accounts(id) on delete cascade,
                    version bigint not null default 0, blob text not null default '',
                    updated_at timestamptz default now(), updated_by text);
create table devices (account uuid references accounts(id) on delete cascade, device text,
                      last_sync timestamptz, primary key (account, device));
alter table accounts enable row level security;  -- no policies: only the functions below
alter table state enable row level security;
alter table devices enable row level security;
```

All functions are `security definer`, granted to `anon`, and take `p_key` (the raw sync key, hashed inside with `encode(digest(p_key,'sha256'),'hex')` using `pgcrypto`):

| Function | What it does |
|---|---|
| `ttf_create_account(p_key)` | Inserts the account and an empty state row. |
| `ttf_pull(p_key)` | Returns `(version, blob, updated_at, updated_by)`. |
| `ttf_push(p_key, p_expected bigint, p_blob text, p_device text)` | Updates the state when `version = p_expected`, setting `version = version + 1`, and returns the new version. Otherwise it returns `-1`. It also upserts the device's `last_sync`. |
| `ttf_devices(p_key)` | Lists the devices. |

A wrong key raises `invalid sync key`.

The user runs the SQL once in the Supabase SQL editor; `docs/sync.md` explains how.

## 4. TTF Sync (`sync/`, Go, standard library only)

### Config

- Windows: `%APPDATA%\ttf-sync\config.json`. Linux: `~/.config/ttf-sync/config.json`.
- Fields: `supabaseUrl`, `anonKey`, `syncKey`, `device` (defaults to the host name), `wowPath`, `account` (the WTF account folder name).

### Commands

| Command | What it does |
|---|---|
| `setup` | Interactive. Asks for the WoW folder (it searches common paths, including Steam Deck compatdata and Lutris prefixes, and lists any it finds), picks the account folder (or asks when there are several), and asks for the Supabase URL and anon key. |
| `init` / `join <key>` | `init` creates the account and prints the key; `join` stores a key and checks it with `ttf_pull`. |
| `sync` | Runs pull → merge → write the local file → push, as described below. |
| `run -- cmd args...` | Runs `sync`, starts `cmd`, waits, then runs `sync` again. If a sync fails, the game still starts. |
| `status` | Shows the config, the last sync and the devices. |
| `restore` | Lists the backups and restores one. |

### How `sync` works

1. Read and parse the local SavedVariables file. A missing file counts as empty.
2. Pull the remote state (version and blob) and decode it.
3. Merge: `local ⊕ remote`.
4. Write the merged result to the local file, after the backup and the process check. If WoW is running, skip the write and say so; still push.
5. Push with the expected version. On `-1`, pull and merge again, up to 3 times.
6. Set `sync = { at, device, version }` in the written file.

### Lua SavedVariables I/O

- **Reading:** a small parser for the subset the client writes:
  - `NAME = <value>` statements
  - values: nil, true/false, numbers (including `-`, decimals and exponents), strings (with `\"`, `\\`, `\n` and `\ddd` escapes), and tables (`{ [k] = v, v, ... }` with string or number keys)
  - `--` comments.
- **Writing:** emits the same shape, with keys sorted (number keys first) so output is deterministic.
- **Representation:** tables become an ordered Go structure that keeps the difference between number keys and string keys, so `["1"]` and `[1]` stay distinct.

### Merge engine (`merge.go`)

Pure and table-driven, with rules by data path (§5). Values with no rule are taken from whichever side has the newer `settingsAt`/`sync.at`; when both are equal, the local side wins.

## 5. Merge rules

The plan's Task 3 first writes `sync/SCHEMA.md` by reading the addon code. That file catalogues every key under `TaxTheFoolsDB` and is checked in review. These rules are the policy it must follow:

| Data | Rule |
|---|---|
| `items[id]` (the item cache) | Union. For each field, prefer the non-nil value; for a learned field such as `vb` or `dep`, take the side with the newer stamp if there is one, else the remote side. |
| `realms[r].history[key].days[day]` | Union by day. When both sides have a day, keep the row with the larger `n` (listing count). Do the same for `months[month]`. |
| `realms[r].snapshot` | Keep the one with the newer `at`. |
| `realms[r].market` | Union by key, keeping the entry from the side whose history has the newest day for that key. Simpler: the addon recomputes market values at login (Task 1 confirms or adds this), so the merge can take either. |
| `realms[r].scan` | `lastFull` takes the max. Resume or job state stays local (never synced). |
| `realms[r].watch`, `realms[r].snipe`, `settings.mail.keep` | Union with removal records. An entry survives when its added time is later than the removal time for its key. Removal records are unioned, keeping the max time, and pruned after 90 days. |
| `realms[r].chars[name]` | Per character. `bags`, `bank` and `professions[prof]`: take the side with the newer `at` (the addon stamps `at` on each capture or scan; Task 1 adds stamps where they're missing). |
| `chars[name].sales` | Union, de-duplicated by `(at, outcome, money, key or name)`. |
| `chars[name].postings` | Union, de-duplicated by `(at, key, stack, buyout)`. `done` is true on either side → true. |
| `chars[name].ledger` | Union, de-duplicated by `(at, kind, amount, key)`. Combined vendor and postage entries (one entry per visit, keeping its first `at`, with an amount that grows) are de-duplicated by `(at, kind)`, keeping the larger amount. |
| `chars[name].seenMail[key]` | Keep the max `n`. |
| `chars[name].pendingBids` / `pendingBuys` | Union, de-duplicated by `(name, amount, at)`. |
| `chars[name].ledgerBackfilled` and similar flags | Logical OR. |
| `recipes[prof].trainer[name]` / `seen[id]` | The newer `at` wins. |
| `settings` (the whole table) | The side with the newer `settingsAt` wins, except `mail.keep`, which follows the rule above. |
| `sync` | Written by the tool. |
| Anything not listed in `SCHEMA.md` | Local wins, and the tool logs the path once per run so it can be added later. |

Caps (5000 ledger entries, 2000 sales, 500 postings) are re-applied after merging, dropping the oldest entries first, the same as the addon does.

## 6. Testing

- **Go unit tests:**
  - Parser round trip on hand-written fixtures and on a larger fixture produced by the addon's own test harness. A `make sync-fixture` Lua script dumps a populated `TaxTheFoolsDB` in SavedVariables format.
  - Escapes, number keys versus string keys, and `nil` values.
  - Each merge rule.
  - Idempotence (`merge(a,a) == a`), commutativity of the union rules, and removal records beating older adds.
  - Caps.
- **Integration tests:** an `httptest` fake implementing the four RPCs with the compare-and-swap semantics. Tests cover a conflict retry, a wrong key, a paused project (HTTP 5xx or a specific body), the backup rotation, the refusal to write while the game is running (process lister injected), and the `run` command order (a fake game command).
- **Addon tests:**
  - `settingsAt` is set by every settings writer.
  - Removal records for watch, snipe and keep; a re-add clears its record.
  - `/ttf sync` text.
  - Timestamps on captures.
- **Manual checklist (`docs/sync.md` plus `testing-checklist.md`):**
  - set up on the PC (`init`), then on the laptop and the Deck (`join`)
  - scan on the PC, then play on the laptop: the prices are there
  - sell on the laptop: History on the PC shows it
  - remove a snipe item on one device and check it stays removed on the others
  - start the game through Steam on the Deck
  - with WoW open, `sync` refuses to write
  - `restore` works.
