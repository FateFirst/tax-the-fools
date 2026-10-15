# Tax The Fools: Phase 4 (Sales Tracking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** Learn what sells from AH mail and show it in History, tooltips, the Sell tab and undersupplied deals. Also add right-click on bag items to search (Browse) or select (Sell).

**Architecture:**
- **Pure rules:** `sales.lua`.
- **Mail reading:** header-only, in `mail.lua`.
- **UI:** a History page (`ui_history.lua`), plus additions to the tooltip, Sell, Deals and options.
- **Bag clicks:** the wrapper in `bagclick.lua`.
- **Plumbing:** everything is wired through `core.lua`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase4-sales-tracking-design.md`, with the parent spec §7 and §10.

## Global Constraints

- Everything in the phase 3b plan's Global Constraints still applies:
  - the Lua 5.0 rules, and no `_G` (use `getglobal`/`getfenv(0)`)
  - a strict fake client (no `_G`, `GetItemInfo` by id or itemString only)
  - check ClassicAPI signatures
  - one commit per task, with a trailer naming the model.
- **Mail calls:** `GetInboxText`, `GetInboxInvoiceInfo`, `TakeInboxMoney`, `TakeInboxItem`, `DeleteInboxItem` and `ReturnInboxItem` are never called anywhere.
- **Auction calls:** `StartAuction`, `CancelAuction`, `SplitContainerItem` and `PlaceAuctionBid` remain click-only. A right-click from the bags only searches or selects.
- **Sales defaults:** `settings.sales = { days = 30, warnPct = 120, tooltip = true }`.
- **Undersupplied defaults:** `settings.deals.under = true`, `underPct = 33` and `premiumPct = 110`.
- **Right-click default:** `settings.bagClick = true`.
- **Pass counts:** each task reports its actual count; the gate is 0 failed. Baseline 370 passed.

## Review Focus

1. **The same mail seen on two visits, or after a relog:** recorded once. Tested in Task 2.
2. **A sold mail whose money fits two different stack/buyout postings:** quantity unknown, and the sale still counts toward the rate. Tested in Task 1.
3. **Right-click on a bag item while the AH window is closed, or with Shift held:** the original game handler runs. Tested in Task 3.
4. **The mailbox opened with 50 AH mails and a burst of update events:** one read per frame and no forbidden call. Tested in Task 2.
5. **An undersupplied deal:** its action never buys. Tested in Task 5.

---

### Task 1: Pure sales rules (`sales.lua`)

**Files:** create `TaxTheFools/sales.lua` (in the .toc after `sell.lua`) and `tests/test_sales.lua`. Add the `settings.sales` defaults to `data.lua`.

**Interfaces produced:** `Sales.Classify(subject)`, `Sales.Record(char, outcome, itemName, money, now, items)`, `Sales.Stats(chars, key, days, now)`, `Sales.Reconcile(char, ownerRows, now)` and `Sales.Prune(char, now)`, as in spec §3. Storage is `char.sales` (a list) and `char.seenMail`.

**Required tests:** the `sales.lua` list in spec §7, plus Review Focus 2.

**Commit:** `feat: pure sales rules for classifying AH mail, matching posts and sell-rate stats`

### Task 2: Reading mail (`mail.lua`) and wiring

**Files:** create `TaxTheFools/mail.lua` (in the .toc after `sales.lua`) and `tests/test_mail.lua`. Modify `tests/wow_stub.lua` (the mail API, events and logging of forbidden calls, each citing its source), `core.lua` (`MAIL_SHOW`, `MAIL_INBOX_UPDATE`, the per-frame tick, the `ERR_AUCTION_SOLD_S` note, and `Sales.Prune` at login, all through `Core.Safe`) and `ui_auctions.lua` (call `Sales.Reconcile` with the owner rows on `Read`).

**Required:** spec §2 in full, and the `Reconcile` hook.

**Required tests:**
- Review Focus 1 and 4
- the live sold note
- `Reconcile` called from the Auctions read
- extend the automation guard in `tests/test_core.lua` with the six forbidden mail calls.

**Commit:** `feat: read AH mail headers into sales history without opening mail`

### Task 3: Right-click from bags (`bagclick.lua`)

**Files:** create `TaxTheFools/bagclick.lua` (in the .toc after `ui_auctions.lua`) and `tests/test_bagclick.lua`. Modify `tests/wow_stub.lua` (`ContainerFrameItemButton_OnClick`, `IsControlKeyDown` and `IsAltKeyDown`) and `core.lua` (install the wrapper at init, once). Add `settings.bagClick` to `data.lua`.

**Required:** spec §5 in full. The wrapper is installed once and is safe to install twice. The setting is read at click time.

**Required tests:** the right-click cases from spec §7 UI, and Review Focus 3.

**Commit:** `feat: right-click bag items to search on Browse or select on Sell`

### Task 4: History tab, tooltip line and Sell panel

**Files:**
- **Create:** `TaxTheFools/ui_history.lua` (in the .toc after `ui_auctions.lua`) and `tests/test_history_ui.lua`.
- **Modify:** `ui_window.lua`, so that `UI.TABS` gains History after Auctions.
- **Modify:** `tooltip.lua`, adding the "Sells" line and the `settings.sales.tooltip` toggle.
- **Modify:** `ui_sell.lua`, adding the sales panel and price warning.
- **Modify:** `tests/test_tooltip.lua` and `tests/test_sell_ui.lua`.

**Required:** spec §4 (History, tooltip, Sell panel).

**Required tests:**
- History rows, filters and totals
- the tooltip line on and off
- the Sell panel text, both with and without history
- the warning above `warnPct`.

**Commit:** `feat: History tab, sell-rate tooltip line and sales panel on the Sell tab`

### Task 5: Undersupplied deals and options

**Files:**
- **Modify:** `deals.lua`, adding the pure undersupplied rule, which takes stats, the snapshot count, the median listing count and holdings as inputs.
- **Modify:** `ui_deals.lua`, adding the "Under" type, the rail switch and the **Sell** action, which calls `UI.ShowPage("sell")` and `SellUI.Select(key)`.
- **Modify:** `options.lua`, adding the Sales options and the new Deals rows.
- **Modify:** `data.lua` defaults.
- **Modify:** `tests/test_deals.lua`, `tests/test_deals_ui.lua` and `tests/test_options.lua`.

**Required:** spec §4 (undersupplied) and §6.

**Required tests:**
- every trigger condition: the rate, `n`, the listing ratio, and holdings
- the profit and suggested price arithmetic
- the Sell action switching tabs, with no buy call (Review Focus 5)
- options binding.

**Commit:** `feat: undersupplied deals with a Sell action, and Sales options`

### Task 6: Docs and version

**Files:** `docs/testing-checklist.md` (the steps from spec §7), `README.md` (sales tracking, History, the Sell panel, undersupplied deals, right-click, and that phase 5 is next), and version 0.5.0 in the .toc and `data.lua`.

**Commit:** `docs: sales tracking checklist, README and version 0.5.0`
