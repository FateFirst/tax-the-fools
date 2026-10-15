TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
local U, Th, W, L, Sales, MailRules, Mailbox, MailHook = A.Util, A.Theme, A.Widgets, A.List, A.Sales, A.MailRules,
  A.Mailbox, A.MailHook
local DB = A.DB
local MailUI = { frame = nil, win = nil, pages = {}, builders = {}, dirty = false, statusDirty = false, wasBusy = false }
A.MailUI = MailUI

-- The mail window (phase 5b spec section 5). The Inbox list reads headers only: painting and opening never
-- call an engine action or GetInboxText. Only a button's OnClick reaches Mailbox.

-- Tab order; a tab with no registered builder is left out of the strip. Pages register with
--   MailUI.builders.send = function(parent) ... return page end
-- and may define Refresh and Layout.
MailUI.TABS = { { key = "inbox", label = "Inbox" }, { key = "send", label = "Send" } }

function MailUI.VisibleTabs()
  local out = {}
  for _, t in ipairs(MailUI.TABS) do
    if MailUI.builders[t.key] then table.insert(out, t) end
  end
  return out
end

local SEP = "  -  "
local TAGS = { sold = "Sold", expired = "Expired", cancelled = "Cancelled", won = "Won", outbid = "Outbid" }

local function money(v)
  if v and v > 0 then return U.money(v) end
  return "-"
end

MailUI.COLUMNS = {
  { label = "Item", width = 36, fmt = function(r) if r.hasItem then return "Item", "gold" end return "" end },
  { label = "From", width = 90, sort = "sender", fmt = function(r) return r.sender or "?" end },
  { label = "Subject", width = 130, sort = "subject", fmt = function(r) return r.subject or "" end },
  { label = "Money", width = 76, align = "RIGHT", sort = "money", fmt = function(r) return money(r.money) end },
  { label = "COD", width = 62, align = "RIGHT", sort = "cod",
    fmt = function(r) if r.cod and r.cod > 0 then return U.money(r.cod), "warn" end return "-", "dim" end },
  { label = "Expires", width = 50, align = "RIGHT", sort = "daysLeft",
    fmt = function(r) return A.UI.Approx((r.daysLeft or 0) * 86400) end },
  { label = "Tag", width = 62, sort = "tag", fmt = function(r) return r.tag or "", "dim" end },
}

-- The tag of a mail: an auction outcome from its subject, or "Returned".
function MailUI.Tag(subject, wasReturned)
  local outcome = Sales.Classify(subject)
  if outcome then return TAGS[outcome] end
  if wasReturned then return "Returned" end
  return nil
end

-- One row per mail, from GetInboxHeaderInfo alone.
function MailUI.Headers()
  local rows = {}
  local n = GetInboxNumItems() or 0
  for i = 1, n do
    local _, _, sender, subject, mny, cod, daysLeft, hasItem, wasRead, wasReturned, textCreated, _, isGM =
      GetInboxHeaderInfo(i)
    table.insert(rows, { index = i, sender = sender, subject = subject, money = mny or 0, cod = cod or 0,
      daysLeft = daysLeft or 0, hasItem = hasItem and true or false, wasRead = wasRead, wasReturned = wasReturned and true or false,
      textCreated = textCreated, isGM = isGM and true or false, tag = MailUI.Tag(subject, wasReturned) })
  end
  return rows
end

function MailUI.PlanOf(r)
  return MailRules.Plan({ sender = r.sender, subject = r.subject, money = r.money, cod = r.cod, hasItem = r.hasItem,
    isGM = r.isGM, wasReturned = r.wasReturned, textCreated = r.textCreated })
end

-- How many mails Collect all would work on (skips ignored), and the money waiting in them.
function MailUI.Totals(rows)
  local n, waiting = 0, 0
  for _, r in ipairs(rows) do
    if MailUI.PlanOf(r) ~= "skip" then
      n = n + 1
      waiting = waiting + (r.money or 0)
    end
  end
  return n, waiting
end

function MailUI.Footer(total, waiting, collected)
  return total .. ((total == 1) and " mail" or " mails") .. SEP .. U.money(waiting) .. " waiting" .. SEP
    .. "collected " .. U.money(collected or 0)
end

local function sameMail(a, b)
  return a and b and a.index == b.index and a.subject == b.subject and a.sender == b.sender
end

function MailUI.Paint()
  local p = MailUI.frame
  if not p then return end
  local rows = MailUI.Headers()
  local prev = p.list.selected
  p.list:SetData(rows)
  if prev then
    local now = rows[prev.index]
    if sameMail(now, prev) then
      -- SetData may have sorted; find the row again by index
      for _, r in ipairs(p.list.data) do
        if r.index == prev.index then p.list.selected = r end
      end
      p.list:Paint()
    else
      p.detail:SetText(MailUI.HINT)
    end
  end
  local n, waiting = MailUI.Totals(rows)
  p.count, p.waiting = n, waiting
  p.total = table.getn(rows)
  MailUI.RefreshFooter()
  MailUI.UpdateBar()
end

function MailUI.RefreshFooter()
  local p = MailUI.frame
  if p then p.footer:SetText(MailUI.Footer(p.total or 0, p.waiting or 0, Mailbox.collected)) end
end

function MailUI.UpdateBar()
  if MailUI.UpdateSend then MailUI.UpdateSend() end
  local p = MailUI.frame
  if not p then return end
  local busy = Mailbox.busy and true or false
  local sel = p.list.selected
  local plan = sel and MailUI.PlanOf(sel)
  local holds = sel and (sel.money > 0 or sel.hasItem)
  p.readBtn:SetEnabled((sel and not busy) and true or false)
  p.collectBtn:SetEnabled((sel and not busy and plan ~= "skip") and true or false)
  p.deleteBtn:SetEnabled((sel and not busy and not holds and not sel.isGM) and true or false)
  p.returnBtn:SetEnabled((sel and not busy and not sel.isGM and not sel.wasReturned and not (sel.sender and string.find(sel.sender, "Auction House", 1, true))
    and not Sales.Classify(sel.subject)) and true or false)
  local s = MailUI.win and MailUI.win.status
  if s then
    s.collect:SetLabel("Collect all (" .. (p.count or 0) .. ")")
    s.collect:SetEnabled((not busy and (p.count or 0) > 0) and true or false)
    if busy then s.stop:Show() else s.stop:Hide() end
  end
end

MailUI.HINT = "Select a mail and press Read to see its text."

function MailUI.Select()
  local p = MailUI.frame
  if p then p.detail:SetText(MailUI.HINT) end
  MailUI.UpdateBar()
end

-- Button handlers (OnClick only).
function MailUI.Sel()
  local p = MailUI.frame
  return p and p.list.selected
end

function MailUI.Read()
  local sel = MailUI.Sel()
  if not sel or Mailbox.busy then return false end
  local body = Mailbox.Read(sel.index)
  local p = MailUI.frame
  if body == nil then p.detail:SetText("That mail is gone.")
  elseif body == "" then p.detail:SetText("(This mail has no text.)")
  else p.detail:SetText(body) end
  MailUI.dirty = true
  return true
end

function MailUI.Collect()
  local sel = MailUI.Sel()
  if sel then Mailbox.CollectOne(sel.index) end
end

function MailUI.Delete()
  local sel = MailUI.Sel()
  if sel then Mailbox.Delete(sel.index) end
end

function MailUI.Return()
  local sel = MailUI.Sel()
  if sel then Mailbox.Return(sel.index) end
end

-- Hovering a row with an item: the client's own inbox item tooltip (InboxFrameItem_OnEnter in 1.12).
function MailUI.Hover(row, r)
  if not r.hasItem then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetInboxItem(r.index)
  GameTooltip:Show()
end

local function buildButtons(p)
  p.readBtn = W.Button(p, "Read", 70, 24, function() MailUI.Read() end)
  p.readBtn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  W.Tip(p.readBtn, "Read", "Show the selected mail's text. This marks it read.")
  p.collectBtn = W.Button(p, "Collect", 80, 24, function() MailUI.Collect() end, "accent")
  p.collectBtn:SetPoint("LEFT", p.readBtn, "RIGHT", 6, 0)
  W.Tip(p.collectBtn, "Collect", "Take the money and item from the selected mail.")
  p.deleteBtn = W.Button(p, "Delete", 70, 24, function() MailUI.Delete() end)
  p.deleteBtn:SetPoint("LEFT", p.collectBtn, "RIGHT", 6, 0)
  W.Tip(p.deleteBtn, "Delete", "Delete the selected mail. Only when it holds no money or item.")
  p.returnBtn = W.Button(p, "Return", 70, 24, function() MailUI.Return() end)
  p.returnBtn:SetPoint("LEFT", p.deleteBtn, "RIGHT", 6, 0)
  W.Tip(p.returnBtn, "Return", "Send the selected mail back to its sender. Not for auction house mail.")
  p.footer = Th.Text(p, "body", 12, "dim")
  p.footer:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 30)
  p.footer:SetJustifyH("LEFT")
end

function MailUI.BuildInbox(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.count, p.waiting = 0, 0
  p.list = L.New(p, MailUI.COLUMNS, 18, function() MailUI.Select() end)
  p.list.onEnter = MailUI.Hover
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 132)
  p.detail = Th.Text(p, "body", 12, "text")
  p.detail:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 4, -6)
  p.detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 54)
  p.detail:SetJustifyH("LEFT")
  p.detail:SetJustifyV("TOP")
  p.detail:SetText(MailUI.HINT)
  buildButtons(p)
  p.Refresh = function(self) MailUI.Paint() end
  p.Layout = function(self) self.list:Paint() end
  MailUI.frame = p
  MailUI.Paint()
  return p
end

MailUI.builders.inbox = MailUI.BuildInbox

-- The status strip: Collect all, Stop, a progress bar and the engine's last message.
function MailUI.CreateStrip(f)
  local s = CreateFrame("Frame", nil, f)
  s:SetHeight(38)
  local bg = Th.Solid(s, "BACKGROUND", "header")
  bg:SetAllPoints(s)
  s.collect = W.Button(s, "Collect all (0)", 130, 22, function() Mailbox.CollectAll() end, "accent")
  s.collect:SetPoint("LEFT", s, "LEFT", 10, 0)
  W.Tip(s.collect, "Collect all", "Take the money and items from every mail that has some. Auction house mail is deleted once empty.")
  s.stop = W.Button(s, "Stop", 70, 22, function() Mailbox.Stop() end)
  s.stop:SetPoint("LEFT", s.collect, "RIGHT", 6, 0)
  s.stop:Hide()
  s.bar = W.Progress(s, 8)
  s.bar:SetPoint("TOPLEFT", s.stop, "TOPRIGHT", 12, -2)
  s.bar:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  s.text = Th.Text(s, "body", 11, "dim")
  s.text:SetPoint("TOPLEFT", s.bar, "BOTTOMLEFT", 0, -4)
  s.text:SetPoint("RIGHT", s, "RIGHT", -10, 0)
  return s
end

function MailUI.RefreshStatus()
  local f = MailUI.win
  if not f then return end
  local s = f.status
  local st = Mailbox.status
  s.text:SetText(st and st.text or "")
  Th.Color(s.text, (st and st.token) or "dim")
  local pr = Mailbox.progress
  if Mailbox.busy and pr and pr.total and pr.total > 0 then s.bar:SetFraction(pr.done / pr.total)
  elseif Mailbox.busy then s.bar:SetFraction(0)
  else s.bar:SetFraction(0) end
end

function MailUI.RefreshGold()
  if MailUI.win then MailUI.win.gold:SetText(U.money(GetMoney())) end
end

function MailUI.ShowPage(key)
  local f = MailUI.win
  if not MailUI.pages[key] and not MailUI.builders[key] then return false end
  for _, page in pairs(MailUI.pages) do page:Hide() end
  local page = MailUI.pages[key]
  if not page then
    page = MailUI.builders[key](f.body)
    page:SetAllPoints(f.body)
    MailUI.pages[key] = page
  end
  page:Show()
  if type(page.Refresh) == "function" then page:Refresh() end
  return true
end

function MailUI.Create()
  if MailUI.win then return MailUI.win end
  local f = W.Window("TaxTheFoolsMail", 700, 460, "Tax the Fools: Mail", { resizable = true, minW = 560, minH = 380, logo = true })
  f.gold = Th.Text(f.header, "body2", 12, "gold")
  f.gold:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
  f.gold:SetJustifyH("RIGHT")
  f.blizzard = W.Button(f.header, "Blizzard", 80, 20, function() MailHook.ShowBlizzard() end)
  f.blizzard:SetPoint("RIGHT", f.gold, "LEFT", -12, 0)
  W.Tip(f.blizzard, "Blizzard", "Switch to the standard mailbox. Its Tax the Fools button brings you back.")
  f.tabs = W.TabStrip(f, MailUI.VisibleTabs(), function(key) MailUI.ShowPage(key) end)
  f.tabs:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -1)
  f.tabs:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -1)
  f.status = MailUI.CreateStrip(f)
  f.status:SetPoint("TOPLEFT", f.tabs, "BOTTOMLEFT", 0, 0)
  f.status:SetPoint("TOPRIGHT", f.tabs, "BOTTOMRIGHT", 0, 0)
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 10, -8)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 22)
  f:SetScript("OnShow", function()
    MailUI.RefreshGold()
    MailUI.RefreshStatus()
    if not f.tabs.selected then f.tabs:Select("inbox") else MailUI.Repaint() end
  end)
  f:SetScript("OnHide", function() MailHook.OnWindowHidden() end)
  f.onResize = function()
    for _, page in pairs(MailUI.pages) do
      if type(page.Layout) == "function" then page:Layout() end
    end
  end
  MailUI.win = f
  MailHook.window = f
  Mailbox.OnChange = function() MailUI.statusDirty = true end
  return f
end

-- Repaint what is on screen. Events and engine changes only set dirty; Tick paints once per frame.
function MailUI.Repaint()
  local f = MailUI.win
  if not f or not f:IsShown() then return end
  MailUI.RefreshStatus()
  MailUI.RefreshGold()
  local sel = f.tabs.selected
  local page = sel and MailUI.pages[sel]
  if page and type(page.Refresh) == "function" then page:Refresh() end
  MailUI.UpdateBar()
end

-- MAIL_INBOX_UPDATE (through Core.Safe)
function MailUI.OnEvent(e)
  MailUI.dirty = true
end

-- Every frame (through Core.Safe)
-- The list repaints on MAIL_INBOX_UPDATE (and when a chain ends); engine changes in between (every frame
-- of a chain) only refresh the status line, footer and buttons.
function MailUI.Tick()
  local busy = Mailbox.busy and true or false
  if MailUI.wasBusy and not busy then MailUI.dirty = true end
  MailUI.wasBusy = busy
  if MailUI.dirty then
    MailUI.dirty, MailUI.statusDirty = false, false
    MailUI.Repaint()
  elseif MailUI.statusDirty then
    MailUI.statusDirty = false
    local f = MailUI.win
    if not f or not f:IsShown() then return end
    MailUI.RefreshStatus()
    MailUI.RefreshFooter()
    MailUI.UpdateBar()
  end
end

-- ---------------------------------------------------------------------------------------------------
-- The Send tab (phase 5b spec section 5). Opening, painting, Fill and right-click only build the
-- attachment list; SendMail, ClickSendMailItemButton and SetSendMailMoney are reached only from the Send
-- button, through Mailbox.Send.
--
-- The list widget has text cells only, so Remove and Keep work on the selected row (two buttons) instead
-- of one pair per row. The body is a single-line edit box.

MailUI.send = { rows = {}, page = false }

MailUI.SEND_COLUMNS = {
  { label = "Item", width = 300, fmt = function(r) return r.name or "?" end },
  { label = "Count", width = 60, align = "RIGHT", fmt = function(r) return tostring(r.count or 1) end },
  { label = "Bag", width = 80, fmt = function(r) return r.bag .. ":" .. r.slot, "dim" end },
}

local BAGS = { 0, 1, 2, 3, 4 }

function MailUI.BankAlt()
  local b = DB.S().mail.bankAlt
  if b and b ~= "" then return b end
  return nil
end

-- Reads one bag slot: { bag, slot, key, id, name, count } or nil.
function MailUI.SlotItem(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if not link then return nil end
  local key, id = U.keyFromLink(link)
  if not key then return nil end
  local _, count = GetContainerItemInfo(bag, slot)
  return { bag = bag, slot = slot, key = key, id = id, name = U.linkName(link) or key, count = count or 1 }
end

function MailUI.Mailable(it)
  return A.Sell.Auctionable(A.Sell.TipLines(it.bag, it.slot)) and true or false
end

function MailUI.Attached(bag, slot)
  for _, r in ipairs(MailUI.send.rows) do
    if r.bag == bag and r.slot == slot then return r end
  end
  return nil
end

-- Adds a bag slot. Returns "added", "dup", "empty" or "unmailable".
function MailUI.AddSlot(bag, slot)
  local it = MailUI.SlotItem(bag, slot)
  if not it then return "empty" end
  if MailUI.Attached(bag, slot) then return "dup" end
  if not MailUI.Mailable(it) then return "unmailable" end
  table.insert(MailUI.send.rows, { bag = bag, slot = slot, key = it.key, name = it.name, count = it.count })
  return "added"
end

-- Right-click from the bags. Returns true when the click is ours (an empty slot passes through).
function MailUI.Attach(bag, slot)
  local r = MailUI.AddSlot(bag, slot)
  if r == "empty" then return false end
  local p = MailUI.send.page
  if r == "unmailable" then MailUI.Note("Can't mail that", "warn")
  elseif r == "dup" then MailUI.Note("Already attached", "dim")
  else MailUI.Note("", "dim") end
  if p then p:Refresh() end
  return true
end

-- True when a bag right-click should attach: our window shows its Send page and TurtleMail isn't loaded.
-- Replacing Blizzard's mailbox doesn't matter: with it off our window is still one button away.
function MailUI.SendShown()
  local f = MailUI.win
  if not f or not f:IsShown() then return false end
  if IsAddOnLoaded and IsAddOnLoaded("TurtleMail") then return false end
  local page = MailUI.pages.send
  return (f.tabs.selected == "send" and page and page:IsShown()) and true or false
end

function MailUI.Note(text, token)
  local p = MailUI.send.page
  if not p then return end
  p.note:SetText(text or "")
  Th.Color(p.note, token or "dim")
end

-- Drops rows whose slot no longer holds the same item and count (sent, moved, stack changed).
function MailUI.Revalidate()
  local keep = {}
  for _, r in ipairs(MailUI.send.rows) do
    local it = MailUI.SlotItem(r.bag, r.slot)
    if it and it.key == r.key and it.count == r.count then table.insert(keep, r) end
  end
  MailUI.send.rows = keep
end

-- Every bag stack that matches the ticked rules and isn't on the keep list; one attachment per stack.
function MailUI.FillRows()
  local mail = DB.S().mail
  local ctx = { products = A.Craft.Index(DB.Realm().chars) }
  local added = 0
  for _, bag in ipairs(BAGS) do
    for slot = 1, GetContainerNumSlots(bag) do
      local it = MailUI.SlotItem(bag, slot)
      if it and not MailUI.Attached(bag, slot) then
        local _, _, _, _, itype = GetItemInfo(it.id)
        local item = { key = it.key, name = it.name, type = itype, auctionable = MailUI.Mailable(it) }
        if MailRules.Matches(item, mail.rules, mail.keep, ctx) then
          table.insert(MailUI.send.rows, { bag = bag, slot = slot, key = it.key, name = it.name, count = it.count })
          added = added + 1
        end
      end
    end
  end
  return added
end

-- Fill for bank alt: attaches and sets the recipient. Never sends anything.
function MailUI.Fill()
  local alt = MailUI.BankAlt()
  local p = MailUI.send.page
  if not alt or not p then return false end
  if alt == DB.charName then
    MailUI.Note("This is the bank alt", "dim")
    return false
  end
  p.to:SetText(alt)
  local n = MailUI.FillRows()
  MailUI.Note(n == 0 and "Nothing matches" or ("Attached " .. n), "dim")
  p:Refresh()
  return true
end

function MailUI.SelRow()
  local p = MailUI.send.page
  return p and p.list.selected or nil
end

function MailUI.RemoveSel()
  local sel = MailUI.SelRow()
  if not sel then return false end
  local keep = {}
  for _, r in ipairs(MailUI.send.rows) do
    if r ~= sel then table.insert(keep, r) end
  end
  MailUI.send.rows = keep
  MailUI.send.page.list.selected = false
  MailUI.send.page:Refresh()
  return true
end

-- Keep: remove the row and never fill this item again.
function MailUI.KeepSel()
  local sel = MailUI.SelRow()
  if not sel then return false end
  DB.S().mail.keep[sel.key] = true
  return MailUI.RemoveSel()
end

function MailUI.DefaultTo()
  local alt = MailUI.BankAlt()
  if alt and alt ~= DB.charName then return alt end
  return ""
end

function MailUI.ClearSend()
  local p = MailUI.send.page
  MailUI.send.rows = {}
  if not p then return end
  p.to:SetText(MailUI.DefaultTo())
  p.subject:SetText("")
  p.body:SetText("")
  p.money:SetValue(nil)
  p.list.selected = false
  MailUI.Note("", "dim")
  p:Refresh()
end

function MailUI.SendNow()
  local p = MailUI.send.page
  if not p or Mailbox.busy then return false end
  local atts = {}
  for _, r in ipairs(MailUI.send.rows) do
    table.insert(atts, { bag = r.bag, slot = r.slot, key = r.key, count = r.count })
  end
  local m = p.money:GetValue()
  if m and m <= 0 then m = nil end
  local started = Mailbox.Send(p.to:GetText(), p.subject:GetText(), p.body:GetText(), m, atts)
  if started then p.pendingClear = true end
  return started
end

-- How many mails Send would make.
function MailUI.Mails()
  local p = MailUI.send.page
  local n = table.getn(MailUI.send.rows)
  if n == 0 and p and (p.money:GetValue() or 0) > 0 then n = 1 end
  return n
end

function MailUI.SendFooter(n, price)
  local postage = (n > 0) and MailRules.Postage(price, n) or 0
  return n .. ((n == 1) and " mail" or " mails") .. SEP .. "postage " .. U.money(postage)
end

function MailUI.SendOptions()
  local out = {}
  local names = {}
  for name in pairs(DB.Realm().chars) do
    if name ~= DB.charName then table.insert(names, name) end
  end
  table.sort(names)
  for _, name in ipairs(names) do table.insert(out, { label = name, value = name }) end
  return out
end

-- Enable states and the footer; also called from UpdateBar on every repaint.
function MailUI.UpdateSend()
  local p = MailUI.send.page
  if not p then return end
  local busy = Mailbox.busy and true or false
  local sel = p.list.selected and true or false
  p.sendBtn:SetEnabled(not busy)
  p.removeBtn:SetEnabled(sel and not busy)
  p.keepBtn:SetEnabled(sel and not busy)
  p.clearBtn:SetEnabled(not busy)
  p.fillBtn:SetEnabled(not busy)
  local alt = MailUI.BankAlt()
  if alt and alt ~= DB.charName then p.fillBtn:Show() else p.fillBtn:Hide() end
  p.footer:SetText(MailUI.SendFooter(MailUI.Mails(), GetSendMailPrice() or 0))
end

-- After a finished chain that sent everything, the subject, body and money are spent.
function MailUI.AfterSend()
  local p = MailUI.send.page
  if not p.pendingClear or Mailbox.busy then return end
  p.pendingClear = false
  local st = Mailbox.status
  if table.getn(MailUI.send.rows) == 0 and not (st and st.token == "bad") then
    p.subject:SetText("")
    p.body:SetText("")
    p.money:SetValue(nil)
  end
end

function MailUI.RefreshSend()
  local p = MailUI.send.page
  MailUI.Revalidate()
  if not Mailbox.busy then MailUI.AfterSend() end
  p.dropdown:SetOptions(MailUI.SendOptions())
  local prev = p.list.selected
  p.list:SetData(MailUI.send.rows)
  if prev then
    for _, r in ipairs(MailUI.send.rows) do
      if r == prev then p.list.selected = r end
    end
    p.list:Paint()
  end
  MailUI.UpdateSend()
end

-- BAG_UPDATE (through Core.Safe): the Send page re-checks its attachments on the next frame.
function MailUI.OnBag()
  local f = MailUI.win
  if f and f.tabs.selected == "send" then MailUI.dirty = true end
end

local function sendLabel(p, text, x, y)
  local t = Th.Text(p, "body", 11, "dim")
  t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
  t:SetText(text)
  return t
end

local function buildFields(p)
  sendLabel(p, "To", 0, -5)
  p.to = W.EditBox(p, 150, nil)
  p.to:SetPoint("TOPLEFT", p, "TOPLEFT", 50, 0)
  p.to:SetText(MailUI.DefaultTo())
  p.dropdown = W.Dropdown(p, 110, MailUI.SendOptions(), function() return p.to:GetText() end,
    function(v) p.to:SetText(v) end)
  p.dropdown:SetPoint("LEFT", p.to, "RIGHT", 6, 0)
  sendLabel(p, "Money", 330, -5)
  p.money = W.MoneyInput(p, function() MailUI.UpdateSend() end)
  p.money:SetPoint("TOPLEFT", p, "TOPLEFT", 372, 0)
  sendLabel(p, "Subject", 0, -33)
  p.subject = W.EditBox(p, 300, nil)
  p.subject:SetPoint("TOPLEFT", p, "TOPLEFT", 50, -28)
  p.subject:SetMaxLetters(64)
  W.Tip(p.subject, "Subject", "Blank means automatic: the item's name and count.")
  sendLabel(p, "Body", 0, -61)
  p.body = W.EditBox(p, 300, nil)
  p.body:SetPoint("TOPLEFT", p, "TOPLEFT", 50, -56)
  p.body:SetMaxLetters(500)
end

local function buildSendButtons(p)
  p.fillBtn = W.Button(p, "Fill for bank alt", 120, 24, function() MailUI.Fill() end, "accent")
  p.fillBtn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  W.Tip(p.fillBtn, "Fill for bank alt", "Attach every bag item that matches your mail rules and isn't on the keep list, and address the mail to your bank alt. Nothing is sent until you press Send.")
  p.clearBtn = W.Button(p, "Clear", 60, 24, function() MailUI.ClearSend() end)
  p.clearBtn:SetPoint("LEFT", p.fillBtn, "RIGHT", 6, 0)
  p.removeBtn = W.Button(p, "Remove", 70, 24, function() MailUI.RemoveSel() end)
  p.removeBtn:SetPoint("LEFT", p.clearBtn, "RIGHT", 6, 0)
  W.Tip(p.removeBtn, "Remove", "Take the selected row off the mail.")
  p.keepBtn = W.Button(p, "Keep", 60, 24, function() MailUI.KeepSel() end)
  p.keepBtn:SetPoint("LEFT", p.removeBtn, "RIGHT", 6, 0)
  W.Tip(p.keepBtn, "Keep", "Take the selected row off and never fill this item again.")
  p.sendBtn = W.Button(p, "Send", 80, 24, function() MailUI.SendNow() end, "accent")
  p.sendBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  W.Tip(p.sendBtn, "Send", "Send one mail per attached stack.")
  p.footer = Th.Text(p, "body", 12, "dim")
  p.footer:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 30)
  p.footer:SetJustifyH("LEFT")
  p.note = Th.Text(p, "body", 11, "dim")
  p.note:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 30)
  p.note:SetJustifyH("RIGHT")
end

function MailUI.BuildSend(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.pendingClear = false
  MailUI.send.page = p
  buildFields(p)
  p.list = L.New(p, MailUI.SEND_COLUMNS, 18, function() MailUI.UpdateSend() end)
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -88)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 54)
  buildSendButtons(p)
  p.Refresh = function(self) MailUI.RefreshSend() end
  p.Layout = function(self) self.list:Paint() end
  MailUI.RefreshSend()
  return p
end

MailUI.builders.send = MailUI.BuildSend
