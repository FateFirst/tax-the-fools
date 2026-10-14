# In-game checklist

Run this after every install, on the real client. The tests prove the logic
against a fake client; this proves the fake client was right.

## Load
1. Log in on the bank character. Chat shows `TTF: v0.2.0 loaded`.
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
8. Start a full scan, press Blizzard UI mid-scan: the scan pauses (strip offers Resume when you come back) and Blizzard's list doesn't change under you.
9. Close our window with the X, then talk to the auctioneer again. It opens
   cleanly. Do the same with Escape.
10. Walk away from the auctioneer. Our window closes.

## Scanning
11. Start a **Full scan**. The strip shows page X/Y, s/page and time left within a few pages.
    Write down the s/page figure (spec §13 Q1).
12. Walk away mid-scan, come back. The strip offers Resume/Discard. Resume. It carries on
    from the same page.
13. Let it finish. `/ttf status` reports items with price history.
14. Select a cloth row, press Watch, then run a **Watchlist** scan. It finishes in seconds.
15. `/ttf probe` again with an AH page loaded: the `auction row 1` line shows 13 values.
    Paste it in as well (duration and time-left values settle spec §13 Q3).

## Tooltips and merchants
16. Hover Silk Cloth in your bags: Market (with confidence), Low now and Vendor lines,
    after a full scan. Hold Shift on a stack: the figures multiply.
17. Open a vendor and close it. Hover a grey item: a Vendor line appears.

## Options and look
18. The minimap button shows the goblin coin. Right-click opens options. Drag it round the minimap; `/reload`; it stays.
19. Options: switch theme to Frost. Open windows recolour at once. Switch back.
20. Headings render in Rajdhani (narrow, squared), body text in Inter — if both look like the stock game font, the bundled fonts failed to load (report it).
21. Turn off "Bundled fonts" and `/reload`: everything still readable in the stock font.
22. Move and resize the auction window, `/reload`, reopen. Same place, same size.
23. Nothing draws outside any window border at scale 80% and 150%.

## Other character
24. Log over to the priest. Hover Silk Cloth: the same market value, with no scan on this character.

## Crafting (phase 2)
25. The auction window and the Crafting window (`/ttf craft`) show the goblin logo
    before the title, 24px, not stretched or tinted.
26. On the tailor, open Tailoring. A dark strip appears just under the window's
    visible bottom edge, inside its width (not floating below empty space, not over
    the Create buttons). If it is off, note by how many pixels and adjust
    `TS.STRIP_X`, `TS.STRIP_Y` and `TS.STRIP_W` in `tradeskill.lua`.
27. Click Bolt of Silk Cloth. Within a quarter second the strip reads
    `Cost ...   Value ...   Profit ...`, green for a profit, red for a loss. Click a
    recipe whose materials were never scanned: `incomplete: <names>` in amber. Click
    a header: `Select a recipe to see its profit.`
28. Collapse a header (the minus beside it), close the window, `/ttf craft`: the
    recipes under that header are still listed.
29. `/ttf watchlist` lists the bolts, cloth and thread from the recipes (auto-watch).
    Options > Crafting, switch "Watch recipe materials automatically" off, unwatch one
    with `/ttf unwatch`, open Tailoring again: it stays unwatched.
30. Visit a trade goods vendor that sells Fine Thread. `/ttf craft`, select a recipe
    using it: the thread line says `vendor` with the vendor's price per thread, unless
    the AH is cheaper. A limited-stock item (some dyes) says `vendor, limited stock`.
31. Open the bank, deposit some Silk Cloth, close it. In `/ttf craft`, a recipe using
    Silk Cloth shows `have` counting bags and bank together.
32. Log over to the bank alt (no Tailoring). Left-click the minimap coin: the
    Crafting window opens on the tailor's recipes, priced from the bank alt's scans,
    and `have` includes what both characters hold.
33. In the AH, the **Crafting** tab shows the same page. Sort by Profit both ways:
    incomplete recipes stay at the bottom.
34. Options > Crafting, "Dim prices older than" 1 day: material lines priced from
    scans older than a day turn grey in the detail pane.
35. At no point above was anything crafted, bought or sold without your click.
