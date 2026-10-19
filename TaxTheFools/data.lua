TaxTheFools = TaxTheFools or {}
local D = {}
TaxTheFools.Data = D

D.VERSION = "0.12.0"
-- Bump when saved data needs a one-time migration (see db.lua MIGRATIONS).
D.DATA_VERSION = 1

D.PAGE_SIZE = 50
D.QUERY_TIMEOUT = 15     -- seconds without a reply before a page is asked for again
D.MAX_RETRIES = 3        -- resends before the scan stalls and asks the player
D.SAFE_DELAY = 4         -- seconds between pages in safe pace
D.MAX_DUPES = 3          -- re-asks of one page that repeats before it is taken as genuine
D.NAME_WAIT = 1          -- seconds to wait for uncached item names on a page
D.MARKET_DAYS = 30
D.DECAY = 0.9
D.KEEP_DAYS = 60
D.KEEP_MONTHS = 12
D.MARKET_PER_FRAME = 300
D.PRUNE_PER_FRAME = 50
D.CRAFT_DEPTH = 4         -- a material crafted from materials crafted from ..., at most this deep
D.AH_CUT = 0.05
D.DEPOSIT_MINUTES = 480   -- the middle duration (8h, shown as 24h on Turtle)
D.ACTION_TIMEOUT = 5      -- seconds to wait for the reply to a buy or bid
D.NOTE_SECS = 10          -- seconds a buy or bid message stays on the status strip

D.DEFAULTS = {
  settings = {
    debug = false,
    replaceBlizzardAH = true,
    replaceBlizzardMail = true,
    minimap = true,
    minimapAngle = 200,
    scale = 1,
    theme = "Pathfinder",
    fonts = true,
    scanDelay = 0.3,
    safeMode = false,
    browseFeedsHistory = true,
    tooltip = { market = true, low = true, vendor = true },
    craft = { autoWatch = true, staleDays = 7 },
    deals = { snipe = true, market = true, vendor = true, mats = true, belowMarketPct = 70, minProfit = 5000, matPct = 85,
              minConfidence = 0.4, under = true, underPct = 33, premiumPct = 110,
              recipe = true, paybackCrafts = 10 },
    buy = { confirmAbove = 50000 },        -- copper; 0 never asks
    sell = { bidPct = 90, floorPct = 80, undercut = 1, duration = 480, repostDays = 7, vendorMult = 3, quickVendor = false },
    bagClick = true,                       -- right-click a bag item at the AH: search (Browse) or select (Sell)
    sales = { days = 30, warnPct = 120, tooltip = true },
    ledger = { vendor = true },
    trend = { tooltip = true },
    alerts = { on = true, minProfit = 10000, sound = true, snipe = true },
    recipes = { tooltip = true, skillAhead = 25 },
    mail = { bankAlt = nil, rules = { crafted = true, tradeGoods = true, patterns = true, auctionable = false }, keep = {}, keepRemoved = {} },
  },
  items = {},
  realms = {},
  recipes = {},
}

D.CHAR_DEFAULTS = { windows = {}, sellView = "bags" }

D.REALM_DEFAULTS = { history = {}, market = {}, scan = {}, chars = {}, watch = {}, snipe = {}, removed = { watch = {}, snipe = {} } }
