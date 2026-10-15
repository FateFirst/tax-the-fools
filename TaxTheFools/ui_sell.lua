TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Auction, Sell, I = TaxTheFools.Auction, TaxTheFools.Sell, TaxTheFools.Items
local SellUI = { frame = nil }
-- Fields that may be nil live here, not on the frame: the fake client's frames answer an unset field with a function.
local st = {}
TaxTheFools.SellUI = SellUI

-- Phase 3b spec section 4. Nothing here spends: a search is a Scan.Browse, and the one button
-- reaches Auction.Split / Auction.Post only from its OnClick.

SellUI.COLS, SellUI.ROWS, SellUI.CELL = 6, 8, 38
SellUI.RX = 252            -- left edge of the pricing panel

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

SellUI.COLUMNS = {
  { label = "Stack", width = 60, align = "RIGHT", sort = "count", fmt = function(r) return tostring(r.count) end },
  { label = "Each", width = 110, align = "RIGHT", sort = "unit", fmt = function(r) return money(r.unit) end },
  { label = "%", width = 60, align = "RIGHT", sort = "pct",
    fmt = function(r) return r.pct and (r.pct .. "%") or "-", TaxTheFools.Browse.PctToken(r.pct) end },
  { label = "Seller", width = 120, sort = "owner",
    fmt = function(r) if r.mine then return "you", "good" end return r.owner or "?" end },
}

function SellUI.Market(item)
  local m = item and DB.Realm().market[item.key]
  return m and m.v or nil
end

function SellUI.Floor(item)
  local m = SellUI.Market(item)
  if not m then return nil end
  return math.ceil(m * DB.S().sell.floorPct / 100)
end

-- ---------- the bags ----------

-- One record per auctionable item key, every bag slot combined, sorted by name.
function SellUI.ReadBags()
  local by, order = {}, {}
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local key, id = U.keyFromLink(link)
      if key and Sell.Auctionable(Sell.TipLines(bag, slot)) then
        local tex, n, locked = GetContainerItemInfo(bag, slot)
        n = n or 1
        local it = by[key]
        if not it then
          local rec = I.Resolve(id)
          it = { key = key, id = id, name = (rec and rec.n) or U.linkName(link) or key, quality = rec and rec.q,
                 tex = tex or (rec and rec.t), total = 0, biggest = 0, maxStack = (rec and rec.st) or 1, slots = {} }
          by[key] = it
          table.insert(order, it)
        end
        it.total = it.total + n
        if n > it.biggest then it.biggest = n end
        table.insert(it.slots, { bag = bag, slot = slot, count = n, locked = locked and true or false })
      end
    end
  end
  for _, it in ipairs(order) do
    if it.biggest > it.maxStack then it.maxStack = it.biggest end
  end
  table.sort(order, function(a, b) return a.name < b.name end)
  return order
end

function SellUI.Find(key)
  local p = SellUI.frame
  for _, it in ipairs(p.items) do
    if it.key == key then return it end
  end
  return nil
end

function SellUI.PaintGrid()
  local p = SellUI.frame
  local per = SellUI.COLS
  local rows = math.ceil(table.getn(p.items) / per)
  local maxOff = math.max(0, rows - SellUI.ROWS)
  if p.gridOffset > maxOff then p.gridOffset = maxOff end
  if p.gridOffset < 0 then p.gridOffset = 0 end
  for i, c in ipairs(p.cells) do
    local it = p.items[i + p.gridOffset * per]
    c.item = it or false
    if it then
      c.icon:SetTexture(it.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
      c.count:SetText(it.total > 1 and tostring(it.total) or "")
      if p.sel and p.sel.key == it.key then c.mark:Show() else c.mark:Hide() end
      c:Show()
    else
      c.count:SetText("")
      c.mark:Hide()
      c:Hide()
    end
  end
end

function SellUI.OnBags()
  local p = SellUI.frame
  if not p then return end
  p.splitting = false
  if p:IsVisible() then SellUI.Refresh() end
end

function SellUI.Refresh()
  local p = SellUI.frame
  if not p then return end
  p.items = SellUI.ReadBags()
  if p.sel then
    p.sel = SellUI.Find(p.sel.key) or false
    if not p.sel then SellUI.Clear() end
  end
  if p.sel then SellUI.Clamp() end
  SellUI.PaintGrid()
  SellUI.Update()
end

-- ---------- selecting and competition ----------

function SellUI.Clear()
  local p = SellUI.frame
  p.sel, p.listings, p.searchKey, st.buyout, st.bid, st.source = false, {}, false, nil, nil, nil
  p.list:SetData({})
  SellUI.FillFields()
end

function SellUI.Select(item)
  local p = SellUI.frame
  p.sel = item
  p.allowBelow, p.posted, p.splitting, p.bidEdited = false, 0, false, false
  p.minutes = DB.S().sell.duration
  p.stackSize = math.max(1, math.min(item.maxStack, item.total))
  p.nStacks = math.max(1, Sell.Stacks(item.total, p.stackSize, item.maxStack))
  p.listings, st.source, st.buyout, st.bid = {}, nil, nil, nil
  p.status:SetText("")
  SellUI.PaintGrid()
  SellUI.Competition(item)
end

-- Page 0 of an exact-name browse, refused while a scan owns the auction house.
function SellUI.Competition(item)
  local p = SellUI.frame
  p.searchKey = false
  if Scan.Busy() then
    U.msg("A scan is using the auction house. Pause it to search.")
    return SellUI.Snapshot(item, "A scan is running: priced from the last scan.")
  end
  local before = Scan.lastFinished
  if not Scan.Browse(item.name, 0, GetTime()) then
    return SellUI.Snapshot(item, "Could not search: priced from the last scan.")
  end
  p.searchKey, st.searchBefore = item.key, before
  p.list:SetData({})
  SellUI.Say("Searching...", "dim")
  SellUI.FillFields()
  SellUI.Update()
end

function SellUI.OnScan()
  local p = SellUI.frame
  if not p or not p.searchKey or Scan.Busy() then return end
  local key, before = p.searchKey, st.searchBefore
  p.searchKey = false
  if not p.sel or p.sel.key ~= key then return end
  if Scan.lastFinished ~= before then
    local listings = {}
    for _, r in ipairs(Scan.lastRows) do
      if r.key == key and r.unit then
        table.insert(listings, { unit = r.unit, count = r.count, owner = r.owner })
      end
    end
    SellUI.SetListings(listings)
    SellUI.Say("", "dim")
  else
    SellUI.Snapshot(p.sel, "No reply from the auction house: priced from the last scan.")
  end
end

function SellUI.Snapshot(item, why)
  local listings = {}
  local snap = DB.Realm().snapshot
  for _, s in ipairs((snap and snap.rows[item.key]) or {}) do
    local count, buyout, _, owner = Scan.ParseSnapRow(s)
    if count and count > 0 and buyout and buyout > 0 then
      table.insert(listings, { unit = buyout / count, count = count, owner = owner })
    end
  end
  SellUI.SetListings(listings)
  SellUI.Say(why, "warn")
end

-- Fills the competition list and the suggested prices.
function SellUI.SetListings(listings)
  local p = SellUI.frame
  local item = p.sel
  local market = SellUI.Market(item)
  local data = {}
  for _, l in ipairs(listings) do
    l.mine = (l.owner ~= nil and l.owner == DB.charName)
    l.pct = market and math.floor(l.unit / market * 100 + 0.5) or nil
    table.insert(data, l)
  end
  table.sort(data, function(a, b) return a.unit < b.unit end)
  p.listings = data
  p.list:SetData(data)
  local s = DB.S().sell
  local sug = Sell.Suggest(data, market, I.Vendor(item.id),
    { floorPct = s.floorPct, undercut = s.undercut, bidPct = s.bidPct, me = DB.charName })
  st.buyout, st.bid, st.source, p.bidEdited = sug.buyout, sug.bid, sug.source, false
  SellUI.FillFields()
  SellUI.Update()
end

function SellUI.FillFields()
  local p = SellUI.frame
  p.updating = true
  p.buyoutIn:SetValue(st.buyout)
  p.bidIn:SetValue(st.bid)
  p.sizeBox:SetText(p.sel and tostring(p.stackSize) or "")
  p.countBox:SetText(p.sel and tostring(p.nStacks) or "")
  p.updating = false
end

-- ---------- editing ----------

local function bidFor(buyout)
  local b = math.floor(buyout * DB.S().sell.bidPct / 100)
  if b < 1 then b = 1 end
  return b
end

function SellUI.BuyoutEdited(v)
  local p = SellUI.frame
  if not p.sel then return end
  if v and v < 1 then v = nil end
  st.buyout, st.source = v, "own"
  if not p.bidEdited then
    st.bid = v and bidFor(v) or nil
    p.updating = true
    p.bidIn:SetValue(st.bid)
    p.updating = false
  end
  SellUI.Update()
end

function SellUI.BidEdited(v)
  local p = SellUI.frame
  if not p.sel then return end
  if v and v < 1 then v = nil end
  st.bid, p.bidEdited = v, true
  SellUI.Update()
end

-- Keeps the size and stack count inside what is held.
function SellUI.Clamp()
  local p = SellUI.frame
  local it = p.sel
  local top = math.max(1, math.min(it.maxStack, it.total))
  if p.stackSize > top then p.stackSize = top end
  if p.stackSize < 1 then p.stackSize = 1 end
  local cap = Sell.Stacks(it.total, p.stackSize, it.maxStack) + p.posted
  if p.nStacks > cap then p.nStacks = cap end
  if p.nStacks < 1 then p.nStacks = 1 end
end

local function boxNumber(box)
  return tonumber(box:GetText())
end

function SellUI.SizeEdited()
  local p = SellUI.frame
  if p.updating or not p.sel then return end
  local n = boxNumber(p.sizeBox)
  if not n then return end
  p.stackSize = math.floor(n)
  p.posted = 0
  SellUI.Clamp()
  p.nStacks = math.max(1, Sell.Stacks(p.sel.total, p.stackSize, p.sel.maxStack))
  p.updating = true
  if n ~= p.stackSize then p.sizeBox:SetText(tostring(p.stackSize)) end
  p.countBox:SetText(tostring(p.nStacks))
  p.updating = false
  SellUI.Update()
end

function SellUI.CountEdited()
  local p = SellUI.frame
  if p.updating or not p.sel then return end
  local n = boxNumber(p.countBox)
  if not n then return end
  p.nStacks = math.floor(n)
  SellUI.Clamp()
  p.updating = true
  if n ~= p.nStacks then p.countBox:SetText(tostring(p.nStacks)) end
  p.updating = false
  SellUI.Update()
end

function SellUI.SetMinutes(m)
  local p = SellUI.frame
  p.minutes = m
  SellUI.Update()
end

-- ---------- the numbers ----------

-- Deposit for the chosen stack: the learned figure, else an estimate from the vendor price.
function SellUI.Deposit()
  local p = SellUI.frame
  local item = p.sel
  local learned = Sell.Deposit(TaxTheFoolsDB.items, item.id, p.minutes, p.stackSize)
  if learned then return learned, false end
  local v = I.Vendor(item.id)
  if v then return TaxTheFools.Craft.Deposit(v, item.maxStack, p.stackSize, p.minutes, 1), true end
  return nil, true
end

-- What the one button would do: { kind = "post" | "split", bag, slot } or nil.
function SellUI.Plan()
  local p = SellUI.frame
  local it = p.sel
  if not it then return nil end
  local size, bigger = p.stackSize, nil
  for _, s in ipairs(it.slots) do
    if not s.locked then
      if s.count == size then return { kind = "post", bag = s.bag, slot = s.slot } end
      if s.count > size and (not bigger or s.count < bigger.count) then bigger = s end
    end
  end
  if bigger then return { kind = "split", bag = bigger.bag, slot = bigger.slot } end
  return nil
end

-- Why the button is unavailable, or nil.
function SellUI.WhyNot()
  local p = SellUI.frame
  if not p.sel then return "Pick an item from your bags." end
  if p.searchKey then return "Searching the auction house." end
  if p.splitting then return "Waiting for your bags to update." end
  if Auction.busy then return "Waiting for the auction house to answer." end
  if p.posted >= p.nStacks then return "All " .. p.nStacks .. " stacks are posted." end
  if not st.buyout then return "Set a buyout price first." end
  if st.bid and st.bid > st.buyout then return "The starting bid is above the buyout." end
  local floor = SellUI.Floor(p.sel)
  if floor and st.buyout < floor and not p.allowBelow then
    return "Below your floor. Tick Allow below floor to post it."
  end
  local plan = SellUI.Plan()
  if not plan then return "You have no stack of " .. p.stackSize .. " and none bigger to split." end
  if plan.kind == "post" then
    local dep = SellUI.Deposit()
    if dep and dep > GetMoney() then return "You can't afford the deposit of " .. U.money(dep, true) .. "." end
  end
  return nil
end

function SellUI.Update()
  local p = SellUI.frame
  if not p then return end
  local it = p.sel
  if not it then
    p.title:SetText("Pick an item from your bags")
    for _, t in ipairs({ p.sourceText, p.depositText, p.netText, p.floorText }) do t:SetText("") end
    p.postBtn:SetLabel("Post")
    p.postBtn:SetEnabled(false)
    W.Tip(p.postBtn, "Post", "Pick an item from your bags.")
    p.allowSw:Refresh()
    return
  end
  p.title:SetText(U.quality(it.quality) .. it.name .. "|r  (" .. it.total .. " held)")
  local labels = { undercut = { "undercut", "good" }, market = { "market", "text" },
                   vendor = { "vendor x3", "warn" }, own = { "your price", "dim" } }
  local l = labels[st.source or ""] or { "set a price", "warn" }
  p.sourceText:SetText(l[1])
  Th.Color(p.sourceText, l[2])
  for m, b in pairs(p.durBtns) do
    b.picked = (m == p.minutes)
    Th.TintSlice(b.fill, b.picked and "accentDeep" or "strip", 1)
  end
  local dep, approx = SellUI.Deposit()
  if dep then p.depositText:SetText("Deposit " .. (approx and "approx " or "") .. U.money(dep, true))
  else p.depositText:SetText("Deposit unknown") end
  if st.buyout then
    p.netText:SetText("You receive " .. U.money(Sell.Net(st.buyout * p.stackSize, dep or 0), true))
  else
    p.netText:SetText("")
  end
  local floor = SellUI.Floor(it)
  if floor and st.buyout and st.buyout < floor then
    p.floorText:SetText("Below your floor (" .. DB.S().sell.floorPct .. "% of market)")
  else
    p.floorText:SetText("")
  end
  p.allowSw:Refresh()
  local plan = SellUI.Plan()
  local why = SellUI.WhyNot()
  if plan and plan.kind == "split" then
    p.postBtn:SetLabel("Split")
  else
    p.postBtn:SetLabel("Post " .. math.min(p.posted + 1, p.nStacks) .. " of " .. p.nStacks)
  end
  p.postBtn:SetEnabled(not why)
  W.Tip(p.postBtn, (plan and plan.kind == "split") and "Split" or "Post",
    why or ((plan and plan.kind == "split") and "Split a stack of " .. p.stackSize .. " off into an empty bag slot."
      or "Post one stack at the prices above."))
end

function SellUI.Say(text, token)
  local p = SellUI.frame
  if not p then return end
  p.status:SetText(text or "")
  Th.Color(p.status, token or "dim")
end

-- ---------- the button ----------

-- OnClick only. Split and Post each make one action's worth of calls.
function SellUI.Click()
  local p = SellUI.frame
  if not p.sel or SellUI.WhyNot() then return false end
  local plan = SellUI.Plan()
  if plan.kind == "split" then
    local ok = Auction.Split(plan.bag, plan.slot, p.stackSize)
    if ok then p.splitting = true end
    SellUI.Update()
    return ok and true or false
  end
  local n = p.stackSize
  local bid = st.bid or bidFor(st.buyout)
  local r = Auction.Post(plan.bag, plan.slot, n, bid * n, st.buyout * n, p.minutes, p.sel.key, p.allowBelow,
    SellUI.Posted, SellUI.PostFailed)
  SellUI.Update()
  return r and true or false
end

function SellUI.Posted()
  local p = SellUI.frame
  p.posted = p.posted + 1
  SellUI.Say(p.posted .. " of " .. p.nStacks .. " posted", "good")
  if TaxTheFools.AuctionsUI and TaxTheFools.AuctionsUI.Request then TaxTheFools.AuctionsUI.Request() end
  SellUI.Refresh()
end

function SellUI.PostFailed(text)
  SellUI.Say(text or "", "bad")
  SellUI.Update()
end

-- ---------- building ----------

local function label(p, text, anchor, x, y)
  local t = Th.Text(p, "body", 12, "dim")
  t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
  t:SetText(text)
  return t
end

function SellUI.BuildGrid(p)
  p.cells = {}
  local per, size = SellUI.COLS, SellUI.CELL
  for i = 1, per * SellUI.ROWS do
    local c = CreateFrame("Button", nil, p)
    c:SetWidth(size - 2)
    c:SetHeight(size - 2)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", math.mod(i - 1, per) * size, -math.floor((i - 1) / per) * size)
    c.bg = Th.Solid(c, "BACKGROUND", "strip")
    c.bg:SetAllPoints(c)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -2, 2)
    c.mark = Th.Solid(c, "OVERLAY", "accent", 0.35)
    c.mark:SetAllPoints(c)
    c.mark:Hide()
    c.count = Th.Text(c, "body", 11, "white", "OVERLAY")
    c.count:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -3, 3)
    c.item = false
    c:SetScript("OnClick", function() if this.item then SellUI.Select(this.item) end end)
    c:SetScript("OnEnter", function()
      local it = this.item
      if not it then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetBagItem(it.slots[1].bag, it.slots[1].slot)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.cells[i] = c
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function()
    p.gridOffset = p.gridOffset - arg1
    SellUI.PaintGrid()
  end)
end

function SellUI.Build(parent)
  local p = CreateFrame("Frame", nil, parent)
  SellUI.frame = p
  p.items, p.gridOffset, p.sel, p.listings = {}, 0, false, {}
  p.searchKey, p.updating, p.splitting = false, false, false
  st.buyout, st.bid, st.source, p.bidEdited = nil, nil, nil, false
  p.stackSize, p.nStacks, p.posted, p.minutes, p.allowBelow = 1, 1, 0, 480, false
  SellUI.BuildGrid(p)
  local RX = SellUI.RX
  p.title = Th.Text(p, "body", 13, "text")
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", RX, -2)
  p.list = L.New(p, SellUI.COLUMNS, 18, nil)
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", RX, -22)
  p.list:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -22)
  p.list:SetHeight(122)
  label(p, "Buyout each", nil, RX, -158)
  p.buyoutIn = W.MoneyInput(p, function(v) if not p.updating then SellUI.BuyoutEdited(v) end end)
  p.buyoutIn:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 96, -154)
  p.sourceText = Th.Text(p, "body", 11, "dim")
  p.sourceText:SetPoint("LEFT", p.buyoutIn, "RIGHT", 10, 0)
  label(p, "Start bid each", nil, RX, -186)
  p.bidIn = W.MoneyInput(p, function(v) if not p.updating then SellUI.BidEdited(v) end end)
  p.bidIn:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 96, -182)
  label(p, "Stack size", nil, RX, -214)
  p.sizeBox = W.EditBox(p, 46, nil)
  p.sizeBox:SetNumeric(true)
  p.sizeBox:SetMaxLetters(3)
  p.sizeBox:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 96, -210)
  p.sizeBox:SetScript("OnTextChanged", function() SellUI.SizeEdited() end)
  label(p, "Stacks", nil, RX + 160, -214)
  p.countBox = W.EditBox(p, 46, nil)
  p.countBox:SetNumeric(true)
  p.countBox:SetMaxLetters(3)
  p.countBox:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 210, -210)
  p.countBox:SetScript("OnTextChanged", function() SellUI.CountEdited() end)
  label(p, "Duration", nil, RX, -242)
  p.durBtns = {}
  for i, m in ipairs(Sell.DURATIONS) do
    local b = W.Button(p, Sell.DURATION_LABELS[m], 52, 22, function(btn) SellUI.SetMinutes(btn.minutes) end)
    b.picked, b.minutes = false, m
    b:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 96 + (i - 1) * 58, -238)
    b:SetScript("OnLeave", function()
      Th.TintSlice(this.fill, this.picked and "accentDeep" or "strip", 1)
      W.HideTip()
    end)
    p.durBtns[m] = b
  end
  p.depositText = Th.Text(p, "body", 12, "text")
  p.depositText:SetPoint("TOPLEFT", p, "TOPLEFT", RX, -270)
  p.netText = Th.Text(p, "body", 12, "text")
  p.netText:SetPoint("TOPLEFT", p, "TOPLEFT", RX + 200, -270)
  p.floorText = Th.Text(p, "body", 12, "warn")
  p.floorText:SetPoint("TOPLEFT", p, "TOPLEFT", RX, -292)
  p.allowSw = W.Switch(p, "Allow below floor", function() return p.allowBelow end,
    function(v) p.allowBelow = v and true or false SellUI.Update() end,
    "Lets you post under your price floor. It resets when you pick another item.")
  p.allowSw:SetWidth(200)
  p.allowSw:SetPoint("TOPLEFT", p, "TOPLEFT", RX, -312)
  p.postBtn = W.Button(p, "Post", 150, 24, function() SellUI.Click() end, "accent")
  p.postBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  p.status = Th.Text(p, "body", 12, "dim")
  p.status:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", RX, 6)
  p.status:SetPoint("RIGHT", p.postBtn, "LEFT", -8, 0)
  p.status:SetJustifyH("LEFT")
  p.Refresh = function(self) SellUI.Refresh() end
  p.Layout = function(self) self.list:Paint() end
  Scan.OnChange(function() SellUI.OnScan() end)
  Auction.OnChange(function() if p:IsVisible() then SellUI.Update() end end)
  SellUI.Refresh()
  return p
end

UI.builders.sell = SellUI.Build
