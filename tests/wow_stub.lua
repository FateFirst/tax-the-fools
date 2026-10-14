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
  WoW.merchant = {}
  WoW.bankOpen = false
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
function GetBuildInfo() return "1.12.1", "5875", "Sep 19 2006" end
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
  return it.tex or "tex", it.count or 1
end
-- Selling at a merchant is a right-click on a bag item, which is this call.
function UseContainerItem(bag, slot) WoW.log("UseContainerItem", bag, slot) end
-- Merchant: WoW.merchant[i] = { id=, name=, price=, quantity=, numAvailable=, noLink= }.
-- price is for the whole lot of `quantity` units; numAvailable -1 means unlimited stock.
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
function GetInventoryItemLink() return nil end
function GetInventoryItemCount() return 0 end

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
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
