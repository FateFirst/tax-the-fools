# Tax the Fools

Auction house price history, deal finding and crafting profit for the Ravencraft
server (Turtle WoW 1.18.1 client, WoW 1.12, Lua 5.0).

Phase 1, this release: the auction window, scanning, price history and tooltips.
Crafting profit, deals with one-click buying, selling, and sales tracking follow
(see `docs/superpowers/specs/2026-10-14-tax-the-fools-design.md`).

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
- **Blizzard UI** switches to the stock window at any time; its **Tax the Fools** button
  switches back. Buying and selling from our own window arrives in phase 3.

Nothing is ever bought, bid on, posted or cancelled without your click. The only
thing that runs by itself is a scan turning pages.

## Commands

    /ttf options              settings
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
