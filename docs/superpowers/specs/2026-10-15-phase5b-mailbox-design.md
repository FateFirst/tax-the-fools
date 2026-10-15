# Tax The Fools: Phase 5b, mailbox

Date: 2026-10-15
Status: approved in conversation, written for review
Parent spec: `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` (§2 phase 5). This phase builds on phase 4's header-only mail reading (`mail.lua`, `sales.lua`) and right-click from bags (`bagclick.lua`), phase 3b's auctionable check (`Sell.Auctionable`), and phase 5a's pattern check (`Recipes.IsPattern`). Where this document and an earlier one disagree, this one wins. The goal is that TTF replaces TurtleMail.

## 1. Decisions

| Topic | Decision |
|---|---|
| Window | A TTF-styled mail window with **Inbox** and **Send** tabs replaces Blizzard's mailbox, the same way the AH window does (`settings.replaceBlizzardMail`, default on). A button switches to Blizzard's, and one on Blizzard's switches back. |
| Clicks | For mail, one click may start a chain: **Collect all** takes every collectable mail, and **Send** sends every attached stack (one mail each, the 1.12 limit). A chain stops on full bags, an error, a 10-second silence or the mailbox closing. The AH rule is unchanged: one click per buy, bid, post, cancel or split. |
| Phase 4 rule change | `GetInboxText`, `TakeInboxMoney`, `TakeInboxItem`, `DeleteInboxItem` and `ReturnInboxItem` may now be called, but only by `mailbox.lua` actions started from a click. `mail.lua`'s header reading never calls them, and `GetInboxInvoiceInfo` is still never called. |
| Never | Paying COD. Touching GM mail. Deleting a mail that still holds money or an item. Deleting a player's letter (a mail with body text not from the auction house) during Collect all. |
| TurtleMail | If `IsAddOnLoaded("TurtleMail")`, TTF doesn't replace the mailbox or attach from bags, and prints once per session: "TurtleMail is loaded, so TTF's mailbox is off. Disable TurtleMail to use it." Header reading for sales still runs. |
| Send to bank alt | A bank alt is chosen once (`settings.mail.bankAlt`). **Fill for bank alt** attaches every bag item that matches the ticked rules and isn't on the keep list, and sets the recipient. The user still presses **Send**. |
| COD | Not supported when sending (YAGNI); money can be sent. |

## 2. Window and hook (`mailhook.lua`)

This mirrors `ahhook.lua`.

- **Opening:** on `MAIL_SHOW`, when replacing, the swap happens on the next frame: hide `MailFrame` and show `TaxTheFoolsMail`. Blizzard shows MailFrame from its own handler for the same event, and hiding it inside that would close the mailbox.
- **Keeping the mailbox open:** MailFrame's `OnHide` calls `CloseMail()`. It is wrapped to do nothing while `keepOpen` is set (while our window is up).
- **Closing:** our window's OnHide calls `CloseMail()`, unless we are only switching windows. `MAIL_CLOSED` hides our window and resets state.
- **Switch buttons:** a "Tax the Fools" button on MailFrame (top right, like the AH one), and a "Blizzard" button in our header.
- **Backpack:** opening our window calls `OpenBackpack()` if no bag is open, as Blizzard's mailbox does.

## 3. Pure rules (`mailrules.lua`)

- **`MailRules.Plan(h)`** returns one of `"skip"`, `"take"` or `"take+delete"`, from a header table `h = { sender, subject, money, cod, hasItem, isGM, wasReturned, textCreated }` and a `body` field filled in only when known:
  - **skip** when `cod > 0`, `isGM`, or there is nothing to take and the mail isn't AH mail.
  - **take+delete** when the mail is AH mail (the sender contains "Auction House", or `Sales.Classify(subject)` gives an outcome), or the body is empty.
  - **take** otherwise: a player's letter keeps its text.
- **`MailRules.Matches(item, rules, keep, ctx)`** decides whether a bag item goes to the bank alt.
  - `item = { key, name, type, auctionable }`
  - `rules = { crafted, tradeGoods, patterns, auctionable }`
  - `ctx = { products = set of keys made by any captured recipe on the realm }`
  - It returns false when the key is in `keep` or the item isn't auctionable. Being auctionable stands in for "mailable": soulbound, quest and conjured items can't be mailed.
  - Otherwise it returns true when any ticked rule fits: `crafted` (the key is a product), `tradeGoods` (type `"Trade Goods"`), `patterns` (`Recipes.IsPattern`), or `auctionable` (any auctionable item).
- **`MailRules.Subject(name, count)`** gives `"Name (count)"`, or `"Name"` when the count is 1.
- **`MailRules.Postage(price, n)`** gives `price × max(1, n)`.

## 4. Engine (`mailbox.lua`)

There is one `Mailbox.busy` lock with `kind = "collect"` or `"send"`. Events set flags; the work happens on the next tick (TurtleMail's pattern).

- **`Mailbox.CollectAll()`** (click only):
  1. Run `Mail.Read()` first, so every AH result is recorded before anything leaves the inbox.
  2. Walk from index 1. For each mail, read the header and apply `Plan`. A plan of `"take+delete"` for non-AH mail needs the body, so `GetInboxText(i)` is read for it.
  3. **Before the first take from an unread mail:** call `GetInboxText(i)`. Reading it is what lets the server clear the minimap's new-mail icon, and Blizzard's mailbox and TurtleMail do the same.
  4. **On take:** call `TakeInboxMoney(i)` if money > 0, else `TakeInboxItem(i)` if it has an item. One call per tick, each waiting for `MAIL_INBOX_UPDATE`.
  5. **When the mail is empty:** delete it if the plan is take+delete, then stay at the same index (the list shifts). Otherwise move to the next index.
  6. **Errors:** `ERR_INV_FULL` stops the chain ("Bags full"). `ERR_ITEM_MAX_COUNT` skips that mail.
  7. **When finished:** call `CheckInbox()` once, to load more if the server holds over 50. Report "Collected Xg from N mails".
  8. A session money total shows in the Inbox footer.
- **`Mailbox.CollectOne(i)`** (click): the same as above for one mail. It never deletes a player's letter.
- **`Mailbox.Delete(i)`** and **`Mailbox.Return(i)`** (click): refuse if the mail still has money or an item (Delete) or is AH mail (Return). Each is one call.
- **`Mailbox.Send(to, subject, body, money, attachments)`** (click):
  - `attachments` is a list of `{ bag, slot, key, count }`.
  - **Each step:**
    1. Re-verify the slot still holds `key × count`, otherwise skip it and note it.
    2. Clear the cursor. If `GetSendMailItem()` holds something, `ClickSendMailItemButton()` and clear it.
    3. `PickupContainerItem(bag, slot)`, then `ClickSendMailItemButton()`.
    4. `SetSendMailMoney(money)` on the first mail only.
    5. `SendMail(to, subject or MailRules.Subject(...), body)`, then wait for `MAIL_SEND_SUCCESS`.
  - **No attachments:** one SendMail with the money.
  - **Errors** stop the chain: `ERR_MAIL_TO_SELF`, `ERR_PLAYER_WRONG_FACTION`, `ERR_MAIL_TARGET_NOT_FOUND`, `ERR_MAIL_REACHED_CAP`, `ERR_NOT_ENOUGH_MONEY`, and `ERR_MAIL_DATABASE_ERROR` (wherever the global exists).
  - **Sending to yourself** is refused before anything is called.
  - **Progress:** "Sent 3 of 9".
- **Stopping:** every chain stops on `MAIL_CLOSED` and on a 10-second silence, and it releases the lock. A **Stop** button ends a chain after the current step.

## 5. UI (`ui_mail.lua`)

- **Window:** `TaxTheFoolsMail`, resizable (minimum 560×380), with the header, logo and status strip of the AH window. Tabs: Inbox, Send.
- **Inbox tab:**
  - **List:** icon (the package icon, or the item via `GameTooltip:SetInboxItem` on hover), From, Subject, Money, COD (warning colour), Expires (days), and a Tag ("Sold", "Expired", "Cancelled", "Won", "Outbid" from `Sales.Classify`, or "Returned").
  - **Footer:** "N mails · X gold waiting · collected this visit Y".
  - **Buttons:** **Collect all (N)**, **Collect**, **Delete** and **Return** (on the selected mail), and **Stop** while a chain runs.
  - **Reading:** selecting a mail doesn't open it. A **Read** button shows its body in a detail pane, and that marks it read.
- **Send tab:**
  - **Fields:** To (an edit box plus a dropdown of the realm's characters, defaulting to the bank alt), Subject (blank means automatic), Body, and Money (a money input).
  - **Attachment list:** icon, name and count, with **Remove** and **Keep** on each row. Keep removes the row and adds the item to the keep list.
  - **Footer:** "N mails · postage X".
  - **Buttons:** **Fill for bank alt** (hidden when this character is the bank alt or no bank alt is set), **Clear** and **Send**.
  - **Adding from bags:** right-click a bag item while the Send tab is shown (extending `bagclick.lua`; modifiers pass through as before). An unmailable item says "Can't mail that". An item that is already attached isn't added twice.
- **Bag click on the Inbox tab:** passes through.

## 6. Options

A **Mail** category:
- "Replace Blizzard's mailbox" (default on)
- the bank alt (a dropdown of realm characters, or none)
- the rules: Crafted goods, Cloth and trade goods, Patterns, Anything auctionable (defaults: crafted, trade goods and patterns on; anything off)
- the keep list, with each item listed and a click to remove it.

Defaults: `settings.mail = { bankAlt = nil, rules = { crafted = true, tradeGoods = true, patterns = true, auctionable = false }, keep = {} }` and `settings.replaceBlizzardMail = true`.

## 7. Testing

- **Fake client:**
  - the inbox model: `GetInboxNumItems`, `GetInboxHeaderInfo`, `GetInboxText`, `TakeInboxMoney`, `TakeInboxItem`, `DeleteInboxItem`, `ReturnInboxItem`, `CheckInbox`, `MAIL_INBOX_UPDATE`, and money and items moving to the bags
  - the send model: `GetSendMailItem`, `ClickSendMailItemButton`, `SetSendMailMoney`, `GetSendMailPrice`, `SendMail`, `MAIL_SEND_SUCCESS` and the error messages
  - `MailFrame` with an OnHide that calls `CloseMail`, `MAIL_SHOW` / `MAIL_CLOSED`, `IsAddOnLoaded`, and `OpenBackpack`.
- **Rules:** every Plan branch (COD, GM, AH, an empty body, a letter), every Matches rule plus keep and unauctionable, Subject and Postage.
- **Engine:**
  - Collect all takes money and items, deletes AH mail and keeps letters, and skips COD and GM mail.
  - Bags full stops the chain. A unique item is skipped.
  - `Mail.Read` records sales before the first take.
  - Send makes the exact call sequence per attachment, puts money on the first mail only, skips a changed slot, and stops on each error.
  - Sending to yourself is refused.
  - `MAIL_CLOSED` and a timeout stop a chain. Stop works. The lock is released in every case.
- **Automation guard:** opening the mailbox, receiving inbox updates and switching tabs never calls any Take, Delete, Return, Send, `GetInboxText` or Click-attachment function. Only the simulated Collect, Read, Delete, Return and Send clicks do.
- **Hook:**
  - opening swaps on the next frame
  - closing our window calls `CloseMail`
  - switching windows doesn't
  - with TurtleMail loaded, nothing is replaced and the notice prints once.
- **UI:**
  - inbox rows and tags, and the footer totals
  - Read shows the body
  - Fill for bank alt attaches the matching items and skips the keep list
  - right-click attaches on Send and passes through on Inbox
  - Remove and Keep
  - the postage line
  - options binding.
- **Probe:** presence of `GetSendMailItem`, `ClickSendMailItemButton`, `SendMail`, `TakeInboxItem` and `CheckInbox`, the value of `ATTACHMENTS_MAX_SEND` (expected nil on 1.12), and whether MailFrame has an OnHide script.
- **In-game checklist:**
  - disable TurtleMail
  - open a mailbox: TTF's window shows, and switching back and forth works
  - Collect all with AH mail and a letter: the letter stays, and History still records sales
  - full bags stop the chain
  - send three stacks to the bank alt in one click
  - Fill for bank alt, then keep one item
  - right-click to attach
  - check whether mail between your own characters arrives instantly (parent spec open question 5).
