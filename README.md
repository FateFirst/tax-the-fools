# Tax the Fools

Auction house price history, deal finding and crafting profit for the Ravencraft
server (Turtle WoW 1.18.1 client, WoW 1.12, Lua 5.0).

This release (0.4.0): the auction window, scanning, price history, tooltips, crafting
profit for every recipe your characters know, buying, and selling. The **Deals** tab finds
below-market, below-vendor and cheap-materials listings; **Browse** buys and bids on
the selected row; **Sell** and **Auctions** post and cancel your own auctions. Next is
phase 4: tracking your sales from auction house mail. See
`docs/superpowers/specs/2026-10-14-tax-the-fools-design.md` for the overall design.

## Install

Copy the `TaxTheFools` folder into `twmoa_1181\Interface\AddOns`, or from this repo:

    make install ADDONS="/path/to/twmoa_1181/Interface/AddOns"

## Use

- **Scan on your bank character.** Talk to an auctioneer and press **Full scan**.
  It pages through the whole auction house at the pace the server allows, which takes
  many minutes. Leave the auctioneer whenever you like; next visit the same day,
  press **Resume**.
- **Watchlist.** Select an item in Browse and press **Watch**, or `/ttf watch Silk Cloth`.
  **Watchlist** scans only those items, in seconds.
- **Every character sees the prices.** Data is account-wide; log over (or `/reload`) and
  hover an item.
- **Tooltips** show market value (a recent-weighted typical price) with how sure
  the addon is (high / medium / low), the lowest price in the latest scan, and the
  vendor price once a merchant has seen the item. Hold Shift for whole-stack values.
- **Crafting profit.** Open your Tailoring window (or any tradeskill) once on each
  crafter; the addon remembers its recipes. A strip under the tradeskill window shows
  the selected recipe's cost, value and profit. `/ttf craft`, the minimap coin, or the
  AH **Crafting** tab lists every recipe with cost, value, profit and cash profit (which
  treats materials any of your characters already hold as free), on any character.
  Materials are priced at the cheaper of the AH and the vendor, or crafted when that
  is cheaper still. A recipe with a missing price says "incomplete" and names it; it
  never guesses.
- **Vendor and bank.** Visiting a vendor teaches the addon its buy prices (thread,
  dye); opening your bank records what is in it, so "have" counts bags and bank.
- **Buying from Browse.** Select a row. **Buy** buys out that listing at its price;
  **Bid** places the next bid. Each is one click. Each is disabled, with a tooltip saying
  why, when it doesn't apply: no buyout, your own auction, can't afford, already the high
  bidder, or the auction house is still answering the last purchase.
- **Deals.** The Deals tab lists listings that look like a bargain, sorted by profit:
  - *Below market*: well under the usual price (default 70% of market).
  - *Below vendor*: under what a vendor pays for the item.
  - *Cheap materials*: a material listed at or under 85% of market that makes one
    of your known recipes more profitable.
  Use the left rail to switch each type on or off, set the thresholds, the minimum profit
  and the minimum confidence. Select a deal and press **Find**: the addon pages through
  the auction house until it finds that listing, and the button becomes **Buy <price>**.
  If the listing has gone, the status bar says `Gone` and the deal is removed. Find is refused while a
  full scan or watchlist scan is running: pause it first.
- **Confirmation.** Options > Deals & buying > "Confirm buys at or above" (default 5g,
  0 = never). A buy at or above that amount opens a Confirm purchase window; nothing is
  bought until you press its **Buy**. Bids are never confirmed.
- **Sell.** Pick an item from your bags and the Sell tab lists the competing auctions for it,
  with a suggested buyout: 1c under the cheapest competing unit price at or above your floor
  (80% of market by default), or the market value when nothing qualifies. The starting bid is
  a percentage of the buyout (90% by default). Set the stack size and how many stacks, pick a
  duration (6h, 24h or 72h), and read the deposit and what you will receive. The deposit shows
  as `approx` until you have posted that item at that duration; after that it is the amount
  the last post actually took. Post is one click per stack: when no bag stack matches the
  size you chose, the button reads **Split** first, which splits one stack into an empty bag
  slot (never a quiver or soul bag). Going below the floor is blocked until you tick
  **Allow below floor**. Items that are soulbound, quest items or conjured are not listed.
- **Auctions.** Your own auctions, one page of up to 50, with the price per unit against the
  competition: red **Undercut** (someone is cheaper, with their price), green **Cheapest**, or
  dim **No competition**. **Cancel auction** takes the selected auction down in one click; if
  it has a bid, a confirmation says the bidder is refunded and you lose the deposit first.
- **Selling options.** Options > Selling: starting bid % (50 to 100), price floor % (50 to
  100), undercut (1c to 1g), and the default duration.
- **Blizzard UI** switches to the stock window at any time; its **Tax the Fools** button
  switches back.

Nothing is ever bought, bid on, posted, cancelled, crafted or sold without your
click. The only thing that runs by itself is a scan turning pages. Sales tracking from
auction house mail is next, in phase 4.

## Commands

    /ttf options              settings
    /ttf craft                crafting profit window
    /ttf watch <item name>    add to the watchlist
    /ttf unwatch <item name>  remove from it
    /ttf watchlist            list it
    /ttf status               what is stored, when the last full scan ran
    /ttf show                 bring the auction window back
    /ttf probe                copyable dump of what this client supports
    /ttf debug                debug messages and stack traces

## Develop

    make test      builds Lua 5.0.3 once, lints, runs the tests against a fake client
    make media     regenerates the textures
    make fonts     re-downloads the bundled fonts

Run `docs/testing-checklist.md` in game after every install.

Fonts: Rajdhani and Inter, SIL Open Font License (`TaxTheFools/media/fonts/OFL-*.txt`).
The look follows Aegis Pathfinder; no code is taken from it.
