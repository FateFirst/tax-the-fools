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
-- The client's global environment, kept for the stub's own use. Lua 5.0 defines a global _G, which
-- Vanilla 1.12 does not (addons use getglobal / getfenv(0)): it is removed again at the end of this file.
local G = getfenv(0)

-- WoW.inbox is another name for WoW.mail (phase 4 tests assign WoW.mail).
setmetatable(WoW, { __index = function(t, k) if k == "inbox" then return rawget(t, "mail") end end,
                    __newindex = function(t, k, v) if k == "inbox" then rawset(t, "mail", v) else rawset(t, k, v) end end })

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
  r.GetWidth = function(self) return rawget(self, "width") or 0 end
  r.GetHeight = function(self) return rawget(self, "height") or 0 end
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
  -- 1.12 frames carry a numeric ID: a bag's container frame holds the bag number, its item buttons the slot.
  f.SetID = function(self, id) self.id = id end
  f.GetID = function(self) return rawget(self, "id") or 0 end
  f.RegisterEvent = function(self, e) self.events[e] = true end
  f.UnregisterEvent = function(self, e) self.events[e] = nil end
  f.SetScript = function(self, s, fn) self.scripts[s] = fn end
  f.GetScript = function(self, s) return self.scripts[s] end
  f.SetText = function(self, t) self.text = t or "" end
  f.GetText = function(self) return self.text end
  f.CreateTexture = function(self) return newTexture() end
  f.CreateFontString = function(self) return newFontString() end
  f.SetScale = function(self, s) self.scale = s end
  f.GetScale = function(self) return rawget(self, "scale") or 1 end
  f.GetEffectiveScale = function(self) return rawget(self, "scale") or 1 end
  f.SetAlpha = function(self, a) self.alpha = a end
  f.GetAlpha = function(self) return rawget(self, "alpha") or 1 end
  f.GetLeft = function(self) return rawget(self, "left") or 100 end
  f.GetTop = function(self) return rawget(self, "top") or 500 end
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
  -- GameTooltipTemplate (1.12): line i's left text is the global <name>TextLeft<i>, a FontString.
  -- Kept in step with f.lines here so addons can read it with getglobal(name .. "TextLeft" .. i).
  local function syncLines(self)
    if not self.name then return end
    for i, l in ipairs(self.lines) do
      local fs = G[self.name .. "TextLeft" .. i]
      if not fs then fs = newFontString() G[self.name .. "TextLeft" .. i] = fs end
      fs:SetText(l[1])
    end
  end
  f.AddLine = function(self, l) table.insert(self.lines, { l }) syncLines(self) end
  f.AddDoubleLine = function(self, l, r) table.insert(self.lines, { l, r }) syncLines(self) end
  f.NumLines = function(self) return table.getn(self.lines) end
  if kind == "GameTooltip" then
    f.SetText = function(self, t) self.lines = { { t } } syncLines(self) end
    f.ClearLines = function(self) self.lines = {} end
    -- With a merchant open the client prices bag items through this script,
    -- passing the whole stack's sell price in arg1.
    f.SetBagItem = function(self, bag, slot)
      self.lines = {}
      local it = WoW.bags[bag] and WoW.bags[bag][slot]
      if it and WoW.merchantOpen and it.vendor then runScript(self, "OnTooltipAddMoney", it.vendor * (it.count or 1)) end
      return "orig-bag"
    end
    -- 1.12 InboxFrameItem_OnEnter: GameTooltip:SetInboxItem(this.index). Reads the mail's item, no mail call.
    f.SetInboxItem = function(self, index)
      self.lines = {}
      WoW.log("SetInboxItem", self.name, index)
      local m = WoW.mail[index]
      if m and m.item then table.insert(self.lines, { m.item.name }) end
      syncLines(self)
    end
    -- Tests put an item's tooltip text in WoW.tooltips[id] = { "line 1", "line 2", ... }.
    f.SetHyperlink = function(self, link)
      self.lines = {}
      WoW.log("SetHyperlink", self.name, link)
      local _, _, n = string.find(link or "", "item:(%d+)")
      for _, t in ipairs((n and WoW.tooltips[tonumber(n)]) or {}) do table.insert(self.lines, { t }) end
      syncLines(self)
    end
  end
  table.insert(WoW.allFrames, f)
  if name then
    WoW.frames[name] = f
    G[name] = f
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
    -- As documented by ClassicAPI (docs/API.md): the plain name takes an
    -- itemLocation table and errors on an item id; the ById form takes the id.
    GetItemSellPrice = function(loc)
      if type(loc) ~= "table" then error("usage: C_Item.GetItemSellPrice(itemLocation)", 2) end
      return nil
    end,
    GetItemSellPriceByID = function(id) local it = WoW.items[id] return it and it.vendor end,
  }
end

function WoW.reset()
  WoW.calls = {}
  WoW.clock = 1000                      -- GetTime(): seconds since the client started
  WoW.now = 20375 * 86400 + 43200       -- time(): midday UTC on day 20375 (2025-10-14)
  WoW.realm, WoW.player, WoW.faction, WoW.class = "Medivh", "Bankalt", "Horde", "WARRIOR"
  WoW.money = 0
  WoW.shift, WoW.ctrl, WoW.alt = false, false, false
  WoW.cursorX, WoW.cursorY = 0, 0
  WoW.items = {}
  WoW.equip = {}
  WoW.bags = {}
  WoW.merchantOpen = false
  WoW.merchant = {}
  WoW.mail, WoW.sent, WoW.returned, WoW.mailErrors, WoW.addons = {}, {}, {}, {}, {}
  WoW.sendSlot, WoW.sendMoney, WoW.mailOpen = nil, 0, false
  WoW.closingMail = false
  if MailFrame then MailFrame.shown = false MailFrame.scripts.OnHide = WoW.mailFrameOnHide end
  WoW.tooltips = {}
  WoW.trainer = {}
  WoW.bankOpen = false
  WoW.tradeskill = { name = "Tailoring", rank = 0, maxRank = 0, selected = 0, rows = {} }
  WoW.rejectFonts = false
  WoW.ah = { listings = {}, canQuery = true, pending = false, current = {}, total = 0, lastPage = false, duplicateNext = 0,
             bids = {}, bidReply = "auto",
             owned = {}, ownerPending = false, posts = {}, postReply = "auto", cancels = {}, cancelReply = "auto",
             depositFactor = 0.6 }
  WoW.cursor, WoW.sellSlot, WoW.lateDeposit = nil, nil, nil
  WoW.classicAPI(false)
  if AuctionFrame then AuctionFrame.shown = false end
  if TradeSkillFrame then TradeSkillFrame.shown = false end
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
-- Models the 1.12 client re-presenting the page it already showed (the server
-- fills in owner names late, so AUCTION_ITEM_LIST_UPDATE fires again for it).
-- The visible page (WoW.ah.current) is left as is, and with withOwners every
-- row on it gains an owner name first. This only changes what the client
-- reads; the caller delivers the event itself (Scan.OnListUpdate(now)).
function WoW.ahRepeatLast(withOwners)
  if withOwners then
    for _, l in ipairs(WoW.ah.current) do l.owner = "Late" .. (l.id or 0) end
  end
end
-- The client keeps two lists: "list" (the last search page) and "owner" (your own
-- auctions, filled by GetOwnerAuctionItems + AUCTION_OWNED_LIST_UPDATE). Other types read empty.
local function auctionList(kind)
  if kind == "list" then return WoW.ah.current end
  if kind == "owner" then return WoW.ah.owned end
  return nil
end
function GetNumAuctionItems(kind)
  if type(kind) ~= "string" then error("Usage: GetNumAuctionItems(\"type\")", 2) end
  if kind == "owner" then return table.getn(WoW.ah.owned), table.getn(WoW.ah.owned) end
  if kind ~= "list" then return 0, 0 end
  return table.getn(WoW.ah.current), WoW.ah.total
end
function GetAuctionItemInfo(kind, i)
  local l = auctionList(kind) and auctionList(kind)[i]
  if not l then return nil end
  -- An item the client has not cached yet comes back without a name at first.
  local name = l.name
  if l.noName then name = nil end
  -- 1.12 order: name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice,
  -- bidAmount, highBidder, owner. The in-game probe (docs/ttf-probe-after-scan.txt) reads
  -- "Amber Topaz, ..., 1, 2, 1, 1, 100, 0, 130, 0, nil, Tlaloc": highBidder is 1 when you hold
  -- the high bid, else nil.
  local high = nil
  if l.highBidder then high = 1 end
  return name, l.tex or "Interface\\Icons\\INV_Fabric_Linen_01", l.count or 1, l.quality or 1, 1, l.level or 1,
    l.minBid or 1, l.minInc or 0, l.buyout or 0, l.bid or 0, high, l.owner
end
function GetAuctionItemLink(kind, i)
  local l = auctionList(kind) and auctionList(kind)[i]
  if not l then return nil end
  return WoW.link(l.id, l.name, l.suffix)
end
function GetAuctionItemTimeLeft(kind, i)
  local list = auctionList(kind)
  if list and list[i] then return 3 end
  return nil
end
function CloseAuctionHouse() WoW.log("CloseAuctionHouse") end
-- The calls that spend or list gold. Logged so a test can prove nothing ever
-- makes them without a click.
--
-- PlaceAuctionBid(type, index, amount), as Blizzard's 1.12 AuctionUI calls it:
-- PlaceAuctionBid("list", GetSelectedAuctionItem("list"), price). A bid at or
-- above the buyout is a buyout (notes-aegis-exchange.md section 5). The real
-- client throws a usage error on a wrong argument type, so this one does too.
-- The server answers later; WoW.bidRespond() delivers that answer:
--   * success: the money leaves at once (a bid is held in escrow), PLAYER_MONEY
--     fires, then CHAT_MSG_SYSTEM with ERR_AUCTION_BID_PLACED, which aux waits
--     for (notes-aux.md section 4). A buyout leaves the server's listings; the
--     page the client shows keeps it until the next query, so indices only shift
--     after a search.
--   * failure: UI_ERROR_MESSAGE with the ERR_* text (UIErrorsFrame's event).
-- WoW.ah.bidReply picks the answer: "auto" (decided as the server would),
-- "money" or "notfound" (that error whatever happens), "none" (no reply ever).
function PlaceAuctionBid(kind, i, amount)
  if type(kind) ~= "string" or type(i) ~= "number" or type(amount) ~= "number" then
    error("Usage: PlaceAuctionBid(\"type\", index, bid)", 2)
  end
  WoW.log("PlaceAuctionBid", kind, i, amount)
  WoW.ah.bids = WoW.ah.bids or {}
  table.insert(WoW.ah.bids, { index = i, amount = amount, listing = WoW.ah.current[i] })
end
function WoW.bidRespond()
  local b = table.remove(WoW.ah.bids or {}, 1)
  if not b then error("no outstanding bid") end
  local reply = WoW.ah.bidReply
  if reply == "none" then return end
  local function fail(msg) WoW.fire("UI_ERROR_MESSAGE", msg) end
  if reply == "money" then return fail(ERR_NOT_ENOUGH_MONEY) end
  if reply == "notfound" then return fail(ERR_ITEM_NOT_FOUND) end
  local l, at = b.listing, nil
  for n, x in ipairs(WoW.ah.listings) do
    if x == l then at = n end
  end
  if not at then return fail(ERR_ITEM_NOT_FOUND) end
  if l.owner == WoW.player then return fail(ERR_AUCTION_BID_OWN) end
  local buyout = l.buyout or 0
  local isBuyout = buyout > 0 and b.amount >= buyout
  local cost = b.amount
  if isBuyout then cost = buyout end
  if cost > WoW.money then return fail(ERR_NOT_ENOUGH_MONEY) end
  if isBuyout then
    table.remove(WoW.ah.listings, at)
  else
    local need = l.minBid or 1
    if (l.bid or 0) > 0 then need = l.bid + (l.minInc or 0) end
    if b.amount < need then return fail(ERR_AUCTION_HIGHER_BID) end
    l.bid, l.highBidder = b.amount, true
  end
  WoW.money = WoW.money - cost
  WoW.fire("PLAYER_MONEY")
  WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_BID_PLACED)
end
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
-- 1.12 returns 1 or nil, like IsShiftKeyDown.
function IsControlKeyDown() if WoW.ctrl then return 1 end return nil end
function IsAltKeyDown() if WoW.alt then return 1 end return nil end
function GetCursorPosition() return WoW.cursorX, WoW.cursorY end
function GetBuildInfo() return "1.12.1", "5875", "Sep 19 2006" end
function ReloadUI() WoW.log("ReloadUI") end
function getglobal(n) return G[n] end
function setglobal(n, v) G[n] = v end
function PlaySound() end
function GetItemInfo(id)
  if type(id) == "string" then
    -- 1.12 takes an id or "item:..." itemString; a full coloured hyperlink finds nothing.
    if string.find(id, "|H", 1, true) then return nil end
    local _, _, n = string.find(id, "item:(%d+)")
    id = tonumber(n)
  end
  local it = WoW.items[id]
  if not it then return nil end
  return it.name, "item:" .. id .. ":0:0:0", it.quality or 1, it.level or 1, it.type or "Trade Goods",
    it.subtype or "", it.stack or 20, "", it.tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- Bags: WoW.bags[bag][slot] = { id=, name=, count=, vendor= } or {} for an empty slot.
-- Bags 0..4 are carried. The bank is container -1 plus bags 5..10, and like the
-- real client it reads as empty unless the bank window is open (WoW.bankOpen).
local function bankBag(bag) return bag == -1 or (bag >= 5 and bag <= 10) end
local function slotItem(bag, slot)
  if bankBag(bag) and not WoW.bankOpen then return nil end
  return WoW.bags[bag] and WoW.bags[bag][slot]
end
function GetContainerNumSlots(bag)
  if bankBag(bag) and not WoW.bankOpen then return 0 end
  return WoW.bags[bag] and table.getn(WoW.bags[bag]) or 0
end
function GetContainerItemLink(bag, slot)
  local it = slotItem(bag, slot)
  if it and it.id then return WoW.link(it.id, it.name) end
  return nil
end
function GetContainerItemInfo(bag, slot)
  local it = slotItem(bag, slot)
  if not it or not it.id then return nil end
  -- 1.12: texture, itemCount, locked, quality, readable
  return it.tex or "tex", it.count or 1, it.locked and 1 or nil
end
-- Selling at a merchant is a right-click on a bag item, which is this call.
function UseContainerItem(bag, slot) WoW.log("UseContainerItem", bag, slot) end
-- FrameXML (ContainerFrame.lua, 1.12): the bag item buttons' OnClick runs ContainerFrameItemButton_OnClick(arg1)
-- with `this` the item button (its parent frame's ID is the bag, its own ID the slot). This original only logs
-- what the game would do with the click.
function ContainerFrameItemButton_OnClick(button, ignoreModifiers)
  local b = this
  WoW.log("ContainerFrameItemButton_OnClick", button, b:GetParent():GetID(), b:GetID())
end
-- A bag item button as the client builds it, and a click on it through the global the OnClick script calls.
function WoW.bagButton(bag, slot)
  local container = CreateFrame("Frame", nil, nil)
  container:SetID(bag)
  local b = CreateFrame("Button", nil, container)
  b:SetID(slot)
  b:SetScript("OnClick", function() ContainerFrameItemButton_OnClick(arg1) end)
  return b
end
-- Looked up at click time, as the XML script does: the global may have been wrapped since the button was made.
function WoW.clickBag(b, mouse)
  local fn = getglobal("ContainerFrameItemButton_OnClick")
  local oldThis, oldArg = this, arg1
  this, arg1 = b, mouse
  fn(mouse)
  this, arg1 = oldThis, oldArg
end
-- Merchant: WoW.merchant[i] = { id=, name=, price=, quantity=, numAvailable=, noLink= }.
-- price is for the whole lot of `quantity` units; numAvailable -1 means unlimited stock.
-- ---------- scripted mailbox ----------
-- Tests put mails in WoW.mail (WoW.inbox is the same table): { subject=, money=, cod=, daysLeft=, hasItem=,
-- sender=, wasRead=, item={id,name,count}, isGM=, returned=, body=, textCreated= }. textCreated means "a copy of
-- the letter was made" and is nil unless a test sets it.
-- GetInboxNumItems() and GetInboxHeaderInfo(index) are logged so a test can count reads.
-- 1.12 GetInboxHeaderInfo(index) returns: packageIcon, stationeryIcon, sender, subject, money, CODAmount,
-- daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM (wowwiki, API GetInboxHeaderInfo).
function GetInboxNumItems() WoW.log("GetInboxNumItems") return table.getn(WoW.mail) end
function GetInboxHeaderInfo(i)
  WoW.log("GetInboxHeaderInfo", i)
  local m = WoW.mail[i]
  if not m then return nil end
  return "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Misc_Note_01", m.sender or "Auction House",
    m.subject, m.money or 0, m.cod or 0, m.daysLeft or 30, (m.item or m.hasItem) and 1 or nil, m.wasRead,
    m.returned and 1 or nil, m.textCreated and 1 or nil, nil, m.isGM and 1 or nil
end
-- GetInboxText, TakeInbox*, DeleteInboxItem, ReturnInboxItem, CheckInbox and the send model follow the cursor
-- model further down (they need it).
-- Events: MAIL_SHOW (mailbox opened), MAIL_INBOX_UPDATE (fires several times on first open), MAIL_CLOSED.

function GetMerchantNumItems() return table.getn(WoW.merchant) end
function GetMerchantItemInfo(i)
  local m = WoW.merchant[i]
  if not m then return nil end
  return m.name, m.tex or "tex", m.price or 0, m.quantity or 1, m.numAvailable or -1, 1
end
function GetMerchantItemLink(i)
  local m = WoW.merchant[i]
  if m and m.id and not m.noLink then return WoW.link(m.id, m.name) end
  return nil
end
function BuyMerchantItem(i, n) WoW.log("BuyMerchantItem", i, n) end

-- Trainer window, as Blizzard's 1.12 TrainerFrame uses it (wowwiki API pages):
-- GetNumTrainerServices() -> n; GetTrainerServiceInfo(i) -> name, rank (subtext), category
-- ("available", "unavailable", "used" or "header"); GetTrainerServiceCost(i) -> moneyCost;
-- GetTrainerServiceSkillReq(i) -> skillName, skillRank (nil when the service has no skill requirement).
-- Tests put rows in WoW.trainer = { { name=, rank=, category=, cost=, skill=, skillRank= } }.
-- Events: TRAINER_SHOW, TRAINER_UPDATE. BuyTrainerService and SetTrainerServiceTypeFilter
-- change the window or the character, so they only log: no addon code may call them.
function GetNumTrainerServices() return table.getn(WoW.trainer) end
function GetTrainerServiceInfo(i)
  local r = WoW.trainer[i]
  if not r then return nil end
  return r.name, r.rank or "", r.category or "available"
end
function GetTrainerServiceCost(i) local r = WoW.trainer[i] return r and (r.cost or 0) end
function GetTrainerServiceSkillReq(i) local r = WoW.trainer[i] if r then return r.skill, r.skillRank end end
function BuyTrainerService(i) WoW.log("BuyTrainerService", i) end
function SetTrainerServiceTypeFilter(kind, on) WoW.log("SetTrainerServiceTypeFilter", kind, on) end

-- ---------- posting, splitting and cancelling ----------
-- Cursor and sell slot. Source: Blizzard 1.12 AuctionFrame.lua and aux-addon (notes-aux.md section 4),
-- which post with ClearCursor(); ClickAuctionSellItemButton(); PickupContainerItem(bag, slot);
-- ClickAuctionSellItemButton(); StartAuction(minBid, buyout, runTime).
-- WoW.cursor = nil | { item =, count =, bag =, slot =, split = bool }: what the hand holds. The source
-- slot stays occupied but locked until the item is dropped or sold, as in the client.
-- WoW.sellSlot = nil | { item =, count =, bag =, slot = }: the auction frame's one item slot.
local function needNumbers(usage, ...)
  for i = 1, arg.n do
    if type(arg[i]) ~= "number" then error("Usage: " .. usage, 3) end
  end
end
local function unlock(c) if c and c.item then c.item.locked = nil end end
function ClearCursor()
  WoW.log("ClearCursor")
  unlock(WoW.cursor)
  WoW.cursor = nil
end
-- SplitContainerItem(bag, slot, count) (1.12 API, wowwiki): the hand then holds `count` of the stack.
function SplitContainerItem(bag, slot, count)
  needNumbers("SplitContainerItem(bag, slot, count)", bag, slot, count)
  WoW.log("SplitContainerItem", bag, slot, count)
  local it = slotItem(bag, slot)
  if not it or not it.id or it.locked or WoW.cursor then return end
  if count < 1 or count >= (it.count or 1) then return end
  it.locked = true
  WoW.cursor = { item = it, count = count, bag = bag, slot = slot, split = true }
end
-- PickupContainerItem(bag, slot): an empty hand takes the stack (locking it); a full hand drops into
-- the slot: empty slot (a split creates the new stack there), the same item (merge), another item (swap).
function PickupContainerItem(bag, slot)
  needNumbers("PickupContainerItem(bag, slot)", bag, slot)
  WoW.log("PickupContainerItem", bag, slot)
  local it = slotItem(bag, slot)
  local c = WoW.cursor
  if not c then
    if it and it.id and not it.locked then
      it.locked = true
      WoW.cursor = { item = it, count = it.count or 1, bag = bag, slot = slot }
    end
    return
  end
  if not WoW.bags[bag] or not WoW.bags[bag][slot] then return end
  if it == c.item then ClearCursor() return end
  if it and it.locked then return end
  if not it or not it.id then
    if c.split then
      local copy = {}
      for k, v in pairs(c.item) do copy[k] = v end
      copy.count, copy.locked = c.count, nil
      c.item.count = (c.item.count or 1) - c.count
      WoW.bags[bag][slot] = copy
    else
      WoW.bags[bag][slot] = c.item
      WoW.bags[c.bag][c.slot] = {}
    end
    unlock(c)
    WoW.cursor = nil
    WoW.fire("BAG_UPDATE")
    return
  end
  if it.id == c.item.id and c.split then
    c.item.count = (c.item.count or 1) - c.count
    it.count = (it.count or 1) + c.count
    unlock(c)
    WoW.cursor = nil
    WoW.fire("BAG_UPDATE")
    return
  end
  if not c.split then
    WoW.bags[bag][slot], WoW.bags[c.bag][c.slot] = c.item, it
    unlock(c)
    WoW.cursor = nil
    WoW.fire("BAG_UPDATE")
  end
end
-- ClickAuctionSellItemButton(): hand holds an item and the slot is empty: it goes in the slot; hand
-- empty and slot full: it comes back to the hand; both full: they swap.
function ClickAuctionSellItemButton()
  WoW.log("ClickAuctionSellItemButton")
  local c, s = WoW.cursor, WoW.sellSlot
  if c then
    WoW.sellSlot = { item = c.item, count = c.count, bag = c.bag, slot = c.slot }
    WoW.cursor = s and { item = s.item, count = s.count, bag = s.bag, slot = s.slot } or nil
  elseif s then
    WoW.cursor, WoW.sellSlot = { item = s.item, count = s.count, bag = s.bag, slot = s.slot }, nil
  end
end
-- 1.12 returns name, texture, count, quality, canUse, price; nothing for an empty slot.
function GetAuctionSellItemInfo()
  local s = WoW.sellSlot
  if not s then return nil end
  return s.item.name, s.item.tex or "tex", s.count, s.item.quality or 1, 1, (s.item.vendor or 0) * s.count
end
-- ---------- mailbox actions and the send slot (phase 5b) ----------
-- Sources: Blizzard 1.12 FrameXML MailFrame.lua / InboxFrame (OpenMail_* and InboxFrame_OnClick call
-- GetInboxText, TakeInboxMoney, TakeInboxItem, DeleteInboxItem, ReturnInboxItem; every take is answered by
-- MAIL_INBOX_UPDATE), SendMailFrame.lua (SendMailFrame_SendMail -> SendMail(to, subject, body); the slot is
-- ClickSendMailItemButton; MAIL_SEND_SUCCESS clears the form), and docs/research/notes-interact-mail.md
-- (TurtleMail's observed sequencing: one take per update event, delete only once the mail is empty).
-- WoW.inbox (alias of WoW.mail): { sender, subject, money, cod, item = { id, name, count, unique } or nil, isGM,
-- returned, body, daysLeft, wasRead }. A take shifts later mails down, as the client's list does.
local function inboxUpdate() WoW.fire("MAIL_INBOX_UPDATE") end
local function errMsg(m) WoW.fire("UI_ERROR_MESSAGE", m) end
-- 1.12: body, stationery, isTakeable, isInvoice. Reading marks the mail read.
function GetInboxText(i)
  WoW.log("GetInboxText", i)
  local m = WoW.mail[i]
  if not m then return nil end
  m.wasRead = 1
  return m.body, "Interface\\Icons\\INV_Misc_Note_01", nil, nil
end
function GetInboxInvoiceInfo(i) WoW.log("GetInboxInvoiceInfo", i) end
function CheckInbox() WoW.log("CheckInbox") end
function TakeInboxMoney(i)
  WoW.log("TakeInboxMoney", i)
  local m = WoW.mail[i]
  if not m or (m.money or 0) <= 0 then return end
  WoW.money = WoW.money + m.money
  m.money = 0
  WoW.fire("PLAYER_MONEY")
  inboxUpdate()
end
-- The item goes to the first free slot of bags 0..4; with none, ERR_INV_FULL and the mail keeps it. A
-- `unique` item the player already carries gives ERR_ITEM_MAX_COUNT. A COD mail is paid first (the addon
-- never does this; ERR_NOT_ENOUGH_MONEY if the player can't). Stacks are not merged into existing ones.
function TakeInboxItem(i)
  WoW.log("TakeInboxItem", i)
  local m = WoW.mail[i]
  if not m or not m.item then return end
  local it = m.item
  if it.unique then
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
        local s = WoW.bags[bag][slot]
        if s and s.id == it.id then return errMsg(ERR_ITEM_MAX_COUNT) end
      end
    end
  end
  if (m.cod or 0) > WoW.money then return errMsg(ERR_NOT_ENOUGH_MONEY) end
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local s = WoW.bags[bag][slot]
      if s and not s.id then
        local tex = WoW.items[it.id] and WoW.items[it.id].tex
        WoW.bags[bag][slot] = { id = it.id, name = it.name, count = it.count or 1, tex = tex, unique = it.unique }
        m.item, m.hasItem = nil, nil
        if (m.cod or 0) > 0 then WoW.money = WoW.money - m.cod m.cod = 0 WoW.fire("PLAYER_MONEY") end
        WoW.fire("BAG_UPDATE")
        inboxUpdate()
        return
      end
    end
  end
  errMsg(ERR_INV_FULL)
end
function DeleteInboxItem(i)
  WoW.log("DeleteInboxItem", i)
  if not WoW.mail[i] then return end
  table.remove(WoW.mail, i)
  inboxUpdate()
end
-- Returned mails are logged in WoW.returned (the sender would receive them).
function ReturnInboxItem(i)
  WoW.log("ReturnInboxItem", i)
  local m = WoW.mail[i]
  if not m then return end
  table.insert(WoW.returned, m)
  table.remove(WoW.mail, i)
  inboxUpdate()
end

-- Send slot. WoW.sendSlot = nil | { item =, count =, bag =, slot = }, WoW.sendMoney in copper.
-- ClickSendMailItemButton works like ClickAuctionSellItemButton: hand and slot swap.
function ClickSendMailItemButton()
  WoW.log("ClickSendMailItemButton")
  local c, s = WoW.cursor, WoW.sendSlot
  if c then
    WoW.sendSlot = { item = c.item, count = c.count, bag = c.bag, slot = c.slot }
    WoW.cursor = s and { item = s.item, count = s.count, bag = s.bag, slot = s.slot } or nil
  elseif s then
    WoW.cursor, WoW.sendSlot = { item = s.item, count = s.count, bag = s.bag, slot = s.slot }, nil
  end
end
-- 1.12: name, texture, count, quality; nothing for an empty slot.
function GetSendMailItem()
  local s = WoW.sendSlot
  if not s then return nil end
  return s.item.name, s.item.tex or "tex", s.count, s.item.quality or 1
end
function SetSendMailMoney(c) WoW.log("SetSendMailMoney", c) WoW.sendMoney = c or 0 end
function GetSendMailMoney() return WoW.sendMoney end
function GetSendMailPrice() return 30 end
-- SendMail(to, subject, body): on success the attachment leaves the bags (a split stack only reduces
-- the source), postage and money are paid (the balance never goes below 0), the slot clears and
-- MAIL_SEND_SUCCESS fires. A queued WoW.mailErrors entry (a string, usually an ERR_* global) is fired as
-- UI_ERROR_MESSAGE instead and nothing changes. Mailing yourself gives ERR_MAIL_TO_SELF.
function SendMail(to, subject, body)
  WoW.log("SendMail", to, subject, body)
  if table.getn(WoW.mailErrors) > 0 then return errMsg(table.remove(WoW.mailErrors, 1)) end
  if string.lower(to or "") == string.lower(WoW.player) then return errMsg(ERR_MAIL_TO_SELF) end
  local s, item = WoW.sendSlot, nil
  if s then
    item = { id = s.item.id, name = s.item.name, count = s.count }
    if s.count < (s.item.count or 1) then s.item.count = s.item.count - s.count
    else WoW.bags[s.bag][s.slot] = {} end
    s.item.locked = nil
  end
  table.insert(WoW.sent, { to = to, subject = subject, body = body, money = WoW.sendMoney, item = item })
  WoW.money = math.max(0, WoW.money - GetSendMailPrice() - WoW.sendMoney)
  WoW.sendSlot, WoW.sendMoney = nil, 0
  WoW.fire("PLAYER_MONEY")
  if item then WoW.fire("BAG_UPDATE") end
  WoW.fire("MAIL_SEND_SUCCESS")
end
-- The mailbox session. Blizzard's MAIL_SHOW handler shows MailFrame (our hook must wait a frame to hide it);
-- CloseMail() ends the session and fires MAIL_CLOSED. MailFrame's OnHide calls CloseMail, so hiding it
-- closes the mailbox: this is what the hook must dodge.
-- Blizzard's MAIL_CLOSED handler hides MailFrame; CloseMail does so too, guarded because its OnHide calls back.
function CloseMail()
  if WoW.closingMail then return end
  WoW.log("CloseMail")
  WoW.closingMail = true
  WoW.mailOpen = false
  if MailFrame and MailFrame.shown then MailFrame:Hide() end
  WoW.closingMail = false
  WoW.fire("MAIL_CLOSED")
end
function OpenBackpack() WoW.log("OpenBackpack") end
function IsAddOnLoaded(name) if WoW.addons[name] then return 1 end return nil end
-- Test helper: the player walks up to a mailbox. MailFrame shows (Blizzard's handler), then MAIL_SHOW and one
-- MAIL_INBOX_UPDATE fire to the addons.
function WoW.openMailbox()
  WoW.mailOpen = true
  MailFrame:Show()
  WoW.fire("MAIL_SHOW")
  WoW.fire("MAIL_INBOX_UPDATE")
end
-- CalculateAuctionDeposit(runTime) is the client's figure for the item in the slot: here 15% of the
-- vendor price per 2 hours, scaled by duration. On Turtle the server charges about 0.6x of it
-- (notes-aegis-exchange.md): WoW.ah.depositFactor.
function CalculateAuctionDeposit(minutes)
  if type(minutes) ~= "number" then error("Usage: CalculateAuctionDeposit(runTime)", 2) end
  local s = WoW.sellSlot
  if not s then return 0 end
  return math.floor((s.item.vendor or 0) * s.count * 0.15 * minutes / 120)
end
-- StartAuction(minBid, buyoutPrice, runTime): run time must be 120, 480 or 1440 on Turtle. The server
-- answers later; WoW.postRespond() delivers the answer. WoW.ah.postReply: "auto", "none" (never),
-- "money" or "limited" (that error whatever happens).
function StartAuction(bid, buyout, minutes)
  needNumbers("StartAuction(minBid, buyoutPrice, runTime)", bid, buyout, minutes)
  if minutes ~= 120 and minutes ~= 480 and minutes ~= 1440 then
    error("Usage: StartAuction(minBid, buyoutPrice, runTime): runTime is 120, 480 or 1440", 2)
  end
  WoW.log("StartAuction", bid, buyout, minutes)
  local s = WoW.sellSlot
  if not s then return end
  table.insert(WoW.ah.posts, { bid = bid, buyout = buyout, minutes = minutes, slot = s })
end
function WoW.postRespond()
  local p = table.remove(WoW.ah.posts, 1)
  if not p then error("no outstanding post") end
  local reply = WoW.ah.postReply
  if reply == "none" then return end
  local function fail(msg) WoW.fire("UI_ERROR_MESSAGE", msg) end
  if reply == "money" then return fail(ERR_NOT_ENOUGH_MONEY) end
  if reply == "limited" then return fail(ERR_AUCTION_LIMITED_DURATION_ITEM) end
  local s = p.slot
  local deposit = math.floor(((s.item.vendor or 0) * s.count * 0.15 * p.minutes / 120) * WoW.ah.depositFactor)
  if deposit > WoW.money then return fail(ERR_NOT_ENOUGH_MONEY) end
  -- WoW.ah.moneyLate: the server's PLAYER_MONEY arrives after the chat reply (WoW.moneyArrive()), as it
  -- often does on the real client.
  if WoW.ah.moneyLate then WoW.lateDeposit = deposit else WoW.money = WoW.money - deposit end
  -- the stack leaves the bag; the auction joins the server's listings
  WoW.bags[s.bag][s.slot] = {}
  WoW.sellSlot = nil
  table.insert(WoW.ah.listings, { id = s.item.id, name = s.item.name, count = s.count, buyout = p.buyout,
    minBid = p.bid, owner = WoW.player, quality = s.item.quality, tex = s.item.tex })
  if not WoW.ah.moneyLate then WoW.fire("PLAYER_MONEY") end
  WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_STARTED)
  WoW.fire("BAG_UPDATE")
end
function WoW.moneyArrive()
  local d = WoW.lateDeposit
  if not d then error("no late deposit") end
  WoW.lateDeposit = nil
  WoW.money = WoW.money - d
  WoW.fire("PLAYER_MONEY")
end
-- GetOwnerAuctionItems(page) asks for your auctions; WoW.ownerRespond() answers with
-- AUCTION_OWNED_LIST_UPDATE (the page the client then shows is a copy, stale until asked again).
function GetOwnerAuctionItems(page)
  if type(page) ~= "number" then error("Usage: GetOwnerAuctionItems(page)", 2) end
  WoW.log("GetOwnerAuctionItems", page)
  WoW.ah.ownerPending = true
end
function WoW.ownerRespond()
  if not WoW.ah.ownerPending then error("no outstanding owner request") end
  WoW.ah.ownerPending = false
  local owned = {}
  for _, l in ipairs(WoW.ah.listings) do
    if l.owner == WoW.player then table.insert(owned, l) end
  end
  WoW.ah.owned = owned
  WoW.fire("AUCTION_OWNED_LIST_UPDATE")
end
-- CancelAuction(index) cancels row `index` of the owner list (1.12 AuctionFrame.lua passes
-- GetSelectedAuctionItem("owner")). The server answers later: WoW.cancelRespond() sends
-- ERR_AUCTION_REMOVED, or ERR_ITEM_NOT_FOUND if that auction is already gone.
function CancelAuction(i)
  needNumbers("CancelAuction(index)", i)
  WoW.log("CancelAuction", i)
  table.insert(WoW.ah.cancels, { listing = WoW.ah.owned[i] })
end
function WoW.cancelRespond()
  local c = table.remove(WoW.ah.cancels, 1)
  if not c then error("no outstanding cancel") end
  if WoW.ah.cancelReply == "none" then return end
  local at = nil
  for n, x in ipairs(WoW.ah.listings) do
    if x == c.listing then at = n end
  end
  if not at then return WoW.fire("UI_ERROR_MESSAGE", ERR_ITEM_NOT_FOUND) end
  table.remove(WoW.ah.listings, at)
  WoW.fire("CHAT_MSG_SYSTEM", ERR_AUCTION_REMOVED)
end
-- ---------- tradeskill window ----------
-- WoW.tradeskill = { name=, rank=, maxRank=, selected=, rows = {
--   { header = true, name = "Cloth", collapsed = nil|true },
--   { name = "Bolt of Silk Cloth", type = "medium", id = 4305, made = { 1, 1 }, available = 2, noLink = nil|true,
--     reagents = { { id = 4306, name = "Silk Cloth", count = 4, have = 37, noLink = nil|true } } } } }
-- Like the real list, a collapsed header hides the recipes under it from every call below.
local function tsRows()
  local out, hide = {}, false
  for _, r in ipairs(WoW.tradeskill.rows) do
    if r.header then
      hide = r.collapsed and true or false
      table.insert(out, r)
    elseif not hide then
      table.insert(out, r)
    end
  end
  return out
end
local function tsRow(i)
  local rows = tsRows()
  return rows[i]
end
function GetTradeSkillLine()
  local t = WoW.tradeskill
  return t.name or "UNKNOWN", t.rank or 0, t.maxRank or 0
end
function GetNumTradeSkills() return table.getn(tsRows()) end
function GetTradeSkillInfo(i)
  local r = tsRow(i)
  if not r then return nil end
  if r.header then
    if r.collapsed then return r.name, "header", 0, nil end
    return r.name, "header", 0, 1
  end
  return r.name, r.type or "medium", r.available or 0, nil
end
function GetTradeSkillItemLink(i)
  local r = tsRow(i)
  if r and r.id and not r.noLink then return WoW.link(r.id, r.product or r.name) end
  return nil
end
function GetTradeSkillNumMade(i)
  local r = tsRow(i)
  if not r or r.header then return 0, 0 end
  local m = r.made or { 1, 1 }
  return m[1], m[2]
end
function GetTradeSkillNumReagents(i)
  local r = tsRow(i)
  if not r or not r.reagents then return 0 end
  return table.getn(r.reagents)
end
function GetTradeSkillReagentInfo(i, n)
  local r = tsRow(i)
  local g = r and r.reagents and r.reagents[n]
  if not g then return nil end
  return g.name, g.tex or "tex", g.count or 1, g.have or 0
end
function GetTradeSkillReagentItemLink(i, n)
  local r = tsRow(i)
  local g = r and r.reagents and r.reagents[n]
  if g and g.id and not g.noLink then return WoW.link(g.id, g.name) end
  return nil
end
function GetTradeSkillSelectionIndex() return WoW.tradeskill.selected or 0 end
function DoTradeSkill(i, n) WoW.log("DoTradeSkill", i, n) end
-- TradeSkillFrame is load-on-demand: it does not exist until the first
-- tradeskill window opens. WoW.openTradeSkill() does what the client does:
-- load it if needed, show it, then fire TRADE_SKILL_SHOW.
function WoW.openTradeSkill()
  if not TradeSkillFrame then
    TradeSkillFrame = newFrame("Frame", "TradeSkillFrame", UIParent)
    TradeSkillFrame.shown = false
  end
  TradeSkillFrame:Show()
  WoW.fire("TRADE_SKILL_SHOW")
end
-- Equipped bags: WoW.equip[inventorySlot] = { id =, name = }; the item's type/subtype come from WoW.items.
-- ContainerIDToInventoryID(bag): bag 1..4 are inventory slots 20..23 (1.12 FrameXML, ContainerFrame.lua
-- uses it as ContainerIDToInventoryID(id) for bag slots 1-4). GetItemInfo's 5th and 6th returns are
-- type and subType ("Container" / "Bag", "Quiver", "Soul Bag", ...).
function ContainerIDToInventoryID(bag)
  if type(bag) ~= "number" then error("Usage: ContainerIDToInventoryID(bagID)", 2) end
  return 19 + bag
end
function GetInventoryItemLink(unit, slot)
  local it = WoW.equip and WoW.equip[slot]
  if unit == "player" and it then return WoW.link(it.id, it.name) end
  return nil
end
function GetInventoryItemCount() return 0 end

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- 1.12 GlobalStrings.lua. ERR_AUCTION_RESTRICTED_ACCOUNT is left undefined:
-- the addon must only match the globals the client has.
ERR_AUCTION_BID_PLACED = "Bid accepted."
ERR_NOT_ENOUGH_MONEY = "You don't have enough money."
ERR_ITEM_NOT_FOUND = "Item not found."
ERR_AUCTION_HIGHER_BID = "There is already a higher bid on that item."
ERR_AUCTION_BID_OWN = "You cannot bid on your own auction."
ERR_AUCTION_DATABASE_ERROR = "Internal auction error."
ERR_AUCTION_STARTED = "Auction created."
ERR_AUCTION_REMOVED = "Auction cancelled."
ERR_AUCTION_SOLD_S = "Your auction of %s sold."
-- Mail subject formats as the probe read them from the client.
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
ERR_INV_FULL = "Inventory is full."
ERR_ITEM_MAX_COUNT = "You can't carry any more of those items."
ERR_MAIL_TO_SELF = "You can't send mail to yourself."
ERR_PLAYER_WRONG_FACTION = "Players of the opposing faction can't receive your mail."
ERR_MAIL_TARGET_NOT_FOUND = "Player not found."
ERR_MAIL_REACHED_CAP = "That player's mailbox is full."
ERR_MAIL_DATABASE_ERROR = "Internal mail database error."
ERR_AUCTION_LIMITED_DURATION_ITEM = "Items with a limited duration cannot be auctioned."
ERR_AUCTION_REPAIR_ITEM = "You must repair that item first."
ERR_AUCTION_USED_CHARGES = "Items with used charges cannot be auctioned."
YES, NO = "Yes", "No"
UIParent = newFrame("Frame", "UIParent")
Minimap = newFrame("Frame", "Minimap")
WorldFrame = newFrame("Frame", "WorldFrame")
GameTooltip = newFrame("GameTooltip", "GameTooltip")
GameTooltip.SetOwner = function(self, owner, anchor) self.owner, self.anchor = owner, anchor end
AuctionFrame = newFrame("Frame", "AuctionFrame")
AuctionFrame.shown = false
-- Blizzard's own OnHide ends the auction session; this is what the swap must dodge.
AuctionFrame:SetScript("OnHide", function() CloseAuctionHouse() end)
MailFrame = newFrame("Frame", "MailFrame")
MailFrame.shown = false
WoW.mailFrameOnHide = function() CloseMail() end
MailFrame:SetScript("OnHide", WoW.mailFrameOnHide)
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

_G = nil          -- 1.12 has no global _G: addon code must use getglobal / getfenv(0)
