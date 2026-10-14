TaxTheFools = TaxTheFools or {}
local D = {}
TaxTheFools.Data = D

D.VERSION = "0.2.0"
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

D.DEFAULTS = {
  settings = {
    debug = false,
    replaceBlizzardAH = true,
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
  },
  items = {},
  realms = {},
}

D.CHAR_DEFAULTS = { windows = {} }

D.REALM_DEFAULTS = { history = {}, market = {}, scan = {}, chars = {}, watch = {} }
