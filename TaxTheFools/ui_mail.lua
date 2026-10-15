TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
local U, Th, W, L, Sales, MailRules, Mailbox, MailHook = A.Util, A.Theme, A.Widgets, A.List, A.Sales, A.MailRules,
  A.Mailbox, A.MailHook
local MailUI = { frame = nil, win = nil, pages = {}, builders = {}, dirty = false }
A.MailUI = MailUI

-- The mail window (phase 5b spec section 5). The Inbox list reads headers only: painting and opening never
-- call an engine action or GetInboxText. Only a button's OnClick reaches Mailbox.

-- Tab order; a tab with no registered builder is left out of the strip. Task 5 adds its page with
--   MailUI.builders.send = function(parent) ... return page end
-- at load time (the "send" entry is already listed here), and the page may define Refresh and Layout.
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
  { label = "Item", width = 40, fmt = function(r) if r.hasItem then return "Item", "gold" end return "" end },
  { label = "From", width = 110, sort = "sender", fmt = function(r) return r.sender or "?" end },
  { label = "Subject", width = 210, sort = "subject", fmt = function(r) return r.subject or "" end },
  { label = "Money", width = 84, align = "RIGHT", sort = "money", fmt = function(r) return money(r.money) end },
  { label = "COD", width = 74, align = "RIGHT", sort = "cod",
    fmt = function(r) if r.cod and r.cod > 0 then return U.money(r.cod), "warn" end return "-", "dim" end },
  { label = "Expires", width = 60, align = "RIGHT", sort = "daysLeft",
    fmt = function(r) return A.UI.Approx((r.daysLeft or 0) * 86400) end },
  { label = "Tag", width = 80, sort = "tag", fmt = function(r) return r.tag or "", "dim" end },
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
  p.footer:SetText(MailUI.Footer(table.getn(rows), waiting, Mailbox.collected))
  MailUI.UpdateBar()
end

function MailUI.UpdateBar()
  local p = MailUI.frame
  if not p then return end
  local busy = Mailbox.busy and true or false
  local sel = p.list.selected
  local plan = sel and MailUI.PlanOf(sel)
  local holds = sel and (sel.money > 0 or sel.hasItem)
  p.readBtn:SetEnabled((sel and not busy) and true or false)
  p.collectBtn:SetEnabled((sel and not busy and plan ~= "skip") and true or false)
  p.deleteBtn:SetEnabled((sel and not busy and not holds and not sel.isGM) and true or false)
  p.returnBtn:SetEnabled((sel and not busy and not sel.isGM and not (sel.sender and string.find(sel.sender, "Auction House", 1, true))
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
  p.footer:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 6)
  p.footer:SetJustifyH("RIGHT")
end

function MailUI.BuildInbox(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.count, p.waiting = 0, 0
  p.list = L.New(p, MailUI.COLUMNS, 18, function() MailUI.Select() end)
  p.list.onEnter = MailUI.Hover
  p.list:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 112)
  p.detail = Th.Text(p, "body", 12, "text")
  p.detail:SetPoint("TOPLEFT", p.list, "BOTTOMLEFT", 4, -6)
  p.detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 34)
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
  Mailbox.OnChange = function() MailUI.dirty = true end
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
function MailUI.Tick()
  if not MailUI.dirty then return end
  MailUI.dirty = false
  MailUI.Repaint()
end
