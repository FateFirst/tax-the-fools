# In-game checklist

Run this after every install, on the real client. The tests prove the logic
against a fake client; this proves the fake client was right.

## Load
1. Log in on the bank character. Chat shows `TTF: v0.1.0 loaded`.
2. `/ttf probe`. The window opens with text selected. Press Ctrl+C and paste it
   into `tools/probe-<date>.txt` in this repo. Check:
   - every `fn` line says `yes`, except possibly `GetInboxInvoiceInfo`, `CalculateAuctionDeposit` (spec §13 Q2)
   - `TURTLE_WOW_VERSION` is set
3. `/reload`. No errors, and no "stopped after an error" lines.

## Auction window
4. Talk to an auctioneer. The Tax the Fools window opens and Blizzard's does not.
5. Search "cloth" in Browse. Results appear with Each, Market (dashes at first) and Seller.
6. Next page, then previous page. The page text follows.
7. Press **Blizzard UI**. Blizzard's window appears. Its **Tax the Fools** button
   brings ours back. Search again to prove the session survived the switches.
8. Close our window with the X, then talk to the auctioneer again. It opens
   cleanly. Do the same with Escape.
9. Walk away from the auctioneer. Our window closes.

## Scanning
10. Start a **Full scan**. The strip shows page X/Y, s/page and time left within a few pages.
    Write down the s/page figure (spec §13 Q1).
11. Walk away mid-scan, come back. The strip offers Resume/Discard. Resume. It carries on
    from the same page.
12. Let it finish. `/ttf status` reports items with price history.
13. Select a cloth row, press Watch, then run a **Watchlist** scan. It finishes in seconds.
14. `/ttf probe` again with an AH page loaded: the `auction row 1` line shows 13 values.
    Paste it in as well (duration and time-left values settle spec §13 Q3).

## Tooltips and merchants
15. Hover Silk Cloth in your bags: Market (with confidence), Low now and Vendor lines,
    after a full scan. Hold Shift on a stack: the figures multiply.
16. Open a vendor and close it. Hover a grey item: a Vendor line appears.

## Options and look
17. Minimap **TF** button opens options. Drag it round the minimap; `/reload`; it stays.
18. Options: switch theme to Frost. Open windows recolour at once. Switch back.
19. Turn off "Bundled fonts" and `/reload`: everything still readable in the stock font.
20. Move and resize the auction window, `/reload`, reopen. Same place, same size.
21. Nothing draws outside any window border at scale 80% and 150%.

## Other character
22. Log over to the priest. Hover Silk Cloth: the same market value, with no scan on this character.
