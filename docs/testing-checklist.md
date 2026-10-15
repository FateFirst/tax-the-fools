# In-game checklist

Run this after every install, on the real client. The tests prove the logic
against a fake client; this proves the fake client was right.

## Load
1. Log in on the bank character. Chat shows `TTF: v0.6.0 loaded`.
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

## Buying (phase 3a)
35. Browse: search for a cheap item that has a buyout. Select its row and press **Buy**
    (it reads `Buy <price>`). Only that listing goes, and the gold drops by its price.
36. Select an auction with a bid and press **Bid** (it reads `Bid <amount>`). The status
    strip says `Bid ... on ...`. Confirm the bid is not treated as a purchase.
37. Options > Deals & buying: set "Confirm buys at or above" to 1g. Press **Buy** on an
    item at or above 1g: the Confirm purchase window opens and nothing is bought yet.
    **Cancel** buys nothing; **Buy** in the window buys exactly once. Set it back to 5g.
38. Set it to 0 (never). Buy an item above 5g: no window appears. Set it back to 5g.
39. Deals: select a deal and press **Find** (`Searching...`, then `Found on page N`).
    The button becomes **Buy <price>**. Press it and the listing is bought.
40. Find a deal whose listing has since sold. The status bar says `Gone` and the deal is removed.
41. Start a Find and close the auction window before it finishes. Reopen it and press
    **Find** again: it searches, rather than staying stuck on `Searching...`.
42. Select a recipe with a long name on the tradeskill window: the profit strip widens to
    fit the text (up to 600px), and narrows again for a short one.
43. Options > Deals & buying lists the same switches, sliders and confidence dropdown as
    the Deals rail (except the two Undersupplied thresholds, which are Options-only). Change one in each place and check the other follows.
44. Finish a full scan, open the Deals tab and press Find on a deal. Nothing is bought
    until you press the Buy button yourself.
45. Find a deal, then Browse-search something else and return to Deals and press **Buy**:
    it refuses ("Listing changed. Press Find again.") and the button goes back to
    **Find**, which works again.
46. A sniped deal (someone else, or another character, buys it first): **Buy** reports
    `Gone: someone else bought it.` and the deal disappears from the list.
47. A late "Bid accepted." after the 5-second no-reply message can be credited to the
    next action. If a message looks wrong, search again.
## Selling (phase 3b)
48. **Post one stack.** On the Sell tab, pick an item with a full stack in your bags. The
    buyout and starting bid show where they came from. Press **Post** (it reads `Post 1 of 1`).
    The status line says `1 of 1 posted`, the auction appears on the Auctions tab, and the
    deposit is taken.
49. **Split, then post.** Pick an item you hold more of, and a stack size no bag stack matches
    exactly. The button reads **Split**. Press it: one stack of that size appears in an empty
    bag slot, and the button then reads **Post**. Press it.
50. **Post several stacks.** Set Stacks to 3. Each press posts one stack: the button reads
    `Post 1 of 3`, then `Post 2 of 3`, and the status line counts `1 of 3 posted`, `2 of 3 posted`.
51. **Price floor.** Type a buyout below 80% of market (the default floor). The warning reads
    "Below your floor (80% of market)", Post is disabled, and nothing posts. Tick **Allow below
    floor** and Post works. Pick another item: the tick is cleared.
52. **Cancel an auction.** On the Auctions tab, select an auction with no bid and press
    **Cancel auction**. It goes from the list at once.
53. **Cancel with a bid.** Select an auction that has a bid and press **Cancel auction**.
    CONFIRM CANCEL appears with the bid and buyout. Its **Cancel** button keeps the auction;
    only its **Cancel auction** button takes it down.
54. **Undercut colours.** After a scan or Browse search for the item: an auction priced above a
    cheaper competitor reads red `Undercut <price>`, the cheapest reads green `Cheapest`, and an
    item nobody else sells reads dim `No competition`.
55. **Deposit.** Before your first post of an item at a duration, the Sell tab shows
    `Deposit approx ...`. After that post, the preview drops "approx" and shows the deposit
    learned from the gold you lost. The server often sends the gold change a moment after the
    "Auction created" message, so the learned figure appears once your purse updates (within
    about 3 seconds of the post), not at the message. Compare it with the gold that actually
    left your purse.
56. **Split never uses a special bag.** Fill your normal bags, leave an empty slot in a quiver or
    soul bag, and press **Split**. It refuses ("No empty slot in a normal bag to split into.")
    and nothing moves.
57. **A failed post can be retried.** Try to post with less gold than the deposit (or an item the
    house refuses). Post reports the failure, the item is not left in the auction sell slot and
    its bag slot is not locked, and after you fix the cause the same stack posts on the next click.
58. At no point above was anything crafted, bought, posted or cancelled without your click.

## Sales tracking (phase 4)
59. Have a posted auction sell, and have another auction expire. Open a mailbox with that
    AH mail waiting. History (the AH tab) fills with the sold and expired counts, and the
    Rate column is the sold share.
60. Check the mail itself is untouched: the sold and expired mails stay unread and keep
    their items and gold for TurtleMail or you. The addon never opens a mail.
61. Close the mailbox, `/reload` or log over and back, open the mailbox again. Nothing is
    counted twice: the History counts and the totals are the same as before.
62. Hover an item you have sold before (the tooltip reads "Sells NN% (n)"). Options > Sales,
    "Sells line in item tooltips" off: the line goes. Turn it back on.
63. Sell tab, pick that item: the sales line reads "Sold X of Y (Z%), avg ... each, sells in ...".
    Pick an item with no history: it reads "No sales history yet."
64. Type a buyout well above the average sale price (more than 120% of it by default). The
    warning reads "You've sold this at about ... rarely sells." Post still works.
    Options > Sales, "Price warning above" 200: the same buyout no longer warns.
65. Deals tab, Undersupplied on (left rail). A deal whose type reads Under shows a **Sell**
    button. Press it: the Sell tab opens with that item selected. Nothing is bought, and
    nothing is posted until you press Post.
66. Browse, AH open: right-click a bag item. Its name fills the search box and Browse searches
    for it. Left-click the same bag item: it behaves as it always does (nothing is searched).
67. Sell tab, AH open: right-click a bag item. That item is selected on the Sell tab. Right-click
    a soulbound or quest item: the status says "Can't auction that".
68. Close the AH. Right-click a potion in your bags: it is drunk, as normal.
69. AH open on Browse or Sell: Shift-right-click a bag item (and Ctrl- or Alt-right-click). Nothing
    is searched or selected; the click behaves as it does away from the AH.
70. Options > General, "Right-click bag items to search or sell" off. Right-click a bag item on
    Browse: nothing is searched. Turn it back on.
71. AH open on the Deals or Auctions tab: right-click a bag item. It behaves normally (it is
    used or sold as it is away from the AH); nothing is searched or selected.
72. Post several identical stacks of one item. When they expire, open the mailbox: History shows
    each expiry (the Rate column and the counts include every one, not just one).

## Recipes and payback (phase 5a)
The trainer and vendor windows are only read. Nothing is bought from them; buy as you normally would.
73. Open Crafting (`/ttf craft`) and press **Not learned**. The rows show Recipe, Skill, Get, Profit,
    Payback and Sells, sorted by payback with "never" and "-" at the bottom.
74. With **Learnable soon** ticked (the default), every row's skill is at most your rank plus the
    skill-ahead setting. Untick it: recipes needing more skill appear. Tick it again.
75. Select a row. The detail pane lists where to get it, the pattern name, the materials and
    "Pays back after N crafts at +X each".
76. Press **Learned**. The usual recipe list comes back, with the same rows and profit figures as
    before this release.
77. Visit a Tailoring trainer, close it without buying, then press **Not learned**. Trainer
    recipes show a gold cost in Get, not "trainer ?".
78. Visit a pattern vendor, close it without buying. Its patterns show a vendor cost in Get, or
    "vendor (limited)" when the vendor's stock is limited.
79. Hover a pattern in the auction house (Browse) and in your bags. The tooltip has a line:
    "Pays back in N crafts (+X each)", "Learned by Name", or "No profit per craft". No line
    appears when no price is known. Options > Crafting, "Pattern payback tooltip line" off:
    the line goes. Turn it back on.
80. Hover a pattern that is not in the Not learned list yet. Reopen Not learned: it now
    appears there, with its reagents as materials.
81. Deals tab, switch on **Recipe** on the left rail. Select a Recipe deal (its detail reads
    "Pays back in N crafts for Name"), press **Find**, and the button becomes **Buy <price>**.
    Press it once: one purchase per click, and nothing else is bought.
82. Options > Deals, "Pays back within" 1 (then back to 10). The Recipe deals list changes to
    match: fewer deals at 1, more at 50.
83. Resize the Tax the Fools window to its smallest size. The Deals rail shows all its switches,
    and none is cut off or overlaps another.
84. Options > Deals has Materials and Minimum confidence, and the rail no longer does. Change
    Minimum confidence and check the Deals list follows it.
85. Options > Crafting, "Learnable soon: skill ahead" at 0: Not learned lists only recipes at or
    under your rank. Set it back to 25.
86. Hover the pattern Green Woolen Bag once, so it is cached. Then `/ttf probe`. Every trainer
    function line reads `yes`: GetNumTrainerServices, GetTrainerServiceInfo,
    GetTrainerServiceCost and GetTrainerServiceSkillReq. Below them are the tooltip lines for
    Pattern: Green Woolen Bag (item 4292), including "Requires Tailoring (n)" and "Teaches you
    how to make ...". Copy them into `tools/probe-<date>.txt`.
