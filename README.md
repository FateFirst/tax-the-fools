# Tax the Fools

Auction house price history, deal finding and crafting profit for the Ravencraft
server (Turtle WoW 1.18.1 client, WoW 1.12, Lua 5.0).

This release (0.9.0): the auction window, scanning, price history, tooltips, crafting
profit for every recipe your characters know, buying, selling, and sales tracking from
auction house mail. The **Deals** tab finds below-market, below-vendor, cheap-materials,
undersupplied and recipe listings; **Browse** buys and bids on the selected row; **Sell** and
**Auctions** post and cancel your own auctions; **History** shows what has sold; **Crafting**
shows the recipes each character could still learn, with what they cost and how fast they pay
back. **Mail** replaces the Blizzard mailbox: an Inbox with Collect all (sales mail is
deleted, letters keep their text and have gold and items taken, COD is never touched) and a
Send tab that fills a mail to your bank alt by rules and sends several stacks in one click.
The **Ledger** (an AH tab, or `/ttf ledger`) totals gold in and out per day and per item for all your
characters, keeping transfers between your own characters out of profit, and item tooltips and Browse
show a 7-day price trend, with a 30-day price chart on Browse and Sell. Gold moved through Blizzard's
own mail window is not recorded.
Next is in-game testing and polish. See
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
- **Recipe database.** The addon ships every Tailoring recipe, including the Turtle-only
  ones, from LibCrafts-1.0 by refaim (MIT; see `TaxTheFools/licenses/LibCrafts-1.0.txt`).
  Your own captures correct it: recipes your characters know, trainer windows, vendor windows
  and pattern tooltips. `make recipes` regenerates the built-in data.
- **Not learned.** On the Crafting page, press **Not learned** to list the recipes a character
  does not know yet: where to get each one (AH, vendor, trainer, drop or quest), its cost,
  profit per craft, payback in crafts, and how often it sells. **Learnable soon** (on by
  default) keeps those within your skill-ahead setting. **Learned** returns the usual list.
- **Payback.** A pattern's tooltip gets a line such as "Pays back in 4 crafts (+1g 20s each)",
  or who can learn it. Options > Crafting turns the line off. The addon never buys from a
  trainer or vendor; you do that in the game.
- **Recipe deals.** The Deals tab's *Recipe* type lists patterns on the auction house that one
  of your characters could learn and that pay back within 10 crafts (changeable in Options >
  Deals). Find and Buy work as they do for any deal.
- **Buying from Browse.** Select a row. **Buy** buys out that listing at its price;
  **Bid** places the next bid. Each is one click. Each is disabled, with a tooltip saying
  why, when it doesn't apply: no buyout, your own auction, can't afford, already the high
  bidder, or the auction house is still answering the last purchase.
- **Deals.** The Deals tab lists listings that look like a bargain, sorted by profit:
  - *Below market*: well under the usual price (default 70% of market).
  - *Below vendor*: under what a vendor pays for the item.
  - *Cheap materials*: a material listed at or under 85% of market that makes one
    of your known recipes more profitable.
  - *Undersupplied*: an item you hold that sells well (at least half of its recent
    auctions) and is scarce on the auction house now. It is a sell suggestion, never a
    buy: its button reads **Sell** and opens the Sell tab with that item selected.
  Use the left rail to switch each type on or off; Options > Deals sets the thresholds, the
  minimum profit and the minimum confidence. Select a deal and press **Find**: the addon pages through
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
- **Repost and Stock.** The Sell tab has a **Bags | Repost | Stock** switch (the last view is kept).
  **Repost** lists items in your bags whose auctions expired or were cancelled in the last 7 days
  (Options > Selling, 1 to 30), with the change in price (last price and price now are in the row tooltip); clicking a row
  selects the item with your last stack size, and Post stays one click per stack. **Stock** lists
  everything your characters hold in bags and bank plus what is on the auction house, with each,
  value, sell rate and trend, a per-character tooltip and a total. Mail is not counted.
- **Auctions.** Your own auctions, one page of up to 50, with the price per unit against the
  competition: red **Undercut** (someone is cheaper, with their price), green **Cheapest**, or
  dim **No competition**. **Cancel auction** takes the selected auction down in one click; if
  it has a bid, a confirmation says the bidder is refunded and you lose the deposit first.
- **Selling options.** Options > Selling: starting bid % (50 to 100), price floor % (50 to
  100), undercut (1c to 1g), the default duration, and how many days the Repost list covers (1 to 30).
- **Sales tracking.** Open a mailbox and the addon reads the headers of your auction mail
  (sold, expired, cancelled, won, outbid) and counts each mail once, across visits and relogs. Identical mails (several stacks expiring
  together, or bought for the same price) are counted individually.
  Reading headers never opens a mail, so nothing is marked read or has its expiry shortened.
- **History tab.** One row per item with sales: Sold, Expired, Rate, Avg price, Avg time and
  Income, for 7, 30 or 90 days, for all characters or one, with a totals line.
- **Sell panel and warning.** The Sell tab shows the selected item's sell rate, average sale
  price and average time to sell. It warns when the buyout is well above that average price
  (120% by default). The warning does not block **Post**. Item tooltips get a **Sells** line.
- **Right-click from bags.** With the auction window open on Browse, right-click a bag item to
  search for it; on Sell, right-click it to select it. With Shift, Ctrl or Alt held, or away from
  the auction house, a right-click works as usual.
- **Sales options.** Options > Sales: the sell-rate window (7 to 90 days), the price warning
  (100% to 200%), and the Sells tooltip line. Options > General: "Right-click bag items to search
  or sell". Options > Deals & buying: Undersupplied, and its thresholds.
- **Mailbox.** TTF replaces TurtleMail: disable TurtleMail to use TTF's mailbox. Opening a
  mailbox shows the TTF window (Options > Mail turns that off). **Inbox** lists your mail;
  **Collect all** takes the gold and items from letters (they stay, so you can read them) and
  deletes sold, expired and cancelled auction mail once its sale is recorded. COD mail is never
  touched; a full bag stops the chain with "Bags full", and **Stop** halts it. **Read** shows a
  letter's text. **Send** attaches several stacks and sends them to one recipient in one
  click (money rides on the first mail). **Fill for bank alt** attaches every bag item that
  matches your rules (crafted goods, cloth and trade goods, patterns, anything auctionable)
  and is not on the keep list; **Keep** adds the selected item to that list. Right-click a bag
  item on Send to attach it. Options > Mail sets the bank alt, the rules and the keep list.
- **Ledger.** The Ledger tab (after History) and `/ttf ledger` list what you earned and spent: Sales,
  Buys, Deposits, Vendor and Mail per day, or Income, Spend and Net per item, for 7, 30 or 90 days and
  any character. Bids count once a won-auction mail is read; outbids count nothing. Transfers to your
  own characters show on their own line. Options > Ledger turns vendor trades off. Gold moved through
  Blizzard's own mail window is not recorded.
- **Price trends.** Item tooltips show a "Trend 7d" line (rising, falling or steady) once there are about
  two weeks of scans. Browse has a sortable Trend column, and selecting an item on Browse or Sell shows a
  30-day price chart; hover a bar for its date and price.
- **Shopping list.** On Craft, set the **Craft** box to a number and press **List**: the materials
  for that many crafts, by the cheapest path (cloth or bolts), less what your characters and the bank
  alt hold. Click a Buy line to search for it on Browse; **Next material** steps through them and
  **Snipe these** adds them to the snipe list.
- **Snipe list.** A max price each per item. The **Snipe** button on Browse adds the selected item at its
  price; `/ttf snipe Silk Cloth 20s` sets one (a bare number after a money part is the next unit down: `1g 50` is 1g 50s) and `/ttf snipe` lists them. Deals > **Snipe** lists
  matching listings (not yours) with Find and Buy, and the Quick scan menu has a Snipe list scan.
- **Alerts.** During any scan or search, a chat line and a sound (at most every 5 seconds) tell you of a
  deal or snipe match, once per listing. Nothing is bought for you. Options > Alerts sets them.
- **Blizzard UI** switches to the stock window at any time; its **Tax the Fools** button
  switches back.

Nothing is ever bought, bid on, posted, cancelled, crafted or sold without your
click. The only things that run by themselves are a scan turning pages and reading the
headers of auction mail. Phase 5 (recipe payback and the mailbox) is done. Next is in-game
testing and polish.

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
    make recipes   regenerates the built-in Tailoring recipe data from LibCrafts-1.0

Run `docs/testing-checklist.md` in game after every install.

Fonts: Rajdhani and Inter, SIL Open Font License (`TaxTheFools/media/fonts/OFL-*.txt`).
The look follows Aegis Pathfinder; no code is taken from it.
Recipe data: LibCrafts-1.0 by refaim, MIT (https://github.com/refaim/LibCrafts-1.0).
