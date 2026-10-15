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
  "ERR_AUCTION_BID_PLACED", "ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_HIGHER_BID",
  "ERR_AUCTION_BID_OWN", "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_RESTRICTED_ACCOUNT",
}

function Probe.Lines()
  local out = {}
  local function add(s) table.insert(out, s) end
  local version, build, built = GetBuildInfo()
  add("Tax the Fools " .. D.VERSION .. "  client " .. tostring(version) .. " build " .. tostring(build)
    .. " (" .. tostring(built) .. ")")
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
