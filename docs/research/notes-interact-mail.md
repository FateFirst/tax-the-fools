# Reference notes: Interact + TurtleMail (for AH/crafting profit addon, 1.12.1 / Turtle 1.18.1)

Clones (read-only, nothing executed):
- refs/turtlemail = https://github.com/TheRealFayz/TurtleMail @ c3c0cd0 (2026-08-03). TOC: v1.4.5, author "shirsig/sica" (descends from shirsig's original vanilla TurtleMail).
- refs/interact = https://github.com/lookino/Interact @ 2db6e51 (2025-11-08). Formerly luskanek/Interact (GitHub redirects). **README only; source is NOT published**, binary ships via Releases (Interact.zip, v1.0.1..v1.0.4).
- refs/interact-unitxp = https://github.com/vargv666/Interact @ 9a9ba07 (2024-11-16). Older copy of luskanek's Interact **with C++ source** (dllmain.cpp, Game.cpp/h). Used below to explain how Interact works.

All paths below are relative to `/private/tmp/claude-501/-Users-liamnorth-repos-tax-the-fools/1468595c-a0b9-4cc9-a51b-d865cd416c66/scratchpad/refs/`.

How I found them: `gh search repos TurtleMail` (8 hits; TheRealFayz is the maintained one with matching description), `gh search repos interact turtle wow` (0 hits), `gh search repos "Interact" vanilla wow addon` (-> lookino/Interact), `gh search code 'UnitXP("interact"'` (-> vargv666/Interact with source).

Other TurtleMail variants seen (not cloned): elboaf/Turtlemail (archived; "fixes for tuesday 3/24 patch crashes" - diffed via API: caps autocomplete names at 200 entries with LRU eviction and caches log filtering; i.e. the crash was unbounded SavedVariables/table growth), jrc13245/TurtleMail, GoesInCircles/TurtleMailCompanion (address-book add-on for TurtleMail), galoryber/TurtleMailer (a .NET thing, unrelated). Also seen: ericraio/vanilla-wow-addons `a/AH_MailCollect/AH_MailCollect.lua` (vanilla AH-mail collector) - potential further reference.

---

## 1. TurtleMail

Files: `turtlemail/TurtleMail.lua` (1744 lines, all logic), `TurtleMail.xml` (848, frames), `Calendar.lua` (date picker for log UI), `localization*.lua`.

### 1.1 SavedVariables layout (TOC)
`turtlemail/TurtleMail.toc:6-7`
```
## SavedVariables: TurtleMail_AutoCompleteNames
## SavedVariablesPerCharacter: TurtleMail_To TurtleMail_Point TurtleMail_Log
```
- `TurtleMail_AutoCompleteNames[realm.."|"..faction][name] = GetTime()` (account-wide, multi-char keyed by `GetCVar("realmName").."|"..UnitFactionGroup("player")`) - TurtleMail.lua:99, 270-278, 322-325.
  - BUG to avoid: stores `GetTime()` (seconds since client start, not epoch) and prunes if `GetTime() - last_seen > 30 days` (TurtleMail.lua:273). Use `time()` for persistent timestamps.
- `TurtleMail_Log` (per character!): `{ Sent = {...}, Received = {...}, Settings = { Enabled, SentFilters, ReceivedFilters{..., AHSold, AHOutbid, AHWon, AHCancelled, AHExpired} } }` - defaults at TurtleMail.lua:45-53 (set in `init()` before SV load; SV overwrites them on load).
- `TurtleMail_To` last recipient; `TurtleMail_Point` frame position.
- Takeaway: the log is per-character, so a bank alt's AH sales are only visible on that alt. For our addon, use one account-wide SV keyed by `realm|char` so the main can see the alt's sales/inventory.

### 1.2 Event registration / state machine skeleton
`TurtleMail.lua:33-42`
```lua
self.update_frame = m.api.CreateFrame( "Frame", "TurtleMailFrame", m.api.MailFrame )   -- parented to MailFrame => OnUpdate only runs while mailbox open
self.update_frame:SetScript( "OnUpdate", self.on_update )
self.update_frame:SetScript( "OnEvent", function() self[ event ]() end )
for _, event in { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } do
```
Pattern: events only set flags (`m.inbox_update`, `m.sendmail_update`); the actual API call happens on the next OnUpdate tick (`on_update`, TurtleMail.lua:114-156). This avoids calling mail APIs re-entrantly inside the event handler.

Other Lua-5.0 idioms used: `m.api = getfenv()` (TurtleMail.lua:22) as a handle to globals; global `this`, `event`, `arg1`; `for k,v in tbl do`; `arg` for varargs (`function pack(...) return arg end`, line 6).
Caution: `string.match` at TurtleMail.lua:361 is not stock Lua 5.0 (5.0 has string.find/gfind only); verify it exists on Turtle before relying on it.

Hook installation: functions are declared as `TurtleMail.hook.X = ...` (metatable collects them into `m.hooks`, line 27), then swapped into globals at PLAYER_LOGIN (TurtleMail.lua:266-269):
```lua
for k, v in m.hooks do
  m.orig[ k ] = m.api[ k ]
  m.api[ k ] = v
end
```
Hooked globals: GetInboxHeaderInfo, OpenMail_Reply, InboxFrame_Update, InboxFrame_OnClick, InboxFrameItem_OnEnter, SendMailFrame_Update, SendMailRadioButton_OnClick, ClickSendMailItemButton, GetContainerItemInfo, PickupContainerItem, SplitContainerItem, UseContainerItem, SendMailFrame_CanSend, MailFrameTab_OnClick, OpenMailFrame_OnHide. (Very invasive; hooking PickupContainerItem/UseContainerItem/GetContainerItemInfo globally will conflict with other bag/AH addons. Our addon should avoid replacing these.)

"hack to prevent beancounter from deleting mail": captures raw TakeInboxMoney/TakeInboxItem/DeleteInboxItem at init time before other addons hook them (TurtleMail.lua:56-57).

### 1.3 Bulk open (inbox) - APIs and sequencing
- Start: "Open Mail" button on InboxFrame -> `inbox_open_all` (TurtleMail.lua:329-348) sets `inbox_opening=true, inbox_index=1, inbox_update=true`.
- Tick (TurtleMail.lua:132-148):
```lua
if m.inbox_update then
  m.inbox_update = false
  local _, _, _, _, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( m.inbox_index )
  if m.inbox_index > m.api.GetInboxNumItems() then
    if m.money_received > 0 then m.info( ...format_money(m.money_received).. "collected" ) end
    m.inbox_abort()
  elseif m.inbox_skip or COD > 0 or isGM then   -- never pays COD, never touches GM mail
    m.inbox_skip = false; m.inbox_index = m.inbox_index + 1; m.inbox_update = true
  else
    m.inbox_open( m.inbox_index )
  end
end
```
- `inbox_open` (TurtleMail.lua:413-450) does everything in one go then waits for `MAIL_INBOX_UPDATE` (line 298-301 sets `inbox_update=true` again):
```lua
local package_icon, _, sender, subject, money, cod, _, has_item, read, returned, _, _, gm = m.api.GetInboxHeaderInfo( i )
...
m.api.GetInboxText( i )      -- marks as read (needed before delete)
m.TakeInboxMoney( i )
m.TakeInboxItem( i )
m.DeleteInboxItem( i )
```
  Index is not advanced after a successful open: the deleted mail disappears, so the next mail shifts into slot `i`. The same mail may be visited twice (first pass takes money/item, next MAIL_INBOX_UPDATE pass logs + deletes) - that's how logging of money mails works (lines 424-443).
- 1.12 GetInboxHeaderInfo return order (as used): `packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM` (lines 415, 743).
- `GetInboxItem(i)` -> name (+texture, count, quality...) used for log (line 419). No `AutoLootMailItem` in 1.12 (not used).
- Error handling: `UI_ERROR_MESSAGE` with `ERR_INV_FULL` aborts; `ERR_ITEM_MAX_COUNT` (unique item) skips (TurtleMail.lua:215-221).
- Polling: `m.timer` counts frames; every 200 frames `CheckInbox()` while mailbox open & not opening (lines 150-155) to refresh inbox (vanilla inbox caps at 50 shown).
- Gold collected: `update_money(money)` accumulates `m.money_received` into a FontString `MoneyReceived` on InboxFrame (TurtleMail.lua:394-403, xml:296-299); reset on MAIL_SHOW (line 205-206); summary printed at end (line 138). Session only, not persisted except via Log.
- Right-click on an inbox row = open that one (InboxFrame_OnClick hook, lines 492-500). COD mail never auto-opened.

### 1.4 Identifying AH mail
Two mechanisms, both string-based (NO GetInboxInvoiceInfo anywhere in the repo):
1. Sender name table for the inbox icon (TurtleMail.lua:12-20, 303-311):
```lua
local INBOX_AUCTIONHOUSES = {
  [ "Stormwind Auction House" ] = true, [ "Alliance Auction House" ] = true, [ "Darnassus Auction House" ] = true,
  [ "Undercity Auction House" ] = true, [ "Thunder Bluff  Auction House" ] = true,   -- note double space (probably a typo)
  [ "Horde Auction House" ] = true, [ "Blackwater Auction House" ] = true,           -- Blackwater = Turtle's neutral AH
}
```
   English-only; a `string.find(sender, "Auction House")` would be more robust.
2. Subject classification at log time using localized GlobalStrings (TurtleMail.lua:1449-1459):
```lua
if string.find( data.subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then      data[ "ah" ] = "Sold"
elseif string.find( data.subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then data[ "ah" ] = "Removed"
elseif string.find( data.subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then data[ "ah" ] = "Expired"
elseif string.find( data.subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then     data[ "ah" ] = "Won"
elseif string.find( data.subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then  data[ "ah" ] = "Outbid"
end
```
   Turtle GlobalStrings values (from SabineWren/wow-api-type-definitions `UI_Turtle/FrameXML/GlobalStrings.d.lua:83-99`):
   `AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"`, `AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"`, `AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"`, `AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"`, `AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"`; also `ERR_AUCTION_SOLD_S = "Your auction of %s sold."` (line 1538).
   Caveat: gsub without escaping leaves pattern magic chars (`:`) - harmless here, but `string.find(s, pat, 1, true)` (plain) is safer. Better for us: turn the format into a capture, e.g. `"^" .. gsub(AUCTION_SOLD_MAIL_SUBJECT, "%%s", "(.+)") .. "$"` to extract the item name.

GetInboxInvoiceInfo: not used, and the Turtle MailFrame type defs (`UI_Turtle/FrameXML/MailFrame.d.lua`) contain no OpenMailInvoice functions, consistent with invoices being a TBC (2.0) addition. Assume unavailable in 1.12; verify in-game with `/script DEFAULT_CHAT_FRAME:AddMessage(tostring(GetInboxInvoiceInfo))`.
Therefore, in 1.12 the sale amount must come from the mail header `money` field of the "Auction successful" mail (net proceeds after AH cut; deposit return handling should be verified in-game), plus `GetInboxText(i)` body if it carries details (verify). Quantity sold is not in the header; derive it by matching against our own record of what we posted (item, stack size, buyout, time) - see section 4.

### 1.5 Record of sales/mail kept
`log.add` (TurtleMail.lua:1426-1463) - only when logging enabled (`/tm log`, off by default):
```lua
local data = { timestamp = time(), icon = state.icon, item = state.item }
if state.cod and state.cod > 0 then data.cod = tonumber( state.cod ) end
-- Sent: participant=to, subject=sent_subject, money (BUG: checks state.send_money instead of sent_money, so sent money never logged)
-- Received: participant=from, subject, returned, gm, money, ah = Sold/Removed/Expired/Won/Outbid
table.insert( m.api.TurtleMail_Log[ log_type ], data )
```
Received entries are written from `inbox_open` (auto/right-click, lines 424-443) and from `OpenMailFrame_OnHide` for manually read text-only mail (lines 741-762). No item count, no per-item price, no aggregation. The log UI (tab 3 on MailFrame, filters by type/player/date range, lines 1197-1560) is the only consumer. Unbounded growth (elboaf fork had to add caching).

### 1.6 Bulk send
- UI: replaces the single 1.12 attachment slot with 21 virtual slots `MailAttachment1..21` (TurtleMail.xml:171-191; `ATTACHMENTS_MAX = 21`, line 8). Hides/disables the stock `SendMailPackageButton` (lines 189-195).
- Adding items: right-click bag item while MailFrame open (UseContainerItem hook, lines 689-707) or drag (PickupContainerItem/ClickSendMailItemButton hooks, 654-682). Right-click with TradeFrame open puts it into trade (lines 696-703) - handy for main<->alt in person.
- Mailability probe (TurtleMail.lua:989-998): put item in the real slot, check `GetSendMailItem()`, take it back:
```lua
m.api.ClearCursor(); m.orig.ClickSendMailItemButton(); m.api.ClearCursor()
m.orig.PickupContainerItem( unpack( item ) ); m.orig.ClickSendMailItemButton()
local mailable = m.api.GetSendMailItem() and true or false
m.orig.ClickSendMailItemButton()
```
- Send pipeline: Send button -> `send_mail_button_onclick` snapshots `{to, subject, body, money, cod, attachments, numMessages}` (lines 764-783), then `sendmail_send` (lines 1043-1098) for ONE attachment:
```lua
local item = table.remove( m.sendmail_state.attachments, 1 )
m.api.ClearCursor(); m.orig.ClickSendMailItemButton(); m.api.ClearCursor()
m.orig.PickupContainerItem( unpack( item ) ); m.orig.ClickSendMailItemButton()
... m.api.SetSendMailCOD( amount ) or m.api.SetSendMailMoney( amount )   -- money only on 1st mail unless "COD all"
subject = item_name .. " (" .. stack_count .. ")"  -- auto subject from GetSendMailItem() if blank; else "subject [n/N]"
m.api.SendMail( m.sendmail_state.to, subject, m.sendmail_state.body )
```
- Sequencing: `MAIL_SEND_SUCCESS` -> log + `sendmail_update = true` (lines 286-296) -> next OnUpdate calls `sendmail_send()` again (lines 123-130) until attachments empty. Errors that abort the chain: `ERR_MAIL_TO_SELF, ERR_PLAYER_WRONG_FACTION, ERR_MAIL_TARGET_NOT_FOUND, ERR_MAIL_REACHED_CAP` (lines 222-227). `BAG_UPDATE` only refreshes the send frame (171-175).
- Important evidence: only the first SendMail is triggered by a click; all following SendMail/PickupContainerItem/ClickSendMailItemButton/TakeInbox*/DeleteInboxItem calls come from OnUpdate, i.e. **mail APIs do NOT need a hardware event in 1.12** (mailbox must be open).
- Postage: `GetSendMailPrice() * max(1, numAttachments)` (line 558) - one mail (30c) per item in 1.12.
- No "send by type" rules (no auto-select of e.g. all cloth/leather). That would be our addition: iterate bags with GetContainerItemLink/GetContainerItemInfo, filter by itemID/class, push into the same queue.
- Recipient autocomplete: names learned from successful sends and from inbox senders with canReply (GetInboxHeaderInfo hook, lines 461-468); filtered by realm|faction key (line 1149).

### 1.7 UI integration into MailFrame
- Third tab "Log" (`PanelTemplates_SetNumTabs(MailFrame, 3)`, line 256; MailFrameTab_OnClick hook, 717-739 swaps textures and shows `TurtleMailLogFrame`).
- InboxFrame: "Open Mail" button (329-334), AH icon + returned arrow per row parented to `MailItem{i}ExpireTime` (xml:231-237), "Money received" text, page counter in title (InboxFrame_Update hook, 483-486), desaturated rows while opening (452-459).
- Movable MailFrame with saved point (lines 254-255, 405-409), `UIPanelWindows["MailFrame"].pushable = 1` (242-246).
- Hard-replaces `SendMailMailButton` with a no-op proxy table to stop Blizzard code (lines 819-830) - fragile; avoid.
- pfUI skin support (line 1569+).

---

## 2. Interact

### 2.1 What it is
`interact/README.md` (whole file): a client DLL loaded through VanillaFixes `dlls.txt`; adds keybindings `Interact` and `Interact (auto-loot)`. Not a pure Lua addon. Release notes (`gh api repos/lookino/Interact/releases`):
- v1.0.1: can interact with utility companions (Field Repair Bot, Mechanical Auctioneer).
- v1.0.2: never re-targets looted corpses; corpses with loot outrank skinnable corpses.
- v1.0.3: interacted candidates get lowered priority (so a corpse with a pending roll doesn't block others); skinnable corpses ignored if Skinning not learned; empty-loot candidates ignored.
- v1.0.4: crash fix for de-spawned game objects (nodes/chests).
Supported interactions: loot corpse, skin corpse, gather herb/mining nodes, open chests/game objects, talk to/interact with NPCs (any live unit within 5yd), companions. Pressing again with loot window open loots all (`interact-unitxp/README.md:20`).

### 2.2 How it works (source in interact-unitxp)
- Lua side is just a binding: `interact-unitxp/Bindings.xml:2-4`
```xml
<Binding name="Interact" header="INTERACT">
    UnitXP("interact", 1)
</Binding>
```
  `Interact.lua:1` only sets `BINDING_HEADER_INTERACT`. TOC Interface 11200.
- The DLL detours the client's native `UnitXP` Lua C function (1.12 API that normally returns player XP) at offset `FUN_UNITXP = 0x517350` using MinHook (`dllmain.cpp:112-124, 138`); if arg1 == "interact" it runs `InteractNearest()`, else falls through to the original. Same trick as allfoxwy's UnitXP_SP3 (credited in README:24).
- `InteractNearest()` (`dllmain.cpp:18-110`): walks the visible object manager list (`VISIBLE_OBJECTS = 0xB41414`), skips objects summoned by players, picks closest UNIT or GAMEOBJECT within 5.0 yd (3D distance); dead units only if lootable (dynamic flags & 1) or skinnable (unit flags 0x4000000) (`Game.cpp:48-59`). Then for units: `SetTarget(guid)` + call the client's internal right-click handler `FUN_RIGHT_CLICK_UNIT 0x60BEA0` with autoloot=1; for objects `FUN_RIGHT_CLICK_OBJECT 0x5F8660` (`dllmain.cpp:99-107`, offsets `Game.h:17-28`).
- No SuperWoW dependency in this source (SuperWoW not referenced); it needs VanillaFixes (or a launcher with DLL-mod support) to inject. Offsets are hard-coded for the 1.12.1 build; Turtle client updates could break it (v1.0.4 crash fix suggests fragility).

### 2.3 What the stock 1.12 Lua API can / cannot do (implications)
- Stock 1.12 has no Lua function to interact with / right-click a world object or corpse, no InteractUnit, no object enumeration. Targeting helpers exist (TargetNearestEnemy, TargetByName, TargetUnit), but looting/skinning/gathering requires a real click in the 3D world - hence the DLL. Our addon must not depend on Interact/UnitXP/SuperWoW; at most detect them (`if UnitXP then pcall(UnitXP, "interact", 1)` is unsafe since UnitXP exists natively - don't).
- Spell casting (e.g. Skinning/Tailoring crafts via CastSpellByName / DoTradeSkill) should be driven from a keybinding or button click to be safe; DoTradeSkill(index, count) can queue a batch from one click.
- Mail (SendMail, TakeInbox*, DeleteInboxItem, ClickSendMailItemButton, PickupContainerItem) works from OnUpdate without hardware events (proven by TurtleMail 1.3/1.6). Auction posting/bidding (StartAuction, PlaceAuctionBid) - verify separately; conventional wisdom is that 1.12 does not require hardware events for these either, but don't assume.
- Turtle WoW policy on client DLLs: verify; keep our addon pure Lua.

---

## 3. General patterns worth copying (and avoiding)
- Event sets flag -> OnUpdate does the work -> wait for confirming event (MAIL_SEND_SUCCESS / MAIL_INBOX_UPDATE) -> repeat. Abort on UI_ERROR_MESSAGE codes and on MAIL_CLOSED (TurtleMail.lua:209-213).
- Parent the OnUpdate frame to MailFrame (or AuctionFrame) so it only ticks while that window is open (TurtleMail.lua:35, 115).
- Frame-count timers (`m.timer = 200`) are frame-rate dependent; prefer `GetTime()` deltas or accumulating `arg1` (elapsed) in OnUpdate.
- Global-function replacement at PLAYER_LOGIN (TurtleMail.lua:266-269) is simple but conflicts with other addons; prefer wrapping only what we need, keep originals, and avoid hooking bag APIs.
- Use `time()` for stored timestamps; `GetTime()` is session-relative (TurtleMail bug at line 273, 324).
- Cap SavedVariables tables (elboaf fork's crash fix: max 200 names).
- Multi-character keying: `GetCVar("realmName").."|"..UnitFactionGroup("player")` (TurtleMail.lua:99); extend to `realm|faction|char` for per-character data in an account-wide SV.

---

## 4. Directly useful for our addon

### Detecting AH sales (what sold, for how much)
1. Real-time signal while online: CHAT_MSG_SYSTEM with `ERR_AUCTION_SOLD_S` ("Your auction of %s sold.") -> parse item name, timestamp. No price in it.
2. Authoritative price: when the mailbox is opened (on the alt), scan all headers with GetInboxHeaderInfo (no need to open): `sender` contains "Auction House" and subject matches `AUCTION_SOLD_MAIL_SUBJECT` -> item name captured from subject, `money` = payout. Also classify Expired/Cancelled (didn't sell -> negative signal for that price), Won/Outbid (our buys). Record BEFORE TakeInboxMoney/Delete, keyed so re-scans don't double-count (e.g. hash of sender+subject+money+daysLeft, or record at take-time like TurtleMail does).
3. Join with our own posting log (record on StartAuction: item, stack size, bid, buyout, duration, time()) to infer quantity/price per unit and time-to-sell; expired mail returns the item (hasItem; GetInboxItem gives name+count) so we know which posting failed.
4. Store account-wide so the main sees the bank alt's results: `DB.realms[realm].chars[char].sales[]`, `.expired[]`, with caps/rollups (per-item aggregates: sold count, expired count, median sold price).

### Moving goods between main and bank alt
- Reuse TurtleMail's send queue design: one item per mail, ClickSendMailItemButton/PickupContainerItem to attach, SendMail, wait MAIL_SEND_SUCCESS, next; auto subject "Item (count)"; abort on ERR_MAIL_* errors; postage 30c per mail.
- Add "send by rule" (TurtleMail lacks it): e.g. on main, one click sends all Tailoring outputs + leather/hides to the alt; on alt, send cloth/mats needed for queued crafts to the main. Recipient = configured alt name (validate same realm/faction; ERR_MAIL_TO_SELF guard).
- Bulk receive: TurtleMail's open-all loop (skip COD/GM, abort on ERR_INV_FULL, skip on ERR_ITEM_MAX_COUNT) + money tally.
- Mail delivery between own characters on the same account is instant in vanilla for items? (Item mail between different accounts has a 1-hour delay; same-account is reportedly instant - verify on Turtle.)
- Also track bag/bank contents per character (BAG_UPDATE, BANKFRAME_OPENED) in the account-wide SV so either character knows stock levels.
