TaxTheFools = TaxTheFools or {}
local U, D, Th, W, DB = TaxTheFools.Util, TaxTheFools.Data, TaxTheFools.Theme, TaxTheFools.Widgets, TaxTheFools.DB
local Opt = { frame = nil }
TaxTheFools.Options = Opt

local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function secs(v) return string.format("%.1fs", v) end
local function days(v)
  if v == 1 then return "1 day" end
  return v .. " days"
end
local function themes()
  local t = {}
  for _, n in ipairs(Th.ORDER) do table.insert(t, { value = n, label = n }) end
  return t
end

-- The Deals rows read and write the same settings.deals table as the Deals
-- page's rail, so a change in one shows in the other the next time it paints.
local function money(v) return U.money(v) end

Opt.CATEGORIES = {
  { key = "general", label = "General", rows = {
    { kind = "switch", key = "replaceBlizzardAH", label = "Replace the Blizzard auction window",
      hint = "Takes effect next time you open the auction house. The Blizzard UI button switches back any time." },
    { kind = "switch", key = "minimap", label = "Minimap button", after = function() TaxTheFools.Minimap.Refresh() end,
      hint = "Shows the Tax the Fools button on the minimap. Left-click opens the crafting profit window, right-click opens these options. Drag it to move it round the minimap." },
    { kind = "slider", key = "scale", label = "Window scale", min = 0.8, max = 1.5, step = 0.05, fmt = pct,
      after = function() W.ApplyScale() end,
      hint = "Sizes every Tax the Fools window. 100% is normal; higher makes the windows and their text bigger. Default 100%." },
    { kind = "switch", key = "bagClick", label = "Right-click bag items to search or sell",
      hint = "At the auction house, right-click a bag item to search for it (Browse) or select it (Sell)." },
    { kind = "switch", key = "debug", label = "Debug messages",
      hint = "Prints extra detail, and shows Lua errors instead of quietly switching the failing part off." },
  } },
  { key = "scanning", label = "Scanning", rows = {
    { kind = "slider", key = "scanDelay", label = "Minimum time between pages", min = 0, max = 2, step = 0.1, fmt = secs,
      hint = "The shortest wait before a scan asks the auction house for its next page. Lower scans faster but the server may drop requests; higher is gentler. Default 0.3s." },
    { kind = "switch", key = "safeMode", label = "Safe pace (4s between pages)",
      hint = "Use this if scans keep repeating pages or stalling." },
    { kind = "switch", key = "browseFeedsHistory", label = "Searches add to price history",
      hint = "When on, the prices your Browse searches see are saved to the price history and market values, like a scan. Off keeps searches out of the history." },
  } },
  { key = "crafting", label = "Crafting", rows = {
    { kind = "switch", path = { "craft", "autoWatch" }, label = "Watch recipe materials automatically",
      hint = "Each time a tradeskill window opens, its products and materials join the Watchlist scan." },
    { kind = "slider", path = { "craft", "staleDays" }, label = "Dim prices older than", min = 1, max = 30, step = 1,
      fmt = days, after = function() TaxTheFools.CraftUI.RefreshAll() end,
      hint = "In the Craft tab, a price last seen more than this many days ago is dimmed, because it may be out of date. Default 7 days." },
    { kind = "switch", path = { "recipes", "tooltip" }, label = "Pattern payback tooltip line",
      hint = "Pattern tooltips say how many crafts pay the pattern back." },
    { kind = "slider", path = { "recipes", "skillAhead" }, label = "Learnable soon: skill ahead", min = 0, max = 75,
      step = 5,
      hint = "A pattern counts as learnable soon when a character is within this many skill points of its required skill. Higher lists patterns that are further off. Default 25." },
  } },
  { key = "deals", label = "Deals & buying", rows = {
    { kind = "switch", path = { "deals", "snipe" }, label = "Snipe",
      hint = "Shows listings on your snipe list that cost no more than your max each, as Snipe deals on the Deals tab. Your own listings are never shown." },
    { kind = "switch", path = { "deals", "market" }, label = "Below market",
      hint = "Lists auctions priced well under the item's market value (see the Below market percentage), if the profit after the 5% auction cut and deposit reaches the minimum." },
    { kind = "switch", path = { "deals", "vendor" }, label = "Below vendor",
      hint = "Lists auctions whose buyout is lower than what a vendor would pay you for the same items." },
    { kind = "switch", path = { "deals", "mats" }, label = "Cheap materials",
      hint = "Lists crafting materials priced under the Materials percentage of market that a known recipe uses, if the recipe would still make the minimum profit." },
    { kind = "slider", path = { "deals", "belowMarketPct" }, label = "Below market", min = 50, max = 95, step = 5,
      fmt = function(v) return v .. "%" end,
      hint = "A listing counts as a deal when its price per item is at or below this % of the market value. Lower finds fewer, better deals. Default 70%." },
    { kind = "slider", path = { "deals", "minProfit" }, label = "Minimum profit", min = 0, max = 100000, step = 1000,
      fmt = money,
      hint = "Below market, Cheap materials and Recipe deals must make at least this much profit to be listed. Higher hides small deals. Default 50s." },
    { kind = "slider", path = { "deals", "matPct" }, label = "Materials", min = 50, max = 100, step = 5,
      fmt = function(v) return v .. "%" end,
      hint = "A material is a cheap-materials deal when its price per item is at or below this % of its market value. Lower finds fewer, better deals. Default 85%." },
    { kind = "dropdown", path = { "deals", "minConfidence" }, label = "Minimum confidence",
      options = TaxTheFools.DealsUI.CONFIDENCE,
      hint = "How well the market value must be backed by scan history before a Below market deal is trusted. High needs plenty of recent scans; Low accepts thin data. Default Medium." },
    { kind = "switch", path = { "deals", "recipe" }, label = "Recipe",
      hint = "Patterns on the auction house that pay back quickly for a character who can learn them. Only single-pattern listings count, and the minimum profit applies too." },
    { kind = "slider", path = { "deals", "paybackCrafts" }, label = "Pays back within", min = 1, max = 50, step = 1,
      fmt = function(v) return v == 1 and "1 craft" or (v .. " crafts") end,
      hint = "A pattern is a deal when the profit from this many crafts covers its price. Lower finds fewer, quicker-paying patterns. Default 10 crafts." },
    { kind = "switch", path = { "deals", "under" }, label = "Undersupplied",
      hint = "Items you hold that sell well and are scarce on the auction house now." },
    { kind = "slider", path = { "deals", "underPct" }, label = "Undersupplied: listed at most", min = 10, max = 90,
      step = 5, fmt = function(v) return v .. "%" end,
      hint = "An item is scarce when the number of listings now is at most this % of its usual (30-day median) number. Lower finds only the scarcest items. Default 33%." },
    { kind = "slider", path = { "deals", "premiumPct" }, label = "Undersupplied: suggest at", min = 100, max = 150,
      step = 5, fmt = function(v) return v .. "%" end,
      hint = "The price Sell suggests for an undersupplied item, as a % of its market value or the lowest listing, whichever is higher. 100% is no premium. Default 110%." },
    { kind = "slider", path = { "buy", "confirmAbove" }, label = "Confirm buys at or above", min = 0, max = 500000,
      step = 10000,
      fmt = function(v) return v == 0 and "never" or money(v) end,
      hint = "A buy or bid at or above this amount asks you to confirm first. Set to never to skip the question. Default 5g." },
  } },
  { key = "alerts", label = "Alerts", rows = {
    { kind = "switch", path = { "alerts", "on" }, label = "Alerts",
      hint = "While any scan or Browse search reads the auction house, prints a chat line for each deal or snipe match it sees. Each listing alerts once per session. Alerts never buy, bid, post or cancel anything." },
    { kind = "slider", path = { "alerts", "minProfit" }, label = "Alert when profit is at least", min = 0,
      max = 200000, step = 5000, fmt = money,
      hint = "A below market, below vendor or cheap materials listing only alerts when its profit reaches this much. It is separate from the Deals minimum profit. Snipe matches ignore it. Default 1g." },
    { kind = "switch", path = { "alerts", "sound" }, label = "Play a sound",
      hint = "Plays a short sound when an alert is printed, at most once every 5 seconds however many alerts a scan finds." },
    { kind = "switch", path = { "alerts", "snipe" }, label = "Alert on snipe matches",
      hint = "Alerts when a listing on your snipe list costs no more than your max each. Your own listings never alert. Off leaves only deal alerts." },
  } },
  { key = "sales", label = "Sales", rows = {
    { kind = "slider", path = { "sales", "days" }, label = "Sell-rate window", min = 7, max = 90, step = 1, fmt = days,
      hint = "How many days of your sales history are used to work out how fast an item sells. Longer smooths out quiet weeks; shorter follows recent trends. Default 30 days." },
    { kind = "slider", path = { "sales", "warnPct" }, label = "Price warning above", min = 100, max = 200, step = 10,
      fmt = function(v) return v .. "%" end,
      hint = "On Sell, warns you when your buyout is above this % of the average price you have sold this item for. Lower warns sooner. Default 120%." },
    { kind = "switch", path = { "sales", "tooltip" }, label = "Sells line in item tooltips",
      hint = "Adds a Sells line to item tooltips: the share of your auctions of this item that sold (rather than expired or were cancelled) in the sell-rate window, and how many auctions that counts." },
  } },
  { key = "ledger", label = "Ledger", rows = {
    { kind = "switch", path = { "ledger", "vendor" }, label = "Count vendor buys and sales",
      hint = "Gold spent at and earned from vendors shows in the Ledger." },
  } },
  { key = "selling", label = "Selling", rows = {
    { kind = "slider", path = { "sell", "bidPct" }, label = "Starting bid, % of buyout", min = 50, max = 100, step = 5,
      fmt = function(v) return v .. "%" end,
      hint = "Sell sets the starting bid to this % of the buyout price. 100% means bid and buyout are equal. Default 90%." },
    { kind = "slider", path = { "sell", "floorPct" }, label = "Price floor, % of market value", min = 50, max = 100,
      step = 5, fmt = function(v) return v .. "%" end,
      hint = "Sell will not suggest a buyout under this % of the item's market value, however low the competition goes, and warns when you type one. Default 80%." },
    { kind = "slider", path = { "sell", "undercut" }, label = "Undercut by", min = 1, max = 10000, step = 1,
      fmt = money,
      hint = "How much Sell takes off the cheapest rival's buyout price per item when it suggests a price. Default 1 copper." },
    { kind = "slider", path = { "sell", "repostDays" }, label = "Repost list covers", min = 1, max = 30, step = 1, fmt = days,
      hint = "The Repost view on Sell lists items in your bags whose auctions expired or were cancelled within this many days. Default 7 days." },
    { kind = "dropdown", path = { "sell", "duration" }, label = "Default duration", options = {
      { value = 120, label = "6h" }, { value = 480, label = "24h" }, { value = 1440, label = "72h" } },
      hint = "How long Sell lists an auction for to begin with. Longer lasts more time but costs a bigger deposit. Default 24h." },
    { kind = "switch", path = { "sell", "quickVendor" }, label = "Include vendor-priced items",
      after = function() if TaxTheFools.QuickUI then TaxTheFools.QuickUI.SettingsChanged() end end,
      hint = "In the Quick view on Sell, Post next also posts items with no auction or market price, at their vendor price times the multiple below. Off passes over them. Default off." },
    { kind = "slider", path = { "sell", "vendorMult" }, label = "Vendor price multiple", min = 1, max = 20, step = 1,
      fmt = function(v) return "x" .. v end,
      after = function() if TaxTheFools.QuickUI then TaxTheFools.QuickUI.SettingsChanged() end end,
      hint = "An item with no auction or market price is priced at its vendor price times this, in the Quick view and the Bags view. Default x3." },
  } },
  { key = "tooltip", label = "Tooltip", rows = {
    { kind = "switch", path = { "tooltip", "market" }, label = "Market value",
      hint = "Adds the item's market value (its usual auction price from your scans) to item tooltips." },
    { kind = "switch", path = { "tooltip", "low" }, label = "Lowest price in the latest scan",
      hint = "Adds the lowest price per item seen in the most recent scan to item tooltips." },
    { kind = "switch", path = { "tooltip", "vendor" }, label = "Vendor price",
      hint = "Adds what a vendor pays for the item to item tooltips." },
    { kind = "switch", path = { "trend", "tooltip" }, label = "Price trend line",
      hint = "Adds a line to item tooltips comparing the median price of the last 7 days with the 7 days before: rising, falling, or steady when within 5%. Needs about two weeks of scans." },
  } },
  { key = "appearance", label = "Appearance", rows = {
    { kind = "dropdown", key = "theme", label = "Theme", options = themes(), after = function(v) Th.Apply(v) end,
      hint = "The colour scheme of every Tax the Fools window. It applies straight away." },
    { kind = "switch", key = "fonts", label = "Bundled fonts (needs /reload)",
      hint = "Uses the fonts that come with the addon. Switch off to use the game's own font. Type /reload after changing it." },
  } },
  { key = "mail", label = "Mail", rows = {
    { kind = "switch", key = "replaceBlizzardMail", label = "Replace Blizzard's mailbox",
      hint = "Takes effect next time you open a mailbox. Disable TurtleMail first; TTF replaces it." },
    { kind = "dropdown", label = "Bank alt", options = function() return Opt.BankAltOptions() end,
      get = function() return DB.S().mail.bankAlt or "" end,
      set = function(v) if v == "" then DB.S().mail.bankAlt = nil else DB.S().mail.bankAlt = v end end,
      hint = "The character that Fill for bank alt in the Mail tab addresses mail to. Pick one of your characters on this realm, or None." },
    { kind = "switch", path = { "mail", "rules", "crafted" }, label = "Crafted goods",
      hint = "Fill for bank alt includes items that one of your recipes makes." },
    { kind = "switch", path = { "mail", "rules", "tradeGoods" }, label = "Cloth and trade goods",
      hint = "Fill for bank alt includes anything in the Trade Goods category, such as cloth, ore and herbs." },
    { kind = "switch", path = { "mail", "rules", "patterns" }, label = "Patterns",
      hint = "Fill for bank alt includes recipes, patterns, formulas and plans." },
    { kind = "switch", path = { "mail", "rules", "auctionable" }, label = "Anything auctionable",
      hint = "Fill for bank alt includes every bag item that can be sold at the auction house. Off by default." },
    { kind = "keeplist", label = "Never fill (click to remove)",
      hint = "Items you told Mail to keep. Fill for bank alt never attaches them. Click a name to take it off the list." },
  } },
  { key = "data", label = "Data", rows = {
    { kind = "info", text = function() return DB.SizeText() end },
    { kind = "button", label = "Prune old data now",
      hint = "Trims old price history now, instead of waiting for the next automatic clean-up. Your settings and recent prices stay.",
      onClick = function()
        DB.StartPrune()
        TaxTheFools.Core.pruned = false
        U.msg("Pruning old price history.")
      end },
    { kind = "button", label = "Reset all data",
      hint = "Asks first, then deletes all price history, items and settings for every character and reloads the interface.",
      onClick = function() StaticPopup_Show("TAXTHEFOOLS_RESET") end },
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

-- "None" plus every character the addon knows on this realm.
function Opt.BankAltOptions()
  local o = { { value = "", label = "None" } }
  local names = {}
  for name in pairs(DB.Realm().chars) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do table.insert(o, { value = name, label = name }) end
  return o
end

Opt.KEEP_SHOWN = 8

-- Keep-list keys, sorted, as { key, name } rows.
function Opt.KeepRows()
  local keys = {}
  for k in pairs(DB.S().mail.keep) do table.insert(keys, k) end
  table.sort(keys)
  local rows = {}
  for _, k in ipairs(keys) do
    local _, _, id = string.find(k, "^(%d+)")
    table.insert(rows, { key = k, name = id and TaxTheFools.Items.Name(tonumber(id)) or k })
  end
  return rows
end

local function path(row) return row.path or { row.key } end

function Opt.Get(row)
  if row.get then return row.get() end
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  return t[p[table.getn(p)]]
end

function Opt.Set(row, v)
  if row.set then
    row.set(v)
    DB.Touch()
    if row.after then row.after(v) end
    return
  end
  local t, p = DB.S(), path(row)
  for i = 1, table.getn(p) - 1 do t = t[p[i]] end
  t[p[table.getn(p)]] = v
  DB.Touch()
  if row.after then row.after(v) end
end

-- One control for one row. row arrives as a parameter, so the closures below
-- each keep their own (a loop variable would be shared in Lua 5.0).
function Opt.Control(parent, row)
  local get = function() return Opt.Get(row) end
  local set = function(v) Opt.Set(row, v) end
  if row.kind == "switch" then return W.Switch(parent, row.label, get, set, row.hint) end
  if row.kind == "slider" then return W.Slider(parent, row.label, row.min, row.max, row.step, get, set, row.fmt, row.hint) end
  if row.kind == "dropdown" then
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(320)
    f:SetHeight(26)
    f.text = Th.Text(f, "body", 13, "text")
    f.text:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text:SetText(row.label)
    local opts = row.options
    if type(opts) == "function" then opts = opts() end
    f.dd = W.Dropdown(f, 140, opts, get, set, row.hint, row.label)
    W.HoverTip(f, row.label, row.hint)
    f.dd:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.Refresh = function(self)
      if type(row.options) == "function" then self.dd:SetOptions(row.options()) end
      self.dd:Refresh()
    end
    return f
  end
  if row.kind == "keeplist" then
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(320)
    f:SetHeight(15 + 13 * (Opt.KEEP_SHOWN + 1))  -- fits under five switches and a dropdown in the 400 high window
    f.title = Th.Text(f, "body", 13, "text")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.title:SetText(row.label)
    W.HoverTip(f, row.label, row.hint)
    f.lines = {}
    for i = 1, Opt.KEEP_SHOWN + 1 do
      local b = CreateFrame("Button", nil, f)
      b:SetHeight(13)
      b:SetWidth(320)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 - 13 * i)
      b.text = Th.Text(b, "body", 11, "dim")
      b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
      b:SetScript("OnClick", function()
        if this.itemKey then
          DB.KeepSet(this.itemKey, false)
          f:Refresh()
        end
      end)
      W.HoverTip(b, row.label, row.hint)
      f.lines[i] = b
    end
    f.Refresh = function(self)
      local rows = Opt.KeepRows()
      local n = table.getn(rows)
      for i = 1, Opt.KEEP_SHOWN do
        local line, r = self.lines[i], rows[i]
        line.itemKey = r and r.key or nil
        line.text:SetText(r and r.name or "")
        if r then line:Show() else line:Hide() end
      end
      local more = self.lines[Opt.KEEP_SHOWN + 1]
      more.itemKey = nil
      if n > Opt.KEEP_SHOWN then
        more.text:SetText("+" .. (n - Opt.KEEP_SHOWN) .. " more")
        more:Show()
      elseif n == 0 then
        more.text:SetText("Nothing kept yet")
        more:Show()
      else
        more:Hide()
      end
    end
    return f
  end
  if row.kind == "button" then
    local b = W.Button(parent, row.label, 180, 24, row.onClick)
    if row.hint then W.Tip(b, row.label, row.hint) end
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

Opt.VIEW_H = 338     -- the page's height in the 400 high window, until the client reports its own
Opt.WHEEL_STEP = 30
Opt.BAR = 10         -- the scrollbar's width

function Opt.Wheel(p, frame)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function() Opt.ScrollTo(p, p.scroll - arg1 * Opt.WHEEL_STEP) end)
end

-- The page is a frame holding a ScrollFrame, whose scroll child holds the controls, and a thin
-- scrollbar that shows only when the controls are taller than the view.
function Opt.Page(f, cat)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f.nav, "TOPRIGHT", 16, -14)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  p.controls, p.scroll, p.range, p.updating = {}, 0, 0, false
  p.sf = CreateFrame("ScrollFrame", nil, p)
  p.sf:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.sf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(Opt.BAR + 6), 0)
  p.child = CreateFrame("Frame", nil, p.sf)
  p.child:SetWidth(340)
  p.child:SetHeight(1)
  p.sf:SetScrollChild(p.child)
  local bar = CreateFrame("Slider", nil, p)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(Opt.BAR)
  bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  local track = Th.Solid(bar, "BACKGROUND", "panel3")
  track:SetAllPoints(bar)
  bar:SetThumbTexture(Th.MEDIA .. "solid")
  local thumb = bar:GetThumbTexture()
  thumb:SetWidth(Opt.BAR)
  thumb:SetHeight(30)
  Th.Tint(thumb, "subtle")
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetScript("OnValueChanged", function()
    if p.updating then return end
    Opt.ScrollTo(p, this:GetValue())
  end)
  bar:Hide()
  p.bar = bar
  p.sf:EnableMouseWheel(true)
  Opt.Wheel(p, p.sf)
  local y = 0
  for _, row in ipairs(cat.rows) do
    local c = Opt.Control(p.child, row)
    c:SetPoint("TOPLEFT", p.child, "TOPLEFT", 0, -y)
    y = y + c:GetHeight() + 10
    table.insert(p.controls, c)
  end
  -- Every control forwards the wheel to the page, so it scrolls with the cursor anywhere on it.
  for _, c in ipairs(p.controls) do
    Opt.Wheel(p, c)
    if type(c.slider) == "table" then Opt.Wheel(p, c.slider) end
    if type(c.dd) == "table" then Opt.Wheel(p, c.dd) end
    if type(c.lines) == "table" then for _, b in ipairs(c.lines) do Opt.Wheel(p, b) end end
  end
  Opt.Wheel(p, bar)
  p.contentH = math.max(1, y - 10)
  p.child:SetHeight(p.contentH)
  -- Guarded: should this client not know the handler, Select's Fit still sizes the page.
  pcall(p.SetScript, p, "OnSizeChanged", function() Opt.Fit(p) end)
  return p
end

-- The scroll offset, kept between 0 and the range; the bar follows.
function Opt.ScrollTo(p, v)
  if v > p.range then v = p.range end
  if v < 0 then v = 0 end
  if v ~= p.scroll then
    -- an open dropdown menu floats on UIParent and would be left behind
    for _, c in ipairs(p.controls) do
      if type(c.dd) == "table" then c.dd.menu:Hide() end
    end
  end
  p.scroll = v
  p.sf:SetVerticalScroll(v)
  p.updating = true
  p.bar:SetValue(v)
  p.updating = false
end

-- Sizes the scroll child to the page's width and works out how far it scrolls.
function Opt.Fit(p)
  local view, w = p.sf:GetHeight(), p.sf:GetWidth()
  if not view or view <= 0 then view = Opt.VIEW_H end
  if w and w > 0 then p.child:SetWidth(w) end
  p.range = math.max(0, p.contentH - view)
  p.bar:SetMinMaxValues(0, p.range)
  if p.range > 0 then p.bar:Show() else p.bar:Hide() end
  Opt.ScrollTo(p, p.scroll)
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
    if on then
      Opt.Fit(page)
      Opt.ScrollTo(page, 0)
    end
  end
  for _, c in ipairs(f.pages[key].controls) do c:Refresh() end
end

function Opt.Toggle()
  local f = Opt.Create()
  if f:IsShown() then f:Hide() else f:Show() end
end
