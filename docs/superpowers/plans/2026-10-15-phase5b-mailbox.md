# Tax The Fools: Phase 5b (Mailbox) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task by task.
> Requirements, interfaces and required tests. Implementers write the code test-first against the spec.

**Goal:** A TTF mailbox window that replaces Blizzard's and TurtleMail: Collect all, multi-stack Send, Fill for bank alt by rules, and right-click to attach.

**Architecture:**
- **Pure rules:** `mailrules.lua`.
- **Engine:** chains with a lock, in `mailbox.lua`.
- **Window hook:** `mailhook.lua` (mirrors `ahhook.lua`).
- **UI:** `ui_mail.lua`, plus additions to `bagclick.lua` and `options.lua`.
- **Plumbing:** wired through `core.lua`.

**Spec:** `docs/superpowers/specs/2026-10-15-phase5b-mailbox-design.md`.

## Global Constraints

- Everything in the phase 4 plan's Global Constraints still applies:
  - the Lua 5.0 rules (no `#`, `%`, `string.match`, `select`; no closures over loop variables; at most 32 upvalues)
  - no `_G` (use `getglobal`)
  - a strict fake client, citing a source for each addition
  - one commit per task, with a trailer naming the model.
- **Mail calls:** `GetInboxText`, `TakeInboxMoney`, `TakeInboxItem`, `DeleteInboxItem`, `ReturnInboxItem`, `SendMail`, `ClickSendMailItemButton`, `SetSendMailMoney` and `CheckInbox` are called only from `mailbox.lua`, and only in chains or actions started by a click. `GetInboxInvoiceInfo` is never called. `mail.lua` stays header-only.
- **Auction calls:** the AH rules are unchanged.
- **Timing:** chains time out after 10 seconds of silence.
- **Defaults:**
  - `settings.mail = { bankAlt = nil, rules = { crafted = true, tradeGoods = true, patterns = true, auctionable = false }, keep = {} }`
  - `settings.replaceBlizzardMail = true`.
- **Pass counts:** each task reports its actual count; the gate is 0 failed. Baseline 500 passed.

## Review Focus

1. **A player's letter with text and an item:** Collect all takes the item and does not delete the letter. Tested in Task 2.
2. **A COD mail, or a GM mail, in the middle of the inbox:** never touched, and the chain moves past it. Tested in Task 2.
3. **The bags fill halfway through Collect all:** the chain stops, the lock is released, and the status says why. Tested in Task 2.
4. **A stack moved or used between Fill and Send:** that attachment is skipped, and the rest are sent. Tested in Task 2.
5. **TurtleMail still enabled:** our window never replaces MailFrame, and bag right-click never attaches. Tested in Tasks 3 and 5.

---

### Task 1: Fake client mail model and pure rules

**Files:** modify `tests/wow_stub.lua` (spec §7 fake client, in full); create `TaxTheFools/mailrules.lua` (in the .toc after `mail.lua`) and `tests/test_mailrules.lua`; add the defaults to `data.lua`.

**Interfaces produced:**
- `MailRules.Plan(h)`
- `MailRules.Matches(item, rules, keep, ctx)`
- `MailRules.Subject(name, count)`
- `MailRules.Postage(price, n)`.

**Stub API (for later tasks):**
- `WoW.inbox`: a list of `{ sender, subject, money, cod, item = { id, name, count } or nil, isGM, returned, body, daysLeft }`.
- `WoW.sent`: a log of sent mails.
- `WoW.mailErrors`: queued errors.
- The events those calls fire, modelled on the 1.12 behaviour.

**Required tests:** the rules list in spec §7, plus smoke tests of the stub inbox and send model.

**Commit:** `feat: fake client mailbox model and pure mail rules`

### Task 2: Engine (`mailbox.lua`)

**Files:** create `TaxTheFools/mailbox.lua` (in the .toc after `mailrules.lua`) and `tests/test_mailbox.lua`; modify `core.lua` (`MAIL_INBOX_UPDATE`, `MAIL_SEND_SUCCESS`, `MAIL_CLOSED`, the `UI_ERROR_MESSAGE` routing to `Mailbox.OnError`, and the per-frame tick, all through `Core.Safe`) and `tests/test_core.lua` (the automation guard from spec §7).

**Required:** spec §4 in full.

**Interfaces produced:**
- `Mailbox.CollectAll()`, `Mailbox.CollectOne(i)`, `Mailbox.Delete(i)`, `Mailbox.Return(i)`, `Mailbox.Read(i)` (returns the body)
- `Mailbox.Send(to, subject, body, money, attachments)`
- `Mailbox.Stop()`
- the state `Mailbox.busy`, `Mailbox.progress = { done, total, kind }`, `Mailbox.status` (text, token) and `Mailbox.collected` (money this visit)
- `Mailbox.OnChange`, a callback the UI sets.

**Required tests:** the engine list in spec §7, the automation guard, and Review Focus 1–4.

**Commit:** `feat: mailbox engine for collect all and multi-stack send, click-started chains`

### Task 3: Window hook (`mailhook.lua`) and probe

**Files:** create `TaxTheFools/mailhook.lua` (in the .toc after `ahhook.lua`) and `tests/test_mailhook.lua`; modify `core.lua` (`MAIL_SHOW` and `MAIL_CLOSED` to the hook, and the tick) and `probe.lua` (spec §7 probe).

**Required:** spec §2, and the TurtleMail rule from spec §1.
- `MailHook.window` is set by Task 4. Until then the tests use a stub frame.
- Expose `MailHook.Active()`: replacing is on, TurtleMail isn't loaded, and our window is shown.

**Required tests:** the hook list in spec §7, and Review Focus 5 (hook side).

**Commit:** `feat: TTF mail window hook with TurtleMail detection`

### Task 4: Mail window and Inbox tab (`ui_mail.lua`)

**Files:** create `TaxTheFools/ui_mail.lua` (in the .toc after `ui_history.lua`) and `tests/test_mail_ui.lua`; modify `core.lua` if the window is built at init.

**Required:** spec §5 (the window and Inbox tab).
- Reuse `W.Window`, `W.TabStrip`, the list, the status strip and the AH window's header pattern.
- Set `MailHook.window`.
- Repaint on `MAIL_INBOX_UPDATE` and `Mailbox.OnChange`.

**Required tests:**
- rows, tags and the footer
- Collect all, Collect, Delete and Return wired to the engine, and Stop
- Read shows the body
- no engine call made by opening or painting.

**Commit:** `feat: TTF mail window with the Inbox tab`

### Task 5: Send tab and right-click to attach

**Files:** modify `TaxTheFools/ui_mail.lua`, `TaxTheFools/bagclick.lua`, `tests/test_mail_ui.lua` and `tests/test_bagclick.lua`.

**Required:** spec §5 (the Send tab and adding from bags).
- Fill for bank alt uses `MailRules.Matches`, with products from `Craft.Index(realm.chars)`, auctionable from `Sell.Auctionable(Sell.TipLines(bag, slot))`, and type from `GetItemInfo(id)`.
- Send calls `Mailbox.Send`.

**Required tests:**
- Fill matches and keep
- right-click attaches on Send, passes through on Inbox, and passes through with TurtleMail loaded (Review Focus 5)
- Remove and Keep
- the postage line
- Send is wired to the engine with the right attachments
- sending to yourself is refused.

**Commit:** `feat: Send tab with Fill for bank alt and right-click to attach`

### Task 6: Options, docs and version

**Files:** `TaxTheFools/options.lua` and `tests/test_options.lua` (the spec §6 Mail category); `docs/testing-checklist.md` (the spec §7 in-game steps, continuing the numbering); `README.md` (mailbox features, "replaces TurtleMail: disable it", and the roadmap); version 0.7.0 in the .toc and `data.lua`.

**Commit:** `feat: Mail options; docs: mailbox checklist, README and version 0.7.0`

## Execution order

Tasks 1 to 6 run in order. Tasks 2, 3 and 4 all touch `core.lua`, and Tasks 4 and 5 share `ui_mail.lua`.
