TaxTheFools = TaxTheFools or {}
local U, Th, W, L, DB, Scan, UI = TaxTheFools.Util, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.List,
  TaxTheFools.DB, TaxTheFools.Scan, TaxTheFools.UI
local Auction, Sell, Q, SellUI = TaxTheFools.Auction, TaxTheFools.Sell, TaxTheFools.Quick, TaxTheFools.SellUI
local QuickUI = {}
TaxTheFools.QuickUI = QuickUI

-- Phase 10 spec sections 3 to 5: the Quick view of the Sell tab. Scan bags is the only part that runs by
-- itself (the scanner pages on its own, as every scan does). Post next reaches Auction.Post only from its
-- OnClick, once per click; a reply only marks the row and moves the highlight.

QuickUI.SCAN_W, QuickUI.DUR_W, QuickUI.DUR_GAP = 90, 44, 4
QuickUI.SW_W, QuickUI.MULT_X, QuickUI.MULT_W = 220, 232, 34
QuickUI.POST_W, QuickUI.SKIP_W, QuickUI.ROW2, QuickUI.LIST_Y, QuickUI.BOTTOM = 150, 70, 28, 56, 30
QuickUI.MAX_MULT = 20
QuickUI.TICK = 5                    -- seconds between repaints of "Prices from 2m ago"

QuickUI.MESSAGES = {
  busy = "Another scan is running. Wait for it, or pause it, first.",
  empty = "Nothing in your bags can be auctioned.",
  idle = "Scan your bags to price them.",
  paused = "Scan paused. Resume it on the bar above.",
}

-- The Quick view lives on the Sell page: SellUI.frame.quick. Fields that may be nil sit in q.st, a plain
-- table (the fake client's frames answer an unset field with a function).
local function frame()
  local p = SellUI.frame
  if not p then return nil end
  return p.quick or nil
end

function QuickUI.ResetState()
  local q = frame()
  if q then q.st = { tick = 0 } end
end

local function includeVendor() return DB.S().sell.quickVendor and true or false end

local function postable(r)
  if not r or r.preview or r.done then return false end
  return r.status == nil or (r.status == "vendor" and includeVendor())
end
QuickUI.Postable = postable

local function indexOf(rows, r)
  for i, x in ipairs(rows) do if x == r then return i end end
  return nil
end

-- Keeps the highlight on a postable row of the current list: a new list (a rescan) starts from the top;
-- a row that can no longer post hands over to the next one after it, then from the top.
local function sync(q)
  local st = q.st
  local rows = Q.rows
  if st.rowsRef ~= rows then st.rowsRef, st.cur = rows, nil end
  if st.cur and not postable(st.cur) then
    local i = Q.Next(rows, indexOf(rows, st.cur) or 0, includeVendor()) or Q.Next(rows, 0, includeVendor())
    st.cur = i and rows[i] or nil
  end
  if not st.cur and Q.state == "ready" then
    local i = Q.Next(rows, 0, includeVendor())
    st.cur = i and rows[i] or nil
  end
end

function QuickUI.Cur()
  local q = frame()
  if not q then return nil end
  sync(q)
  return q.st.cur
end

local function minutes(q) return q.st.minutes or DB.S().sell.duration end

-- ---------- the list ----------

function QuickUI.StatusText(r)
  if r.preview then return "scan for prices", "dim" end
  if r.done == "posted" then return "Posted", "good" end
  if r.done == "failed" then return "Failed: " .. (r.reason or "no reason given"), "bad" end
  if r.done == "skipped" then return "Skipped", "dim" end
  if r.status == "noprice" then return "no price", "dim" end
  if r.status == "notscanned" then return "not scanned", "dim" end
  if r.status == "vendor" then return "vendor x" .. DB.S().sell.vendorMult, "warn" end
  if r.atFloor then return "at floor", "warn" end
  return "", "text"
end

local function short(c) return TaxTheFools.StockUI.Short(c) end

QuickUI.COLUMNS = {
  { label = "Item", width = 150, flex = 2,
    fmt = function(r)
      local mark = (r == QuickUI.Cur()) and "> " or ""
      return mark .. U.quality(r.quality) .. r.name .. "|r"
    end },
  { label = "Stack", width = 44, align = "RIGHT", fmt = function(r) return tostring(r.count) end },
  { label = "Each", width = 70, align = "RIGHT",
    fmt = function(r) if r.preview or not r.unit then return "-", "dim" end return short(r.unit) end },
  { label = "Total", width = 76, align = "RIGHT",
    fmt = function(r) if r.preview or not r.unit then return "-", "dim" end return short(r.unit * r.count) end },
  { label = "Status", width = 120, flex = 1, fmt = function(r) return QuickUI.StatusText(r) end },
}

-- The rows to show: the scan's, or before any scan the bag slots with no price yet.
function QuickUI.Rows()
  if Q.state == "ready" or table.getn(Q.rows) > 0 then return Q.rows, false end
  local rows = Q.Rows(Q.ReadSlots(), nil)
  for _, r in ipairs(rows) do r.preview = true end
  return rows, true
end

function QuickUI.RowTip(row, r)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetBagItem(r.bag, r.slot)
  if GameTooltip:NumLines() == 0 then GameTooltip:SetText(r.name) end
  if r.reason then GameTooltip:AddLine("Failed: " .. r.reason, 1, 0.45, 0.45, 1) end
  if r.atFloor and not r.done then
    GameTooltip:AddLine("Priced at your floor: another seller is at or under it.", 1, 0.82, 0.3, 1)
  end
  GameTooltip:Show()
end

-- ---------- painting ----------

function QuickUI.StatusLine(q)
  if q.st.msg then return q.st.msg, "warn" end
  if Q.state == "scanning" then
    local job = Scan.job
    if job and job.kind == "quick" then
      return "Scanning " .. job.qi .. " of " .. table.getn(job.queries) .. "...", "text"
    end
    return QuickUI.MESSAGES.paused, "warn"
  end
  if Q.state == "ready" and Q.scannedAt then
    local age = time() - Q.scannedAt
    if age < 60 then return "Prices from just now", "dim" end
    return "Prices from " .. UI.Duration(age) .. " ago", "dim"
  end
  return QuickUI.MESSAGES.idle, "dim"
end

function QuickUI.PaintStatus(q)
  local text, token = QuickUI.StatusLine(q)
  q.statusText:SetText(text)
  Th.Color(q.statusText, token)
end

function QuickUI.Summary(rows)
  local n, total = 0, 0
  for _, r in ipairs(rows) do
    if r.done == "posted" then
      n = n + 1
      total = total + math.floor(r.unit) * r.count
    end
  end
  return n .. " of " .. table.getn(rows) .. " posted, " .. U.money(total, true)
end

local function whyNot(q, preview)
  if Q.state == "scanning" then return "Wait for the scan to finish." end
  if preview or Q.state ~= "ready" then return "Scan your bags first." end
  if Auction.busy then return "Waiting for the auction house to answer." end
  if not q.st.cur then return "Nothing left to post. Scan bags again to start over." end
  return nil
end

function QuickUI.Paint()
  local q = frame()
  if not q then return end
  sync(q)
  local st = q.st
  local rows, preview = QuickUI.Rows()
  q.list.data = rows
  q.list.selected = st.cur or false
  q.list:Paint()
  QuickUI.PaintStatus(q)
  for m, b in pairs(q.durBtns) do
    b.picked = (m == minutes(q))
    Th.TintSlice(b.fill, b.picked and "accentDeep" or "strip", 1)
  end
  q.vendorSw:Refresh()
  q.scanBtn:SetEnabled(Q.state ~= "scanning")
  local why = whyNot(q, preview)
  q.postBtn:SetLabel(Auction.busy and "Waiting..." or "Post next")
  q.postBtn:SetEnabled(not why)
  W.Tip(q.postBtn, "Post next", why or "Posts the highlighted row, one stack, at the price shown. One click, one auction.")
  q.skipBtn:SetEnabled(not why)
  q.summary:SetText(preview and "" or QuickUI.Summary(rows))
end

-- ---------- actions (OnClick only) ----------

function QuickUI.ScanClick()
  local q = frame()
  local ok, why = Q.Scan(GetTime())
  if ok then q.st.msg = nil
  else q.st.msg = QuickUI.MESSAGES[why or ""] or ("Could not scan: " .. tostring(why)) end
  QuickUI.Paint()
  return ok
end

function QuickUI.Posted(r)
  r.done = "posted"
  if TaxTheFools.AuctionsUI and TaxTheFools.AuctionsUI.Request then TaxTheFools.AuctionsUI.Request() end
  QuickUI.Paint()
end

function QuickUI.Failed(r, text)
  r.done, r.reason = "failed", text or "no reason given"
  QuickUI.Paint()
end

-- One click: at most one Auction.Post, so at most one StartAuction.
function QuickUI.PostNext()
  local q = frame()
  if not q or Auction.busy or Q.state ~= "ready" then return false end
  sync(q)
  local r = q.st.cur
  if not postable(r) then return false end
  local n = r.count
  local unit = math.floor(r.unit)
  local bid = math.floor(r.bid or unit)
  local ok = Auction.Post(r.bag, r.slot, n, bid * n, unit * n, minutes(q), r.key, false,
    function() QuickUI.Posted(r) end, function(text) QuickUI.Failed(r, text) end)
  if not ok then
    local note = Auction.note
    QuickUI.Failed(r, note and note.text or nil)
  end
  QuickUI.Paint()
  return ok and true or false
end

function QuickUI.Skip()
  local q = frame()
  if not q or Auction.busy or Q.state ~= "ready" then return false end
  sync(q)
  local r = q.st.cur
  if not r then return false end
  r.done = "skipped"
  QuickUI.Paint()
  return true
end

-- A clicked row becomes the next one, if it can be posted.
function QuickUI.Pick(r)
  local q = frame()
  if not q then return end
  if postable(r) and indexOf(Q.rows, r) then q.st.cur = r end
  QuickUI.Paint()
end

function QuickUI.SetMinutes(m)
  local q = frame()
  q.st.minutes = m
  QuickUI.Paint()
end

-- Prices again from the kept listings (a new multiple), keeping the list, its marks and the highlight.
-- Rows are matched by bag, slot and item; a row whose slot changed keeps its old price.
function QuickUI.Reprice()
  if Q.state ~= "ready" then return end
  local old = Q.rows
  local by = {}
  for _, r in ipairs(Q.Reprice()) do by[r.bag .. ":" .. r.slot .. ":" .. r.key] = r end
  for _, r in ipairs(old) do
    local n = by[r.bag .. ":" .. r.slot .. ":" .. r.key]
    if n then r.unit, r.bid, r.source, r.atFloor, r.status = n.unit, n.bid, n.source, n.atFloor, n.status end
  end
  Q.rows = old
end

local function fillMult(q)
  q.st.updating = true
  q.multBox:SetText(tostring(DB.S().sell.vendorMult))
  q.st.updating = false
end

function QuickUI.MultEdited()
  local q = frame()
  if not q or q.st.updating then return end
  local n = tonumber(q.multBox:GetText())
  if not n or n < 1 then return end
  n = math.floor(n)
  if n > QuickUI.MAX_MULT then n = QuickUI.MAX_MULT end
  if n ~= DB.S().sell.vendorMult then
    DB.S().sell.vendorMult = n
    DB.Touch()
    QuickUI.Reprice()
  end
  if tonumber(q.multBox:GetText()) ~= n then fillMult(q) end
  QuickUI.Paint()
end

-- The Options window changed quickVendor or vendorMult.
function QuickUI.SettingsChanged()
  local q = frame()
  if not q then return end
  fillMult(q)
  QuickUI.Reprice()
  QuickUI.Paint()
end

function QuickUI.Show(p, on)
  local q = p.quick
  if not q then return end
  if on then
    q:Show()
    fillMult(q)
    QuickUI.Paint()
  else
    q:Hide()
  end
end

-- ---------- layout ----------

-- Whether every fixed text fits the page at `width` (the 660 window leaves a 640 page).
function QuickUI.Fits(width)
  local function w(s) return string.len(s) * 6 end
  local statusW = width - QuickUI.SCAN_W - 8 - (3 * QuickUI.DUR_W + 2 * QuickUI.DUR_GAP) - 8
  for _, m in pairs(QuickUI.MESSAGES) do
    if w(m) > statusW then return { ok = false, why = m .. " needs " .. w(m) .. ", has " .. statusW } end
  end
  if w("Scanning 99 of 99...") > statusW or w("Prices from 23h 59m ago") > statusW then
    return { ok = false, why = "progress text" }
  end
  if 38 + w("Include vendor-priced items") > QuickUI.SW_W then return { ok = false, why = "vendor switch" } end
  if QuickUI.SW_W > QuickUI.MULT_X then return { ok = false, why = "switch overlaps the multiple" } end
  if QuickUI.MULT_X + w("Vendor price x") + 4 + QuickUI.MULT_W > width then return { ok = false, why = "multiple" } end
  local sumW = width - QuickUI.POST_W - 6 - QuickUI.SKIP_W - 8 - 4
  if w("99 of 99 posted, 99999g 99s 99c") > sumW then return { ok = false, why = "summary" } end
  if w("WAITING...") > QuickUI.POST_W - 8 or w("POST NEXT") > QuickUI.POST_W - 8 then return { ok = false, why = "post" } end
  if w("SKIP") > QuickUI.SKIP_W - 8 or w("SCAN BAGS") > QuickUI.SCAN_W - 8 then return { ok = false, why = "buttons" } end
  if w("72H") > QuickUI.DUR_W - 8 then return { ok = false, why = "durations" } end
  return { ok = true }
end

local function buildTop(q)
  q.scanBtn = W.Button(q, "Scan bags", QuickUI.SCAN_W, 22, function() QuickUI.ScanClick() end, "accent")
  q.scanBtn:SetPoint("TOPLEFT", q, "TOPLEFT", 0, 0)
  W.Tip(q.scanBtn, "Scan bags", "Searches the auction house once for each item in your bags and prices every stack. "
    .. "It pages by itself like any scan, and never posts.")
  q.durBtns = {}
  local x = -(3 * QuickUI.DUR_W + 2 * QuickUI.DUR_GAP)
  for _, m in ipairs(Sell.DURATIONS) do
    local b = W.Button(q, Sell.DURATION_LABELS[m], QuickUI.DUR_W, 22, function(btn) QuickUI.SetMinutes(btn.minutes) end)
    b.picked, b.minutes = false, m
    b:SetPoint("TOPLEFT", q, "TOPRIGHT", x, 0)
    x = x + QuickUI.DUR_W + QuickUI.DUR_GAP
    b:SetScript("OnLeave", function()
      Th.TintSlice(this.fill, this.picked and "accentDeep" or "strip", 1)
      W.HideTip()
    end)
    W.Tip(b, "Duration", "For every post from this list. It doesn't change your Sell default.")
    q.durBtns[m] = b
  end
  q.statusText = Th.Text(q, "body", 12, "dim")
  q.statusText:SetPoint("LEFT", q.scanBtn, "RIGHT", 8, 0)
  q.statusText:SetPoint("RIGHT", q.durBtns[Sell.DURATIONS[1]], "LEFT", -8, 0)
  q.statusText:SetJustifyH("LEFT")
  q.vendorSw = W.Switch(q, "Include vendor-priced items", function() return includeVendor() end,
    function(v)
      DB.S().sell.quickVendor = v and true or false
      DB.Touch()
      q.st.cur = nil
      QuickUI.Paint()
    end,
    "Post next also posts items with no auction or market price, at their vendor price times the multiple. Off passes over them.")
  q.vendorSw:SetWidth(QuickUI.SW_W)
  q.vendorSw:SetPoint("TOPLEFT", q, "TOPLEFT", 0, -QuickUI.ROW2)
  q.multLabel = Th.Text(q, "body", 12, "dim")
  q.multLabel:SetPoint("TOPLEFT", q, "TOPLEFT", QuickUI.MULT_X, -(QuickUI.ROW2 + 5))
  q.multLabel:SetText("Vendor price x")
  q.multBox = W.EditBox(q, QuickUI.MULT_W, nil)
  q.multBox:SetNumeric(true)
  q.multBox:SetMaxLetters(2)
  q.multBox:SetPoint("LEFT", q.multLabel, "RIGHT", 4, 0)
  q.multBox:SetScript("OnTextChanged", function() QuickUI.MultEdited() end)
  W.HoverTip(q.multBox, "Vendor price multiple", "A vendor-priced item is posted at its vendor price times this. "
    .. "The Bags view's vendor suggestion uses it too. Default 3.")
end

function QuickUI.Build(p)
  local q = CreateFrame("Frame", nil, p)
  p.quick = q
  q.st = { tick = 0 }
  q:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -SellUI.GY)
  q:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  buildTop(q)
  q.list = L.New(q, QuickUI.COLUMNS, 18, function(item) QuickUI.Pick(item) end)
  q.list.onEnter = function(row, item) QuickUI.RowTip(row, item) end
  q.list:SetPoint("TOPLEFT", q, "TOPLEFT", 0, -QuickUI.LIST_Y)
  q.list:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, QuickUI.BOTTOM)
  q.postBtn = W.Button(q, "Post next", QuickUI.POST_W, 24, function() QuickUI.PostNext() end, "accent")
  q.postBtn:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
  q.skipBtn = W.Button(q, "Skip", QuickUI.SKIP_W, 24, function() QuickUI.Skip() end)
  q.skipBtn:SetPoint("RIGHT", q.postBtn, "LEFT", -6, 0)
  W.Tip(q.skipBtn, "Skip", "Passes over the highlighted row without posting it.")
  q.summary = Th.Text(q, "body", 12, "text")
  q.summary:SetPoint("BOTTOMLEFT", q, "BOTTOMLEFT", 4, 6)
  q.summary:SetPoint("RIGHT", q.skipBtn, "LEFT", -8, 0)
  q.summary:SetJustifyH("LEFT")
  -- Only repaints the age of the prices. Nothing here posts.
  q:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - q.st.tick < QuickUI.TICK then return end
    q.st.tick = now
    QuickUI.PaintStatus(q)
  end)
  q:Hide()
  local layout = p.Layout
  p.Layout = function(self)
    layout(self)
    self.quick.list:Paint()
  end
  Q.OnChange(function()
    local f = frame()
    if not f then return end
    if Q.state ~= "idle" then f.st.msg = nil end
    if f:IsVisible() then QuickUI.Paint() end
  end)
  Scan.OnChange(function()
    local f = frame()
    if f and f:IsVisible() and Q.state == "scanning" then QuickUI.PaintStatus(f) end
  end)
  Auction.OnChange(function()
    local f = frame()
    if f and f:IsVisible() then QuickUI.Paint() end
  end)
  return q
end
