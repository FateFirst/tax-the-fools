TaxTheFools = TaxTheFools or {}
local A = TaxTheFools
local MailRules = {}
A.MailRules = MailRules

-- Pure mailbox rules (phase 5b spec section 3): every table arrives as an argument. Sales and Recipes are
-- read at call time.

-- True for mail from the auction house: the sender says so, or the subject is an auction outcome.
local function isAuctionMail(h)
  if h.sender and string.find(h.sender, "Auction House", 1, true) then return true end
  return A.Sales.Classify(h.subject) ~= nil
end

-- h = { sender, subject, money, cod, hasItem, isGM, wasReturned, textCreated, body }; body only when known.
-- Returns "skip", "take" or "take+delete".
function MailRules.Plan(h)
  if (h.cod or 0) > 0 or h.isGM then return "skip" end
  local ah = isAuctionMail(h)
  if (h.money or 0) <= 0 and not h.hasItem and not ah then return "skip" end
  if ah or h.body == nil or h.body == "" then return "take+delete" end
  return "take"
end

-- item = { key, name, type, auctionable }; rules = { crafted, tradeGoods, patterns, auctionable };
-- keep = set of keys; ctx = { products = set of keys }.
function MailRules.Matches(item, rules, keep, ctx)
  if keep and keep[item.key] then return false end
  if not item.auctionable then return false end
  rules = rules or {}
  if rules.crafted and ctx and ctx.products and ctx.products[item.key] then return true end
  if rules.tradeGoods and item.type == "Trade Goods" then return true end
  if rules.patterns and A.Recipes.IsPattern(item.name, item.type) then return true end
  if rules.auctionable then return true end
  return false
end

function MailRules.Subject(name, count)
  if (count or 1) > 1 then return name .. " (" .. count .. ")" end
  return name
end

function MailRules.Postage(price, n)
  if (n or 0) < 1 then n = 1 end
  return price * n
end
