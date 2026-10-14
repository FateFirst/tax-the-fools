# AuctionQueryThrottle (AQT): research notes

Researched 2026-10-14. Source was cloned to `scratchpad/refs/aqt/src` and read only. No binaries were downloaded and nothing was run.

## Bottom line for Ravencraft
**Don't install it for Ravencraft.** The author's README names Ravencraft as a server where the DLL has **no effect**, because the server throttles auction queries itself. The only bug report (issue #1, Capycraft + Ravencraft) says it is worse than useless: the gate reopens at once, but the "next page" comes back holding the **same data as the previous page**, and then the 5 s wait applies anyway. A scanner that trusts the gate (Aegis "auto" does) could record duplicate pages or skip real ones. The author's reply to the issue: "Guess so." (closed 2026-08-31, the same day the README compatibility note was added).

## Identity
- Repo: https://github.com/brues-code/AuctionQueryThrottle. Owner brues-code, who also wrote ClassicAPI and keeps nampower and Auctionator mirrors/forks.
- Description: "Removes hardcoded 5s throttle on 1.12.1 auction search". 24 stars. Created 2026-07-16, last push 2026-08-31.
- License: **GPL-3.0-or-later** ("a derivative of ClassicAPI"). **Full source is available**: `src/DllMain.cpp`, `src/Offsets.h`, a `.def` file, CMake, and MinHook as a submodule.
- Releases: v1.0.0 (2026-07-16), v1.1.0 (2026-08-03), v1.2.0 (2026-08-25). Each ships one `AuctionQueryThrottle.dll`, built by GitHub Actions on windows-latest (`.github/workflows/build.yml`, `cmake -A Win32`). The CI build is reproducible from the tag.

## How it works (from the source)
- `Offsets.h`, with VAs taken from the Octo WoW.exe (vanilla 1.12.1, ImageBase 0x400000):
  - `VAR_AUCTION_NEXT_ALLOWED_MS = 0x00B72638` is the single throttle word. `QueryAuctionItems` (0x004CE980) sets it to `clock()+5000` on every send. `CanSendAuctionQuery` (0x004CFBB0) only reads it. Per the xrefs, nothing else uses it, so owner and bidder list queries are unaffected.
  - `FUN_AH_LIST_RESULT_HANDLER = 0x004CC7F0` is the handler for SMSG_AUCTION_LIST_RESULT (opcode 0x25C).
- It places a MinHook detour on that handler. On each browse-list result packet it writes 0 to the throttle word, then calls the original handler. So `CanSendAuctionQuery()` is already true by the time `AUCTION_ITEM_LIST_UPDATE` fires.
- The client's own re-arm on send (+5000 ms) is left alone. That keeps one query in flight at a time, and a dropped reply falls back to the normal 5 s.
- It does not patch the exe on disk and adds no new code paths. It only changes the timer and makes one detour.
- Install timing: it exports `Load`, which VanillaFixes (v1.4+) calls on the main thread after injection. Without VfPatcher.dll it falls back to a worker thread, so other injectors also work.

## Client support
- The offsets are hard-coded for a 1.12.1 build 5875 WoW.exe (Octo's copy). Both the issue reporter (Capy and Ravencraft clients, which are Turtle 1.18.1-derived) and Aegis's README (Octo, Capy) saw the gate open quickly. So the hook does load and apply on Turtle-family 1.18.1 exes.
- There is no version or offset check. If a client exe's code differs at those addresses, the hook would hit the wrong memory and could crash. Nobody has reported that.

## Lua API and detection
- It exposes **no Lua API**, and there is nothing for `IsAddOnLoaded` to find. The only way to detect it is by behaviour: `CanSendAuctionQuery()` turns true within about a second of the reply instead of about 5 s.
- Aegis_Exchange does exactly this:
  - `core/scan.lua:296-311`: `scan.FAST_GATE = 1.5`, `scan.FAST_DELAY = 0.05`. When the gate opens within 1.5 s it sets `st.fastGate = true` and logs "throttle looks lifted (AuctionQueryThrottle?)".
  - `ui/frame.lua:2643-2667` shows the readout "fast — gate X, server Y" or "client throttled — gate X". The pacing setting `queryThrottle` is `auto` or `safe` (safe = fixed 4 s).
  - Aegis does **not** check whether a page is a duplicate. On a server that silently refuses the query, a fast gate plus a stale or echoed list could end up counted as a new page.

## Measured speedups
- AQT README: queries go at round-trip speed ("a fraction of a second on a healthy connection"). It gives no numbers.
- Aegis README: "Octo WoW dramatically faster, Capy WoW around 2×". Example readout: `fast — gate 0.02s, server 0.61s`. Note that the AQT README and issue #1 later said Capy is server-throttled and the DLL does nothing there, which conflicts with Aegis's "2×" claim.
- Nobody has measured Ravencraft with a positive result. The only data point is issue #1, which saw no gain.

## Servers that throttle on their side
- The README (commit 2026-08-31, "Note server-side throttling servers where the DLL has no effect") lists **Kronos, Capybara, Ravencraft**. It says the DLL helps only on servers that "leave the pacing to the client and clear their in-flight lock on send (e.g. Octo)".

## Install method (for reference only, not recommended on Ravencraft)
1. Install VanillaFixes (https://github.com/hannesmann/vanillafixes, MIT).
2. Put `AuctionQueryThrottle.dll` next to WoW.exe.
3. Add a line `AuctionQueryThrottle.dll` to `dlls.txt`.
4. Launch the game with VanillaFixes.exe.

Other injectors also work through the worker-thread fallback.

## Ravencraft, Turtle and launcher policy
- ravencraft.io/rules, Fair Play > Cheating/Hacking: "Use or promotion of any hack, cheat, or other client modification to gain an unfair advantage over other players. This includes botting and automation." It also bans programs that automate character actions and multibox sync software. **DLLs and addons are not mentioned explicitly.** Whether a faster AH scan counts as an "unfair advantage" is a grey area. I found no ruling.
- ravencraft.io names Turtle WoW as its base. The client is downloaded from vikingfile or gofile mirrors. Discord: discord.gg/PYeP4475Sn.
- **IchaLaunch:** web searches turned up nothing, and the site doesn't name a launcher. I could not verify whether it bundles AQT. Given the README says Ravencraft throttles on the server, bundling it would be pointless. To settle it, check the launcher's install folder for `dlls.txt` or `AuctionQueryThrottle.dll`, or ask on the Discord.
- Turtle: I found no official written allow-list. In practice the community runs SuperWoW, nampower and UnitXP_SP3 through VanillaFixes or the SuperWoW launcher, and pfUI's Turtle edition requires nampower. VanillaFixes' README says Warden shows no conflict, but use is "at your own risk".

## Other client mods that could help AH scanning
- **VanillaFixes:** fixes timers and stutter, and loads DLLs. Nothing AH-specific.
- **SuperWoW** (balakethelock): its README lists nothing AH-specific. It adds `ExportFile`, which Aegis uses for its live file. No faster GetItemInfo.
- **Nampower** (namreeb, with Turtle forks such as Emyrk/brues-code mirror 4.6.1): adds `GetItemStats` and other item/spell info, plus file I/O (`WriteCustomFile`, `ExportFile`, `ImportFile`). Its focus is casting. Nothing AH-specific was found.
- **ClassicAPI** (brues-code, GPL-3, same loader) is the most useful for AH work:
  - `GetAuctionItemID`, so no parsing of links.
  - `C_Item.GetItemInfoInstant`, a cache peek that never blocks.
  - `C_Item.RequestLoadItemDataByID` plus the `ITEM_DATA_LOAD_RESULT` event, which actively warms the item cache. That fixes vanilla's "GetItemInfo returns nil until seen".
  - `C_Item.GetItemSellPrice`, item level, and `C_AuctionHouse.PostItem` (multi-stack posting).
  - Aegis already uses `C_Item` from it, behind a guard.
  - Caveat: issue #1 lists ClassicAPI loaded alongside AQT, so the two coexist.
