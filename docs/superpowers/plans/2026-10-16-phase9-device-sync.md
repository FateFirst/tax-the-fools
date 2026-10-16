# Tax The Fools: Phase 9 (Device Sync) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** TTF data stays in step across the PC, the laptop and the Steam Deck. The `ttf-sync` companion program does this through a private Supabase backend, merging rule by rule.

**Spec:** `docs/superpowers/specs/2026-10-16-phase9-device-sync-design.md`.

## Global Constraints

**Addon (Lua 5.0):**
- The usual rules apply: no `#`, no `%`, no `string.match`/`gmatch`, no `select`, no `_G`, no closures over loop variables, and at most 32 upvalues per function.
- Keep the fake client strict.

**Go code:**
- Standard library only.
- The module lives in `sync/` and is named `github.com/FateFirst/tax-the-fools/sync`.
- Run `go vet` and `go test ./...` from `sync/`.
- The root `make test` also runs `go test` for `sync/` when Go is installed.
- Cross-compile with `make sync-build`, which writes `sync/dist/ttf-sync-windows-amd64.exe` and `sync/dist/ttf-sync-linux-amd64`. `dist/` is git-ignored.

**Safety and secrets:**
- Never write the SavedVariables file while WoW is running, and never overwrite a file that fails to parse.
- Back up before every write, keeping 5 copies.
- No secrets in the repo. The sync key, URL and anon key live only in the user's config.

**Process:**
- One commit per task, with a trailer naming the model.
- Baseline: 788 Lua tests passing, with 0 failures as the gate. Go tests must all pass.

## Review Focus

1. **Sale on the laptop, scan on the PC, then sync both in either order.** Both survive and nothing is duplicated (Task 3).
2. **Snipe item removed on the Deck while still present in an older laptop copy.** After syncing, it stays removed (Tasks 1 and 3).
3. **Push races another device.** The compare-and-swap rejects it, and the retry re-merges instead of overwriting (Task 4).
4. **WoW is still running when the after-game sync starts** (for example, Proton exits slowly). No write happens, and the push still runs (Task 5).
5. **A SavedVariables file with unusual strings** (quotes, backslashes, newlines, item links with `|`). It round-trips byte-for-byte after one write (Task 2).

---

### Task 1: Addon support

**Files:** `TaxTheFools/options.lua`, `ui_deals.lua` (the rail), `db.lua`, `data.lua`, `snipe.lua`, `ui_browse.lua` and `core.lua` (watch add and remove, `/ttf watch`, `/ttf sync`), `ui_mail.lua` and `options.lua` (keep), `tradeskill.lua` and `inventory.lua` (timestamps on captures, only where missing), plus tests.

**Required:** spec §2.
- Also confirm whether market values are recomputed from history at login. If they aren't, add that recompute: one pass over the history entries, the same as at the end of a scan.
- Report exactly which settings writers were found.

**Commit:** `feat: settings timestamp, removal records, capture timestamps and /ttf sync status for device sync`

### Task 2: Lua SavedVariables reader and writer (Go)

**Files:**
- `sync/go.mod`
- `sync/luasv/` (reader, writer and an ordered table type) with tests
- `tools/sv-fixture.lua`, a script run by `make sync-fixture`. It loads the addon under the fake client, fills a realistic DB, and writes `sync/luasv/testdata/big.lua` in SavedVariables format.
- `Makefile` targets.

**Required:** spec §4 Lua SavedVariables I/O, plus Review Focus 5.

**Commit:** `feat: Go reader and writer for WoW SavedVariables with a round-trip fixture from the addon`

### Task 3: Merge engine and SCHEMA.md

**Files:** `sync/SCHEMA.md` (catalogued from the addon code), `sync/merge/` and its tests.

**Required:** spec §5 in full, plus Review Focus 1 and 2.

**Commit:** `feat: rule-by-rule merge of TaxTheFoolsDB with removal records and caps`

### Task 4: Supabase SQL and API client

**Files:** `sync/supabase/001_init.sql`, `sync/api/` (client and an `httptest` fake) and their tests.

**Required:** spec §3 and the client side of §4 (pull and push with compare-and-swap, error mapping, paused-project detection), plus Review Focus 3.

**Commit:** `feat: Supabase schema with key-checked RPCs and a Go client with compare-and-swap pushes`

### Task 5: The ttf-sync command

**Files:** `sync/cmd/ttf-sync/` (setup, init, join, sync, run, status and restore), `sync/internal/` (config, paths, process check, backups) and their tests; `docs/sync.md`, a step-by-step user guide that covers creating the Supabase project, running the SQL, the Windows shortcut and the Steam Deck launch options.

**Required:** spec §1 and §4, plus Review Focus 4.

**Commit:** `feat: ttf-sync command with setup, sync and a run-the-game wrapper`

### Task 6: Docs, version and release build

**Files:**
- `README.md`: the Sync section.
- `docs/testing-checklist.md`: the sync steps.
- Version 0.11.0 for the addon, and `ttf-sync` version 1.0.0 (set by `-ldflags`).
- A `make sync-build` check.

**Commit:** `docs: sync guide, checklist, README and version 0.11.0`

## Execution order

1. Tasks 1, 2 and 4 in parallel. They touch separate files: Task 1 the addon, Task 2 `sync/luasv` and `tools/`, Task 4 `sync/api` and `sync/supabase`. The controller pre-creates `sync/go.mod`.
2. Task 3, which needs Task 2's types.
3. Task 5.
4. Task 6.
