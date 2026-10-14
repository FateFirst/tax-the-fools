# Tax The Fools — Phase 1 (Core and Scanning) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an installable WoW 1.12 addon that replaces the Blizzard auction window with a themed window. It runs full and watchlist scans that pace themselves and can be resumed, keeps an account-wide price history with a market value and a confidence rating, and shows prices in item tooltips.

**Architecture:** Plain Lua 5.0 modules sharing one global namespace, `TaxTheFools`, in the same layout as HealMyAss:
- The pure-logic modules (`util`, `stats`, `price`) make no game calls and are unit-tested directly.
- Game-facing modules (`db`, `items`, `scan`, `ahhook`, `tooltip`, UI) run against a fake client in `tests/wow_stub.lua`, which includes a scripted auction house.
- One event frame in `core.lua`, loaded last, drives everything.

**Tech Stack:** Lua 5.0.3 (built locally by the Makefile), WoW 1.12.1 API (Interface 11200), Python 3 standard library only (texture generation), POSIX sh, curl (fonts and Lua download).

**Spec:** `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md`. This plan covers spec §2 phase 1.

## Global Constraints

- Client: WoW 1.12.1 build 5875 (Turtle 1.18.1 / Ravencraft), `## Interface: 11200`, **Lua 5.0**.
- Banned constructs: `#`, `%`, `string.match`, `string.gmatch`, `select`, `hooksecurefunc`, `strsplit`, `math.huge`, `function(self, event`. Use `table.getn`, `math.mod`, `string.find` captures and `string.gfind` instead. Event and script handlers read the globals `this`, `event`, `arg1`..`arg9`.
- A function may reference at most 32 upvalues. `luac -p` from Lua 5.0 rejects more, and so does the client, which then refuses to load the whole file.
- **Never capture a `for` loop variable in a closure.** In Lua 5.0 every iteration shares the same variable. Pass the value through a function parameter, or store it on the frame and read it back via `this`.
- **Never pass a multi-return call straight into `ipairs(...)`.** Assign the result to a local first.
- SavedVariables:
  - `TaxTheFoolsDB` and `TaxTheFoolsDB_broken` are account-wide.
  - `TaxTheFoolsCharDB` is per character and holds window state only.
  - Prices are keyed by realm name.
- Item key is `itemId:suffixId` (strings such as `"14047:0"`).
- Day number is `math.floor(time() / 86400)`, a UTC day. Every timestamp that gets saved uses `time()`, never `GetTime()`. `GetTime()` is only used for pacing within a session.
- **Automation rule:** phase 1 never calls `PlaceAuctionBid`, `StartAuction` or `CancelAuction`. The scan is the only thing that sends queries without a click.
- Scan pacing:
  - wait for `CanSendAuctionQuery()`, plus a minimum delay of `scanDelay` (default 0.3 s), or 4 s in safe mode
  - 15 s query timeout, at most 3 resends, then stall
  - duplicate-page guard: re-ask after 4 s; after 2 duplicates, switch to safe pace
  - name and level arguments to `QueryAuctionItems` are always strings, never nil.
- Market value:
  - weighted median of daily `p25` over the last 30 days, with weight `0.9^ageDays`
  - confidence = `min(1, daysSeen/5) × (1 − clamp(cv,0,0.6)/0.6 × 0.5)`
  - labels: high ≥ 0.7, medium ≥ 0.4, otherwise low.
- Retention: daily rows for 60 days, then folded into monthly rows kept for about 12 months.
- Visual:
  - colour tokens `bg #202020`, `header #111111`, `strip #3b3b3b`, `border #050505`, `accent #52c722`, `gold #ffed71`, `text #e6e6e6`, `dim #c7c7bd`, `bad #d9534f`, `good #52c722`, `warn #e0a030`
  - Rajdhani (headings) and Inter (body), both OFL and bundled
  - textures are 32-bit uncompressed power-of-two TGA white masks, tinted with `SetVertexColor`
  - no Blizzard frame art in our own windows
  - **no code copied from Aegis Pathfinder (GPLv3).**
- Chat prefix `TTF:`; slash commands `/ttf` and `/taxthefools`.
- Fake-client rule: unknown widget methods are no-ops, and an unset field on a frame reads back as a function, not nil. Initialise every frame field the code later tests for truth to `false`.

## Review Focus

1. **AH closed while a page request is outstanding:** the resume point must be that unaccepted page, so the page is asked for again and not skipped. Test in Task 6.
2. **A watched item whose name the client doesn't know yet:** it must be left out of the watchlist scan, never sent as an empty-name query, which would silently become a full scan. Test in Task 6.
3. **Searching in Browse while a full scan is running:** refused with a chat message, and the scan's job and data are left untouched. Test in Task 6.
4. **Listings with no buyout (bid-only), and items whose only rows lack prices:** counted in `n`/`qty`, no price fields, and the tooltip says "no data" instead of crashing. Tests in Task 3 and Task 10.
5. **Saved data in an older or damaged shape** (a history entry with no `days` table, a settings value of the wrong type): market and prune must not throw, and a damaged top-level table is set aside, not merged into. Tests in Task 3 and Task 4.

## Deviations from the spec, decided while planning

- A broken saved table is set aside into a second SavedVariable, `TaxTheFoolsDB_broken[time()]`. A renamed global would never be written to disk.
- **The built-in vendor-price table moves to phase 3,** where the deals that need it are built. Phase 1 learns vendor prices at merchants, and from ClassicAPI when it is present.
- Control tooltips use `GameTooltip` rather than a custom tooltip frame.
- Phase 1 Browse is read-only: search, paging, market % and watch. Buying arrives in phase 3; until then the header's "Blizzard UI" button switches to the stock window.
- Left-click on the minimap button opens Options until phase 2 gives it the Crafting window.
- Option pages don't scroll yet; each category fits on one screen.
- The status strip shows the average seconds per page and an estimate of time left, but does not yet split each page's time into client wait, server reply and our delay. The probe reports the average.
- The 32-upvalue limit is enforced by `luac -p` itself, which errors with "too many upvalues"; no separate `luac -l` pass is needed.

---

## File Structure

```
Makefile                       lua / lint / test / media / fonts / install / clean
.gitignore                     tools/lua-5.0.3/
tools/lint.sh                  5.1-only grep + luac -p
tools/make-media.py            writes TaxTheFools/media/*.tga (white masks)
tools/fetch-fonts.sh           downloads Rajdhani + Inter TTFs and their OFL licences
tests/wow_stub.lua             fake 1.12 client incl. scripted auction house, T framework
tests/run.lua                  loads stub, addon files in .toc order, runs test files
tests/test_*.lua               one file per module
TaxTheFools/TaxTheFools.toc
TaxTheFools/data.lua           constants + defaults
TaxTheFools/util.lua           chat, strings, money, links, days, scan tooltip
TaxTheFools/stats.lua          weighted percentile, median, coefficient of variation
TaxTheFools/price.lua          day summary, record rules, market value, compaction
TaxTheFools/db.lua             SavedVariables init/validation/migration, realm/char, prune
TaxTheFools/items.lua          item cache, uncached lookups, vendor prices
TaxTheFools/scan.lua           scan state machine (full / watch / browse), resume
TaxTheFools/ahhook.lua         replace Blizzard AuctionFrame without killing the session
TaxTheFools/theme.lua          colour tokens, live re-theme, fonts, nine-slice textures
TaxTheFools/widgets.lua        button, icon button, switch, slider, dropdown, edit box, progress, tabs, window
TaxTheFools/list.lua           virtual sortable list with pooled rows
TaxTheFools/tooltip.lua        price lines on GameTooltip
TaxTheFools/ui_window.lua      AH window shell, status strip, page registry
TaxTheFools/ui_browse.lua      Browse page
TaxTheFools/options.lua        options window
TaxTheFools/minimap.lua        minimap button
TaxTheFools/probe.lua          /ttf probe API dump
TaxTheFools/core.lua           event frame, init, OnUpdate, slash commands
TaxTheFools/media/             generated textures + fonts/
docs/testing-checklist.md      in-game checks after install
README.md                      install, use, commands
```

---

### Task 1: Harness, lint and addon skeleton

**Files:**
- Create: `Makefile`, `.gitignore`, `tools/lint.sh`, `tests/wow_stub.lua`, `tests/run.lua`, `tests/test_core.lua`
- Create: `TaxTheFools/TaxTheFools.toc`, `TaxTheFools/data.lua`, `TaxTheFools/util.lua`, `TaxTheFools/core.lua`

**Interfaces:**
- Produces:
  - `TaxTheFools` (global table).
  - `TaxTheFools.Data` (`D.VERSION`, `D.DATA_VERSION`, constants, `D.DEFAULTS`, `D.CHAR_DEFAULTS`, `D.REALM_DEFAULTS`).
  - `TaxTheFools.Util`: `U.msg(text)`, `U.debug(text)`, `U.trim(s)`, `U.words(s)`, `U.count(t)`.
  - `TaxTheFools.Core`: `Core.ready`, `Core.Safe(name, fn, a1, a2, a3)`, `Core.Command(msg)`.
  - Test harness globals:
    - `WoW.reset()`, `WoW.fire(event, a1..a5)`, `WoW.runScript(frame, script, a1)`, `WoW.log(...)`
    - `WoW.ahRespond()`, `WoW.link(id, name, suffix)`, `WoW.classicAPI(on)`, `WoW.newFontString()`
    - `T.test`, `T.eq`, `T.near`, `T.ok`, `T.calledWith`, `T.count`.
  - Convention: any module table may define `ResetState()`, which `WoW.reset()` calls before every test.

- [ ] **Step 1: Makefile, .gitignore and lint script**

`Makefile`:
```make
LUA_DIR := tools/lua-5.0.3
LUA := $(LUA_DIR)/bin/lua
LUAC := $(LUA_DIR)/bin/luac
ADDON := TaxTheFools

.PHONY: test lint lua clean install media fonts

lua: $(LUA)

$(LUA):
	mkdir -p tools
	curl -sSL https://www.lua.org/ftp/lua-5.0.3.tar.gz | tar xz -C tools
	$(MAKE) -C $(LUA_DIR)

lint: $(LUA)
	LUAC=$(LUAC) sh tools/lint.sh

test: lint
	$(LUA) tests/run.lua $(wildcard tests/test_*.lua)

# Regenerate the white-mask textures the theme tints at run time.
media:
	python3 tools/make-media.py

# Download the bundled fonts (OFL) and their licences.
fonts:
	sh tools/fetch-fonts.sh

clean:
	rm -rf $(LUA_DIR)

# Copy the addon into a WoW AddOns folder: make install ADDONS=/path/to/Interface/AddOns
install:
	@test -n "$(ADDONS)" || (echo "usage: make install ADDONS=/path/to/Interface/AddOns" && exit 1)
	rm -rf "$(ADDONS)/$(ADDON)"
	cp -R $(ADDON) "$(ADDONS)/$(ADDON)"
	@echo "installed to $(ADDONS)/$(ADDON)"
```

`.gitignore`:
```
tools/lua-5.0.3/
```

`tools/lint.sh`:
```sh
#!/bin/sh
# Reject Lua 5.1-only constructs and syntax-check every file with Lua 5.0's own
# compiler. luac -p also enforces the 5.0 limits later tools miss: no `#` or `%`
# operators, and at most 32 upvalues per function -- more and the client refuses
# to load the whole file.
set -e
status=0
for f in TaxTheFools/*.lua tests/*.lua; do
  if grep -nE 'string\.match|string\.gmatch|[^a-zA-Z_.]select\(|hooksecurefunc|strsplit|math\.huge|function *\( *self *, *event' "$f"; then
    echo "lint: 5.1-only construct in $f"
    status=1
  fi
  if ! "$LUAC" -p "$f"; then
    echo "lint: luac failed on $f"
    status=1
  fi
done
exit $status
```

- [ ] **Step 2: The fake client**

`tests/wow_stub.lua`:
```lua
-- Fake WoW 1.12 client for Tax the Fools. Tests change WoW.* and fire events;
-- API calls the addon makes are logged to WoW.calls.
--
-- Two habits carried over from HealMyAss's stub:
--   * Unknown widget methods are no-ops, so a test never dies on a cosmetic
--     call. The price: an unset field on a frame reads back as a function, not
--     nil. Addon code initialises every frame field it later tests for truth.
--   * Show/Hide fire OnShow/OnHide only when visibility actually changes, as
--     the real client does. The auction window swap depends on exactly that.
WoW = { frames = {}, allFrames = {} }
_G = getfenv(0)

local function noop() end
local meta = { __index = function(t, k) return noop end }

local function runScript(frame, name, a1)
  local fn = frame.scripts and frame.scripts[name]
  if not fn then return end
  local oldThis, oldArg = this, arg1
  this, arg1 = frame, a1
  fn()
  this, arg1 = oldThis, oldArg
end
WoW.runScript = runScript

local function region(kind)
  local r = { kind = kind, shown = true, points = {} }
  r.Show = function(self) self.shown = true end
  r.Hide = function(self) self.shown = false end
  r.IsShown = function(self) return self.shown end
  r.SetPoint = function(self, p, rel, rp, x, y) table.insert(self.points, { p, rel, rp, x, y }) end
  r.ClearAllPoints = function(self) self.points = {} end
  r.SetWidth = function(self, w) self.width = w end
  r.SetHeight = function(self, h) self.height = h end
  r.GetWidth = function(self) return self.width or 0 end
  r.GetHeight = function(self) return self.height or 0 end
  return setmetatable(r, meta)
end

local function newTexture()
  local t = region("Texture")
  t.SetTexture = function(self, v) self.texture = v end
  t.GetTexture = function(self) return self.texture end
  t.SetTexCoord = function(self, a, b, c, d) self.coords = { a, b, c, d } end
  t.SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
  return t
end

local function setFont(self, path, size, flags)
  -- SetFont returns nil when the client refuses the file: the only way 1.12
  -- tells you a bundled font failed to load.
  if WoW.rejectFonts and path ~= STANDARD_TEXT_FONT then return nil end
  self.font, self.fontSize = path, size
  return 1
end

local function newFontString()
  local fs = region("FontString")
  fs.text = ""
  fs.SetText = function(self, t) self.text = t or "" end
  fs.GetText = function(self) return self.text end
  fs.SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
  -- The real client measures rendered text. Six pixels a character keeps the
  -- one property layout relies on: width grows with length.
  fs.GetStringWidth = function(self) return string.len(self.text or "") * 6 end
  fs.SetFont = setFont
  return fs
end
WoW.newFontString = newFontString

local function newFrame(kind, name, parent)
  local f = region(kind)
  f.name, f.parent, f.events, f.scripts, f.text = name, parent or false, {}, {}, ""
  f.Show = function(self) if not self.shown then self.shown = true runScript(self, "OnShow") end end
  f.Hide = function(self) if self.shown then self.shown = false runScript(self, "OnHide") end end
  f.IsVisible = function(self)
    if not self.shown then return nil end
    local up = self.parent
    while type(up) == "table" do
      if up.shown == false then return nil end
      up = up.parent
    end
    return 1
  end
  f.GetName = function(self) return self.name end
  f.GetParent = function(self) return self.parent or nil end
  f.RegisterEvent = function(self, e) self.events[e] = true end
  f.UnregisterEvent = function(self, e) self.events[e] = nil end
  f.SetScript = function(self, s, fn) self.scripts[s] = fn end
  f.GetScript = function(self, s) return self.scripts[s] end
  f.SetText = function(self, t) self.text = t or "" end
  f.GetText = function(self) return self.text end
  f.CreateTexture = function(self) return newTexture() end
  f.CreateFontString = function(self) return newFontString() end
  f.SetScale = function(self, s) self.scale = s end
  f.GetScale = function(self) return self.scale or 1 end
  f.GetEffectiveScale = function(self) return self.scale or 1 end
  f.SetAlpha = function(self, a) self.alpha = a end
  f.GetAlpha = function(self) return self.alpha or 1 end
  f.GetLeft = function(self) return self.left or 100 end
  f.GetTop = function(self) return self.top or 500 end
  f.GetCenter = function(self) return 100, 100 end
  f.SetFont = setFont
  f.SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
  f.StartSizing = function(self, p) WoW.log("StartSizing", p) end
  f.StartMoving = function(self) WoW.log("StartMoving") end
  f.StopMovingOrSizing = function(self) WoW.log("StopMovingOrSizing") end
  f.SetMinResize = function(self, w, h) self.minResize = { w, h } end
  f.SetResizable = function(self, v) self.resizable = v end
  -- Sliders
  f.value, f.min, f.max = 0, 0, 0
  f.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
  f.GetMinMaxValues = function(self) return self.min, self.max end
  f.SetValue = function(self, v)
    if v < self.min then v = self.min end
    if v > self.max then v = self.max end
    self.value = v
    runScript(self, "OnValueChanged")
  end
  f.GetValue = function(self) return self.value end
  f.SetThumbTexture = function(self, path) self.thumb = newTexture() self.thumb:SetTexture(path) end
  f.GetThumbTexture = function(self) return self.thumb end
  -- Tooltips
  f.lines = {}
  f.AddLine = function(self, l) table.insert(self.lines, { l }) end
  f.AddDoubleLine = function(self, l, r) table.insert(self.lines, { l, r }) end
  f.NumLines = function(self) return table.getn(self.lines) end
  if kind == "GameTooltip" then
    f.SetText = function(self, t) self.lines = { { t } } end
    f.ClearLines = function(self) self.lines = {} end
    -- With a merchant open the client prices bag items through this script,
    -- passing the whole stack's sell price in arg1.
    f.SetBagItem = function(self, bag, slot)
      self.lines = {}
      local it = WoW.bags[bag] and WoW.bags[bag][slot]
      if it and WoW.merchantOpen and it.vendor then runScript(self, "OnTooltipAddMoney", it.vendor * (it.count or 1)) end
      return "orig-bag"
    end
    f.SetHyperlink = function(self, link) self.lines = {} WoW.log("SetHyperlink", self.name, link) end
  end
  table.insert(WoW.allFrames, f)
  if name then
    WoW.frames[name] = f
    _G[name] = f
  end
  return f
end

local function newEditBox(name, parent)
  local e = newFrame("EditBox", name, parent)
  e.value, e.focused = "", false
  e.SetText = function(self, t) self.value = t or "" end
  e.GetText = function(self) return self.value end
  e.SetFocus = function(self) self.focused = true end
  e.ClearFocus = function(self) self.focused = false end
  e.HasFocus = function(self) if self.focused then return 1 end return nil end
  e.HighlightText = function(self) self.highlighted = true end
  return e
end

function CreateFrame(kind, name, parent, template)
  if kind == "EditBox" then return newEditBox(name, parent) end
  return newFrame(kind, name, parent)
end

function WoW.log(...)
  local parts = {}
  for i = 1, arg.n do table.insert(parts, tostring(arg[i])) end
  table.insert(WoW.calls, table.concat(parts, " "))
end

function WoW.fire(eventName, a1, a2, a3, a4, a5)
  event = eventName
  arg1, arg2, arg3, arg4, arg5 = a1, a2, a3, a4, a5
  for _, f in ipairs(WoW.allFrames) do
    if f.events[eventName] and f.scripts.OnEvent then
      this = f
      f.scripts.OnEvent()
    end
  end
end

function WoW.link(id, name, suffix)
  return "|cffffffff|Hitem:" .. id .. ":0:" .. (suffix or 0) .. ":0|h[" .. name .. "]|h|r"
end

-- ClassicAPI on or off, so both paths are tested: the addon must work without the DLL.
function WoW.classicAPI(on)
  if not on then C_Item = nil return end
  C_Item = {
    RequestLoadItemDataByID = function(id) WoW.log("RequestLoadItemDataByID", id) end,
    GetItemSellPrice = function(id) local it = WoW.items[id] return it and it.vendor end,
  }
end

function WoW.reset()
  WoW.calls = {}
  WoW.clock = 1000                      -- GetTime(): seconds since the client started
  WoW.now = 20375 * 86400 + 43200       -- time(): midday UTC on day 20375 (2025-10-14)
  WoW.realm, WoW.player, WoW.faction, WoW.class = "Medivh", "Bankalt", "Horde", "WARRIOR"
  WoW.money = 0
  WoW.shift = false
  WoW.cursorX, WoW.cursorY = 0, 0
  WoW.items = {}
  WoW.bags = {}
  WoW.merchantOpen = false
  WoW.rejectFonts = false
  WoW.ah = { listings = {}, canQuery = true, pending = false, current = {}, total = 0, lastPage = false, duplicateNext = 0 }
  WoW.classicAPI(false)
  if AuctionFrame then AuctionFrame.shown = false end
  TaxTheFoolsDB, TaxTheFoolsCharDB, TaxTheFoolsDB_broken = nil, nil, nil
  if TaxTheFools then
    for _, m in pairs(TaxTheFools) do
      if type(m) == "table" and type(m.ResetState) == "function" then m.ResetState() end
    end
    if TaxTheFools.DB then TaxTheFools.DB.Init() end
  end
end

-- ---------- scripted auction house ----------
-- Tests put rows in WoW.ah.listings: { id=, name=, count=, buyout=, minBid=, bid=, owner=, noName= }.
-- QueryAuctionItems records the request; WoW.ahRespond() answers it as the server would.
function CanSendAuctionQuery() if WoW.ah.canQuery then return 1 end return nil end
function QueryAuctionItems(name, minLevel, maxLevel, invType, class, subclass, page, usable, quality)
  WoW.log("QueryAuctionItems", "[" .. tostring(name) .. "]", "[" .. tostring(minLevel) .. "]", "[" .. tostring(maxLevel) .. "]", page)
  WoW.ah.pending = { name = name or "", page = page or 0 }
end
function WoW.ahRespond()
  local q = WoW.ah.pending
  if not q then error("no outstanding auction query") end
  WoW.ah.pending = false
  local matches = {}
  for _, l in ipairs(WoW.ah.listings) do
    if q.name == "" or string.find(string.lower(l.name), string.lower(q.name), 1, true) then
      table.insert(matches, l)
    end
  end
  local page = {}
  if WoW.ah.duplicateNext > 0 and WoW.ah.lastPage then
    -- The reply some servers send under load: the previous page again.
    WoW.ah.duplicateNext = WoW.ah.duplicateNext - 1
    page = WoW.ah.lastPage
  else
    for i = q.page * 50 + 1, math.min(table.getn(matches), q.page * 50 + 50) do table.insert(page, matches[i]) end
  end
  WoW.ah.current, WoW.ah.total, WoW.ah.lastPage = page, table.getn(matches), page
  WoW.fire("AUCTION_ITEM_LIST_UPDATE")
end
function GetNumAuctionItems(kind)
  if kind ~= "list" then return 0, 0 end
  return table.getn(WoW.ah.current), WoW.ah.total
end
function GetAuctionItemInfo(kind, i)
  local l = WoW.ah.current[i]
  if not l then return nil end
  -- An item the client has not cached yet comes back without a name at first.
  local name = l.name
  if l.noName then name = nil end
  return name, l.tex or "Interface\\Icons\\INV_Fabric_Linen_01", l.count or 1, l.quality or 1, 1, l.level or 1,
    l.minBid or 1, l.minInc or 0, l.buyout or 0, l.bid or 0, nil, l.owner
end
function GetAuctionItemLink(kind, i)
  local l = WoW.ah.current[i]
  if not l then return nil end
  return WoW.link(l.id, l.name, l.suffix)
end
function GetAuctionItemTimeLeft(kind, i) if WoW.ah.current[i] then return 3 end return nil end
function CloseAuctionHouse() WoW.log("CloseAuctionHouse") end
-- The calls that spend or list gold. Logged so a test can prove nothing ever
-- makes them without a click.
function PlaceAuctionBid(kind, i, amount) WoW.log("PlaceAuctionBid", kind, i, amount) end
function StartAuction(bid, buyout, minutes) WoW.log("StartAuction", bid, buyout, minutes) end
function CancelAuction(i) WoW.log("CancelAuction", i) end
function ShowUIPanel(f) WoW.log("ShowUIPanel", f:GetName()) f:Show() end
function HideUIPanel(f) WoW.log("HideUIPanel", f:GetName()) f:Hide() end

-- ---------- general API ----------
function GetTime() return WoW.clock end
function time() return WoW.now end
date = os.date
function GetRealmName() return WoW.realm end
function UnitName(u) if u == "player" then return WoW.player end return nil end
function UnitClass(u) return WoW.class, WoW.class end
function UnitFactionGroup(u) return WoW.faction, WoW.faction end
function GetMoney() return WoW.money end
function IsShiftKeyDown() if WoW.shift then return 1 end return nil end
function GetCursorPosition() return WoW.cursorX, WoW.cursorY end
function GetBuildInfo() return "1.12.1", "5875", "Sep 19 2006", 11200 end
function ReloadUI() WoW.log("ReloadUI") end
function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end
function PlaySound() end
function GetItemInfo(id)
  if type(id) == "string" then
    local _, _, n = string.find(id, "item:(%d+)")
    id = tonumber(n)
  end
  local it = WoW.items[id]
  if not it then return nil end
  return it.name, "item:" .. id .. ":0:0:0", it.quality or 1, it.level or 1, it.type or "Trade Goods",
    it.subtype or "", it.stack or 20, "", it.tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- Bags: WoW.bags[bag][slot] = { id=, name=, count=, vendor= } or {} for an empty slot.
function GetContainerNumSlots(bag) return WoW.bags[bag] and table.getn(WoW.bags[bag]) or 0 end
function GetContainerItemLink(bag, slot)
  local it = WoW.bags[bag] and WoW.bags[bag][slot]
  if it and it.id then return WoW.link(it.id, it.name) end
  return nil
end
function GetContainerItemInfo(bag, slot)
  local it = WoW.bags[bag] and WoW.bags[bag][slot]
  if not it or not it.id then return nil end
  return it.tex or "tex", it.count or 1
end
function GetInventoryItemLink() return nil end
function GetInventoryItemCount() return 0 end

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
YES, NO = "Yes", "No"
UIParent = newFrame("Frame", "UIParent")
Minimap = newFrame("Frame", "Minimap")
WorldFrame = newFrame("Frame", "WorldFrame")
GameTooltip = newFrame("GameTooltip", "GameTooltip")
GameTooltip.SetOwner = function(self, owner, anchor) self.owner = owner end
AuctionFrame = newFrame("Frame", "AuctionFrame")
AuctionFrame.shown = false
-- Blizzard's own OnHide ends the auction session; this is what the swap must dodge.
AuctionFrame:SetScript("OnHide", function() CloseAuctionHouse() end)
AuctionFrameAuctions = newFrame("Frame", "AuctionFrameAuctions")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) WoW.log("CHAT", msg) end }
SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which) WoW.log("StaticPopup_Show", which) end

-- ---------- tiny test framework ----------
T = { passed = 0, failed = 0, failures = {} }
function T.test(name, fn)
  WoW.reset()
  local ok, err = pcall(fn)
  if ok then T.passed = T.passed + 1
  else T.failed = T.failed + 1 table.insert(T.failures, name .. ": " .. tostring(err)) end
end
function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "eq") .. ": expected " .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end
function T.near(actual, expected, tol, msg)
  if math.abs(actual - expected) > (tol or 0.5) then
    error((msg or "near") .. ": expected ~" .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end
function T.ok(cond, msg) if not cond then error(msg or "assertion failed", 2) end end
function T.calledWith(fragment)
  for _, c in ipairs(WoW.calls) do if string.find(c, fragment, 1, true) then return true end end
  return false
end
function T.count(fragment)
  local n = 0
  for _, c in ipairs(WoW.calls) do if string.find(c, fragment, 1, true) then n = n + 1 end end
  return n
end
```

`tests/run.lua`:
```lua
dofile("tests/wow_stub.lua")
WoW.reset()

-- Load addon files in TOC order, exactly as the client does.
local toc = io.open("TaxTheFools/TaxTheFools.toc")
local files = {}
for line in toc:lines() do
  local _, _, f = string.find(line, "^([%w_]+%.lua)%s*$")
  if f then table.insert(files, f) end
end
toc:close()
for _, f in ipairs(files) do dofile("TaxTheFools/" .. f) end
WoW.fire("VARIABLES_LOADED")

-- Lua 5.0 has no io.popen by default: the Makefile passes the test files as arguments.
for i = 1, table.getn(arg) do dofile(arg[i]) end

print(string.format("%d passed, %d failed", T.passed, T.failed))
for _, f in ipairs(T.failures) do print("FAIL " .. f) end
if T.failed > 0 then os.exit(1) end
```

- [ ] **Step 3: Write the failing test**

`tests/test_core.lua`:
```lua
T.test("core is ready once saved variables load", function()
  T.ok(TaxTheFools.Core.ready, "VARIABLES_LOADED initialises the core")
end)

T.test("/ttf with no arguments prints help", function()
  SlashCmdList["TAXTHEFOOLS"]("")
  T.ok(T.calledWith("/ttf help"), "help lists itself")
end)

T.test("chat messages carry the TTF prefix", function()
  TaxTheFools.Util.msg("hello")
  T.ok(T.calledWith("TTF:|r hello"), "prefixed")
end)

T.test("Safe switches a part off after an error instead of erroring every frame", function()
  local Core = TaxTheFools.Core
  local calls = 0
  local boom = function() calls = calls + 1 error("bad") end
  Core.Safe("thing", boom)
  Core.Safe("thing", boom)
  T.eq(calls, 1, "second call skipped")
  T.ok(T.calledWith("thing stopped after an error"), "player told once")
end)
```

- [ ] **Step 4: Run it to make sure it fails**

Run: `make test`
Expected: the Lua build runs once, then `run.lua` fails opening `TaxTheFools/TaxTheFools.toc`, with an error such as `attempt to index a nil value`.

- [ ] **Step 5: Write the skeleton**

`TaxTheFools/TaxTheFools.toc`:
```
## Interface: 11200
## Title: Tax the Fools
## Notes: Auction house price history, deals and crafting profit for Ravencraft.
## Author: Liam North
## Version: 0.1.0
## SavedVariables: TaxTheFoolsDB, TaxTheFoolsDB_broken
## SavedVariablesPerCharacter: TaxTheFoolsCharDB

data.lua
util.lua
core.lua
```

`TaxTheFools/data.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local D = {}
TaxTheFools.Data = D

D.VERSION = "0.1.0"
-- Bump when saved data needs a one-time migration (see db.lua MIGRATIONS).
D.DATA_VERSION = 1

D.PAGE_SIZE = 50
D.QUERY_TIMEOUT = 15     -- seconds without a reply before a page is asked for again
D.MAX_RETRIES = 3        -- resends before the scan stalls and asks the player
D.SAFE_DELAY = 4         -- seconds between pages in safe pace
D.NAME_WAIT = 1          -- seconds to wait for uncached item names on a page
D.MARKET_DAYS = 30
D.DECAY = 0.9
D.KEEP_DAYS = 60
D.KEEP_MONTHS = 12
D.MARKET_PER_FRAME = 300
D.PRUNE_PER_FRAME = 50

D.DEFAULTS = {
  settings = {
    debug = false,
    replaceBlizzardAH = true,
    minimap = true,
    minimapAngle = 200,
    scale = 1,
    theme = "Pathfinder",
    fonts = true,
    scanDelay = 0.3,
    safeMode = false,
    browseFeedsHistory = true,
    tooltip = { market = true, low = true, vendor = true },
  },
  items = {},
  realms = {},
}

D.CHAR_DEFAULTS = { windows = {} }

D.REALM_DEFAULTS = { history = {}, market = {}, scan = {}, chars = {}, watch = {} }
```

`TaxTheFools/util.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U = {}
TaxTheFools.Util = U

U.PREFIX = "|cff52c722TTF:|r "

function U.msg(text)
  DEFAULT_CHAT_FRAME:AddMessage(U.PREFIX .. tostring(text))
end

function U.debug(text)
  if TaxTheFoolsDB and TaxTheFoolsDB.settings and TaxTheFoolsDB.settings.debug then
    U.msg("|cff888888" .. tostring(text) .. "|r")
  end
end

function U.trim(s)
  local _, _, r = string.find(s or "", "^%s*(.-)%s*$")
  return r or ""
end

function U.words(s)
  local t = {}
  for w in string.gfind(s or "", "%S+") do table.insert(t, w) end
  return t
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end
```

`TaxTheFools/core.lua` (Task 13 replaces this file in full):
```lua
local A = TaxTheFools
local U, D = A.Util, A.Data
local Core = { ready = false, disabled = {} }
A.Core = Core

function Core.ResetState() Core.disabled = {} end

-- Runs fn. With debug off, an error switches that part off for the session
-- instead of throwing every frame; with debug on it throws, for a stack trace.
function Core.Safe(name, fn, a1, a2, a3)
  if Core.disabled[name] then return end
  local s = TaxTheFoolsDB and TaxTheFoolsDB.settings
  if s and s.debug then return fn(a1, a2, a3) end
  local ok, err = pcall(fn, a1, a2, a3)
  if not ok then
    Core.disabled[name] = true
    U.msg(name .. " stopped after an error: " .. tostring(err) .. " (/reload to retry)")
  end
end

function Core.Init()
  Core.ready = true
  U.msg("v" .. D.VERSION .. " loaded. /ttf for commands.")
end

function Core.Command(msg)
  U.msg("commands:")
  U.msg("  /ttf help - this list")
end

SLASH_TAXTHEFOOLS1 = "/ttf"
SLASH_TAXTHEFOOLS2 = "/taxthefools"
SlashCmdList["TAXTHEFOOLS"] = function(msg) Core.Safe("command", Core.Command, msg) end

local frame = CreateFrame("Frame", "TaxTheFoolsCore")
frame:RegisterEvent("VARIABLES_LOADED")
frame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then Core.Init() end
end)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test`
Expected: `4 passed, 0 failed`

- [ ] **Step 7: Commit**

```bash
git add Makefile .gitignore tools/lint.sh tests TaxTheFools
git commit -m "feat: addon skeleton, Lua 5.0 harness and fake client"
```

---

### Task 2: Money, item links, days, and statistics

**Files:**
- Modify: `TaxTheFools/util.lua` (append)
- Create: `TaxTheFools/stats.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `stats.lua` after `util.lua`)
- Test: `tests/test_util.lua`, `tests/test_stats.lua`

**Interfaces:**
- Consumes: `TaxTheFools.Util` (Task 1).
- Produces:
  - `U.money(copper, plain) -> string`: `"12g 34s 56c"`, coloured unless `plain`, negative values prefixed `-`, zero shown as `"0c"`.
  - `U.parseLink(link) -> id, suffix, enchant` (numbers) or nil.
  - `U.keyFromLink(link) -> key, id`.
  - `U.key(id, suffix) -> "id:suffix"`.
  - `U.keyId(key) -> number`.
  - `U.linkString(link) -> "item:..."` or nil.
  - `U.day(t) -> integer`.
  - `U.daysAgo(n) -> "today" | "1d ago" | "Nd ago"`.
  - `U.quality(q) -> "|cffrrggbb"`.
  - `U.scanTip() -> GameTooltip` named `TaxTheFoolsScanTip`.
  - `TaxTheFools.Stats`:
    - `S.weightedPercentile(values, weights, p) -> value|nil`, where p is 0..1 and the walk starts at the cheapest; `weights` may be nil.
    - `S.median(values)`
    - `S.cv(values) -> number`, which is 0 for fewer than 2 values or a zero mean.

- [ ] **Step 1: Write the failing tests**

`tests/test_util.lua`:
```lua
local U = TaxTheFools.Util

T.test("money formats gold, silver and copper", function()
  T.eq(U.money(123456, true), "12g 34s 56c")
  T.eq(U.money(100, true), "1s")
  T.eq(U.money(10050, true), "1g 50c")
  T.eq(U.money(0, true), "0c")
  T.eq(U.money(-250, true), "-2s 50c")
  T.eq(U.money(99.6, true), "1s", "rounds to whole copper")
end)

T.test("coloured money keeps the numbers readable", function()
  local s = U.money(10203)
  T.ok(string.find(s, "1g", 1, true) and string.find(s, "2s", 1, true) and string.find(s, "3c", 1, true), s)
  T.ok(string.find(s, "|cff", 1, true), "coloured")
end)

T.test("item links parse to id, suffix and enchant", function()
  local id, suffix, enchant = U.parseLink("|cff1eff00|Hitem:10245:12:1179:0|h[Charger's Belt of the Monkey]|h|r")
  T.eq(id, 10245) T.eq(suffix, 1179) T.eq(enchant, 12)
  T.eq(U.parseLink(nil), nil)
  T.eq(U.parseLink("not a link"), nil)
end)

T.test("item keys ignore enchants but keep random suffixes", function()
  T.eq(U.keyFromLink(WoW.link(14047, "Runecloth")), "14047:0")
  local key, id = U.keyFromLink("|Hitem:10245:12:1179:0|h[x]|h")
  T.eq(key, "10245:1179") T.eq(id, 10245)
  T.eq(U.key(4306), "4306:0")
  T.eq(U.keyId("10245:1179"), 10245)
end)

T.test("link string is what SetHyperlink takes", function()
  T.eq(U.linkString(WoW.link(14047, "Runecloth")), "item:14047:0:0:0")
end)

T.test("days are UTC day numbers", function()
  T.eq(U.day(20375 * 86400), 20375)
  T.eq(U.day(20375 * 86400 + 86399), 20375)
  T.eq(U.day(), 20375, "defaults to time()")
  T.eq(U.daysAgo(0), "today")
  T.eq(U.daysAgo(1), "1d ago")
  T.eq(U.daysAgo(5), "5d ago")
end)

T.test("quality colours", function()
  T.eq(U.quality(2), "|cff1eff00")
  T.eq(U.quality(nil), "|cffffffff")
end)

T.test("words and trim", function()
  T.eq(U.trim("  a b  "), "a b")
  T.eq(table.getn(U.words(" watch  Silk Cloth ")), 3)
end)
```

`tests/test_stats.lua`:
```lua
local S = TaxTheFools.Stats

T.test("percentile walks up from the cheapest", function()
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0), 10, "p0 is the minimum")
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0.25), 10)
  T.eq(S.weightedPercentile({ 30, 10, 40, 20 }, nil, 0.5), 20, "lower median")
  T.eq(S.weightedPercentile({}, nil, 0.5), nil)
end)

T.test("one cheap unit can't drag a quantity-weighted p25 down", function()
  -- a troll lists 1 at 100, a real seller lists 19 at 200
  T.eq(S.weightedPercentile({ 100, 200 }, { 1, 19 }, 0.25), 200)
end)

T.test("median", function()
  T.eq(S.median({ 5, 1, 3 }), 3)
end)

T.test("coefficient of variation", function()
  T.eq(S.cv({ 100, 100, 100 }), 0)
  T.eq(S.cv({ 100 }), 0, "one value")
  T.near(S.cv({ 50, 150, 50, 150, 50 }), 0.5443, 0.001)
  T.eq(S.cv({ 0, 0 }), 0, "zero mean")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL. `test_util` fails with `attempt to call field 'money' (a nil value)`, and `test_stats` fails with `attempt to index local 'S' (a nil value)`.

- [ ] **Step 3: Implement**

Append to `TaxTheFools/util.lua`:
```lua
-- Money as "12g 34s 56c". Zero parts are left out; nothing at all reads "0c".
-- Coloured like the client's coins unless plain is set.
function U.money(c, plain)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0
  if neg then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor(math.mod(c, 10000) / 100)
  local cp = math.mod(c, 100)
  local G, S, C, E = "|cffffd100", "|cffc7c7cf", "|cffc77840", "|r"
  if plain then G, S, C, E = "", "", "", "" end
  local parts = {}
  if g > 0 then table.insert(parts, G .. g .. "g" .. E) end
  if s > 0 then table.insert(parts, S .. s .. "s" .. E) end
  if cp > 0 or table.getn(parts) == 0 then table.insert(parts, C .. cp .. "c" .. E) end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- 1.12 links are item:id:enchant:suffix:unique.
function U.parseLink(link)
  if not link then return nil end
  local _, _, id, enchant, suffix = string.find(link, "item:(%d+):(%d*):(%d*)")
  if not id then return nil end
  return tonumber(id), tonumber(suffix) or 0, tonumber(enchant) or 0
end

function U.key(id, suffix) return id .. ":" .. (suffix or 0) end

-- Enchants and unique ids are ignored; random suffixes ("of the Monkey") price separately.
function U.keyFromLink(link)
  local id, suffix = U.parseLink(link)
  if not id then return nil end
  return U.key(id, suffix), id
end

function U.keyId(key)
  local _, _, id = string.find(key or "", "^(%d+)")
  return tonumber(id)
end

function U.linkString(link)
  local _, _, s = string.find(link or "", "(item:[%d:%-]+)")
  return s
end

function U.day(t) return math.floor((t or time()) / 86400) end

function U.daysAgo(n)
  if not n or n <= 0 then return "today" end
  return n .. "d ago"
end

U.QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
function U.quality(q) return "|cff" .. (U.QUALITY[q or 1] or "ffffff") end

-- One hidden tooltip for reading what the client knows about an item.
local scanTip
function U.scanTip()
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "TaxTheFoolsScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  return scanTip
end
```

`TaxTheFools/stats.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local S = {}
TaxTheFools.Stats = S

-- The value at fraction p (0..1) of the total weight, walking up from the
-- cheapest. Weighting by quantity is what stops one cheap single unit from
-- setting the price of a market full of stacks. weights may be nil (all 1).
function S.weightedPercentile(values, weights, p)
  local n = table.getn(values)
  if n == 0 then return nil end
  local idx = {}
  for i = 1, n do idx[i] = i end
  table.sort(idx, function(a, b) return values[a] < values[b] end)
  local total = 0
  for i = 1, n do total = total + (weights and weights[i] or 1) end
  local target = p * total
  local cum = 0
  for _, i in ipairs(idx) do
    cum = cum + (weights and weights[i] or 1)
    if cum >= target then return values[i] end
  end
  return values[idx[n]]
end

function S.median(values) return S.weightedPercentile(values, nil, 0.5) end

-- Spread relative to the mean; 0 when there is nothing to compare.
function S.cv(values)
  local n = table.getn(values)
  if n < 2 then return 0 end
  local sum = 0
  for _, v in ipairs(values) do sum = sum + v end
  local mean = sum / n
  if mean == 0 then return 0 end
  local sq = 0
  for _, v in ipairs(values) do sq = sq + (v - mean) * (v - mean) end
  return math.sqrt(sq / n) / mean
end
```

In `TaxTheFools/TaxTheFools.toc`, the file list becomes:
```
data.lua
util.lua
stats.lua
core.lua
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `16 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: money, item link and day helpers; weighted statistics"
```

---

### Task 3: Price model: day summary, record rules, market value, compaction

**Files:**
- Create: `TaxTheFools/price.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `price.lua` after `stats.lua`)
- Test: `tests/test_price.lua`

**Interfaces:**
- Consumes: `U.day`, `S.weightedPercentile`, `S.median`, `S.cv`, and the `D.*` constants.
- Produces:
  - `P.Summarize(listings) -> { [key] = row }`.
    - Each input listing is `{key=, unit=number|nil, qty=, owner=string|nil}`.
    - Each output row is `{ n, qty, min?, p25?, med?, sellers? }` (integers).
  - `P.Record(history, rows, day, src) -> touchedKeys`. `src` is `"full"`, `"watch"` or `"browse"`. A browse row never overwrites a full or watch row from the same day.
  - `P.Market(entry, today) -> { v, conf, low, lowDay, seen, n } | nil`.
  - `P.ConfLabel(conf) -> "high"|"medium"|"low"`.
  - `P.Compact(entry, today) -> boolean`: true when the entry is now empty.
  - History entry shape: `{ days = { [day] = row }, months = { [yyyymm] = { p25, n, d } } }`.

- [ ] **Step 1: Write the failing test**

`tests/test_price.lua`:
```lua
local P = TaxTheFools.Price
local TODAY = 20375

local function L(unit, qty, owner) return { key = "14047:0", unit = unit, qty = qty, owner = owner } end

T.test("summary weights by quantity and ignores one cheap single unit", function()
  local rows = P.Summarize({ L(1, 1, "Troll"), L(400, 20, "A"), L(410, 20, "B"), L(900, 20, "A") })
  local r = rows["14047:0"]
  T.eq(r.n, 4) T.eq(r.qty, 61)
  T.eq(r.min, 1, "min is honest")
  T.eq(r.p25, 400, "p25 isn't fooled by the troll")
  T.eq(r.med, 410)
  T.eq(r.sellers, 3)
end)

T.test("bid-only listings count but carry no price", function()
  local rows = P.Summarize({ L(nil, 5, nil) })
  local r = rows["14047:0"]
  T.eq(r.n, 1) T.eq(r.qty, 5)
  T.eq(r.p25, nil) T.eq(r.min, nil) T.eq(r.sellers, nil)
end)

T.test("a browse never overwrites a full scan's row from the same day", function()
  local hist = {}
  P.Record(hist, { ["14047:0"] = { n = 100, p25 = 400 } }, TODAY, "full")
  local touched = P.Record(hist, { ["14047:0"] = { n = 3, p25 = 999 } }, TODAY, "browse")
  T.eq(table.getn(touched), 0)
  T.eq(hist["14047:0"].days[TODAY].p25, 400)
  T.eq(hist["14047:0"].days[TODAY].src, "full")
end)

T.test("watch replaces, and browse replaces a browse", function()
  local hist = {}
  P.Record(hist, { k = { n = 1, p25 = 10 } }, TODAY, "browse")
  P.Record(hist, { k = { n = 2, p25 = 20 } }, TODAY, "browse")
  T.eq(hist.k.days[TODAY].p25, 20)
  P.Record(hist, { k = { n = 3, p25 = 30 } }, TODAY, "watch")
  T.eq(hist.k.days[TODAY].p25, 30)
end)

local function entry(days) local e = { days = {}, months = {} } for d, v in pairs(days) do e.days[TODAY - d] = v end return e end

T.test("recent days count more than old ones", function()
  local m = P.Market(entry({ [0] = { p25 = 100, min = 90 }, [10] = { p25 = 200, min = 150 } }), TODAY)
  T.eq(m.v, 100)
  T.eq(m.low, 90, "low comes from the newest row")
  T.eq(m.lowDay, TODAY)
end)

T.test("confidence grows with days seen and falls with volatility", function()
  local three = P.Market(entry({ [0] = { p25 = 100 }, [1] = { p25 = 100 }, [2] = { p25 = 100 } }), TODAY)
  T.near(three.conf, 0.6, 0.001) T.eq(P.ConfLabel(three.conf), "medium")
  local five = P.Market(entry({ [0] = { p25 = 100 }, [1] = { p25 = 100 }, [2] = { p25 = 100 }, [3] = { p25 = 100 }, [4] = { p25 = 100 } }), TODAY)
  T.eq(five.conf, 1) T.eq(P.ConfLabel(five.conf), "high")
  local wild = P.Market(entry({ [0] = { p25 = 50 }, [1] = { p25 = 150 }, [2] = { p25 = 50 }, [3] = { p25 = 150 }, [4] = { p25 = 50 } }), TODAY)
  T.near(wild.conf, 0.5464, 0.001)
  T.eq(P.ConfLabel(0.2), "low")
end)

T.test("days older than 30 are left out of market value", function()
  local m = P.Market(entry({ [0] = { p25 = 100 }, [31] = { p25 = 5000 } }), TODAY)
  T.eq(m.v, 100) T.eq(m.seen, 1)
end)

T.test("only monthly data falls back with low confidence", function()
  local e = { days = {}, months = { [202501] = { p25 = 300, n = 5, d = 4 } } }
  local m = P.Market(e, TODAY)
  T.eq(m.v, 300) T.eq(m.conf, 0.1)
end)

T.test("no priced data, or a damaged entry, gives no market value", function()
  T.eq(P.Market(entry({ [0] = { n = 2 } }), TODAY), nil)
  T.eq(P.Market({}, TODAY), nil, "entry without days/months tables")
  T.eq(P.Market(nil, TODAY), nil)
end)

T.test("old days fold into months and very old months are dropped", function()
  local e = entry({ [0] = { p25 = 100 }, [70] = { p25 = 200, n = 4 }, [71] = { p25 = 300, n = 6 } })
  e.months[201001] = { p25 = 1, n = 1, d = 1 }
  local empty = P.Compact(e, TODAY)
  T.eq(empty, false)
  T.eq(e.days[TODAY - 70], nil)
  T.ok(e.days[TODAY], "recent day kept")
  local month = tonumber(date("!%Y%m", (TODAY - 70) * 86400))
  T.eq(e.months[month].p25, 250, "mean of the folded days")
  T.eq(e.months[month].d, 2)
  T.eq(e.months[201001], nil, "month older than a year dropped")
end)

T.test("compacting an entry with nothing recent reports it empty", function()
  local e = entry({ [400] = { n = 1 } })
  T.eq(P.Compact(e, TODAY), true)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'P' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/price.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local S, D = TaxTheFools.Stats, TaxTheFools.Data
local P = {}
TaxTheFools.Price = P

local function round(x) return math.floor(x + 0.5) end

-- One day's facts per item from raw listings { key, unit, qty, owner }.
-- unit is nil for a listing with no buyout: it still counts as supply.
function P.Summarize(listings)
  local by = {}
  for _, l in ipairs(listings) do
    local b = by[l.key]
    if not b then
      b = { units = {}, qtys = {}, n = 0, qty = 0, owners = {}, nOwners = 0 }
      by[l.key] = b
    end
    b.n = b.n + 1
    b.qty = b.qty + (l.qty or 1)
    if l.unit then
      table.insert(b.units, l.unit)
      table.insert(b.qtys, l.qty or 1)
    end
    if l.owner and not b.owners[l.owner] then
      b.owners[l.owner] = true
      b.nOwners = b.nOwners + 1
    end
  end
  local rows = {}
  for key, b in pairs(by) do
    local row = { n = b.n, qty = b.qty }
    if table.getn(b.units) > 0 then
      row.min = round(S.weightedPercentile(b.units, nil, 0))
      row.p25 = round(S.weightedPercentile(b.units, b.qtys, 0.25))
      row.med = round(S.weightedPercentile(b.units, b.qtys, 0.5))
    end
    if b.nOwners > 0 then row.sellers = b.nOwners end
    rows[key] = row
  end
  return rows
end

-- Writes day rows. A browse sees a sliver of the market, so it never replaces
-- a full or watchlist row written the same day.
function P.Record(history, rows, day, src)
  local touched = {}
  for key, row in pairs(rows) do
    local entry = history[key]
    if not entry then
      entry = { days = {}, months = {} }
      history[key] = entry
    end
    local old = entry.days[day]
    if src ~= "browse" or not old or old.src == "browse" then
      row.src = src
      entry.days[day] = row
      table.insert(touched, key)
    end
  end
  return touched
end

function P.ConfLabel(conf)
  if conf >= 0.7 then return "high" end
  if conf >= 0.4 then return "medium" end
  return "low"
end

-- Market value: weighted median of daily p25 over 30 days, recent days counting
-- more. Confidence: how many days, discounted by how much the price moves.
function P.Market(entry, today)
  if not entry then return nil end
  local vals, ws, ns = {}, {}, {}
  local low, lowDay
  for day, row in pairs(entry.days or {}) do
    local age = today - day
    if age >= 0 and age < D.MARKET_DAYS and row.p25 then
      table.insert(vals, row.p25)
      table.insert(ws, math.pow(D.DECAY, age))
      table.insert(ns, row.n or 0)
    end
    if row.min and (not lowDay or day > lowDay) then low, lowDay = row.min, day end
  end
  local seen = table.getn(vals)
  if seen == 0 then
    local mv = {}
    for _, m in pairs(entry.months or {}) do
      if m.p25 then table.insert(mv, m.p25) end
    end
    if table.getn(mv) == 0 then return nil end
    return { v = round(S.median(mv)), conf = 0.1, low = low, lowDay = lowDay, seen = 0 }
  end
  local cv = S.cv(vals)
  if cv > 0.6 then cv = 0.6 end
  local conf = math.min(1, seen / 5) * (1 - cv / 0.6 * 0.5)
  return { v = round(S.weightedPercentile(vals, ws, 0.5)), conf = conf, low = low, lowDay = lowDay,
           seen = seen, n = S.median(ns) }
end

local function monthOf(day) return tonumber(date("!%Y%m", day * 86400)) end

-- Days past KEEP_DAYS become monthly averages; months past about a year go.
-- Returns true when nothing is left, so the caller can drop the entry.
function P.Compact(entry, today)
  entry.days = entry.days or {}
  entry.months = entry.months or {}
  for day, row in pairs(entry.days) do
    if today - day >= D.KEEP_DAYS then
      if row.p25 then
        local mk = monthOf(day)
        local m = entry.months[mk]
        if not m then
          m = { p25 = 0, n = 0, d = 0 }
          entry.months[mk] = m
        end
        m.p25 = round((m.p25 * m.d + row.p25) / (m.d + 1))
        m.n = round((m.n * m.d + (row.n or 0)) / (m.d + 1))
        m.d = m.d + 1
      end
      entry.days[day] = nil
    end
  end
  local oldest = monthOf(today - D.KEEP_MONTHS * 31)
  for mk in pairs(entry.months) do
    if mk < oldest then entry.months[mk] = nil end
  end
  return next(entry.days) == nil and next(entry.months) == nil
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `core.lua`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `27 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: price model with market value, confidence and retention"
```

---

### Task 4: Saved data, validation, realm/char tables and incremental pruning

**Files:**
- Create: `TaxTheFools/db.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `db.lua` after `price.lua`)
- Test: `tests/test_db.lua`

**Interfaces:**
- Consumes: `D.DEFAULTS`, `D.CHAR_DEFAULTS`, `D.REALM_DEFAULTS`, `D.DATA_VERSION`, `P.Compact`.
- Produces:
  - `DB.Init() -> TaxTheFoolsDB`
  - `DB.Valid(db) -> bool`
  - `DB.S() -> settings`
  - `DB.Realm() -> realm table` (`history`, `market`, `scan`, `chars`, `watch`)
  - `DB.Char() -> character table`
  - `DB.StartPrune()`
  - `DB.PruneStep(budget, today) -> done:boolean`
  - `DB.SizeText() -> string`
  - `DB.Wipe()`
  - `DB.wasBroken` (bool)
  - `DB.realmName`, `DB.charName`

- [ ] **Step 1: Write the failing test**

`tests/test_db.lua`:
```lua
local DB = TaxTheFools.DB

T.test("a fresh install gets every default", function()
  T.eq(TaxTheFoolsDB.dataVersion, 1)
  T.eq(DB.S().scanDelay, 0.3)
  T.eq(DB.S().tooltip.market, true)
  T.eq(type(TaxTheFoolsCharDB.windows), "table")
end)

T.test("existing choices survive and new defaults fill in", function()
  TaxTheFoolsDB = { dataVersion = 1, settings = { scanDelay = 1, tooltip = { vendor = false } } }
  DB.Init()
  T.eq(DB.S().scanDelay, 1)
  T.eq(DB.S().tooltip.vendor, false)
  T.eq(DB.S().tooltip.market, true, "new nested default added")
  T.eq(DB.S().safeMode, false)
end)

T.test("an unreadable saved table is set aside, not merged into", function()
  TaxTheFoolsDB = { settings = 5 }
  DB.Init()
  T.ok(DB.wasBroken)
  T.eq(TaxTheFoolsDB_broken[WoW.now].settings, 5)
  T.eq(type(DB.S()), "table")
  TaxTheFoolsDB = "garbage"
  DB.Init()
  T.eq(TaxTheFoolsDB_broken[WoW.now], "garbage")
end)

T.test("realm and character tables are created once", function()
  local r = DB.Realm()
  T.eq(type(r.history), "table") T.eq(type(r.watch), "table")
  T.eq(DB.Realm(), r)
  T.eq(TaxTheFoolsDB.realms.Medivh, r)
  T.eq(DB.Char().class, "WARRIOR")
  T.eq(r.chars.Bankalt, DB.Char())
end)

T.test("pruning runs a few items per step and removes emptied entries", function()
  local r = DB.Realm()
  local today = 20375
  r.history["1:0"] = { days = { [today] = { p25 = 10 } }, months = {} }
  r.history["2:0"] = { days = { [today - 400] = { n = 1 } }, months = {} }
  r.history["3:0"] = { days = { [today - 70] = { p25 = 30, n = 1 } }, months = {} }
  r.market["2:0"] = { v = 1 }
  DB.StartPrune()
  T.eq(DB.PruneStep(2, today), false, "three entries, budget two")
  T.eq(DB.PruneStep(2, today), true)
  T.eq(r.history["2:0"], nil, "empty entry removed")
  T.eq(r.market["2:0"], nil, "and its market value")
  T.ok(r.history["1:0"].days[today], "recent kept")
  T.eq(next(r.history["3:0"].days), nil, "old day folded")
  T.ok(next(r.history["3:0"].months), "into a month")
  T.eq(DB.PruneStep(2, today), true, "nothing to do afterwards")
end)

T.test("pruning survives entries added between steps", function()
  local r = DB.Realm()
  for i = 1, 10 do r.history[i .. ":0"] = { days = { [20375] = { p25 = i } }, months = {} } end
  DB.StartPrune()
  DB.PruneStep(3, 20375)
  for i = 11, 200 do r.history[i .. ":0"] = { days = { [20375] = { p25 = i } }, months = {} } end
  local done = false
  for _ = 1, 10 do done = DB.PruneStep(3, 20375) if done then break end end
  T.ok(done, "finishes the snapshot it started with")
end)

T.test("size text counts what is stored", function()
  local r = DB.Realm()
  TaxTheFoolsDB.items[1] = { n = "x" }
  r.history["1:0"] = { days = { [20375] = {}, [20374] = {} }, months = {} }
  local s = DB.SizeText()
  T.ok(string.find(s, "1 items known", 1, true), s)
  T.ok(string.find(s, "2 daily rows", 1, true), s)
end)

T.test("wipe starts again from defaults", function()
  DB.S().scanDelay = 2
  DB.Wipe()
  T.eq(DB.S().scanDelay, 0.3)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'DB' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/db.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local D = TaxTheFools.Data
local DB = { wasBroken = false }
TaxTheFools.DB = DB

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end
DB.copyDefaults = copyDefaults

-- One-time changes to existing saved data, keyed by the version that needs them:
-- MIGRATIONS[2] = function(db) ... end runs once for anyone below version 2.
local MIGRATIONS = {}

function DB.ResetState()
  DB.wasBroken = false
  DB.pruneKeys, DB.pruneIndex = nil, 1
end

-- What a saved table must look like to be trusted.
function DB.Valid(db)
  if type(db) ~= "table" then return false end
  for _, k in ipairs({ "settings", "items", "realms" }) do
    if db[k] ~= nil and type(db[k]) ~= "table" then return false end
  end
  return true
end

function DB.Init()
  if TaxTheFoolsDB ~= nil and not DB.Valid(TaxTheFoolsDB) then
    if type(TaxTheFoolsDB_broken) ~= "table" then TaxTheFoolsDB_broken = {} end
    TaxTheFoolsDB_broken[time()] = TaxTheFoolsDB
    TaxTheFoolsDB = nil
    DB.wasBroken = true
  end
  if TaxTheFoolsDB == nil then TaxTheFoolsDB = { dataVersion = D.DATA_VERSION } end
  copyDefaults(TaxTheFoolsDB, D.DEFAULTS)
  local v = TaxTheFoolsDB.dataVersion or 0
  for n = v + 1, D.DATA_VERSION do
    if MIGRATIONS[n] then MIGRATIONS[n](TaxTheFoolsDB) end
  end
  TaxTheFoolsDB.dataVersion = D.DATA_VERSION
  if type(TaxTheFoolsCharDB) ~= "table" then TaxTheFoolsCharDB = {} end
  copyDefaults(TaxTheFoolsCharDB, D.CHAR_DEFAULTS)
  DB.realmName = GetRealmName() or "?"
  DB.charName = UnitName("player") or "?"
  return TaxTheFoolsDB
end

function DB.S() return TaxTheFoolsDB.settings end

-- Prices are per realm: the auction house is cross-faction on this server.
function DB.Realm()
  local realms = TaxTheFoolsDB.realms
  local r = realms[DB.realmName]
  if not r then
    r = {}
    realms[DB.realmName] = r
  end
  copyDefaults(r, D.REALM_DEFAULTS)
  return r
end

function DB.Char()
  local chars = DB.Realm().chars
  local c = chars[DB.charName]
  if not c then
    local _, class = UnitClass("player")
    c = { class = class }
    chars[DB.charName] = c
  end
  return c
end

function DB.Wipe()
  TaxTheFoolsDB, TaxTheFoolsCharDB = nil, nil
  DB.Init()
end

-- Retention runs over a snapshot of keys, a few per frame: next() over a table
-- that gains keys between calls is undefined in Lua.
DB.pruneKeys, DB.pruneIndex = nil, 1

function DB.StartPrune()
  local keys = {}
  for k in pairs(DB.Realm().history) do table.insert(keys, k) end
  DB.pruneKeys, DB.pruneIndex = keys, 1
end

function DB.PruneStep(budget, today)
  local keys = DB.pruneKeys
  if not keys then return true end
  local realm = DB.Realm()
  local last = math.min(table.getn(keys), DB.pruneIndex + budget - 1)
  for i = DB.pruneIndex, last do
    local key = keys[i]
    local entry = realm.history[key]
    if entry and TaxTheFools.Price.Compact(entry, today) then
      realm.history[key] = nil
      realm.market[key] = nil
    end
  end
  DB.pruneIndex = last + 1
  if DB.pruneIndex > table.getn(keys) then
    DB.pruneKeys = nil
    return true
  end
  return false
end

function DB.SizeText()
  local realm = DB.Realm()
  local items, priced, rows = 0, 0, 0
  for _ in pairs(TaxTheFoolsDB.items) do items = items + 1 end
  for _, e in pairs(realm.history) do
    priced = priced + 1
    for _ in pairs(e.days or {}) do rows = rows + 1 end
  end
  return items .. " items known, " .. priced .. " with price history, " .. rows .. " daily rows on " .. DB.realmName
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `core.lua`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `35 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: saved data with validation, migration hook and incremental pruning"
```

---

### Task 5: Item cache, uncached lookups and vendor prices

**Files:**
- Create: `TaxTheFools/items.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `items.lua` after `db.lua`)
- Test: `tests/test_items.lua`

**Interfaces:**
- Consumes: `U.parseLink`, `U.scanTip`, `TaxTheFoolsDB.items`.
- Produces:
  - `I.Get(id) -> record|nil`, where a record is `{ n=name, q=quality, st=stackSize, t=texture, v=vendorPerUnit }`
  - `I.Remember(id, name, quality, stack, texture) -> record`
  - `I.Resolve(id) -> record|nil`
  - `I.Request(id)`
  - `I.Name(id) -> string`
  - `I.Vendor(id) -> copper|nil`
  - `I.LearnVendorPrices()`
  - `I.FindByName(name) -> id|nil`

- [ ] **Step 1: Write the failing test**

`tests/test_items.lua`:
```lua
local I = TaxTheFools.Items

T.test("resolve fills a record from what the client knows", function()
  WoW.items[4306] = { name = "Silk Cloth", quality = 1, stack = 20 }
  local rec = I.Resolve(4306)
  T.eq(rec.n, "Silk Cloth") T.eq(rec.st, 20) T.eq(rec.q, 1)
  T.eq(TaxTheFoolsDB.items[4306], rec, "kept account-wide")
end)

T.test("an uncached item is asked for once through the scan tooltip", function()
  T.eq(I.Resolve(5000), nil)
  I.Resolve(5000)
  T.eq(T.count("SetHyperlink TaxTheFoolsScanTip item:5000:0:0:0"), 1)
  T.eq(I.Name(5000), "Unknown item #5000")
end)

T.test("with ClassicAPI the request goes through it instead", function()
  WoW.classicAPI(true)
  I.Resolve(5001)
  T.ok(T.calledWith("RequestLoadItemDataByID 5001"))
  T.ok(not T.calledWith("SetHyperlink"), "no tooltip trick needed")
end)

T.test("vendor prices learned at a merchant are stored per unit", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 }, {}, { id = 14047, name = "Runecloth", count = 1, vendor = 100 } }
  WoW.merchantOpen = true
  I.LearnVendorPrices()
  T.eq(I.Vendor(4306), 37)
  T.eq(I.Vendor(14047), 100)
end)

T.test("without a merchant nothing is learned", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 } }
  I.LearnVendorPrices()
  T.eq(I.Vendor(4306), nil)
end)

T.test("ClassicAPI supplies vendor prices never seen at a merchant", function()
  WoW.classicAPI(true)
  WoW.items[2589] = { name = "Linen Cloth", vendor = 13 }
  T.eq(I.Vendor(2589), 13)
  T.eq(TaxTheFoolsDB.items[2589].v, 13, "remembered")
end)

T.test("find by name ignores case", function()
  I.Remember(4306, "Silk Cloth")
  T.eq(I.FindByName("silk cloth"), 4306)
  T.eq(I.FindByName("Mageweave"), nil)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'I' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/items.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U = TaxTheFools.Util
local I = { requested = {}, tipMoney = false }
TaxTheFools.Items = I

function I.ResetState() I.requested = {} I.tipMoney = false end

function I.Get(id) return TaxTheFoolsDB.items[id] end

function I.Remember(id, name, quality, stack, texture)
  if not id then return nil end
  local rec = TaxTheFoolsDB.items[id]
  if not rec then
    rec = {}
    TaxTheFoolsDB.items[id] = rec
  end
  if name then rec.n = name end
  if quality then rec.q = quality end
  if stack then rec.st = stack end
  if texture then rec.t = texture end
  return rec
end

-- What the client knows about an item, remembered for every character.
-- GetItemInfo returns nothing for items this client has never seen; those
-- are requested from the server once per session.
function I.Resolve(id)
  local rec = TaxTheFoolsDB.items[id]
  if rec and rec.n and rec.st then return rec end
  local name, _, quality, _, _, _, stack, _, texture = GetItemInfo(id)
  if name then return I.Remember(id, name, quality, stack, texture) end
  I.Request(id)
  return rec
end

-- Only ever called for ids seen in the AH, bags or a link: asking the server
-- for an id that does not exist can disconnect a 1.12 client.
function I.Request(id)
  if I.requested[id] then return end
  I.requested[id] = true
  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(id)
    return
  end
  local tip = U.scanTip()
  tip:ClearLines()
  tip:SetHyperlink("item:" .. id .. ":0:0:0")
end

function I.Name(id)
  local rec = I.Resolve(id)
  return (rec and rec.n) or ("Unknown item #" .. tostring(id))
end

function I.Vendor(id)
  local rec = TaxTheFoolsDB.items[id]
  if rec and rec.v then return rec.v end
  if C_Item and C_Item.GetItemSellPrice then
    local v = C_Item.GetItemSellPrice(id)
    if v and v > 0 then
      I.Remember(id).v = v
      return v
    end
  end
  return nil
end

-- With a merchant open, the client prices every bag item on its tooltip and
-- reports the stack's value through OnTooltipAddMoney.
function I.LearnVendorPrices()
  local tip = U.scanTip()
  tip:SetScript("OnTooltipAddMoney", function() I.tipMoney = arg1 end)
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local id = U.parseLink(GetContainerItemLink(bag, slot))
      if id then
        local _, count = GetContainerItemInfo(bag, slot)
        I.tipMoney = false
        tip:ClearLines()
        tip:SetBagItem(bag, slot)
        if I.tipMoney and count and count > 0 then
          I.Remember(id).v = math.floor(I.tipMoney / count + 0.5)
        end
      end
    end
  end
end

function I.FindByName(name)
  local want = string.lower(name or "")
  for id, rec in pairs(TaxTheFoolsDB.items) do
    if rec.n and string.lower(rec.n) == want then return id end
  end
  return nil
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `items.lua`, `core.lua`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `42 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: account-wide item cache, uncached lookups and vendor prices"
```

---

### Task 6: Scan engine

**Files:**
- Create: `TaxTheFools/scan.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `scan.lua` after `items.lua`)
- Test: `tests/test_scan.lua`

**Interfaces:**
- Consumes:
  - `P.Summarize`, `P.Record`, `P.Market`
  - `DB.S()`, `DB.Realm()`
  - `I.Remember`, `I.Get`
  - `U.keyFromLink`, `U.keyId`, `U.day`
  - the `D.*` timing constants.
- Produces:
  - `Scan.StartFull(now)`, `Scan.StartWatch(now)` and `Scan.Browse(name, page, now)`, each returning `ok, why` with `why` one of `"busy"` or `"empty"`.
  - `Scan.Tick(now)` (call every frame) and `Scan.OnListUpdate(now)` (on `AUCTION_ITEM_LIST_UPDATE`).
  - `Scan.Pause(reason)`, `Scan.Continue()`, `Scan.Resume(now) -> bool`, `Scan.Discard()`.
  - `Scan.Resumable() -> saved|nil`, where `saved = { kind, queries, qi, page, day, pagesDone, rows = {"key|unit|qty|owner", ...} }`.
  - `Scan.Progress(now) -> { kind, state, reason, page, totalPages, qi, nq, listings, safe, secsPerPage?, eta? } | nil`. `state` is `"wait"`, `"sent"` or `"stalled"`.
  - `Scan.Busy() -> bool`.
  - `Scan.OnChange(fn)`, which registers a listener called whenever scan state changes.
  - Browse results:
    - `Scan.lastRows`: rows of `{ key, id, name, link, texture, quality, count, minBid, bid, minInc, buyout, unit, owner, index }`
    - `Scan.lastTotal`, `Scan.lastPage`
  - `Scan.lastFinished = { kind, pages, listings, secs }`.
  - `Scan.QueueMarket(keys)` and `Scan.MarketStep()`.
  - `Scan.WatchQueries() -> { {name=...}, ... }`.

- [ ] **Step 1: Write the failing test**

`tests/test_scan.lua`:
```lua
local Scan, DB, I = TaxTheFools.Scan, TaxTheFools.DB, TaxTheFools.Items

local function fill(n, id, name, base)
  for i = 1, n do
    table.insert(WoW.ah.listings, { id = id or 14047, name = name or "Runecloth", count = 20,
      buyout = (base or 8000) + i, owner = "S" .. math.mod(i, 7) })
  end
end

-- Advance the clock half a second at a time, answering every query the scan sends.
local function pump(limit)
  for i = 1, limit or 200 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return i end
  end
end

-- One step at time t, sharing WoW.clock with pump(); answer=true replies to any query.
local function at(t, answer)
  WoW.clock = t
  Scan.Tick(t)
  if answer and WoW.ah.pending then
    WoW.ahRespond()
    Scan.OnListUpdate(t)
  end
end

local function day(key) return DB.Realm().history[key].days[20375] end

T.test("a full scan pages through everything and records one day row", function()
  fill(120)
  T.ok(Scan.StartFull(WoW.clock))
  pump()
  -- name and levels go as "" (never nil): Ravencraft ignores the query otherwise
  T.ok(T.calledWith("QueryAuctionItems [] [] [] 0"), "page 0")
  T.ok(T.calledWith("QueryAuctionItems [] [] [] 2"), "page 2")
  T.ok(not T.calledWith("QueryAuctionItems [] [] [] 3"), "stops after the last page")
  local r = day("14047:0")
  T.eq(r.n, 120) T.eq(r.qty, 2400) T.eq(r.src, "full")
  T.eq(r.min, 400) T.eq(r.p25, 402) T.eq(r.med, 403) T.eq(r.sellers, 7)
  T.eq(DB.Realm().scan.lastFull, WoW.now)
  T.eq(Scan.lastFinished.pages, 3)
end)

T.test("market values are worked out after the scan, a batch per frame", function()
  fill(10)
  Scan.StartFull(WoW.clock)
  pump()
  Scan.Tick(WoW.clock)
  T.eq(DB.Realm().market["14047:0"].v, day("14047:0").p25)
end)

T.test("nothing is sent while the client's query gate is shut", function()
  fill(10)
  WoW.ah.canQuery = false
  Scan.StartFull(WoW.clock)
  Scan.Tick(WoW.clock + 5)
  T.eq(T.count("QueryAuctionItems"), 0)
  WoW.ah.canQuery = true
  Scan.Tick(WoW.clock + 6)
  T.eq(T.count("QueryAuctionItems"), 1)
end)

T.test("pages are spaced by the minimum delay", function()
  fill(120)
  Scan.StartFull(0)
  at(10, true)
  at(10.1)
  T.eq(T.count("QueryAuctionItems"), 1, "too soon")
  at(10.4)
  T.eq(T.count("QueryAuctionItems"), 2)
end)

T.test("an unanswered page is asked for again, then the scan stalls", function()
  fill(10)
  Scan.StartFull(0)
  local t = 0
  for _ = 1, 5 do
    t = t + 1 Scan.Tick(t)        -- sends (or resends)
    t = t + 16 Scan.Tick(t)       -- times out
  end
  T.eq(T.count("QueryAuctionItems"), 4, "first try plus three resends")
  local p = Scan.Progress(t)
  T.eq(p.state, "stalled") T.eq(p.reason, "server not responding")
  Scan.Continue()
  Scan.Tick(t + 1)
  T.eq(T.count("QueryAuctionItems"), 5, "continue tries again")
end)

T.test("a repeated page is not counted twice and is asked for again after a pause", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  WoW.ah.duplicateNext = 1
  at(2, true)                                   -- page 1 asked for, page 0 sent again
  at(3)
  T.eq(T.count("QueryAuctionItems [] [] [] 1"), 1, "waits the safe delay before re-asking")
  at(6.5)
  T.eq(T.count("QueryAuctionItems [] [] [] 1"), 2)
  pump()
  T.eq(day("14047:0").n, 120, "no duplicates recorded")
end)

T.test("two repeated pages switch the rest of the scan to safe pace", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  WoW.ah.duplicateNext = 2
  at(2, true)
  at(7, true)
  T.ok(Scan.Progress(7).safe)
end)

T.test("a page with uncached names waits for them, briefly", function()
  fill(3)
  WoW.ah.listings[2].noName = true
  Scan.StartFull(0)
  at(1, true)
  T.eq(Scan.Progress(1).state, "sent", "still waiting for names")
  WoW.ah.listings[2].noName = false
  Scan.OnListUpdate(1.2)
  T.eq(Scan.job, nil, "complete page accepted")
  T.eq(day("14047:0").n, 3)
end)

T.test("names that never arrive don't hold the scan up", function()
  fill(3)
  WoW.ah.listings[2].noName = true
  Scan.StartFull(0)
  at(1, true)
  at(2.1)
  T.eq(Scan.job, nil)
  T.eq(day("14047:0").n, 2, "the nameless row is skipped")
end)

T.test("closing the AH mid-scan keeps progress, re-asking the unanswered page", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  at(2)                                 -- page 1 requested, never answered
  Scan.Pause("closed")
  T.eq(Scan.job, nil)
  local saved = Scan.Resumable()
  T.eq(saved.page, 1) T.eq(table.getn(saved.rows), 50)
  WoW.ah.pending = false                -- that request died with the session
  WoW.clock = 10
  T.ok(Scan.Resume(10))
  pump()
  T.eq(day("14047:0").n, 120)
  T.eq(DB.Realm().scan.resume, nil)
end)

T.test("a paused scan from yesterday is discarded, not mixed into today", function()
  fill(120)
  Scan.StartFull(0)
  at(1, true)
  Scan.Pause("closed")
  WoW.now = WoW.now + 86400
  T.eq(Scan.Resumable(), nil)
  T.eq(Scan.Resume(5), false)
end)

T.test("watchlist scan asks for each known name and skips unknown ones", function()
  I.Remember(14047, "Runecloth") I.Remember(4306, "Silk Cloth")
  local w = DB.Realm().watch
  w["14047:0"] = true w["4306:0"] = true w["99999:0"] = true
  fill(5) fill(5, 4306, "Silk Cloth", 600)
  T.ok(Scan.StartWatch(0))
  pump()
  T.ok(T.calledWith("QueryAuctionItems [Runecloth]"))
  T.ok(T.calledWith("QueryAuctionItems [Silk Cloth]"))
  T.ok(not T.calledWith("QueryAuctionItems []"), "never an empty name: that would be a full scan")
  T.eq(day("4306:0").src, "watch")
end)

T.test("an empty watchlist doesn't start", function()
  local ok, why = Scan.StartWatch(0)
  T.eq(ok, false) T.eq(why, "empty")
end)

T.test("browse shows one page and feeds history without trumping a full scan", function()
  fill(60, 4306, "Silk Cloth", 600)
  Scan.StartFull(0) pump()
  local full = day("4306:0").p25
  T.ok(Scan.Browse("Silk", 1, WoW.clock))
  pump()
  T.eq(table.getn(Scan.lastRows), 10, "second page")
  T.eq(Scan.lastTotal, 60)
  T.eq(Scan.lastPage, 1)
  T.eq(Scan.lastRows[1].name, "Silk Cloth")
  T.eq(day("4306:0").p25, full)
end)

T.test("browse can be kept out of history", function()
  DB.S().browseFeedsHistory = false
  fill(5)
  Scan.Browse("Rune", 0, 0) pump()
  T.eq(DB.Realm().history["14047:0"], nil)
end)

T.test("searching during a full scan is refused and the scan carries on", function()
  fill(120)
  Scan.StartFull(0)
  at(1)
  local ok, why = Scan.Browse("Rune", 0, 1)
  T.eq(ok, false) T.eq(why, "busy")
  T.eq(Scan.job.kind, "full")
  pump()
  T.eq(day("14047:0").n, 120)
end)

T.test("progress estimates time left from the measured page rate", function()
  fill(500)
  Scan.StartFull(0)
  at(0, true)
  at(5, true)
  local p = Scan.Progress(10)
  T.eq(p.totalPages, 10) T.eq(p.page, 2)
  T.near(p.secsPerPage, 5, 0.01)
  T.near(p.eta, 40, 0.01)
end)

T.test("listeners hear about changes", function()
  local heard = 0
  Scan.OnChange(function() heard = heard + 1 end)
  fill(5)
  Scan.StartFull(0) pump()
  T.ok(heard >= 2)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'Scan' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/scan.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, D, P, DB, I = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Price, TaxTheFools.DB, TaxTheFools.Items
local Scan = { job = nil, listeners = {}, lastRows = {}, lastTotal = 0, lastPage = 0 }
TaxTheFools.Scan = Scan

function Scan.ResetState()
  Scan.job, Scan.lastRows, Scan.lastTotal, Scan.lastPage = nil, {}, 0, 0
  Scan.pendingMarket, Scan.lastFinished = nil, nil
end

function Scan.OnChange(fn) table.insert(Scan.listeners, fn) end
local function changed() for _, fn in ipairs(Scan.listeners) do fn() end end

function Scan.Busy() return Scan.job ~= nil end

local function delay(job)
  if job.safe or DB.S().safeMode then return D.SAFE_DELAY end
  return DB.S().scanDelay or 0.3
end

local function newJob(kind, queries, now)
  return { kind = kind, queries = queries, qi = 1, page = queries[1].page or 0, totalPages = nil,
           state = "wait", reason = nil, lastQueryAt = -1000, sentAt = 0, holdUntil = 0,
           retries = 0, dupes = 0, safe = false, lastSig = nil, incompleteSince = nil,
           listings = {}, pagesDone = 0, pagesRun = 0, firstSentAt = nil,
           startedAt = now, day = U.day(time()) }
end

function Scan.Start(kind, queries, now)
  if Scan.job then return false, "busy" end
  if table.getn(queries) == 0 then return false, "empty" end
  Scan.job = newJob(kind, queries, now)
  changed()
  return true
end

function Scan.StartFull(now) return Scan.Start("full", { { name = "" } }, now) end

-- One exact-name query per watched item whose name is known. An unknown name
-- is skipped, never sent as "": an empty name is a full scan.
function Scan.WatchQueries()
  local seen, names = {}, {}
  for key in pairs(DB.Realm().watch) do
    local rec = I.Get(U.keyId(key))
    local name = rec and rec.n
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  local queries = {}
  for _, n in ipairs(names) do table.insert(queries, { name = n }) end
  return queries
end

function Scan.StartWatch(now) return Scan.Start("watch", Scan.WatchQueries(), now) end

function Scan.Browse(name, page, now)
  return Scan.Start("browse", { { name = name or "", page = page or 0 } }, now)
end

local function send(job, now)
  local q = job.queries[job.qi]
  QueryAuctionItems(q.name or "", "", "", nil, nil, nil, job.page, nil, nil)
  job.state, job.sentAt, job.lastQueryAt = "sent", now, now
  job.incompleteSince = nil
  if not job.firstSentAt then job.firstSentAt = now end
end

function Scan.ReadRow(i)
  local name, texture, count, quality, _, _, minBid, minInc, buyout, bid, _, owner = GetAuctionItemInfo("list", i)
  local link = GetAuctionItemLink("list", i)
  local key, id = U.keyFromLink(link)
  if not name or not key then return nil end
  I.Remember(id, name, quality, nil, texture)
  if not count or count < 1 then count = 1 end
  local unit = nil
  if buyout and buyout > 0 then unit = buyout / count end
  return { key = key, id = id, name = name, link = link, texture = texture, quality = quality, count = count,
           minBid = minBid or 0, bid = bid or 0, minInc = minInc or 0, buyout = buyout or 0,
           unit = unit, owner = owner, index = i }
end

local function signature(rows)
  local parts = { table.getn(rows) }
  for _, r in ipairs(rows) do table.insert(parts, r.key .. "/" .. r.count .. "/" .. r.buyout) end
  return table.concat(parts, ";")
end

-- Takes the page the server sent. Waits up to NAME_WAIT for rows whose item the
-- client has not cached yet (they arrive nameless); force accepts regardless.
function Scan.Accept(now, force)
  local job = Scan.job
  if not job or job.state ~= "sent" then return end
  local batch, total = GetNumAuctionItems("list")
  local rows, missing = {}, 0
  for i = 1, batch do
    local r = Scan.ReadRow(i)
    if r then table.insert(rows, r) else missing = missing + 1 end
  end
  if missing > 0 and not force then
    if not job.incompleteSince then job.incompleteSince = now end
    return
  end
  local sig = signature(rows)
  if job.lastSig and sig == job.lastSig then
    -- The server repeated the previous page. Ask again after a pause; twice
    -- and the rest of this scan goes at safe pace.
    job.dupes = job.dupes + 1
    if job.dupes >= 2 then job.safe = true end
    job.state, job.holdUntil = "wait", now + D.SAFE_DELAY
    changed()
    return
  end
  job.lastSig, job.retries = sig, 0
  for _, r in ipairs(rows) do
    table.insert(job.listings, { key = r.key, unit = r.unit, qty = r.count, owner = r.owner })
  end
  job.pagesDone, job.pagesRun = job.pagesDone + 1, job.pagesRun + 1
  job.totalPages = math.ceil(total / D.PAGE_SIZE)
  if job.kind == "browse" then
    Scan.lastRows, Scan.lastTotal, Scan.lastPage = rows, total, job.page
    return Scan.Finish(now)
  end
  if batch == 0 or (job.page + 1) * D.PAGE_SIZE >= total then
    job.qi, job.page, job.lastSig, job.totalPages = job.qi + 1, 0, nil, nil
    if job.qi > table.getn(job.queries) then return Scan.Finish(now) end
  else
    job.page = job.page + 1
  end
  job.state = "wait"
  changed()
end

function Scan.OnListUpdate(now) Scan.Accept(now, false) end

function Scan.Tick(now)
  local job = Scan.job
  if job then
    if job.state == "wait" then
      if now >= job.holdUntil and now - job.lastQueryAt >= delay(job) and CanSendAuctionQuery() then
        send(job, now)
      end
    elseif job.state == "sent" then
      if job.incompleteSince and now - job.incompleteSince >= D.NAME_WAIT then
        Scan.Accept(now, true)
      elseif now - job.sentAt > D.QUERY_TIMEOUT then
        job.retries = job.retries + 1
        if job.retries > D.MAX_RETRIES then
          job.state, job.reason = "stalled", "server not responding"
        else
          job.state = "wait"
        end
        changed()
      end
    end
  end
  Scan.MarketStep()
end

function Scan.Finish(now)
  local job = Scan.job
  Scan.job = nil
  local realm = DB.Realm()
  if job.kind ~= "browse" or DB.S().browseFeedsHistory then
    local touched = P.Record(realm.history, P.Summarize(job.listings), job.day, job.kind)
    Scan.QueueMarket(touched)
  end
  if job.kind == "full" then realm.scan.lastFull = time() end
  if job.kind ~= "browse" then realm.scan.resume = nil end
  Scan.lastFinished = { kind = job.kind, pages = job.pagesDone, listings = table.getn(job.listings),
                        secs = now - job.startedAt }
  changed()
end

function Scan.QueueMarket(keys)
  Scan.pendingMarket = Scan.pendingMarket or {}
  for _, k in ipairs(keys) do table.insert(Scan.pendingMarket, k) end
end

function Scan.MarketStep()
  local q = Scan.pendingMarket
  if not q then return end
  local realm, today = DB.Realm(), U.day(time())
  for _ = 1, D.MARKET_PER_FRAME do
    local key = table.remove(q)
    if not key then
      Scan.pendingMarket = nil
      changed()
      return
    end
    realm.market[key] = P.Market(realm.history[key], today)
  end
end

-- Stops the scan and keeps what it has, so the next visit can carry on. The
-- page in flight was never accepted, so resuming asks for it again.
function Scan.Pause(reason)
  local job = Scan.job
  if not job then return end
  Scan.job = nil
  if job.kind ~= "browse" then
    local saved = { kind = job.kind, queries = job.queries, qi = job.qi, page = job.page, day = job.day,
                    pagesDone = job.pagesDone, rows = {} }
    for _, l in ipairs(job.listings) do
      table.insert(saved.rows, l.key .. "|" .. (l.unit or "") .. "|" .. l.qty .. "|" .. (l.owner or ""))
    end
    DB.Realm().scan.resume = saved
  end
  changed()
end

-- Retry after "server not responding".
function Scan.Continue()
  local job = Scan.job
  if not job or job.state ~= "stalled" then return end
  job.state, job.retries, job.reason = "wait", 0, nil
  changed()
end

-- A saved scan, or nil. One from an earlier day is dropped: a day row never
-- mixes listings from two days.
function Scan.Resumable()
  local saved = DB.Realm().scan.resume
  if not saved then return nil end
  if saved.day ~= U.day(time()) then
    DB.Realm().scan.resume = nil
    return nil
  end
  return saved
end

function Scan.Resume(now)
  if Scan.job then return false end
  local saved = Scan.Resumable()
  if not saved then return false end
  local job = newJob(saved.kind, saved.queries, now)
  job.qi, job.page, job.pagesDone, job.day = saved.qi, saved.page, saved.pagesDone, saved.day
  for _, s in ipairs(saved.rows) do
    local _, _, key, unit, qty, owner = string.find(s, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if key then
      if owner == "" then owner = nil end
      table.insert(job.listings, { key = key, unit = tonumber(unit), qty = tonumber(qty) or 1, owner = owner })
    end
  end
  DB.Realm().scan.resume = nil
  Scan.job = job
  changed()
  return true
end

function Scan.Discard()
  DB.Realm().scan.resume = nil
  changed()
end

function Scan.Progress(now)
  local job = Scan.job
  if not job then return nil end
  local p = { kind = job.kind, state = job.state, reason = job.reason, page = job.page, totalPages = job.totalPages,
              qi = job.qi, nq = table.getn(job.queries), listings = table.getn(job.listings), safe = job.safe }
  if job.firstSentAt and job.pagesRun > 0 then
    p.secsPerPage = (now - job.firstSentAt) / job.pagesRun
    local left
    if job.kind == "full" and job.totalPages then left = job.totalPages - job.page
    else left = p.nq - job.qi + 1 end
    p.eta = left * p.secsPerPage
  end
  return p
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `items.lua`, `scan.lua`, `core.lua`.

Two details the tests depend on:
- `newJob` sets `lastQueryAt = -1000`, so the first query goes out on the first tick.
- `holdUntil` starts at 0.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `60 passed, 0 failed`

If "progress estimates time left" fails, check the pacing. After two pages answered at t=0 and t=5, `pagesRun` is 2 and `firstSentAt` is 0. At t=10 that gives `secsPerPage` = 5, with `page` = 2 of 10 pages, so `eta` = (10 − 2) × 5 = 40.

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: resumable AH scan engine with pacing, retries and duplicate-page guard"
```

---

### Task 7: Replace Blizzard's auction window without ending the session

**Files:**
- Create: `TaxTheFools/ahhook.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `ahhook.lua` after `scan.lua`)
- Test: `tests/test_ahhook.lua`

**Interfaces:**
- Consumes: `DB.S().replaceBlizzardAH`, `Scan.Pause`.
- Produces:
  - `AH.window`: our window, any frame with Show/Hide/IsShown. It is assigned by the UI in Task 11.
  - `AH.open` (bool), `AH.keepOpen` (bool)
  - `AH.OnShow()` for `AUCTION_HOUSE_SHOW`
  - `AH.Tick()`, called every frame
  - `AH.OnClosed()` for `AUCTION_HOUSE_CLOSED`
  - `AH.ShowOurs()`, `AH.ShowBlizzard()`
  - `AH.OnWindowHidden()`, which our window's OnHide must call
  - `AH.Hook()`

- [ ] **Step 1: Write the failing test**

`tests/test_ahhook.lua`:
```lua
local AH, Scan, DB = TaxTheFools.AH, TaxTheFools.Scan, TaxTheFools.DB

-- A stand-in for our window until the real one exists (Task 11).
local function fakeWindow()
  local w = CreateFrame("Frame", "TTFTestWindow", UIParent)
  w:Hide()
  w:SetScript("OnHide", function() AH.OnWindowHidden() end)
  return w
end

local function open()
  AuctionFrame:Show()          -- Blizzard shows its window when you talk to an auctioneer
  AH.OnShow()
  AH.Tick()                    -- the swap happens a frame later
end

T.test("opening the AH swaps in our window and keeps the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  T.eq(AuctionFrame:IsShown(), false, "Blizzard's window hidden")
  T.ok(AH.window:IsShown(), "ours shown")
  T.ok(not T.calledWith("CloseAuctionHouse"), "session still open")
  AH.window = old
end)

T.test("the swap waits a frame: hiding during Blizzard's own OnShow would close the AH", function()
  local old = AH.window
  AH.window = fakeWindow()
  AuctionFrame:Show()
  AH.OnShow()
  T.ok(AuctionFrame:IsShown(), "nothing happens in the event itself")
  AH.Tick()
  T.eq(AuctionFrame:IsShown(), false)
  AH.window = old
end)

T.test("closing our window ends the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  AH.window:Hide()
  T.ok(T.calledWith("CloseAuctionHouse"))
  AH.window = old
end)

T.test("switching to Blizzard's window and back keeps the session", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  AH.ShowBlizzard()
  T.ok(AuctionFrame:IsShown()) T.eq(AH.window:IsShown(), false)
  AH.ShowOurs()
  T.eq(AuctionFrame:IsShown(), false) T.ok(AH.window:IsShown())
  T.ok(not T.calledWith("CloseAuctionHouse"))
  AH.window = old
end)

T.test("leaving the auctioneer pauses a running scan and hides our window", function()
  local old = AH.window
  AH.window = fakeWindow()
  open()
  table.insert(WoW.ah.listings, { id = 1, name = "x", count = 1, buyout = 5 })
  Scan.StartFull(0)
  AH.OnClosed()
  T.eq(Scan.job, nil)
  T.ok(DB.Realm().scan.resume, "progress saved")
  T.eq(AH.window:IsShown(), false)
  T.eq(AH.open, false)
  AH.window = old
end)

T.test("with replacement off, Blizzard's window is left alone", function()
  local old = AH.window
  AH.window = fakeWindow()
  DB.S().replaceBlizzardAH = false
  open()
  T.ok(AuctionFrame:IsShown())
  T.eq(AH.window:IsShown(), false)
  AH.window = old
end)

T.test("Blizzard's window gets a button back to ours", function()
  AH.Hook()
  T.ok(TaxTheFoolsBackButton, "button exists")
  T.eq(AuctionFrameAuctions.page, 0, "seeded so Blizzard's owner-list handler doesn't throw")
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'AH' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/ahhook.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local DB = TaxTheFools.DB
local AH = { open = false, keepOpen = false, pending = false, hooked = false, switching = false, window = nil }
TaxTheFools.AH = AH

function AH.ResetState()
  AH.open, AH.keepOpen, AH.pending, AH.switching = false, false, false, false
end

-- Blizzard's AuctionFrame calls CloseAuctionHouse() from its OnHide, and every
-- query after that is silently ignored. So its OnHide is wrapped to do nothing
-- while we are holding the session open behind our own window.
function AH.Hook()
  if AH.hooked or not AuctionFrame then return end
  AH.hooked = true
  local orig = AuctionFrame:GetScript("OnHide")
  AuctionFrame:SetScript("OnHide", function()
    if AH.keepOpen then return end
    if orig then orig() end
  end)
  -- Blizzard's own AUCTION_OWNED_LIST_UPDATE handler indexes this page counter.
  if AuctionFrameAuctions and type(AuctionFrameAuctions.page) ~= "number" then AuctionFrameAuctions.page = 0 end
  local b = CreateFrame("Button", "TaxTheFoolsBackButton", AuctionFrame, "UIPanelButtonTemplate")
  b:SetWidth(110)
  b:SetHeight(20)
  b:SetText("Tax the Fools")
  b:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -40, -14)
  b:SetScript("OnClick", function() AH.ShowOurs() end)
end

function AH.OnShow()
  AH.open = true
  if DB.S().replaceBlizzardAH then
    AH.pending = true
  elseif AuctionFrame then
    AH.Hook()
  end
end

-- AuctionFrame is loaded on demand and shown by Blizzard's own handler for the
-- same event; hiding it before then (or from inside its OnShow) closes the AH.
-- So the swap happens on the next frame.
function AH.Tick()
  if not AH.pending then return end
  AH.pending = false
  if not AuctionFrame then return end
  AH.Hook()
  AH.ShowOurs()
end

function AH.ShowOurs()
  AH.keepOpen = true
  if AuctionFrame and AuctionFrame:IsShown() then HideUIPanel(AuctionFrame) end
  if AH.window then AH.window:Show() end
end

function AH.ShowBlizzard()
  AH.switching = true
  if AH.window then AH.window:Hide() end
  AH.switching = false
  AH.keepOpen = false
  if AuctionFrame then ShowUIPanel(AuctionFrame) end
end

-- Our window's OnHide: closing it ends the visit, unless we are only switching windows.
function AH.OnWindowHidden()
  if AH.switching then return end
  AH.keepOpen = false
  if AH.open then
    AH.open = false
    CloseAuctionHouse()
  end
end

function AH.OnClosed()
  AH.open, AH.keepOpen, AH.pending = false, false, false
  TaxTheFools.Scan.Pause("closed")
  if AH.window and AH.window:IsShown() then AH.window:Hide() end
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `items.lua`, `scan.lua`, `ahhook.lua`, `core.lua`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `67 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: swap Blizzard's auction window for ours without ending the session"
```

---

### Task 8: Textures, fonts and theme

**Files:**
- Create: `tools/make-media.py`, `tools/fetch-fonts.sh`, `TaxTheFools/theme.lua`
- Generated (committed): `TaxTheFools/media/*.tga`, `TaxTheFools/media/fonts/*.ttf`, `TaxTheFools/media/fonts/OFL-*.txt`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `theme.lua` after `ahhook.lua`)
- Test: `tests/test_theme.lua`

**Interfaces:**
- Consumes: `TaxTheFoolsDB.settings.fonts` (read defensively, because the theme can run before the DB exists).
- Produces:
  - Constants:
    - `Th.MEDIA`: the addon media path, with a trailing backslash.
    - `Th.TEXTURES`: the list of texture names.
    - `Th.FONTS[role]`, where role is `display`, `display2`, `body` or `body2`.
  - Themes and colours:
    - `Th.THEMES`, `Th.ORDER`, `Th.current`
    - `Th.color[token] -> {r,g,b}`
    - `Th.Apply(name)`, which re-tints every registered region.
  - Painting:
    - `Th.Tint(texture, token, alpha) -> texture` and `Th.Color(fontString, token, alpha) -> fontString`, both registered for re-theming.
    - `Th.Code(token) -> "|cffrrggbb"`.
  - Fonts and text:
    - `Th.SetFont(fontString, role, size, flags)`, which falls back to `STANDARD_TEXT_FONT`.
    - `Th.Text(parent, role, size, token, layer) -> fontString`.
  - Textures:
    - `Th.Solid(parent, layer, token, alpha) -> texture`.
    - `Th.NineSlice(frame, file, layer, token, alpha, cornerPx) -> parts`, keyed by `TOPLEFT`, `TOP`, …, `CENTER`.
    - `Th.TintSlice(parts, token, alpha)`.
    - `Th.Panel(frame, token)`, which sets `frame.fill` and `frame.edge`.

- [ ] **Step 1: Generate the textures**

`tools/make-media.py`:
```python
#!/usr/bin/env python3
"""Draw the addon's textures as white masks that the theme tints at run time.

The client only loads textures from an addon folder as TGA: 32 bit with alpha,
uncompressed, power-of-two sides. Anything else fails silently and looks like
a button that works but draws nothing, so every file is checked after writing.
Standard library only.
"""
import math
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "TaxTheFools", "media")
SS = 4  # supersamples per axis, for antialiased edges


def write_tga(path, w, h, alpha):
    # 18-byte header: uncompressed true colour (type 2), 32 bpp, 8 alpha bits,
    # bottom-left origin -- so rows are written bottom first.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            body += bytes((255, 255, 255, alpha(x, y)))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def coverage(inside):
    def alpha(x, y):
        hit = 0
        for i in range(SS):
            for j in range(SS):
                if inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                    hit += 1
        return round(255 * hit / (SS * SS))
    return alpha


def rrect(w, h, r):
    """Signed distance to a rounded rectangle covering [0,w] x [0,h]."""
    def sd(px, py):
        qx = abs(px - w / 2) - (w / 2 - r)
        qy = abs(py - h / 2) - (h / 2 - r)
        return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    return sd


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def strokes(segments, width):
    return lambda x, y: any(seg_dist(x, y, *s) <= width / 2 for s in segments)


def dots(points, radius):
    return lambda x, y: any(math.hypot(x - cx, y - cy) <= radius for cx, cy in points)


PANEL = rrect(32, 32, 10)
TAB = rrect(32, 32, 5)

# name: (width, height, inside(x, y)) with y measured from the top
SHAPES = {
    "solid": (8, 8, lambda x, y: True),
    "panel-fill": (32, 32, lambda x, y: PANEL(x, y) <= 0),
    "panel-border": (32, 32, lambda x, y: -1 <= PANEL(x, y) <= 0),
    "tab-fill": (32, 32, lambda x, y: TAB(x, y) <= 0),
    "tab-border": (32, 32, lambda x, y: -1 <= TAB(x, y) <= 0),
    "circle": (32, 32, lambda x, y: math.hypot(x - 16, y - 16) <= 15.5),
    "icon-close": (32, 32, strokes([(9, 9, 23, 23), (23, 9, 9, 23)], 3)),
    "icon-check": (32, 32, strokes([(8, 17, 14, 23), (14, 23, 24, 9)], 3)),
    "icon-caret-down": (32, 32, strokes([(9, 12, 16, 20), (16, 20, 23, 12)], 3)),
    "icon-caret-up": (32, 32, strokes([(9, 20, 16, 12), (16, 12, 23, 20)], 3)),
    "icon-arrow-left": (32, 32, strokes([(20, 8, 12, 16), (12, 16, 20, 24)], 3)),
    "icon-arrow-right": (32, 32, strokes([(12, 8, 20, 16), (20, 16, 12, 24)], 3)),
    "icon-grip": (16, 16, dots([(12, 4), (12, 8), (8, 8), (12, 12), (8, 12), (4, 12)], 1.3)),
}


def check(path, w, h):
    with open(path, "rb") as f:
        head = f.read(18)
    kind, bpp = head[2], head[16]
    pw, ph = struct.unpack("<HH", head[12:16])
    assert kind == 2, f"{path}: not uncompressed true colour (type {kind})"
    assert bpp == 32, f"{path}: not 32 bit ({bpp})"
    assert (pw, ph) == (w, h) and pw & (pw - 1) == 0 and ph & (ph - 1) == 0, f"{path}: bad size {pw}x{ph}"


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, inside) in SHAPES.items():
        path = os.path.join(OUT, name + ".tga")
        write_tga(path, w, h, coverage(inside))
        check(path, w, h)
        print(f"{name}.tga ok ({w}x{h})")


if __name__ == "__main__":
    main()
```

Run: `make media`
Expected: 13 lines such as `panel-fill.tga ok (32x32)`. No assertion errors.

- [ ] **Step 2: Fetch the fonts**

`tools/fetch-fonts.sh`:
```sh
#!/bin/sh
# Download the two OFL fonts the theme uses, as static TTFs (the 1.12 client
# cannot use variable fonts), plus their licences.
set -e
cd "$(dirname "$0")/.."
OUT=TaxTheFools/media/fonts
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GF=https://raw.githubusercontent.com/google/fonts/main/ofl/rajdhani
curl -fsSL -o "$OUT/Rajdhani-Bold.ttf" "$GF/Rajdhani-Bold.ttf"
curl -fsSL -o "$OUT/Rajdhani-SemiBold.ttf" "$GF/Rajdhani-SemiBold.ttf"
curl -fsSL -o "$OUT/OFL-Rajdhani.txt" "$GF/OFL.txt"

curl -fsSL -o "$TMP/inter.zip" https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip
unzip -q -o "$TMP/inter.zip" -d "$TMP/inter"
cp "$(find "$TMP/inter" -name 'Inter-Regular.ttf' | head -1)" "$OUT/Inter-Regular.ttf"
cp "$(find "$TMP/inter" -name 'Inter-SemiBold.ttf' | head -1)" "$OUT/Inter-SemiBold.ttf"
cp "$(find "$TMP/inter" -name 'LICENSE.txt' | head -1)" "$OUT/OFL-Inter.txt"

for f in "$OUT"/*.ttf; do
  magic=$(xxd -p -l 4 "$f")
  [ "$magic" = "00010000" ] || { echo "$f is not a TrueType font (magic $magic)" >&2; exit 1; }
  echo "$f ok"
done
```

Run: `make fonts`
Expected: four `... ok` lines. If a URL returns 404, find the file's current location:
- Rajdhani lives in `google/fonts` under `ofl/rajdhani/`.
- Inter's static TTFs are inside the `rsms/inter` v4.0 release zip under `extras/ttf/`.

Fix the URL and rerun. Don't substitute a variable font.

- [ ] **Step 3: Write the failing test**

`tests/test_theme.lua`:
```lua
local Th, DB = TaxTheFools.Theme, TaxTheFools.DB

T.test("switching theme re-colours what is already drawn", function()
  local t = Th.Solid(CreateFrame("Frame"), "ARTWORK", "accent")
  T.near(t.color[2], 0xc7 / 255, 0.005, "Pathfinder green")
  Th.Apply("Frost")
  T.near(t.color[1], 0x5b / 255, 0.005, "Frost blue")
  local fs = Th.Text(CreateFrame("Frame"), "body", 12, "accent")
  T.near(fs.color[3], 0xd6 / 255, 0.005, "text drawn later uses the current theme")
end)

T.test("an unknown theme falls back to Pathfinder", function()
  Th.Apply("Nope")
  T.eq(Th.current, "Pathfinder")
  T.near(Th.color.accent[1], 0x52 / 255, 0.005)
end)

T.test("chat colour codes come from the tokens", function()
  T.eq(Th.Code("accent"), "|cff52c722")
end)

T.test("bundled fonts are used when the client accepts them", function()
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.ok(string.find(fs.font, "Inter-Regular", 1, true), fs.font)
  Th.SetFont(fs, "display", 14)
  T.ok(string.find(fs.font, "Rajdhani-Bold", 1, true), fs.font)
end)

T.test("a font the client refuses falls back to the standard one", function()
  WoW.rejectFonts = true
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.eq(fs.font, STANDARD_TEXT_FONT)
end)

T.test("fonts switched off in options use the standard font", function()
  DB.S().fonts = false
  local fs = WoW.newFontString()
  Th.SetFont(fs, "body", 12)
  T.eq(fs.font, STANDARD_TEXT_FONT)
end)

T.test("nine-slice keeps corners at their size and cuts the texture at the corner", function()
  local parts = Th.NineSlice(CreateFrame("Frame"), "panel-fill", "BACKGROUND", "bg", 1, 10)
  local n = 0
  for _ in pairs(parts) do n = n + 1 end
  T.eq(n, 9)
  T.eq(parts.TOPLEFT.width, 10)
  T.eq(parts.TOPLEFT.coords[2], 10 / 32)
  T.eq(parts.CENTER.texture, Th.MEDIA .. "panel-fill")
end)

local function onDisk(path)
  local f = io.open((string.gsub(path, "\\", "/")), "rb")
  if f then f:close() return true end
  return false
end

T.test("every texture the theme names exists in the addon folder", function()
  for _, name in ipairs(Th.TEXTURES) do
    T.ok(onDisk("TaxTheFools/media/" .. name .. ".tga"), name .. ".tga missing: run make media")
  end
end)

T.test("every font the theme names exists in the addon folder", function()
  for _, file in pairs(Th.FONTS) do
    T.ok(onDisk("TaxTheFools/media/" .. file), file .. " missing: run make fonts")
  end
end)
```

- [ ] **Step 4: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'Th' (a nil value)`

- [ ] **Step 5: Implement**

`TaxTheFools/theme.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local Th = { color = {}, current = "Pathfinder" }
TaxTheFools.Theme = Th

-- The look of Aegis Pathfinder, rebuilt from scratch (its code is GPLv3):
-- flat dark panels, one accent colour, white-mask textures tinted at run time.
Th.MEDIA = "Interface\\AddOns\\TaxTheFools\\media\\"
Th.TEXTURES = { "solid", "panel-fill", "panel-border", "tab-fill", "tab-border", "circle",
  "icon-close", "icon-check", "icon-caret-down", "icon-caret-up", "icon-arrow-left", "icon-arrow-right", "icon-grip" }
Th.FONTS = {
  display = "fonts\\Rajdhani-Bold.ttf",
  display2 = "fonts\\Rajdhani-SemiBold.ttf",
  body = "fonts\\Inter-Regular.ttf",
  body2 = "fonts\\Inter-SemiBold.ttf",
}

Th.BASE = {
  bg = "202020", header = "111111", panel3 = "1a1a1a", strip = "3b3b3b", border = "050505", subtle = "545454",
  accent = "52c722", accentDeep = "2e850e", accentGlow = "8fe066",
  gold = "ffed71", text = "e6e6e6", white = "ffffff", dim = "c7c7bd",
  bad = "d9534f", good = "52c722", warn = "e0a030",
}
-- A theme only overrides the accent family; meaning colours (good/bad) stay put.
Th.THEMES = {
  Pathfinder = {},
  Frost = { accent = "5b9fd6", accentDeep = "2f6ea8", accentGlow = "9cc8ef" },
  Ember = { accent = "e0a030", accentDeep = "a8701a", accentGlow = "f2c46e" },
}
Th.ORDER = { "Pathfinder", "Frost", "Ember" }

-- Every tinted region, weakly held, so a theme change re-colours what is on screen.
Th.registry = setmetatable({}, { __mode = "k" })

local function hex(s)
  return { tonumber(string.sub(s, 1, 2), 16) / 255, tonumber(string.sub(s, 3, 4), 16) / 255,
           tonumber(string.sub(s, 5, 6), 16) / 255 }
end

function Th.paint(region, r)
  local c = Th.color[r.token] or Th.color.text
  if r.kind == "text" then region:SetTextColor(c[1], c[2], c[3], r.alpha)
  else region:SetVertexColor(c[1], c[2], c[3], r.alpha) end
end

function Th.Apply(name)
  if not Th.THEMES[name] then name = "Pathfinder" end
  local over = Th.THEMES[name]
  for k, v in pairs(Th.BASE) do Th.color[k] = hex(over[k] or v) end
  Th.current = name
  for region, r in pairs(Th.registry) do Th.paint(region, r) end
end

function Th.ResetState() Th.Apply("Pathfinder") end

function Th.Tint(tex, token, alpha)
  local r = { token = token, alpha = alpha or 1, kind = "tex" }
  Th.registry[tex] = r
  Th.paint(tex, r)
  return tex
end

function Th.Color(fs, token, alpha)
  local r = { token = token, alpha = alpha or 1, kind = "text" }
  Th.registry[fs] = r
  Th.paint(fs, r)
  return fs
end

function Th.Code(token)
  local c = Th.color[token] or Th.color.text
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
    math.floor(c[3] * 255 + 0.5))
end

-- SetFont returns nil when the client refuses a file; the stock font is the fallback.
function Th.SetFont(fs, role, size, flags)
  local s = TaxTheFoolsDB and TaxTheFoolsDB.settings
  local own = not s or s.fonts ~= false
  if own and fs:SetFont(Th.MEDIA .. (Th.FONTS[role] or Th.FONTS.body), size, flags) then return end
  fs:SetFont(STANDARD_TEXT_FONT, size, flags)
end

function Th.Text(parent, role, size, token, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  Th.SetFont(fs, role, size)
  Th.Color(fs, token or "text")
  fs:SetJustifyH("LEFT")
  return fs
end

function Th.Solid(parent, layer, token, alpha)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(Th.MEDIA .. "solid")
  return Th.Tint(t, token, alpha)
end

-- Nine pieces from one 32px mask: corners keep their size, edges and middle stretch.
local function pieces(c)
  return {
    { "TOPLEFT", 0, c, 0, c }, { "TOP", c, 1 - c, 0, c }, { "TOPRIGHT", 1 - c, 1, 0, c },
    { "LEFT", 0, c, c, 1 - c }, { "CENTER", c, 1 - c, c, 1 - c }, { "RIGHT", 1 - c, 1, c, 1 - c },
    { "BOTTOMLEFT", 0, c, 1 - c, 1 }, { "BOTTOM", c, 1 - c, 1 - c, 1 }, { "BOTTOMRIGHT", 1 - c, 1, 1 - c, 1 },
  }
end

function Th.NineSlice(frame, file, layer, token, alpha, corner)
  corner = corner or 10
  local parts = {}
  for _, p in ipairs(pieces(corner / 32)) do
    local t = frame:CreateTexture(nil, layer)
    t:SetTexture(Th.MEDIA .. file)
    t:SetTexCoord(p[2], p[3], p[4], p[5])
    Th.Tint(t, token, alpha)
    parts[p[1]] = t
  end
  local tl, tr, bl, br = parts.TOPLEFT, parts.TOPRIGHT, parts.BOTTOMLEFT, parts.BOTTOMRIGHT
  for _, c in ipairs({ tl, tr, bl, br }) do
    c:SetWidth(corner)
    c:SetHeight(corner)
  end
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT")
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
  parts.TOP:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  parts.TOP:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  parts.BOTTOM:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  parts.BOTTOM:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  parts.LEFT:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  parts.LEFT:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  parts.RIGHT:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  parts.RIGHT:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  parts.CENTER:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
  parts.CENTER:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  return parts
end

function Th.TintSlice(parts, token, alpha)
  for _, t in pairs(parts) do Th.Tint(t, token, alpha) end
end

function Th.Panel(frame, token)
  frame.fill = Th.NineSlice(frame, "panel-fill", "BACKGROUND", token or "bg", 1, 10)
  frame.edge = Th.NineSlice(frame, "panel-border", "BORDER", "border", 1, 10)
end

Th.Apply("Pathfinder")
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `items.lua`, `scan.lua`, `ahhook.lua`, `theme.lua`, `core.lua`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test`
Expected: `76 passed, 0 failed`

- [ ] **Step 7: Commit**

```bash
git add tools/make-media.py tools/fetch-fonts.sh TaxTheFools tests
git commit -m "feat: theme tokens, live re-theming, bundled fonts and generated textures"
```

---

### Task 9: Widgets and the virtual list

**Files:**
- Create: `TaxTheFools/widgets.lua`, `TaxTheFools/list.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `widgets.lua` and `list.lua` after `theme.lua`)
- Test: `tests/test_widgets.lua`, `tests/test_list.lua`

**Interfaces:**
- Consumes: `Th.*` (Task 8), `DB.S().scale`, `TaxTheFoolsCharDB.windows`.
- Produces:
  - Buttons: `W.Button(parent, label, w, h, onClick, style) -> button`.
    - `style` is `"accent"` or nil.
    - The button has `:SetLabel(text)`, `:SetEnabled(bool)`, `.label` and `.enabled`.
    - `onClick(button)` only runs while the button is enabled.
  - `W.IconButton(parent, iconName, size, onClick) -> button`.
  - Controls that have a `:Refresh()` method:
    - `W.Switch(parent, label, get, set, hint) -> frame`, with `.on`.
    - `W.Slider(parent, label, min, max, step, get, set, fmt) -> frame`, with `.slider`, `.value` and `.text`. The new value is committed on mouse-up, snapped to the step.
    - `W.Dropdown(parent, width, options, get, set) -> button`, with `.menu` and `.menu.items[i]`. `options` is a list of `{value=, label=}`.
  - `W.EditBox(parent, width, onEnter) -> editBox`.
  - `W.Progress(parent, height) -> frame`, with `:SetFraction(x)`, `.fraction` and `.bar`.
  - `W.TabStrip(parent, tabs, onSelect) -> frame`, with `:Select(key)`, `.selected`, `.buttons[key]` and `.buttons[key].line`.
  - Windows:
    - `W.Window(name, w, h, title, opts) -> frame`.
      - It has `.header`, `.close` and `.windowKey`.
      - It starts hidden, closes on Escape, and is draggable.
      - `opts.resizable`, `opts.minW` and `opts.minH` add a corner grip.
      - It calls `f.onResize()` after a resize, if that is a function.
    - `W.SavePosition(f)`, `W.RestorePosition(f)`, `W.ApplyScale()`.
  - Control tooltips:
    - `W.Tip(frame, title, body) -> frame`
    - `W.ShowTip(frame)`, `W.HideTip()`.
  - List helpers:
    - `L.Clamp(total, shown, offset) -> offset, max`
    - `L.Sort(rows, key, desc)`, which always puts nil values last.
  - The list itself, `L.New(parent, columns, rowHeight, onClick) -> list`:
    - Column format: `{ label=, width=, align="LEFT"|"RIGHT", sort=rowKey|nil, desc=bool, fmt=function(row) return text, token end }`.
    - Methods: `list:SetData(rows)`, `list:Paint()`, `list:Scroll(delta)`, `list:SortBy(col)`.
    - Fields: `.rows[i].cells[c]`, `.headers[c]`, `.selected`, `.offset`.
    - Hooks: `.onClick(item, mouseButton)` and `.onEnter(rowFrame, item)`.

- [ ] **Step 1: Write the failing tests**

`tests/test_widgets.lua`:
```lua
local W, DB = TaxTheFools.Widgets, TaxTheFools.DB

T.test("a switch flips its setting and shows the new state", function()
  local v = false
  local s = W.Switch(UIParent, "Thing", function() return v end, function(n) v = n end)
  T.eq(s.on, false)
  WoW.runScript(s, "OnClick")
  T.eq(v, true) T.eq(s.on, true)
end)

T.test("a slider only saves when the mouse is released, snapped to its step", function()
  local v = 0.3
  local s = W.Slider(UIParent, "Delay", 0, 2, 0.1, function() return v end, function(n) v = n end,
    function(x) return string.format("%.1fs", x) end)
  T.eq(s.value:GetText(), "0.3s")
  s.slider:SetValue(1.23)
  T.eq(v, 0.3, "dragging doesn't save")
  T.eq(s.value:GetText(), "1.2s", "but the label follows")
  WoW.runScript(s.slider, "OnMouseUp")
  T.near(v, 1.2, 0.0001)
end)

T.test("a dropdown sets the chosen value and shows its label", function()
  local v = "a"
  local d = W.Dropdown(UIParent, 120, { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
    function() return v end, function(n) v = n end)
  T.eq(d.label:GetText(), "Alpha")
  WoW.runScript(d, "OnClick")
  T.ok(d.menu:IsShown(), "menu opens")
  WoW.runScript(d.menu.items[2], "OnClick")
  T.eq(v, "b") T.eq(d.label:GetText(), "Beta") T.eq(d.menu:IsShown(), false)
end)

T.test("windows remember where they were left and close on Escape", function()
  local f = W.Window("TTFTestWinA", 300, 200, "Test")
  local listed = false
  for _, n in ipairs(UISpecialFrames) do if n == "TTFTestWinA" then listed = true end end
  T.ok(listed, "Escape closes it")
  T.eq(f:IsShown(), false, "starts hidden")
  f.left, f.top = 300, 400
  W.SavePosition(f)
  T.eq(TaxTheFoolsCharDB.windows.TTFTestWinA.x, 300)
  W.RestorePosition(f)
  local p = f.points[1]
  T.eq(p[1], "TOPLEFT") T.eq(p[3], "BOTTOMLEFT") T.eq(p[4], 300) T.eq(p[5], 400)
end)

T.test("the close button hides the window", function()
  local f = W.Window("TTFTestWinB", 300, 200, "Test")
  f:Show()
  WoW.runScript(f.close, "OnClick")
  T.eq(f:IsShown(), false)
end)

T.test("a disabled button ignores clicks and dims", function()
  local clicks = 0
  local b = W.Button(UIParent, "Go", 80, 22, function() clicks = clicks + 1 end)
  b:SetEnabled(false)
  WoW.runScript(b, "OnClick")
  T.eq(clicks, 0) T.eq(b.alpha, 0.45)
  b:SetEnabled(true)
  WoW.runScript(b, "OnClick")
  T.eq(clicks, 1)
end)

T.test("tabs mark the selected one and report it", function()
  local picked
  local s = W.TabStrip(UIParent, { { key = "a", label = "One" }, { key = "b", label = "Two" } },
    function(k) picked = k end)
  WoW.runScript(s.buttons.b, "OnClick")
  T.eq(picked, "b") T.eq(s.selected, "b")
  T.eq(s.buttons.b.line:IsShown(), true)
  T.eq(s.buttons.a.line:IsShown(), false)
end)

T.test("the progress bar's width follows the fraction", function()
  local p = W.Progress(UIParent, 8)
  p:SetWidth(102)
  p:SetFraction(0.5)
  T.eq(p.bar:GetWidth(), 50)
  p:SetFraction(0)
  T.eq(p.bar:IsShown(), false)
  p:SetFraction(3)
  T.eq(p.fraction, 1)
end)

T.test("window scale follows the setting", function()
  local f = W.Window("TTFTestWinC", 300, 200, "Test")
  DB.S().scale = 1.2
  W.ApplyScale()
  T.eq(f:GetScale(), 1.2)
end)
```

`tests/test_list.lua`:
```lua
local L = TaxTheFools.List

local COLS = { { label = "Name", width = 100, sort = "name", fmt = function(r) return r.name end } }

T.test("clamp keeps the visible window inside the data", function()
  T.eq(L.Clamp(10, 4, 8), 6)
  T.eq(L.Clamp(3, 4, 2), 0)
  T.eq(L.Clamp(10, 4, -1), 0)
end)

T.test("sorting puts missing values last whichever way", function()
  local rows = { { v = 2 }, {}, { v = 1 } }
  L.Sort(rows, "v", false)
  T.eq(rows[1].v, 1) T.eq(rows[3].v, nil)
  L.Sort(rows, "v", true)
  T.eq(rows[1].v, 2) T.eq(rows[3].v, nil)
end)

T.test("a list draws only the rows that fit and scrolls", function()
  local l = L.New(UIParent, COLS, 18)
  l:SetHeight(20 + 18 * 3)
  l:SetData({ { name = "a" }, { name = "b" }, { name = "c" }, { name = "d" }, { name = "e" } })
  T.eq(l.rows[1].cells[1]:GetText(), "a")
  T.eq(l.rows[4], nil, "only three rows built")
  l:Scroll(5)
  T.eq(l.offset, 2)
  T.eq(l.rows[1].cells[1]:GetText(), "c")
end)

T.test("clicking a header sorts, and clicking again reverses", function()
  local l = L.New(UIParent, COLS, 18)
  l:SetHeight(20 + 18 * 3)
  l:SetData({ { name = "b" }, { name = "a" }, { name = "c" } })
  WoW.runScript(l.headers[1], "OnClick")
  T.eq(l.rows[1].cells[1]:GetText(), "a")
  WoW.runScript(l.headers[1], "OnClick")
  T.eq(l.rows[1].cells[1]:GetText(), "c")
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `make test`
Expected: FAIL, `attempt to index local 'W' (a nil value)` and `attempt to index local 'L' (a nil value)`

- [ ] **Step 3: Implement the widgets**

`TaxTheFools/widgets.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local Th, DB = TaxTheFools.Theme, TaxTheFools.DB
local W = { windows = {} }
TaxTheFools.Widgets = W

function W.Tip(f, title, body)
  f.tip = { title = title, body = body }
  return f
end

function W.ShowTip(f)
  if type(f.tip) ~= "table" then return end
  GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
  GameTooltip:SetText(f.tip.title, 1, 1, 1)
  if f.tip.body then GameTooltip:AddLine(f.tip.body, 0.78, 0.78, 0.74, 1) end
  GameTooltip:Show()
end

function W.HideTip() GameTooltip:Hide() end

function W.Button(parent, label, width, height, onClick, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width)
  b:SetHeight(height or 22)
  local base = (style == "accent") and "accentDeep" or "strip"
  local over = (style == "accent") and "accent" or "subtle"
  b.fill = Th.NineSlice(b, "tab-fill", "BACKGROUND", base, 1, 6)
  b.edge = Th.NineSlice(b, "tab-border", "BORDER", "border", 1, 6)
  b.label = Th.Text(b, "display", 11, "white")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetJustifyH("CENTER")
  b.enabled = true
  b.SetLabel = function(self, t) self.label:SetText(string.upper(t or "")) end
  b.SetEnabled = function(self, on)
    self.enabled = on and true or false
    self:SetAlpha(on and 1 or 0.45)
  end
  b:SetLabel(label)
  b:SetScript("OnEnter", function()
    if this.enabled then Th.TintSlice(this.fill, over, 1) end
    W.ShowTip(this)
  end)
  b:SetScript("OnLeave", function()
    Th.TintSlice(this.fill, base, 1)
    W.HideTip()
  end)
  b:SetScript("OnClick", function()
    if this.enabled and onClick then onClick(this) end
  end)
  return b
end

function W.IconButton(parent, icon, size, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size)
  b:SetHeight(size)
  b.fill = Th.NineSlice(b, "tab-fill", "BACKGROUND", "white", 0.04, 6)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(Th.MEDIA .. icon)
  b.icon:SetWidth(size * 0.6)
  b.icon:SetHeight(size * 0.6)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  Th.Tint(b.icon, "dim")
  b:SetScript("OnEnter", function()
    Th.TintSlice(this.fill, "white", 0.1)
    Th.Tint(this.icon, "white")
    W.ShowTip(this)
  end)
  b:SetScript("OnLeave", function()
    Th.TintSlice(this.fill, "white", 0.04)
    Th.Tint(this.icon, "dim")
    W.HideTip()
  end)
  b:SetScript("OnClick", function() onClick(this) end)
  return b
end

function W.Switch(parent, label, get, set, hint)
  local f = CreateFrame("Button", nil, parent)
  f:SetWidth(320)
  f:SetHeight(24)
  f.locked, f.on = false, false
  f.track = CreateFrame("Frame", nil, f)
  f.track:SetWidth(30)
  f.track:SetHeight(16)
  f.track:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.trackFill = Th.NineSlice(f.track, "tab-fill", "BACKGROUND", "strip", 1, 6)
  f.knob = f.track:CreateTexture(nil, "ARTWORK")
  f.knob:SetTexture(Th.MEDIA .. "circle")
  f.knob:SetWidth(12)
  f.knob:SetHeight(12)
  Th.Tint(f.knob, "white")
  f.text = Th.Text(f, "body", 13, "text")
  f.text:SetPoint("LEFT", f.track, "RIGHT", 8, 0)
  f.text:SetText(label)
  f.Refresh = function(self)
    self.on = get() and true or false
    Th.TintSlice(self.trackFill, self.on and "accentDeep" or "strip", 1)
    self.knob:ClearAllPoints()
    if self.on then self.knob:SetPoint("RIGHT", self.track, "RIGHT", -2, 0)
    else self.knob:SetPoint("LEFT", self.track, "LEFT", 2, 0) end
  end
  f:SetScript("OnClick", function()
    if this.locked then return end
    set(not this.on)
    this:Refresh()
  end)
  if hint then
    W.Tip(f, label, hint)
    f:SetScript("OnEnter", function() W.ShowTip(this) end)
    f:SetScript("OnLeave", function() W.HideTip() end)
  end
  f:Refresh()
  return f
end

function W.Slider(parent, label, min, max, step, get, set, fmt)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(320)
  f:SetHeight(38)
  f.text = Th.Text(f, "body", 13, "text")
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.text:SetText(label)
  f.value = Th.Text(f, "body2", 12, "gold")
  f.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.value:SetJustifyH("RIGHT")
  local s = CreateFrame("Slider", nil, f)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(12)
  s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
  s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
  s.track = Th.NineSlice(s, "tab-fill", "BACKGROUND", "strip", 1, 6)
  s:SetThumbTexture(Th.MEDIA .. "circle")
  local thumb = s:GetThumbTexture()
  thumb:SetWidth(14)
  thumb:SetHeight(14)
  Th.Tint(thumb, "accent")
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  local function snap(v) return math.floor(v / step + 0.5) * step end
  local function show(v) f.value:SetText(fmt and fmt(snap(v)) or tostring(snap(v))) end
  s:SetScript("OnValueChanged", function() show(this:GetValue()) end)
  -- Saving on release, not on every step of a drag, keeps the scan and the
  -- windows from reacting to values the player is only passing through.
  s:SetScript("OnMouseUp", function() set(snap(this:GetValue())) end)
  f.slider = s
  f.Refresh = function(self)
    local v = get()
    s:SetValue(v)
    show(v)
  end
  f:Refresh()
  return f
end

function W.Dropdown(parent, width, options, get, set)
  local menu
  local b = W.Button(parent, "", width, 22, function(self)
    if menu:IsShown() then menu:Hide() return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end)
  Th.SetFont(b.label, "body", 12)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.label:SetJustifyH("LEFT")
  b.SetLabel = function(self, t) self.label:SetText(t or "") end
  b.caret = b:CreateTexture(nil, "OVERLAY")
  b.caret:SetTexture(Th.MEDIA .. "icon-caret-down")
  b.caret:SetWidth(12)
  b.caret:SetHeight(12)
  b.caret:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  Th.Tint(b.caret, "dim")
  -- The list sits on the top layer of UIParent so no scroll frame can clip it.
  menu = CreateFrame("Frame", nil, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetWidth(width)
  menu:SetHeight(8 + table.getn(options) * 20)
  Th.Panel(menu, "header")
  menu.items = {}
  for i, o in ipairs(options) do
    menu.items[i] = W.MenuItem(menu, i, o, function(value)
      set(value)
      menu:Hide()
      b:Refresh()
    end)
  end
  menu:Hide()
  b.menu = menu
  b:SetScript("OnHide", function() menu:Hide() end)
  b.Refresh = function(self)
    local v = get()
    for _, o in ipairs(options) do
      if o.value == v then self:SetLabel(o.label) end
    end
  end
  b:Refresh()
  return b
end

function W.MenuItem(menu, i, option, choose)
  local item = CreateFrame("Button", nil, menu)
  item:SetHeight(20)
  item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
  item:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
  local hl = item:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(item)
  hl:SetVertexColor(1, 1, 1, 0.06)
  item.text = Th.Text(item, "body", 12, "text")
  item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
  item.text:SetText(option.label)
  item.value = option.value
  item:SetScript("OnClick", function() choose(this.value) end)
  return item
end

function W.EditBox(parent, width, onEnter)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetWidth(width)
  e:SetHeight(22)
  e:SetAutoFocus(false)
  e.fill = Th.NineSlice(e, "tab-fill", "BACKGROUND", "header", 1, 6)
  e.edge = Th.NineSlice(e, "tab-border", "BORDER", "subtle", 1, 6)
  Th.SetFont(e, "body", 12)
  Th.Color(e, "text")
  e:SetTextInsets(6, 6, 0, 0)
  e:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    if onEnter then onEnter(this:GetText()) end
  end)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  return e
end

function W.Progress(parent, height)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(height or 8)
  f.track = Th.Solid(f, "BACKGROUND", "panel3")
  f.track:SetAllPoints(f)
  f.bar = Th.Solid(f, "ARTWORK", "accent")
  f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  f.fraction = 0
  f.SetFraction = function(self, x)
    x = math.max(0, math.min(1, x or 0))
    self.fraction = x
    local w = (self:GetWidth() - 2) * x
    if w < 1 then self.bar:Hide()
    else
      self.bar:Show()
      self.bar:SetWidth(w)
    end
  end
  f:SetFraction(0)
  return f
end

function W.TabStrip(parent, tabs, onSelect)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(28)
  strip.bg = Th.Solid(strip, "BACKGROUND", "panel3")
  strip.bg:SetAllPoints(strip)
  strip.buttons, strip.selected = {}, false
  local x = 8
  for _, t in ipairs(tabs) do
    local b = W.Tab(strip, t)
    b:SetPoint("LEFT", strip, "LEFT", x, 0)
    x = x + b:GetWidth()
    strip.buttons[t.key] = b
  end
  strip.Select = function(self, key)
    self.selected = key
    for k, b in pairs(self.buttons) do
      Th.Color(b.text, (k == key) and "white" or "dim")
      if k == key then b.line:Show() else b.line:Hide() end
    end
    onSelect(key)
  end
  return strip
end

function W.Tab(strip, t)
  local b = CreateFrame("Button", nil, strip)
  b:SetHeight(28)
  b.text = Th.Text(b, "display", 13, "dim")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text:SetText(string.upper(t.label))
  b:SetWidth(b.text:GetStringWidth() + 24)
  b.line = Th.Solid(b, "ARTWORK", "accent")
  b.line:SetHeight(2)
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 0)
  b.line:Hide()
  b.key = t.key
  b:SetScript("OnClick", function() strip:Select(this.key) end)
  return b
end

-- Windows are re-pinned by their top-left corner after a drag: left to itself
-- the client re-anchors by whichever corner it likes, and the saved spot drifts.
function W.SavePosition(f)
  local x, y = f:GetLeft(), f:GetTop()
  if not x or not y then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  local p = TaxTheFoolsCharDB.windows[f.windowKey] or {}
  p.x, p.y, p.w, p.h = x, y, f:GetWidth(), f:GetHeight()
  TaxTheFoolsCharDB.windows[f.windowKey] = p
end

function W.RestorePosition(f)
  local p = TaxTheFoolsCharDB.windows[f.windowKey]
  f:ClearAllPoints()
  if p and p.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    if p.w and p.h then
      f:SetWidth(p.w)
      f:SetHeight(p.h)
    end
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

function W.ApplyScale()
  local s = DB.S().scale or 1
  for _, f in ipairs(W.windows) do f:SetScale(s) end
end

function W.Grip(f, minW, minH)
  f:SetResizable(true)
  f:SetMinResize(minW, minH)
  local g = CreateFrame("Button", nil, f)
  g:SetWidth(16)
  g:SetHeight(16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  local t = g:CreateTexture(nil, "OVERLAY")
  t:SetTexture(Th.MEDIA .. "icon-grip")
  t:SetAllPoints(g)
  Th.Tint(t, "subtle")
  g:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  -- 1.12 has no size-changed event: lay out again once the drag ends.
  g:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    W.SavePosition(f)
    if type(f.onResize) == "function" then f.onResize() end
  end)
  f.grip = g
end

function W.Window(name, width, height, title, opts)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetWidth(width)
  f:SetHeight(height)
  f:SetMovable(true)
  f:EnableMouse(true)
  f.windowKey = name
  Th.Panel(f, "bg")
  local h = CreateFrame("Frame", nil, f)
  h:SetHeight(30)
  h:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  h.fill = Th.NineSlice(h, "panel-fill", "BACKGROUND", "header", 1, 10)
  -- squares off the header's bottom corners so it meets the body cleanly
  h.square = Th.Solid(h, "BACKGROUND", "header")
  h.square:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
  h.square:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
  h.square:SetHeight(12)
  h.title = Th.Text(h, "display", 14, "white")
  h.title:SetPoint("LEFT", h, "LEFT", 12, 0)
  h.title:SetText(string.upper(title))
  h:EnableMouse(true)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() f:StartMoving() end)
  h:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    W.SavePosition(f)
  end)
  f.header = h
  f.close = W.IconButton(h, "icon-close", 20, function() f:Hide() end)
  f.close:SetPoint("RIGHT", h, "RIGHT", -6, 0)
  local line = Th.Solid(f, "ARTWORK", "border")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, 0)
  table.insert(UISpecialFrames, name)
  table.insert(W.windows, f)
  f:SetScale(DB.S().scale or 1)
  W.RestorePosition(f)
  if opts and opts.resizable then W.Grip(f, opts.minW or width, opts.minH or height) end
  f:Hide()
  return f
end
```

- [ ] **Step 4: Implement the list**

`TaxTheFools/list.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local Th = TaxTheFools.Theme
local L = {}
TaxTheFools.List = L

local HEAD = 20
local BAR = 12

-- Which slice of total rows to draw in `shown` slots.
function L.Clamp(total, shown, offset)
  local max = total - shown
  if max < 0 then max = 0 end
  if offset < 0 then offset = 0 end
  if offset > max then offset = max end
  return offset, max
end

-- Missing values sink to the bottom in both directions: "no market price" is
-- never the most interesting row.
function L.Sort(rows, key, desc)
  table.sort(rows, function(a, b)
    local x, y = a[key], b[key]
    if x == nil then return false end
    if y == nil then return true end
    if x == y then return false end
    if desc then return x > y end
    return x < y
  end)
end

local M = {}

function M:SetData(data)
  self.data = data or {}
  self.selected = false
  if self.sortCol then L.Sort(self.data, self.sortCol.sort, self.sortDesc) end
  self:Paint()
end

function M:SortBy(col)
  if not col.sort then return end
  if self.sortCol == col then self.sortDesc = not self.sortDesc
  else self.sortCol, self.sortDesc = col, col.desc or false end
  L.Sort(self.data, col.sort, self.sortDesc)
  self:Paint()
end

function M:Scroll(delta)
  self.offset = self.offset + delta
  self:Paint()
end

function M:Slots()
  return math.max(1, math.floor((self:GetHeight() - HEAD) / self.rowHeight))
end

function M:Row(i)
  if self.rows[i] then return self.rows[i] end
  local list = self
  local r = CreateFrame("Button", nil, self)
  r:SetHeight(self.rowHeight)
  r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -HEAD - (i - 1) * self.rowHeight)
  r:SetPoint("RIGHT", self, "RIGHT", -BAR, 0)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(r)
  hl:SetVertexColor(1, 1, 1, 0.05)
  r.sel = Th.Solid(r, "BACKGROUND", "strip")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.cells = {}
  local x = 0
  for c, col in ipairs(self.columns) do
    local fs = Th.Text(r, "body", 11, "text")
    fs:SetPoint("LEFT", r, "LEFT", x + 6, 0)
    fs:SetWidth(col.width - 12)
    fs:SetJustifyH(col.align or "LEFT")
    r.cells[c] = fs
    x = x + col.width
  end
  r.item = false
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function()
    if not this.item then return end
    list.selected = this.item
    list:Paint()
    if type(list.onClick) == "function" then list.onClick(this.item, arg1) end
  end)
  r:SetScript("OnEnter", function()
    if this.item and type(list.onEnter) == "function" then list.onEnter(this, this.item) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.rows[i] = r
  return r
end

function M:Paint()
  local shown = self:Slots()
  local offset, max = L.Clamp(table.getn(self.data), shown, self.offset)
  self.offset = offset
  self.updating = true
  self.bar:SetMinMaxValues(0, max)
  self.bar:SetValue(offset)
  self.updating = false
  if max == 0 then self.bar:Hide() else self.bar:Show() end
  for i = 1, shown do
    local r = self:Row(i)
    local item = self.data[i + offset]
    if item then
      r.item = item
      for c, col in ipairs(self.columns) do
        local text, token = col.fmt(item)
        r.cells[c]:SetText(text or "")
        Th.Color(r.cells[c], token or "text")
      end
      if item == self.selected then r.sel:Show() else r.sel:Hide() end
      r:Show()
    else
      r.item = false
      r:Hide()
    end
  end
  for i = shown + 1, table.getn(self.rows) do self.rows[i]:Hide() end
end

function L.Header(list, c, col, x)
  local b = CreateFrame("Button", nil, list.head)
  b:SetHeight(HEAD)
  b:SetWidth(col.width)
  b:SetPoint("LEFT", list.head, "LEFT", x, 0)
  b.text = Th.Text(b, "display", 11, "dim")
  b.text:SetText(string.upper(col.label))
  b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.text:SetJustifyH(col.align or "LEFT")
  b.col = col
  b:SetScript("OnClick", function() list:SortBy(this.col) end)
  return b
end

function L.New(parent, columns, rowHeight, onClick)
  local f = CreateFrame("Frame", nil, parent)
  for k, v in pairs(M) do f[k] = v end
  f.columns, f.rowHeight, f.rows, f.data, f.offset = columns, rowHeight or 18, {}, {}, 0
  f.onClick, f.onEnter, f.selected, f.updating = onClick or false, false, false, false
  f.sortCol, f.sortDesc = false, false
  f.head = CreateFrame("Frame", nil, f)
  f.head:SetHeight(HEAD)
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -BAR, 0)
  local hb = Th.Solid(f.head, "BACKGROUND", "strip")
  hb:SetAllPoints(f.head)
  f.headers = {}
  local x = 0
  for c, col in ipairs(columns) do
    f.headers[c] = L.Header(f, c, col, x)
    x = x + col.width
  end
  local bar = CreateFrame("Slider", nil, f)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(10)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local track = Th.Solid(bar, "BACKGROUND", "panel3")
  track:SetAllPoints(bar)
  bar:SetThumbTexture(Th.MEDIA .. "solid")
  local thumb = bar:GetThumbTexture()
  thumb:SetWidth(10)
  thumb:SetHeight(30)
  Th.Tint(thumb, "subtle")
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetScript("OnValueChanged", function()
    if f.updating then return end
    f.offset = math.floor(this:GetValue() + 0.5)
    f:Paint()
  end)
  f.bar = bar
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function() f:Scroll(-arg1 * 3) end)
  return f
end
```

The `.toc` file list becomes: `data.lua`, `util.lua`, `stats.lua`, `price.lua`, `db.lua`, `items.lua`, `scan.lua`, `ahhook.lua`, `theme.lua`, `widgets.lua`, `list.lua`, `core.lua`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `89 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: themed widget kit, windows with saved positions, virtual sortable list"
```

---

### Task 10: Prices in item tooltips

**Files:**
- Create: `TaxTheFools/tooltip.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `tooltip.lua` after `list.lua`)
- Test: `tests/test_tooltip.lua`

**Interfaces:**
- Consumes:
  - `DB.S().tooltip`, `DB.Realm().market`
  - `I.Vendor`, `I.Resolve`
  - `P.ConfLabel`
  - `U.money`, `U.day`, `U.daysAgo`, `U.keyFromLink`, `U.keyId`
  - `Th.Code`
- Produces:
  - `Tip.Lines(key, count, now) -> { {left, right}, ... }`
  - `Tip.Add(tooltip, link, count)`
  - `Tip.Hook()`, which is idempotent and wraps the GameTooltip `Set*` methods while keeping their return values.

- [ ] **Step 1: Write the failing test**

`tests/test_tooltip.lua`:
```lua
local Tip, DB, I = TaxTheFools.Tooltip, TaxTheFools.DB, TaxTheFools.Items

local function seed()
  I.Remember(14047, "Runecloth", 1, 20)
  TaxTheFoolsDB.items[14047].v = 100
  DB.Realm().market["14047:0"] = { v = 400, conf = 0.8, low = 380, lowDay = 20374, seen = 6 }
end

T.test("lines show market with confidence, the latest low and the vendor price", function()
  seed()
  local lines = Tip.Lines("14047:0", 1, WoW.now)
  T.eq(lines[1][1], "Market")
  T.ok(string.find(lines[1][2], "4s", 1, true), lines[1][2])
  T.ok(string.find(lines[1][2], "high", 1, true), "confidence named")
  T.eq(lines[2][1], "Low now")
  T.ok(string.find(lines[2][2], "1d ago", 1, true), lines[2][2])
  T.eq(lines[3][1], "Vendor")
end)

T.test("shift multiplies by the stack", function()
  seed()
  WoW.shift = true
  local lines = Tip.Lines("14047:0", 20, WoW.now)
  T.eq(lines[1][1], "Market x20")
  T.ok(string.find(lines[1][2], "80s", 1, true), lines[1][2])
end)

T.test("an item with no prices says so rather than failing", function()
  local lines = Tip.Lines("5000:0", 1, WoW.now)
  T.eq(lines[1][1], "Market")
  T.ok(string.find(lines[1][2], "no data", 1, true))
  T.eq(table.getn(lines), 1)
end)

T.test("lines switched off in options are left out", function()
  seed()
  DB.S().tooltip.vendor = false
  DB.S().tooltip.low = false
  T.eq(table.getn(Tip.Lines("14047:0", 1, WoW.now)), 1)
end)

T.test("hovering a bag item adds the prices and keeps the original return", function()
  seed()
  WoW.bags[0] = { { id = 14047, name = "Runecloth", count = 20 } }
  Tip.Hook()
  Tip.Hook()                                  -- hooking twice must not add lines twice
  local r = GameTooltip:SetBagItem(0, 1)
  T.eq(r, "orig-bag")
  T.eq(GameTooltip.lines[1][1], "Market")
  T.eq(table.getn(GameTooltip.lines), 3)
end)

T.test("hovering an item teaches the cache its name", function()
  WoW.items[4306] = { name = "Silk Cloth", stack = 20 }
  Tip.Hook()
  GameTooltip:SetHyperlink("item:4306:0:0:0")
  T.eq(TaxTheFoolsDB.items[4306].n, "Silk Cloth")
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'Tip' (a nil value)`

- [ ] **Step 3: Implement**

`TaxTheFools/tooltip.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, DB, I, P, Th = TaxTheFools.Util, TaxTheFools.DB, TaxTheFools.Items, TaxTheFools.Price, TaxTheFools.Theme
local Tip = { hooked = false }
TaxTheFools.Tooltip = Tip

local CONF_TOKEN = { high = "good", medium = "warn", low = "bad" }

function Tip.Lines(key, count, now)
  local s = DB.S().tooltip
  local m = DB.Realm().market[key]
  local lines = {}
  count = (count and count > 1) and count or 1
  local mult = (IsShiftKeyDown() and count > 1) and count or 1
  local suffix = (mult > 1) and (" x" .. mult) or ""
  if s.market then
    if m and m.v then
      local label = P.ConfLabel(m.conf or 0)
      table.insert(lines, { "Market" .. suffix, U.money(m.v * mult) .. " " .. Th.Code(CONF_TOKEN[label]) .. "(" .. label .. ")|r" })
    else
      table.insert(lines, { "Market", "|cff888888no data|r" })
    end
  end
  if s.low and m and m.low and m.lowDay then
    table.insert(lines, { "Low now" .. suffix, U.money(m.low * mult) .. "  " .. U.daysAgo(U.day(now) - m.lowDay) })
  end
  if s.vendor then
    local v = I.Vendor(U.keyId(key))
    if v then table.insert(lines, { "Vendor" .. suffix, U.money(v * mult) }) end
  end
  return lines
end

function Tip.Add(tt, link, count)
  if not link or not TaxTheFoolsDB then return end
  local key, id = U.keyFromLink(link)
  if not key then return end
  I.Resolve(id)
  local lines = Tip.Lines(key, count, time())
  for _, l in ipairs(lines) do tt:AddDoubleLine(l[1], l[2], 0.78, 0.78, 0.74, 1, 1, 1) end
  if table.getn(lines) > 0 then tt:Show() end
end

-- Where each tooltip method's item comes from. The originals' return values
-- (SetBagItem returns cooldown and repair cost) are passed straight back.
Tip.SOURCES = {
  SetBagItem = function(bag, slot)
    local _, count = GetContainerItemInfo(bag, slot)
    return GetContainerItemLink(bag, slot), count
  end,
  SetInventoryItem = function(unit, slot) return GetInventoryItemLink(unit, slot), GetInventoryItemCount(unit, slot) end,
  SetAuctionItem = function(kind, i)
    local _, _, count = GetAuctionItemInfo(kind, i)
    return GetAuctionItemLink(kind, i), count
  end,
  SetMerchantItem = function(i)
    local _, _, _, qty = GetMerchantItemInfo(i)
    return GetMerchantItemLink(i), qty
  end,
  SetLootItem = function(i)
    local _, _, qty = GetLootSlotInfo(i)
    return GetLootSlotLink(i), qty
  end,
  SetTradeSkillItem = function(skill, reagent)
    if reagent then
      local _, _, count = GetTradeSkillReagentInfo(skill, reagent)
      return GetTradeSkillReagentItemLink(skill, reagent), count
    end
    return GetTradeSkillItemLink(skill), 1
  end,
  SetHyperlink = function(link) return link, 1 end,
}

local function wrap(name, source)
  local orig = GameTooltip[name]
  if type(orig) ~= "function" then return end
  GameTooltip[name] = function(self, a1, a2, a3)
    local r1, r2, r3 = orig(self, a1, a2, a3)
    local ok, err = pcall(function()
      local link, count = source(a1, a2, a3)
      Tip.Add(self, link, count)
    end)
    if not ok then U.debug("tooltip: " .. tostring(err)) end
    return r1, r2, r3
  end
end

function Tip.Hook()
  if Tip.hooked then return end
  Tip.hooked = true
  for name, source in pairs(Tip.SOURCES) do wrap(name, source) end
end
```

`wrap` is called with `name, source` as parameters, so its closures capture parameters, not loop variables. That follows the Global Constraints.

The `.toc` file list becomes: … `list.lua`, `tooltip.lua`, `core.lua`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `95 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: market, low and vendor prices in item tooltips"
```

---

### Task 11: The auction window and the Browse tab

**Files:**
- Create: `TaxTheFools/ui_window.lua`, `TaxTheFools/ui_browse.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add both after `tooltip.lua`)
- Test: `tests/test_ui.lua`

**Interfaces:**
- Consumes:
  - `W.*` and `L.New` (Task 9), `Th.*`
  - `Scan.*` (Task 6), `AH.*` (Task 7)
  - `DB.Realm().market`, `DB.Realm().watch`, `DB.Realm().scan.lastFull`
  - `U.money`, `U.quality`, `U.linkString`
- Produces:
  - Window and page registry:
    - `UI.CreateAH() -> frame`. It is idempotent, sets `AH.window`, and has `.gold`, `.tabs`, `.status` and `.body`.
    - `UI.TABS`, `UI.builders[key] = function(parent) -> page`, `UI.pages[key]`, `UI.ShowPage(key)`.
  - `UI.Duration(seconds) -> string`, giving `"45s"`, `"22m"`, `"1h 5m"` or `"1d 1h"`.
  - `UI.Describe(progress, resume, lastFull, now) -> { text, fraction, pause = false|"Pause"|"Resume", discard = bool, canStart = bool }`.
  - `UI.RefreshStatus()`, `UI.RefreshGold()`, `UI.StartScan(kind)`, `UI.PauseOrResume()`, `UI.Tick(now)`.
  - Browse:
    - `Browse.Build(parent)`, `Browse.Search(text, page) -> bool`, `Browse.Paint()`
    - `Browse.Decorate(rows, market) -> rows`, which adds `market`, `pct`, `bidNow` and `buy` to each row
    - `Browse.PctToken(pct) -> token`
    - `Browse.ToggleWatch()`, `Browse.UpdateWatchButton()`
    - `Browse.frame`, which has `.list`, `.pageText` and `.watchBtn`.

- [ ] **Step 1: Write the failing test**

`tests/test_ui.lua`:
```lua
local UI, Browse, AH, Scan, DB = TaxTheFools.UI, TaxTheFools.Browse, TaxTheFools.AH, TaxTheFools.Scan, TaxTheFools.DB

local function openAH()
  UI.CreateAH()
  AH.switching = true
  UI.ah:Hide()
  AH.switching = false
  AH.open = true
  AH.ShowOurs()
end

local function answer()
  for _ = 1, 20 do
    WoW.clock = WoW.clock + 0.5
    Scan.Tick(WoW.clock)
    if WoW.ah.pending then
      WoW.ahRespond()
      Scan.OnListUpdate(WoW.clock)
    end
    if not Scan.job then return end
  end
end

T.test("durations read naturally", function()
  T.eq(UI.Duration(45), "45s")
  T.eq(UI.Duration(1320), "22m")
  T.eq(UI.Duration(3900), "1h 5m")
  T.eq(UI.Duration(90000), "1d 1h")
end)

T.test("an idle strip says when the last full scan ran", function()
  local d = UI.Describe(nil, nil, nil, WoW.now)
  T.ok(string.find(d.text, "No full scan yet", 1, true), d.text)
  T.ok(d.canStart) T.eq(d.pause, false)
  d = UI.Describe(nil, nil, WoW.now - 7200, WoW.now)
  T.eq(d.text, "Last full scan 2h 0m ago")
end)

T.test("a running full scan shows the page, pace and time left", function()
  local d = UI.Describe({ kind = "full", state = "wait", page = 2, totalPages = 10, qi = 1, nq = 1, listings = 100,
    safe = false, secsPerPage = 5, eta = 40 }, nil, nil, WoW.now)
  T.ok(string.find(d.text, "page 3/10", 1, true), d.text)
  T.ok(string.find(d.text, "5.0s/page", 1, true), d.text)
  T.ok(string.find(d.text, "~40s left", 1, true), d.text)
  T.eq(d.pause, "Pause") T.eq(d.canStart, false)
  T.near(d.fraction, 0.2, 0.001)
end)

T.test("a stalled scan offers to try again", function()
  local d = UI.Describe({ kind = "watch", state = "stalled", page = 0, qi = 2, nq = 5, listings = 0, safe = false },
    nil, nil, WoW.now)
  T.ok(string.find(d.text, "server not responding", 1, true), d.text)
  T.eq(d.pause, "Resume")
end)

T.test("a paused scan offers resume or discard", function()
  local d = UI.Describe(nil, { kind = "full", page = 4, rows = { "a", "b" } }, nil, WoW.now)
  T.ok(string.find(d.text, "page 5", 1, true), d.text)
  T.eq(d.pause, "Resume") T.ok(d.discard) T.eq(d.canStart, false)
end)

T.test("browse rows get market value and percent of market", function()
  DB.Realm().market["1:0"] = { v = 400 }
  local rows = Browse.Decorate({ { key = "1:0", unit = 300 }, { key = "2:0", unit = 5 }, { key = "1:0" } }, DB.Realm().market)
  T.eq(rows[1].pct, 75) T.eq(rows[2].pct, nil) T.eq(rows[3].pct, nil)
  T.eq(Browse.PctToken(70), "good") T.eq(Browse.PctToken(130), "bad")
  T.eq(Browse.PctToken(100), "text") T.eq(Browse.PctToken(nil), "dim")
end)

T.test("opening the AH shows our window on the Browse tab with your gold", function()
  WoW.money = 123456
  openAH()
  T.ok(UI.ah:IsShown())
  T.eq(UI.ah.tabs.selected, "browse")
  T.ok(UI.pages.browse:IsShown())
  T.ok(string.find(UI.ah.gold:GetText(), "12g", 1, true))
end)

T.test("a search fills the list with market percentages", function()
  openAH()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 6000 })
  DB.Realm().market["14047:0"] = { v = 400 }
  T.ok(Browse.Search("Rune", 0))
  answer()
  local data = UI.pages.browse.list.data
  T.eq(table.getn(data), 1)
  T.eq(data[1].pct, 75)
  T.ok(string.find(UI.pages.browse.pageText:GetText(), "1 found", 1, true))
end)

T.test("watch toggles the selected row's item", function()
  openAH()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 6000 })
  Browse.Search("Rune", 0)
  answer()
  local p = UI.pages.browse
  p.list.selected = p.list.data[1]
  Browse.ToggleWatch()
  T.ok(DB.Realm().watch["14047:0"])
  T.eq(p.watchBtn.label:GetText(), "UNWATCH")
  Browse.ToggleWatch()
  T.eq(DB.Realm().watch["14047:0"], nil)
end)

T.test("searching during a scan is refused and the strip shows the scan", function()
  openAH()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  UI.StartScan("full")
  T.eq(Browse.Search("Rune", 0), false)
  T.ok(T.calledWith("Pause it to search"))
  UI.RefreshStatus()
  T.eq(UI.ah.status.full.enabled, false)
  T.eq(UI.ah.status.pause.label:GetText(), "PAUSE")
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'UI' (a nil value)`

- [ ] **Step 3: Implement the window**

`TaxTheFools/ui_window.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, Th, W, DB, Scan, AH = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB,
  TaxTheFools.Scan, TaxTheFools.AH
local UI = { pages = {}, builders = {}, ah = nil }
TaxTheFools.UI = UI

-- Later phases add Deals, Sell, Auctions, Crafting and History here.
UI.TABS = { { key = "browse", label = "Browse" } }

local SEP = "  -  "

function UI.Duration(s)
  s = math.floor((s or 0) + 0.5)
  if s < 60 then return s .. "s" end
  local m = math.floor(s / 60)
  if m < 60 then return m .. "m" end
  local h = math.floor(m / 60)
  if h < 24 then return h .. "h " .. math.mod(m, 60) .. "m" end
  return math.floor(h / 24) .. "d " .. math.mod(h, 24) .. "h"
end

-- What the status strip says and offers, from the scan's state alone.
function UI.Describe(p, resume, lastFull, now)
  local d = { text = "", fraction = 0, pause = false, discard = false, canStart = true }
  if p then
    d.canStart = false
    if p.kind == "browse" then
      d.text = "Searching..."
      return d
    end
    local label = (p.kind == "full") and "Full scan" or "Watchlist"
    if p.state == "stalled" then
      d.text = label .. " stopped: server not responding. Press Resume to try again."
      d.pause = "Resume"
      return d
    end
    local parts = { label }
    if p.kind == "full" then
      if p.totalPages and p.totalPages > 0 then
        table.insert(parts, "page " .. (p.page + 1) .. "/" .. p.totalPages)
        d.fraction = p.page / p.totalPages
      else
        table.insert(parts, "starting")
      end
    else
      table.insert(parts, "item " .. p.qi .. "/" .. p.nq)
      d.fraction = (p.qi - 1) / p.nq
    end
    if p.secsPerPage then table.insert(parts, string.format("%.1fs/page", p.secsPerPage)) end
    if p.eta then table.insert(parts, "~" .. UI.Duration(p.eta) .. " left") end
    if p.safe then table.insert(parts, "safe pace") end
    d.text = table.concat(parts, SEP)
    d.pause = "Pause"
    return d
  end
  if resume then
    d.text = "Paused " .. ((resume.kind == "full") and "full scan" or "watchlist scan") .. " at page " .. (resume.page + 1)
      .. " with " .. table.getn(resume.rows) .. " listings. Resume or discard it."
    d.pause, d.discard, d.canStart = "Resume", true, false
    return d
  end
  if lastFull then
    d.text = "Last full scan " .. UI.Duration(now - lastFull) .. " ago"
    d.fraction = 1
  else
    d.text = "No full scan yet. It takes a while; you can close the AH and resume later today."
  end
  return d
end

function UI.CreateStatusStrip(f)
  local s = CreateFrame("Frame", nil, f)
  s:SetHeight(38)
  local bg = Th.Solid(s, "BACKGROUND", "header")
  bg:SetAllPoints(s)
  s.full = W.Button(s, "Full scan", 92, 22, function() UI.StartScan("full") end, "accent")
  s.full:SetPoint("LEFT", s, "LEFT", 10, 0)
  W.Tip(s.full, "Full scan", "Pages through the whole auction house. Expect many minutes; it pauses if you leave and resumes later the same day.")
  s.watch = W.Button(s, "Watchlist", 92, 22, function() UI.StartScan("watch") end)
  s.watch:SetPoint("LEFT", s.full, "RIGHT", 6, 0)
  W.Tip(s.watch, "Watchlist scan", "Looks up only the items you watch. Quick.")
  s.pause = W.Button(s, "Pause", 76, 22, function() UI.PauseOrResume() end)
  s.pause:SetPoint("LEFT", s.watch, "RIGHT", 6, 0)
  s.discard = W.Button(s, "Discard", 76, 22, function() Scan.Discard() end)
  s.discard:SetPoint("LEFT", s.pause, "RIGHT", 6, 0)
  s.bar = W.Progress(s, 8)
  s.bar:SetPoint("TOPLEFT", s.discard, "TOPRIGHT", 12, -2)
  s.bar:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  s.text = Th.Text(s, "body", 11, "dim")
  s.text:SetPoint("TOPLEFT", s.bar, "BOTTOMLEFT", 0, -4)
  s.text:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  return s
end

function UI.CreateAH()
  if UI.ah then return UI.ah end
  local f = W.Window("TaxTheFoolsAH", 780, 500, "Tax the Fools", { resizable = true, minW = 660, minH = 380 })
  f.gold = Th.Text(f.header, "body2", 12, "gold")
  f.gold:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
  f.gold:SetJustifyH("RIGHT")
  f.blizzard = W.Button(f.header, "Blizzard UI", 96, 20, function() AH.ShowBlizzard() end)
  f.blizzard:SetPoint("RIGHT", f.gold, "LEFT", -12, 0)
  W.Tip(f.blizzard, "Blizzard UI", "Switch to the standard auction window. Its Tax the Fools button brings you back.")
  f.tabs = W.TabStrip(f, UI.TABS, function(key) UI.ShowPage(key) end)
  f.tabs:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -1)
  f.tabs:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -1)
  f.status = UI.CreateStatusStrip(f)
  f.status:SetPoint("TOPLEFT", f.tabs, "BOTTOMLEFT", 0, 0)
  f.status:SetPoint("TOPRIGHT", f.tabs, "BOTTOMRIGHT", 0, 0)
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 10, -8)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f:SetScript("OnShow", function()
    UI.RefreshGold()
    UI.RefreshStatus()
    if not f.tabs.selected then f.tabs:Select("browse") end
  end)
  f:SetScript("OnHide", function() AH.OnWindowHidden() end)
  f.onResize = function()
    for _, page in pairs(UI.pages) do
      if type(page.Layout) == "function" then page:Layout() end
    end
  end
  UI.ah = f
  AH.window = f
  Scan.OnChange(function() UI.RefreshStatus() end)
  return f
end

function UI.ShowPage(key)
  local f = UI.ah
  for _, page in pairs(UI.pages) do page:Hide() end
  local page = UI.pages[key]
  if not page then
    page = UI.builders[key](f.body)
    page:SetAllPoints(f.body)
    UI.pages[key] = page
  end
  page:Show()
  if type(page.Refresh) == "function" then page:Refresh() end
end

function UI.RefreshGold()
  if UI.ah then UI.ah.gold:SetText(U.money(GetMoney())) end
end

function UI.RefreshStatus()
  local f = UI.ah
  if not f or not f:IsShown() then return end
  local s = f.status
  local d = UI.Describe(Scan.Progress(GetTime()), Scan.Resumable(), DB.Realm().scan.lastFull, time())
  s.text:SetText(d.text)
  s.bar:SetFraction(d.fraction)
  if d.pause then
    s.pause:SetLabel(d.pause)
    s.pause:Show()
  else
    s.pause:Hide()
  end
  if d.discard then s.discard:Show() else s.discard:Hide() end
  s.full:SetEnabled(d.canStart)
  s.watch:SetEnabled(d.canStart)
end

function UI.StartScan(kind)
  local ok, why
  if kind == "full" then ok, why = Scan.StartFull(GetTime()) else ok, why = Scan.StartWatch(GetTime()) end
  if not ok and why == "empty" then
    U.msg("Your watchlist is empty. Select an item in Browse and press Watch, or type /ttf watch <item name>.")
  elseif not ok and why == "busy" then
    U.msg("A scan is already running.")
  end
  UI.RefreshStatus()
end

function UI.PauseOrResume()
  local p = Scan.Progress(GetTime())
  if p and p.state == "stalled" then Scan.Continue()
  elseif p then Scan.Pause("user")
  else Scan.Resume(GetTime()) end
  UI.RefreshStatus()
end

function UI.Tick(now)
  if UI.ah and UI.ah:IsShown() then UI.RefreshStatus() end
end
```

- [ ] **Step 4: Implement Browse**

`TaxTheFools/ui_browse.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Browse = { query = "", page = 0, frame = nil }
TaxTheFools.Browse = Browse

function Browse.ResetState() Browse.query, Browse.page = "", 0 end

-- Cheap against market reads green, dear reads red.
function Browse.PctToken(p)
  if not p then return "dim" end
  if p <= 70 then return "good" end
  if p >= 130 then return "bad" end
  return "text"
end

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

Browse.COLUMNS = {
  { label = "Item", width = 220, sort = "name", fmt = function(r) return U.quality(r.quality) .. r.name .. "|r" end },
  { label = "Qty", width = 44, align = "RIGHT", sort = "count", desc = true, fmt = function(r) return tostring(r.count) end },
  { label = "Bid", width = 92, align = "RIGHT", sort = "bidNow", fmt = function(r) return money(r.bidNow) end },
  { label = "Buyout", width = 92, align = "RIGHT", sort = "buy", fmt = function(r) return money(r.buy) end },
  { label = "Each", width = 84, align = "RIGHT", sort = "unit", fmt = function(r) return money(r.unit) end },
  { label = "Market", width = 84, align = "RIGHT", sort = "market", fmt = function(r) return money(r.market) end },
  { label = "%", width = 48, align = "RIGHT", sort = "pct",
    fmt = function(r) return r.pct and (r.pct .. "%") or "-", Browse.PctToken(r.pct) end },
  { label = "Seller", width = 92, sort = "owner", fmt = function(r) return r.owner or "?" end },
}

function Browse.Decorate(rows, market)
  for _, r in ipairs(rows) do
    local m = market[r.key]
    r.market = m and m.v or nil
    r.pct = nil
    if r.unit and r.market and r.market > 0 then r.pct = math.floor(r.unit / r.market * 100 + 0.5) end
    r.bidNow = ((r.bid or 0) > 0) and r.bid or r.minBid
    r.buy = ((r.buyout or 0) > 0) and r.buyout or nil
  end
  return rows
end

function Browse.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.search = W.EditBox(p, 220, function(text) Browse.Search(text, 0) end)
  p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.go = W.Button(p, "Search", 80, 22, function() Browse.Search(p.search:GetText(), 0) end, "accent")
  p.go:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
  p.watchBtn = W.Button(p, "Watch", 90, 22, function() Browse.ToggleWatch() end)
  p.watchBtn:SetPoint("LEFT", p.go, "RIGHT", 6, 0)
  W.Tip(p.watchBtn, "Watchlist", "Watched items are priced by the quick Watchlist scan.")
  p.next = W.IconButton(p, "icon-arrow-right", 22, function() Browse.Search(Browse.query, Browse.page + 1) end)
  p.next:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  p.prev = W.IconButton(p, "icon-arrow-left", 22, function() Browse.Search(Browse.query, Browse.page - 1) end)
  p.prev:SetPoint("RIGHT", p.next, "LEFT", -4, 0)
  p.pageText = Th.Text(p, "body", 11, "dim")
  p.pageText:SetPoint("RIGHT", p.prev, "LEFT", -8, 0)
  p.pageText:SetJustifyH("RIGHT")
  p.list = L.New(p, Browse.COLUMNS, 18, function() Browse.UpdateWatchButton() end)
  p.list:SetPoint("TOPLEFT", p.search, "BOTTOMLEFT", 0, -8)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.list.onEnter = function(row, item) Browse.RowTip(row, item) end
  p.Refresh = function(self) Browse.Paint() end
  p.Layout = function(self) self.list:Paint() end
  Browse.frame = p
  Scan.OnChange(function() if p:IsVisible() then Browse.Paint() end end)
  Browse.Paint()
  return p
end

function Browse.Paint()
  local p = Browse.frame
  if not p then return end
  p.list:SetData(Browse.Decorate(Scan.lastRows, DB.Realm().market))
  local pages = math.max(1, math.ceil(Scan.lastTotal / 50))
  p.pageText:SetText("Page " .. (Scan.lastPage + 1) .. " of " .. pages .. ", " .. Scan.lastTotal .. " found")
  Browse.UpdateWatchButton()
end

function Browse.Search(text, page)
  if page < 0 then return false end
  if page > 0 and page * 50 >= Scan.lastTotal then return false end
  Browse.query, Browse.page = text or "", page
  local ok, why = Scan.Browse(Browse.query, page, GetTime())
  if not ok and why == "busy" then U.msg("A scan is using the auction house. Pause it to search.") end
  return ok and true or false
end

function Browse.UpdateWatchButton()
  local p = Browse.frame
  if not p then return end
  local sel = p.list.selected
  p.watchBtn:SetEnabled(sel and true or false)
  p.watchBtn:SetLabel((sel and DB.Realm().watch[sel.key]) and "Unwatch" or "Watch")
end

function Browse.ToggleWatch()
  local p = Browse.frame
  local item = p and p.list.selected
  if not item then
    U.msg("Select an item first.")
    return
  end
  local watch = DB.Realm().watch
  if watch[item.key] then watch[item.key] = nil else watch[item.key] = true end
  Browse.UpdateWatchButton()
end

-- A hyperlink rather than SetAuctionItem: a scan may have replaced the
-- auction list since this page was drawn.
function Browse.RowTip(row, item)
  local link = U.linkString(item.link)
  if not link then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(link)
  GameTooltip:Show()
end

UI.builders.browse = Browse.Build
```

The `.toc` file list becomes: … `tooltip.lua`, `ui_window.lua`, `ui_browse.lua`, `core.lua`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `105 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: themed auction window with scan status strip and Browse tab"
```

---

### Task 12: Options window and minimap button

**Files:**
- Create: `TaxTheFools/options.lua`, `TaxTheFools/minimap.lua`
- Modify: `TaxTheFools/TaxTheFools.toc` (add both after `ui_browse.lua`)
- Test: `tests/test_options.lua`

**Interfaces:**
- Consumes: `W.*`, `Th.*`, `DB.S()`, `DB.SizeText`, `DB.StartPrune`, `DB.Wipe`.
- Produces:
  - Options:
    - `Opt.CATEGORIES`: a list of `{ key, label, rows }`. Each row is `{ kind = "switch"|"slider"|"dropdown"|"button"|"info", key|path, label, hint, min, max, step, fmt, options, after, onClick, text }`.
    - `Opt.Get(row)`, `Opt.Set(row, v)`.
    - `Opt.Create() -> frame`, with `.pages[key].controls`, `.navRows[key]` and `.selected`.
    - `Opt.Select(key)`, `Opt.Toggle()`.
    - `StaticPopupDialogs.TAXTHEFOOLS_RESET`.
  - Minimap:
    - `Mini.Position(angleDegrees) -> x, y`, `Mini.AngleFrom(cx, cy, mx, my) -> degrees`.
    - `Mini.Create()` (idempotent), `Mini.Refresh()`, `Mini.DragUpdate()`, `Mini.Click(button)`.
    - `Mini.button`.

- [ ] **Step 1: Write the failing test**

`tests/test_options.lua`:
```lua
local Opt, Mini, DB = TaxTheFools.Options, TaxTheFools.Minimap, TaxTheFools.DB

T.test("options read and write nested settings, then run the follow-up", function()
  local row = { kind = "switch", path = { "tooltip", "vendor" } }
  T.eq(Opt.Get(row), true)
  Opt.Set(row, false)
  T.eq(DB.S().tooltip.vendor, false)
  local hit
  Opt.Set({ key = "safeMode", after = function(v) hit = v end }, true)
  T.eq(DB.S().safeMode, true) T.eq(hit, true)
end)

T.test("the options window opens on its first page with one control per row", function()
  local f = Opt.Create()
  f:Hide()
  f.selected = false
  Opt.Toggle()
  T.ok(f:IsShown())
  T.eq(f.selected, "general")
  T.eq(table.getn(f.pages.general.controls), table.getn(Opt.CATEGORIES[1].rows))
end)

T.test("choosing a category shows only that page", function()
  local f = Opt.Create()
  Opt.Select("general")
  Opt.Select("scanning")
  T.ok(f.pages.scanning:IsShown())
  T.eq(f.pages.general:IsShown(), false)
  T.ok(f.navRows.scanning.bar:IsShown())
end)

T.test("a switch in options changes the setting", function()
  Opt.Create()
  Opt.Select("scanning")
  WoW.runScript(Opt.frame.pages.scanning.controls[2], "OnClick")
  T.eq(DB.S().safeMode, true)
end)

T.test("reset asks first, then wipes and reloads", function()
  Opt.Create()
  Opt.Select("data")
  WoW.runScript(Opt.frame.pages.data.controls[3], "OnClick")
  T.ok(T.calledWith("StaticPopup_Show TAXTHEFOOLS_RESET"))
  DB.S().scanDelay = 2
  StaticPopupDialogs.TAXTHEFOOLS_RESET.OnAccept()
  T.eq(DB.S().scanDelay, 0.3)
  T.ok(T.calledWith("ReloadUI"))
end)

T.test("the minimap button sits on a circle at the saved angle", function()
  local x, y = Mini.Position(0)
  T.near(x, 80, 0.01) T.near(y, 0, 0.01)
  x, y = Mini.Position(90)
  T.near(x, 0, 0.01) T.near(y, 80, 0.01)
end)

T.test("dragging the minimap button saves the angle under the cursor", function()
  Mini.Create()
  WoW.cursorX, WoW.cursorY = 100, 200     -- straight above the minimap centre (100, 100)
  Mini.DragUpdate()
  T.near(DB.S().minimapAngle, 90, 0.01)
end)

T.test("the minimap button hides when switched off", function()
  Mini.Create()
  DB.S().minimap = false
  Mini.Refresh()
  T.eq(Mini.button:IsShown(), false)
  DB.S().minimap = true
  Mini.Refresh()
  T.ok(Mini.button:IsShown())
end)

T.test("clicking the minimap button opens options", function()
  Mini.Create()
  Opt.Create():Hide()
  WoW.runScript(Mini.button, "OnClick", "LeftButton")
  T.ok(Opt.frame:IsShown())
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'Opt' (a nil value)`

- [ ] **Step 3: Implement options**

`TaxTheFools/options.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local U, D, Th, W, DB = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB
local Opt = { frame = nil }
TaxTheFools.Options = Opt

local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function secs(v) return string.format("%.1fs", v) end
local function themes()
  local t = {}
  for _, n in ipairs(Th.ORDER) do table.insert(t, { value = n, label = n }) end
  return t
end

-- Phase 3 adds Deals and Selling pages; phase 2 adds Crafting.
Opt.CATEGORIES = {
  { key = "general", label = "General", rows = {
    { kind = "switch", key = "replaceBlizzardAH", label = "Replace the Blizzard auction window",
      hint = "Takes effect next time you open the auction house. The Blizzard UI button switches back any time." },
    { kind = "switch", key = "minimap", label = "Minimap button", after = function() TaxTheFools.Minimap.Refresh() end },
    { kind = "slider", key = "scale", label = "Window scale", min = 0.8, max = 1.5, step = 0.05, fmt = pct,
      after = function() W.ApplyScale() end },
    { kind = "switch", key = "debug", label = "Debug messages",
      hint = "Prints extra detail, and shows Lua errors instead of quietly switching the failing part off." },
  } },
  { key = "scanning", label = "Scanning", rows = {
    { kind = "slider", key = "scanDelay", label = "Minimum time between pages", min = 0, max = 2, step = 0.1, fmt = secs },
    { kind = "switch", key = "safeMode", label = "Safe pace (4s between pages)",
      hint = "Use this if scans keep repeating pages or stalling." },
    { kind = "switch", key = "browseFeedsHistory", label = "Searches add to price history" },
  } },
  { key = "tooltip", label = "Tooltip", rows = {
    { kind = "switch", path = { "tooltip", "market" }, label = "Market value" },
    { kind = "switch", path = { "tooltip", "low" }, label = "Lowest price in the latest scan" },
    { kind = "switch", path = { "tooltip", "vendor" }, label = "Vendor price" },
  } },
  { key = "appearance", label = "Appearance", rows = {
    { kind = "dropdown", key = "theme", label = "Theme", options = themes(), after = function(v) Th.Apply(v) end },
    { kind = "switch", key = "fonts", label = "Bundled fonts (needs /reload)" },
  } },
  { key = "data", label = "Data", rows = {
    { kind = "info", text = function() return DB.SizeText() end },
    { kind = "button", label = "Prune old data now", onClick = function()
      DB.StartPrune()
      TaxTheFools.Core.pruned = false
      U.msg("Pruning old price history.")
    end },
    { kind = "button", label = "Reset all data", onClick = function() StaticPopup_Show("TAXTHEFOOLS_RESET") end },
  } },
}

StaticPopupDialogs["TAXTHEFOOLS_RESET"] = {
  text = "Delete all Tax the Fools price history, items and settings for every character, then reload?",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    DB.Wipe()
    ReloadUI()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local function path(row) return row.path or { row.key } end

function Opt.Get(row)
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  return t[p[table.getn(p)]]
end

function Opt.Set(row, v)
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  t[p[table.getn(p)]] = v
  if row.after then row.after(v) end
end

-- One control for one row. row arrives as a parameter, so the closures below
-- each keep their own (a loop variable would be shared in Lua 5.0).
function Opt.Control(parent, row)
  local get = function() return Opt.Get(row) end
  local set = function(v) Opt.Set(row, v) end
  if row.kind == "switch" then return W.Switch(parent, row.label, get, set, row.hint) end
  if row.kind == "slider" then return W.Slider(parent, row.label, row.min, row.max, row.step, get, set, row.fmt) end
  if row.kind == "dropdown" then
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(320)
    f:SetHeight(26)
    f.text = Th.Text(f, "body", 13, "text")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetText(row.label)
    f.dd = W.Dropdown(f, 140, row.options, get, set)
    f.dd:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.Refresh = function(self) self.dd:Refresh() end
    return f
  end
  if row.kind == "button" then
    local b = W.Button(parent, row.label, 180, 24, row.onClick)
    b.Refresh = function() end
    return b
  end
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(320)
  f:SetHeight(32)
  f.text = Th.Text(f, "body", 12, "dim")
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.text:SetWidth(320)
  f.Refresh = function(self) self.text:SetText(row.text()) end
  return f
end

function Opt.Page(f, cat)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 16, -14)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  p.controls = {}
  local y = 0
  for _, row in ipairs(cat.rows) do
    local c = Opt.Control(p, row)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
    y = y + c:GetHeight() + 10
    table.insert(p.controls, c)
  end
  return p
end

function Opt.NavRow(f, i, cat)
  local b = CreateFrame("Button", nil, f.nav)
  b:SetHeight(30)
  b:SetPoint("TOPLEFT", f.nav, "TOPLEFT", 0, -8 - (i - 1) * 30)
  b:SetPoint("RIGHT", f.nav, "RIGHT", 0, 0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(Th.MEDIA .. "solid")
  hl:SetAllPoints(b)
  hl:SetVertexColor(1, 1, 1, 0.04)
  b.bar = Th.Solid(b, "ARTWORK", "accent")
  b.bar:SetWidth(3)
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.bar:Hide()
  b.text = Th.Text(b, "body", 13, "dim")
  b.text:SetPoint("LEFT", b, "LEFT", 14, 0)
  b.text:SetText(cat.label)
  b.key = cat.key
  b:SetScript("OnClick", function() Opt.Select(this.key) end)
  return b
end

function Opt.Create()
  if Opt.frame then return Opt.frame end
  local f = W.Window("TaxTheFoolsOptions", 540, 400, "Tax the Fools  -  Options")
  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetWidth(150)
  f.nav:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -1)
  f.nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  local bg = Th.Solid(f.nav, "BACKGROUND", "panel3")
  bg:SetAllPoints(f.nav)
  f.version = Th.Text(f.nav, "body", 10, "subtle")
  f.version:SetPoint("BOTTOMLEFT", f.nav, "BOTTOMLEFT", 14, 10)
  f.version:SetText("v" .. D.VERSION)
  f.pages, f.navRows, f.selected = {}, {}, false
  for i, cat in ipairs(Opt.CATEGORIES) do f.navRows[cat.key] = Opt.NavRow(f, i, cat) end
  f:SetScript("OnShow", function() Opt.Select(f.selected or Opt.CATEGORIES[1].key) end)
  Opt.frame = f
  return f
end

function Opt.Select(key)
  local f = Opt.Create()
  f.selected = key
  for _, cat in ipairs(Opt.CATEGORIES) do
    local on = (cat.key == key)
    local nav = f.navRows[cat.key]
    Th.Color(nav.text, on and "white" or "dim")
    if on then nav.bar:Show() else nav.bar:Hide() end
    local page = f.pages[cat.key]
    if on and not page then
      page = Opt.Page(f, cat)
      f.pages[cat.key] = page
    end
    if page then
      if on then page:Show() else page:Hide() end
    end
  end
  for _, c in ipairs(f.pages[key].controls) do c:Refresh() end
end

function Opt.Toggle()
  local f = Opt.Create()
  if f:IsShown() then f:Hide() else f:Show() end
end
```

- [ ] **Step 4: Implement the minimap button**

`TaxTheFools/minimap.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local Th, W, DB = TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB
local Mini = { RADIUS = 80, button = nil }
TaxTheFools.Minimap = Mini

-- math.* works in radians; WoW's global sin/cos take degrees. Use math.* only.
function Mini.Position(angle)
  local r = math.rad(angle)
  return math.cos(r) * Mini.RADIUS, math.sin(r) * Mini.RADIUS
end

function Mini.AngleFrom(cx, cy, mx, my)
  return math.deg(math.atan2(cy - my, cx - mx))
end

function Mini.Create()
  if Mini.button then return Mini.button end
  local b = CreateFrame("Button", "TaxTheFoolsMinimap", Minimap)
  b:SetWidth(28)
  b:SetHeight(28)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(Th.MEDIA .. "circle")
  bg:SetAllPoints(b)
  Th.Tint(bg, "header")
  b.text = Th.Text(b, "display", 14, "accent")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText("TF")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function() Mini.Click(arg1) end)
  b:SetScript("OnDragStart", function() this:SetScript("OnUpdate", function() Mini.DragUpdate() end) end)
  b:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  W.Tip(b, "Tax the Fools", "Click: options. Drag: move this button.")
  b:SetScript("OnEnter", function() W.ShowTip(this) end)
  b:SetScript("OnLeave", function() W.HideTip() end)
  Mini.button = b
  Mini.Refresh()
  return b
end

function Mini.Refresh()
  local b = Mini.button
  if not b then return end
  if DB.S().minimap then b:Show() else b:Hide() end
  local x, y = Mini.Position(DB.S().minimapAngle or 200)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Mini.DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  DB.S().minimapAngle = Mini.AngleFrom(cx / s, cy / s, mx, my)
  Mini.Refresh()
end

-- Phase 2 gives left-click the Crafting window.
function Mini.Click(button)
  TaxTheFools.Options.Toggle()
end
```

The `.toc` file list becomes: … `ui_browse.lua`, `options.lua`, `minimap.lua`, `core.lua`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: `114 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: Aegis-style options window and minimap button"
```

---

### Task 13: Wire everything into the core

**Files:**
- Modify: `TaxTheFools/core.lua` (replace the whole file)
- Modify: `tests/test_core.lua` (replace the whole file)

**Interfaces:**
- Consumes: every module above. `TaxTheFools.Probe` is looked up when called, and is created in Task 14.
- Produces:
  - `Core.Init()`, which is safe to call again.
  - `Core.OnEvent(event)`, `Core.Update(now)`, `Core.PruneTick()`.
  - `Core.Command(msg)`, `Core.Watch(name, on)`, `Core.WatchList()`, `Core.Status()`.
  - `Core.HELP`, `Core.pruned`, `Core.uiAt`.
  - The event frame `TaxTheFoolsCore`.

- [ ] **Step 1: Write the failing tests**

Replace `tests/test_core.lua` with:
```lua
local A = TaxTheFools
local Core, DB, Scan, UI, AH = A.Core, A.DB, A.Scan, A.UI, A.AH
local function ttf(msg) SlashCmdList["TAXTHEFOOLS"](msg) end

T.test("core is ready once saved variables load", function()
  T.ok(Core.ready)
end)

T.test("/ttf with no arguments lists the commands", function()
  ttf("")
  T.ok(T.calledWith("/ttf options")) T.ok(T.calledWith("/ttf watch")) T.ok(T.calledWith("/ttf probe"))
end)

T.test("chat messages carry the TTF prefix", function()
  A.Util.msg("hello")
  T.ok(T.calledWith("TTF:|r hello"))
end)

T.test("Safe switches a part off after an error instead of erroring every frame", function()
  local calls = 0
  local boom = function() calls = calls + 1 error("bad") end
  Core.Safe("thing", boom)
  Core.Safe("thing", boom)
  T.eq(calls, 1)
  T.ok(T.calledWith("thing stopped after an error"))
end)

T.test("an upgrade says which version it replaced", function()
  TaxTheFoolsDB.version = "0.0.9"
  Core.Init()
  T.ok(T.calledWith("loaded, replaces v0.0.9"))
end)

T.test("talking to an auctioneer opens our window a frame later, leaving closes it", function()
  AH.switching = true UI.ah:Hide() AH.switching = false
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  T.ok(UI.ah:IsShown())
  T.eq(AuctionFrame:IsShown(), false)
  WoW.fire("AUCTION_HOUSE_CLOSED")
  T.eq(UI.ah:IsShown(), false)
  T.ok(not T.calledWith("CloseAuctionHouse"), "the server already closed it")
end)

T.test("auction list updates reach the scan", function()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  Scan.StartFull(WoW.clock)
  WoW.runScript(TaxTheFoolsCore, "OnUpdate")
  WoW.ahRespond()
  T.eq(Scan.job.page, 1, "first page accepted through the event")
end)

T.test("opening a merchant learns vendor prices", function()
  WoW.bags[0] = { { id = 4306, name = "Silk Cloth", count = 20, vendor = 37 } }
  WoW.merchantOpen = true
  WoW.fire("MERCHANT_SHOW")
  T.eq(A.Items.Vendor(4306), 37)
end)

T.test("watch, list and unwatch by name", function()
  A.Items.Remember(4306, "Silk Cloth")
  ttf("watch silk cloth")
  T.ok(DB.Realm().watch["4306:0"])
  ttf("watchlist")
  T.ok(T.calledWith("Watching 1: Silk Cloth"))
  ttf("unwatch Silk Cloth")
  T.eq(DB.Realm().watch["4306:0"], nil)
end)

T.test("watching an item the addon hasn't seen explains how to teach it", function()
  ttf("watch Felcloth")
  T.ok(T.calledWith("don't know \"Felcloth\" yet"))
end)

T.test("status reports what is stored and the last full scan", function()
  DB.Realm().scan.lastFull = WoW.now - 90000
  ttf("status")
  T.ok(T.calledWith("items known"))
  T.ok(T.calledWith("Last full scan 1d 1h ago"))
end)

T.test("debug toggles", function()
  ttf("debug") T.eq(DB.S().debug, true)
  ttf("debug") T.eq(DB.S().debug, false)
end)

T.test("nothing is bought, bid on, posted or cancelled without a click", function()
  for i = 1, 120 do table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 1, buyout = 100 + i }) end
  DB.Realm().market["14047:0"] = { v = 100000, conf = 1 }     -- everything looks like a bargain
  AuctionFrame:Show()
  WoW.fire("AUCTION_HOUSE_SHOW")
  A.UI.StartScan("full")
  for _ = 1, 50 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  A.Browse.Search("Rune", 0)
  for _ = 1, 5 do
    WoW.clock = WoW.clock + 0.5
    WoW.runScript(TaxTheFoolsCore, "OnUpdate")
    if WoW.ah.pending then WoW.ahRespond() end
  end
  T.ok(T.calledWith("QueryAuctionItems"), "it did scan")
  T.ok(not T.calledWith("PlaceAuctionBid"), "no bid or buyout")
  T.ok(not T.calledWith("StartAuction"), "no post")
  T.ok(not T.calledWith("CancelAuction"), "no cancel")
end)

T.test("after login, retention runs and market values are refreshed", function()
  DB.Realm().history["14047:0"] = { days = { [20375] = { p25 = 400, min = 390, n = 3 } }, months = {} }
  DB.StartPrune()
  Core.pruned = false
  for _ = 1, 3 do WoW.runScript(TaxTheFoolsCore, "OnUpdate") end
  T.eq(DB.Realm().market["14047:0"].v, 400)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `make test`
Expected: FAIL in test_core. For example, help does not list `/ttf options`, the AH events do nothing, and `ttf("watch ...")` only prints help.

- [ ] **Step 3: Replace the core**

`TaxTheFools/core.lua`:
```lua
local A = TaxTheFools
local U, D, DB = A.Util, A.Data, A.DB
local Core = { ready = false, disabled = {}, pruned = true, uiAt = 0 }
A.Core = Core

function Core.ResetState()
  Core.disabled = {}
  Core.uiAt = 0
end

-- Runs fn. With debug off, an error switches that part off for the session
-- instead of throwing every frame; with debug on it throws, for a stack trace.
function Core.Safe(name, fn, a1, a2, a3)
  if Core.disabled[name] then return end
  local s = TaxTheFoolsDB and TaxTheFoolsDB.settings
  if s and s.debug then return fn(a1, a2, a3) end
  local ok, err = pcall(fn, a1, a2, a3)
  if not ok then
    Core.disabled[name] = true
    U.msg(name .. " stopped after an error: " .. tostring(err) .. " (/reload to retry)")
  end
end

-- Safe to run twice: every builder below returns what it already made.
function Core.Init()
  DB.Init()
  A.Theme.Apply(DB.S().theme)
  A.Tooltip.Hook()
  A.UI.CreateAH()
  A.Minimap.Create()
  DB.StartPrune()
  Core.pruned = false
  Core.ready = true
  local prev = TaxTheFoolsDB.version
  TaxTheFoolsDB.version = D.VERSION
  if prev and prev ~= D.VERSION then
    U.msg("v" .. D.VERSION .. " loaded, replaces v" .. prev .. ".")
  else
    U.msg("v" .. D.VERSION .. " loaded. /ttf for commands.")
  end
  if DB.wasBroken then
    U.msg("Saved data could not be read and was set aside (TaxTheFoolsDB_broken); starting fresh.")
  end
end

function Core.OnEvent(e)
  if e == "VARIABLES_LOADED" then return Core.Init() end
  if not Core.ready then return end
  if e == "AUCTION_HOUSE_SHOW" then Core.Safe("auction window", A.AH.OnShow)
  elseif e == "AUCTION_HOUSE_CLOSED" then Core.Safe("auction window", A.AH.OnClosed)
  elseif e == "AUCTION_ITEM_LIST_UPDATE" then Core.Safe("scan", A.Scan.OnListUpdate, GetTime())
  elseif e == "MERCHANT_SHOW" then Core.Safe("items", A.Items.LearnVendorPrices)
  elseif e == "PLAYER_MONEY" then Core.Safe("interface", A.UI.RefreshGold)
  end
end

-- Retention first, then a fresh market value for everything: decay depends on
-- today's date, so yesterday's values are a day stale at every login.
function Core.PruneTick()
  if DB.PruneStep(D.PRUNE_PER_FRAME, U.day(time())) then
    Core.pruned = true
    local keys = {}
    for k in pairs(DB.Realm().history) do table.insert(keys, k) end
    A.Scan.QueueMarket(keys)
  end
end

function Core.Update(now)
  if not Core.ready then return end
  Core.Safe("auction window", A.AH.Tick)
  Core.Safe("scan", A.Scan.Tick, now)
  if not Core.pruned then Core.Safe("prune", Core.PruneTick) end
  if now - Core.uiAt >= 0.25 then
    Core.uiAt = now
    Core.Safe("interface", A.UI.Tick, now)
  end
end

Core.HELP = {
  "/ttf options - settings",
  "/ttf watch <item name> - add an item to the watchlist scan",
  "/ttf unwatch <item name> - take it off",
  "/ttf watchlist - list watched items",
  "/ttf status - what is stored and when the last full scan ran",
  "/ttf show - bring back the Tax the Fools auction window",
  "/ttf probe - dump what this client supports, to copy out",
  "/ttf debug - toggle debug messages and stack traces",
  "/ttf help - this list",
}

function Core.Watch(name, on)
  if name == "" then
    U.msg("usage: /ttf " .. (on and "watch" or "unwatch") .. " <item name>")
    return
  end
  local id = A.Items.FindByName(name)
  if not id then
    U.msg("I don't know \"" .. name .. "\" yet. Hover it in your bags or find it in Browse first.")
    return
  end
  local key = U.key(id)
  if on then DB.Realm().watch[key] = true else DB.Realm().watch[key] = nil end
  U.msg((on and "Watching " or "No longer watching ") .. A.Items.Name(id) .. ".")
end

function Core.WatchList()
  local names = {}
  for key in pairs(DB.Realm().watch) do table.insert(names, A.Items.Name(U.keyId(key))) end
  table.sort(names)
  if table.getn(names) == 0 then
    U.msg("The watchlist is empty.")
    return
  end
  U.msg("Watching " .. table.getn(names) .. ": " .. table.concat(names, ", "))
end

function Core.Status()
  U.msg(DB.SizeText())
  local last = DB.Realm().scan.lastFull
  if last then U.msg("Last full scan " .. A.UI.Duration(time() - last) .. " ago.")
  else U.msg("No full scan yet.") end
end

function Core.Command(msg)
  msg = msg or ""
  local cmd = string.lower(U.words(msg)[1] or "")
  local rest = U.trim((string.gsub(msg, "^%s*%S+", "")))
  if cmd == "options" or cmd == "config" then A.Options.Toggle()
  elseif cmd == "watch" then Core.Watch(rest, true)
  elseif cmd == "unwatch" then Core.Watch(rest, false)
  elseif cmd == "watchlist" then Core.WatchList()
  elseif cmd == "status" then Core.Status()
  elseif cmd == "show" then
    if A.AH.open then A.AH.ShowOurs() else U.msg("Talk to an auctioneer first.") end
  elseif cmd == "probe" then A.Probe.Show()
  elseif cmd == "debug" then
    local s = DB.S()
    s.debug = not s.debug
    U.msg("debug " .. (s.debug and "on" or "off"))
  else
    U.msg("commands:")
    for _, line in ipairs(Core.HELP) do U.msg("  " .. line) end
  end
end

SLASH_TAXTHEFOOLS1 = "/ttf"
SLASH_TAXTHEFOOLS2 = "/taxthefools"
SlashCmdList["TAXTHEFOOLS"] = function(msg) Core.Safe("command", Core.Command, msg) end

local frame = CreateFrame("Frame", "TaxTheFoolsCore")
for _, e in ipairs({ "VARIABLES_LOADED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE",
                     "MERCHANT_SHOW", "PLAYER_MONEY" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function() Core.OnEvent(event) end)
frame:SetScript("OnUpdate", function() Core.Update(GetTime()) end)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `124 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add TaxTheFools tests
git commit -m "feat: wire events, frame updates, retention and slash commands into the core"
```

---

### Task 14: Probe, in-game checklist and README

**Files:**
- Create: `TaxTheFools/probe.lua`, `tests/test_probe.lua`, `docs/testing-checklist.md`, `README.md`
- Modify: `TaxTheFools/TaxTheFools.toc` (add `probe.lua` before `core.lua`)

**Interfaces:**
- Consumes: `W.Window`, `Th.SetFont`, `D.VERSION`, `Scan.lastFinished`.
- Produces:
  - `Probe.FUNCTIONS`, `Probe.VARS`
  - `Probe.Lines() -> { string }`
  - `Probe.Show()`, which saves the lines to `TaxTheFoolsDB.probe`
  - `Probe.frame.edit`

- [ ] **Step 1: Write the failing test**

`tests/test_probe.lua`:
```lua
local Probe = TaxTheFools.Probe

T.test("the probe reports which API functions this client has", function()
  local all = table.concat(Probe.Lines(), "\n")
  T.ok(string.find(all, "fn QueryAuctionItems yes", 1, true), all)
  T.ok(string.find(all, "fn GetInboxInvoiceInfo MISSING", 1, true), all)
  T.ok(string.find(all, "realm Medivh", 1, true), all)
end)

T.test("with an auction page loaded it samples a real row", function()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 8000, owner = "Bob" })
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
  local all = table.concat(Probe.Lines(), "\n")
  T.ok(string.find(all, "auction row 1: Runecloth", 1, true), all)
  T.ok(string.find(all, "Bob", 1, true))
end)

T.test("the probe window holds copyable text and the dump is saved", function()
  table.insert(WoW.ah.listings, { id = 14047, name = "Runecloth", count = 20, buyout = 8000 })
  QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, nil)
  WoW.ahRespond()
  Probe.Show()
  T.ok(table.getn(TaxTheFoolsDB.probe) > 5)
  T.ok(Probe.frame:IsShown())
  T.ok(string.find(Probe.frame.edit:GetText(), "||Hitem:14047", 1, true), "links shown as text, not as links")
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test`
Expected: FAIL, `attempt to index local 'Probe' (a nil value)`

- [ ] **Step 3: Implement the probe**

`TaxTheFools/probe.lua`:
```lua
TaxTheFools = TaxTheFools or {}
local D, Th, W = TaxTheFools.Data, TaxTheFools.Theme, TaxTheFools.Widgets
local Probe = { frame = nil }
TaxTheFools.Probe = Probe

-- What this client actually offers. The answers settle the spec's open
-- questions (invoice API, duration labels, page timing) from the real game.
Probe.FUNCTIONS = {
  "QueryAuctionItems", "CanSendAuctionQuery", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "GetAuctionItemTimeLeft", "PlaceAuctionBid", "StartAuction", "CancelAuction", "GetOwnerAuctionItems",
  "ClickAuctionSellItemButton", "GetAuctionSellItemInfo", "CalculateAuctionDeposit",
  "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem", "TakeInboxMoney",
  "GetTradeSkillInfo", "GetTradeSkillNumMade", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
  "GetTradeSkillItemLink", "GetMerchantItemLink", "GetItemInfo",
}
Probe.VARS = {
  "TURTLE_WOW_VERSION", "SUPERWOW_VERSION", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT",
  "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT", "ERR_AUCTION_SOLD_S",
  "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE",
}

function Probe.Lines()
  local out = {}
  local function add(s) table.insert(out, s) end
  local version, build, _, iface = GetBuildInfo()
  add("Tax the Fools " .. D.VERSION .. "  client " .. tostring(version) .. " build " .. tostring(build)
    .. " interface " .. tostring(iface))
  add("realm " .. tostring(GetRealmName()) .. "  character " .. tostring(UnitName("player"))
    .. "  faction " .. tostring(UnitFactionGroup("player")))
  add("ClassicAPI " .. ((C_Item ~= nil) and "yes" or "no"))
  for _, n in ipairs(Probe.FUNCTIONS) do
    add("fn " .. n .. " " .. ((type(getglobal(n)) == "function") and "yes" or "MISSING"))
  end
  for _, n in ipairs(Probe.VARS) do add("var " .. n .. " = " .. tostring(getglobal(n))) end
  local batch, total = GetNumAuctionItems("list")
  if batch and batch > 0 then
    local r = { GetAuctionItemInfo("list", 1) }
    local parts = {}
    for i = 1, 13 do table.insert(parts, tostring(r[i])) end
    add("auction row 1: " .. table.concat(parts, ", "))
    add("auction link 1: " .. tostring(GetAuctionItemLink("list", 1)))
    add("auction time left 1: " .. tostring(GetAuctionItemTimeLeft("list", 1)))
    add("auction list: " .. batch .. " on this page, " .. tostring(total) .. " in total")
  else
    add("auction list empty: open the AH and search for something, then probe again")
  end
  local f = TaxTheFools.Scan.lastFinished
  if f then
    local per = (f.pages > 0) and (f.secs / f.pages) or 0
    add(string.format("last scan: %s, %d pages, %d listings, %.0fs, %.2fs/page", f.kind, f.pages, f.listings, f.secs, per))
  end
  return out
end

function Probe.Show()
  local lines = Probe.Lines()
  TaxTheFoolsDB.probe = lines
  local f = Probe.frame
  if not f then
    f = W.Window("TaxTheFoolsProbe", 560, 360, "Tax the Fools  -  Probe", { resizable = true, minW = 360, minH = 200 })
    local sf = CreateFrame("ScrollFrame", "TaxTheFoolsProbeScroll", f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -42)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 22)
    local e = CreateFrame("EditBox", "TaxTheFoolsProbeText", sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetWidth(530)
    e:SetHeight(2000)
    Th.SetFont(e, "body", 11)
    e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    sf:SetScrollChild(e)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function()
      local v = this:GetVerticalScroll() - arg1 * 40
      if v < 0 then v = 0 end
      this:SetVerticalScroll(v)
    end)
    f.edit = e
    Probe.frame = f
  end
  -- "||" shows a link as its raw text, which is what you want to paste out.
  f.edit:SetText((string.gsub(table.concat(lines, "\n"), "|", "||")))
  f:Show()
  f.edit:SetFocus()
  f.edit:HighlightText()
end
```

The final `.toc` file list:
```
data.lua
util.lua
stats.lua
price.lua
db.lua
items.lua
scan.lua
ahhook.lua
theme.lua
widgets.lua
list.lua
tooltip.lua
ui_window.lua
ui_browse.lua
options.lua
minimap.lua
probe.lua
core.lua
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test`
Expected: `127 passed, 0 failed`

- [ ] **Step 5: Write the in-game checklist**

`docs/testing-checklist.md`:
```markdown
# In-game checklist

Run this after every install, on the real client. The tests prove the logic
against a fake client; this proves the fake client was right.

## Load
1. Log in on the bank character. Chat shows `TTF: v0.1.0 loaded`.
2. `/ttf probe`. The window opens with text selected. Press Ctrl+C and paste it
   into `tools/probe-<date>.txt` in this repo. Check:
   - every `fn` line says `yes`, except possibly `GetInboxInvoiceInfo`, `CalculateAuctionDeposit` (spec §13 Q2)
   - `TURTLE_WOW_VERSION` is set
3. `/reload`. No errors, and no "stopped after an error" lines.

## Auction window
4. Talk to an auctioneer. The Tax the Fools window opens and Blizzard's does not.
5. Search "cloth" in Browse. Results appear with Each, Market (dashes at first) and Seller.
6. Next page, then previous page. The page text follows.
7. Press **Blizzard UI**. Blizzard's window appears. Its **Tax the Fools** button
   brings ours back. Search again to prove the session survived the switches.
8. Close our window with the X, then talk to the auctioneer again. It opens
   cleanly. Do the same with Escape.
9. Walk away from the auctioneer. Our window closes.

## Scanning
10. Start a **Full scan**. The strip shows page X/Y, s/page and time left within a few pages.
    Write down the s/page figure (spec §13 Q1).
11. Walk away mid-scan, come back. The strip offers Resume/Discard. Resume. It carries on
    from the same page.
12. Let it finish. `/ttf status` reports items with price history.
13. Select a cloth row, press Watch, then run a **Watchlist** scan. It finishes in seconds.
14. `/ttf probe` again with an AH page loaded: the `auction row 1` line shows 13 values.
    Paste it in as well (duration and time-left values settle spec §13 Q3).

## Tooltips and merchants
15. Hover Silk Cloth in your bags: Market (with confidence), Low now and Vendor lines,
    after a full scan. Hold Shift on a stack: the figures multiply.
16. Open a vendor and close it. Hover a grey item: a Vendor line appears.

## Options and look
17. Minimap **TF** button opens options. Drag it round the minimap; `/reload`; it stays.
18. Options: switch theme to Frost. Open windows recolour at once. Switch back.
19. Turn off "Bundled fonts" and `/reload`: everything still readable in the stock font.
20. Move and resize the auction window, `/reload`, reopen. Same place, same size.
21. Nothing draws outside any window border at scale 80% and 150%.

## Other character
22. Log over to the priest. Hover Silk Cloth: the same market value, with no scan on this character.
```

- [ ] **Step 6: Write the README**

`README.md`:
```markdown
# Tax the Fools

Auction house price history, deal finding and crafting profit for the Ravencraft
server (Turtle WoW 1.18.1 client, WoW 1.12, Lua 5.0).

Phase 1, this release: the auction window, scanning, price history and tooltips.
Crafting profit, deals with one-click buying, selling, and sales tracking follow
(see `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md`).

## Install

Copy the `TaxTheFools` folder into `twmoa_1181\Interface\AddOns`, or from this repo:

    make install ADDONS="/path/to/twmoa_1181/Interface/AddOns"

## Use

- **Scan on your bank character.** Talk to an auctioneer and press **Full scan**.
  It pages through the whole auction house at the pace the server allows, which takes
  many minutes. Leave the auctioneer whenever you like; next visit the same day,
  press **Resume**.
- **Watchlist.** Select an item in Browse and press **Watch**, or `/ttf watch Silk Cloth`.
  **Watchlist** scans only those items, in seconds.
- **Every character sees the prices.** Data is account-wide; log over (or `/reload`) and
  hover an item.
- **Tooltips** show market value (a recent-weighted typical price) with how sure
  the addon is (high / medium / low), the lowest price in the latest scan, and the
  vendor price once a merchant has seen the item. Hold Shift for whole-stack values.
- **Blizzard UI** switches to the stock window at any time; its **Tax the Fools** button
  switches back. Buying and selling from our own window arrives in phase 3.

Nothing is ever bought, bid on, posted or cancelled without your click. The only
thing that runs by itself is a scan turning pages.

## Commands

    /ttf options              settings
    /ttf watch <item name>    add to the watchlist
    /ttf unwatch <item name>  remove from it
    /ttf watchlist            list it
    /ttf status               what is stored, when the last full scan ran
    /ttf show                 bring the auction window back
    /ttf probe                copyable dump of what this client supports
    /ttf debug                debug messages and stack traces

## Develop

    make test      builds Lua 5.0.3 once, lints, runs the tests against a fake client
    make media     regenerates the textures
    make fonts     re-downloads the bundled fonts

Run `docs/testing-checklist.md` in game after every install.

Fonts: Rajdhani and Inter, SIL Open Font License (`TaxTheFools/media/fonts/OFL-*.txt`).
The look follows Aegis Pathfinder; no code is taken from it.
```

- [ ] **Step 7: Run the full suite one last time**

Run: `make test`
Expected: `127 passed, 0 failed`, with no lint output.

- [ ] **Step 8: Commit**

```bash
git add TaxTheFools tests docs/testing-checklist.md README.md
git commit -m "feat: API probe, in-game checklist and README"
```
