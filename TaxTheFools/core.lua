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
  A.MailUI.Create()
  A.Minimap.Create()
  A.BagClick.Install()
  DB.StartPrune()
  Core.pruned = false
  Core.Safe("selling log", A.Sell.Prune, DB.Char(), time())
  Core.Safe("sales log", A.Sales.Prune, DB.Char(), time())
  Core.Safe("ledger prune", A.Ledger.Prune, DB.Char(), time())
  Core.Safe("ledger backfill", A.Ledger.Backfill, DB.Char())
  Core.Safe("ledger", A.LedgerHooks.Sync)
  A.Inventory.bagsDirty = true      -- count the bags once at login, whichever event comes first
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

Core.INVENTORY_EVENTS = { BAG_UPDATE = true, BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true,
                          PLAYERBANKSLOTS_CHANGED = true, PLAYER_ENTERING_WORLD = true }

function Core.OnEvent(e)
  if e == "VARIABLES_LOADED" then return Core.Init() end
  if not Core.ready then return end
  if e == "AUCTION_HOUSE_SHOW" then Core.Safe("auction open", A.AH.OnShow)
  elseif e == "AUCTION_HOUSE_CLOSED" then Core.Safe("auction close", A.AH.OnClosed)
  elseif e == "AUCTION_ITEM_LIST_UPDATE" then Core.Safe("scan", A.Scan.OnListUpdate, GetTime())
  elseif e == "MERCHANT_SHOW" then
    Core.Safe("items", A.Items.LearnVendorPrices)
    Core.Safe("items", A.Items.LearnMerchantPrices)
    Core.Safe("ledger", A.LedgerHooks.MerchantShow)
  elseif e == "MERCHANT_CLOSED" then Core.Safe("ledger", A.LedgerHooks.MerchantClosed)
  elseif Core.INVENTORY_EVENTS[e] then
    Core.Safe("inventory", A.Inventory.OnEvent, e)
    if e == "BAG_UPDATE" then Core.Safe("mail window", A.MailUI.OnBag) end
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_UPDATE" or e == "TRADE_SKILL_CLOSE" then
    Core.Safe("tradeskill", A.TradeSkill.OnEvent, e, GetTime())
  elseif e == "PLAYER_MONEY" then
    Core.Safe("interface", A.UI.RefreshGold)
    Core.Safe("auction money", A.Auction.OnMoney, GetTime())
    Core.Safe("ledger", A.LedgerHooks.OnMoney)
    Core.Safe("auction", A.Auction.Changed)
  elseif e == "AUCTION_OWNED_LIST_UPDATE" then Core.Safe("auctions", A.AuctionsUI.Read)
  elseif e == "MAIL_SHOW" or e == "MAIL_INBOX_UPDATE" then
    Core.Safe("mail", A.Mail.OnEvent, e)
    Core.Safe("mailbox", A.Mailbox.OnEvent, e)
    if e == "MAIL_INBOX_UPDATE" then Core.Safe("mail window", A.MailUI.OnEvent, e) end
    if e == "MAIL_SHOW" then Core.Safe("mail window", A.MailHook.OnShow) end
  elseif e == "MAIL_SEND_SUCCESS" then Core.Safe("mailbox", A.Mailbox.OnEvent, e)
  elseif e == "MAIL_CLOSED" then
    Core.Safe("mailbox", A.Mailbox.OnClosed)
    Core.Safe("mail window", A.MailHook.OnClosed)
  elseif e == "TRAINER_SHOW" or e == "TRAINER_UPDATE" then Core.Safe("trainer", A.RecipesLearn.OnTrainer)
  elseif e == "CHAT_MSG_SYSTEM" or e == "UI_ERROR_MESSAGE" then
    Core.Safe("auction", A.Auction.OnMessage, arg1)
    if e == "CHAT_MSG_SYSTEM" then Core.Safe("mail note", A.Mail.OnMessage, arg1)
    else Core.Safe("mailbox", A.Mailbox.OnError, arg1) end
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
  Core.Safe("auction tick", A.AH.Tick)
  Core.Safe("scan", A.Scan.Tick, now)
  Core.Safe("auction", A.Auction.Tick, now)
  Core.Safe("inventory", A.Inventory.Tick, now)
  Core.Safe("tradeskill", A.TradeSkill.Tick, now)
  Core.Safe("mail", A.Mail.Tick)
  Core.Safe("mail window", A.MailHook.Tick)
  Core.Safe("mailbox", A.Mailbox.Tick, now)
  Core.Safe("mail window", A.MailUI.Tick)
  Core.Safe("trainer", A.RecipesLearn.Tick)
  if not Core.pruned then Core.Safe("prune", Core.PruneTick) end
  if now - Core.uiAt >= 0.25 then
    Core.uiAt = now
    Core.Safe("interface", A.UI.Tick, now)
    Core.Safe("tradeskill", A.TradeSkill.Poll, now)
  end
end

Core.HELP = {
  "/ttf options - settings",
  "/ttf craft - crafting profit for every recipe you have captured",
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
  elseif cmd == "craft" then A.CraftUI.Toggle()
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
                     "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_MONEY", "BAG_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                     "PLAYERBANKSLOTS_CHANGED", "PLAYER_ENTERING_WORLD", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
                     "TRADE_SKILL_CLOSE", "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE", "AUCTION_OWNED_LIST_UPDATE",
                     "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_CLOSED", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function() Core.OnEvent(event) end)
frame:SetScript("OnUpdate", function() Core.Update(GetTime()) end)
