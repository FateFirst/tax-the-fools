# Syncing Tax The Fools between devices

The game can't reach the internet from an addon, so a small helper program, **ttf-sync**, does it for you. It runs when you start WoW and again when you quit. Each time it:

1. reads your Tax The Fools save file on this device,
2. downloads the shared copy from your own Supabase project,
3. merges the two (scans, prices, sales, ledger, snipe list, settings and character data all survive from both sides),
4. writes the merged file back (a backup is kept first), and
5. uploads the result.

Everything lives in a free Supabase project that only you own. No one else can read it without your sync key.

## One-time setup (about 10 minutes)

### 1. Create the Supabase project

1. Go to <https://supabase.com> and sign in (Google sign-in is fine). The free plan is enough.
2. Click **New project**, give it any name (for example `ttf-sync`), choose a region near you and set a database password (you won't need it again). Wait for it to finish creating.
3. Open **SQL Editor** in the left menu and click **New query**.
4. Open `sync/supabase/001_init.sql` from this repo, copy the whole file, paste it into the editor and click **Run**. You should see "Success". It is safe to run twice.
5. Open **Project Settings, then API**. Copy two things:
   - the **Project URL** (like `https://abcdxyz.supabase.co`)
   - the **anon public** key (a long string starting `eyJ`)

   The anon key on its own can't read any data. The sync key (below) is what protects it.

### 2. Get ttf-sync

Download the files from the GitHub release:

- `ttf-sync-windows-amd64.exe` for Windows PCs and laptops
- `ttf-sync-linux-amd64` for the Steam Deck

Or build them yourself with Go installed: `make sync-build` puts both in `sync/dist/`.

**Rename the download** to something short, and use that name everywhere below:

- Windows: `ttf-sync.exe`, in a folder such as `C:\Tools\`
- Steam Deck: `ttf-sync`, in `~/ttf-sync/`

On Windows, open a terminal in that folder: open the folder in File Explorer, click the address bar, type `powershell` and press Enter. PowerShell only runs programs from the current folder when you start them with `.\`, so the commands look like `.\ttf-sync.exe setup`. Command Prompt (type `cmd` in the address bar instead) accepts plain `ttf-sync.exe setup`.

### 3. First device

In a terminal in the folder holding the program (PowerShell on Windows, Konsole on the Deck), run the two commands below. On Windows that is `.\ttf-sync.exe setup`; on the Deck `~/ttf-sync/ttf-sync setup`. The rest of this guide writes just `ttf-sync`: use whichever form fits your device.

```
.\ttf-sync.exe setup
.\ttf-sync.exe init
```

`setup` looks for your WoW folder (including Steam Deck and Lutris locations), asks which account folder to use, then asks for the Supabase URL and anon key. It also asks for a device name (defaults to the computer's name), which shows up in messages such as "Pulled v12 from Laptop".

`init` creates your sync account and prints a long **sync key**.

**Save that key now** in a password manager. Anyone with it can read and change your synced data, and it can't be recovered if you lose it.

Then run one sync by hand to check everything works:

```
.\ttf-sync.exe sync
```

### 4. Every other device

Run `setup` (same Supabase URL and anon key), then:

```
.\ttf-sync.exe join YOUR-SYNC-KEY
.\ttf-sync.exe sync
```

`join` checks the key against the server before saving it.

## Starting the game through ttf-sync

### Windows

Make a shortcut so that WoW always starts through ttf-sync. Right-click the desktop, **New, Shortcut**, and use this as the target (adjust both paths):

```
"C:\Tools\ttf-sync.exe" run -- "C:\Games\TurtleWoW\WoW.exe"
```

ttf-sync starts WoW in WoW's own folder, so you don't need to touch the shortcut's **Start in** field. If you'd like to be safe anyway, set **Start in** to the WoW folder.

A small console window stays open while you play and shows what the sync did. **Leave it open**: it closes itself after the second sync. Closing it early skips the after-game sync (nothing is lost; the next launch catches up). Use this shortcut instead of the normal one.

### Steam Deck

1. Switch to Desktop Mode.
2. In Steam, **Add a Game, Add a Non-Steam Game**, and add WoW's `WoW.exe`. Under its **Properties, Compatibility**, force a Proton version, like you do for any Windows game.
3. Make a folder `~/ttf-sync/`, put the downloaded file in it, renamed to `ttf-sync`, and make it runnable:

   ```
   chmod +x ~/ttf-sync/ttf-sync
   ```

4. In Konsole, run `~/ttf-sync/ttf-sync setup`, then `~/ttf-sync/ttf-sync join YOUR-SYNC-KEY` (once only).
5. In the WoW entry's **Properties, Launch Options**, put:

   ```
   ~/ttf-sync/ttf-sync run -- %command%
   ```

6. Back in Game Mode, launch WoW as usual.

Game Mode shows no console, so look in the log file (below) for results. If you quit with Steam's **Exit game** button, ttf-sync may be stopped before its after-game sync; the next launch's pre-game sync catches up, so nothing is lost.

## Daily use

Just play. When you launch, ttf-sync pulls what your other devices did. When you quit it merges and uploads. The game starts even if a sync fails (no network, project paused), and `run` returns the game's own exit code.

- In game, `/ttf sync` shows when this device last synced, for example "Last synced 2h ago from Laptop (TTF Sync 1.0.0)".
- `ttf-sync sync` runs a sync by hand (with WoW closed).
- `ttf-sync status` shows this device's setup, the last sync, the server version and all devices.
- ttf-sync never writes the save file while WoW is running. After you quit it waits up to 60 seconds for the game to exit (WoW saves its data as it exits, and Proton can be slow) before it reads anything. If WoW is still running after that, it skips that sync completely and the next one catches up. If ttf-sync can't tell whether WoW is running, it won't write the file either.
- If the network is slow, the sync before the game gives up after 20 seconds so the game isn't held up.
- Every run is logged, with times, in `ttf-sync.log` next to the config (it rotates at 1 MB, keeping one older file). `ttf-sync status` shows the result of the last run. Look there if a sync fails when you can't see the console, for example "project paused".
- If it can't read your save file, it changes nothing, anywhere, and tells you why.

## Restoring a backup

Before every write, ttf-sync copies your file into a `backups` folder next to its config and keeps the 5 newest. Close WoW, then run:

```
ttf-sync restore
```

Pick a backup from the list. The current file is backed up first. The next sync merges the restored data with the server copy again, so if you want to go back for good, restore and then fix the data in the game before the next sync.

Config and backups live in `%APPDATA%\ttf-sync\` on Windows and `~/.config/ttf-sync/` on Linux.

## Troubleshooting

**"Your Supabase project is paused."** Free projects pause after about a week without activity (regular syncs count as activity). Open the Supabase dashboard and click **Resume project**, then sync again. Your data is kept.

**"That sync key was not accepted."** The key was copied wrongly, or `setup` on this device points at a different Supabase project than the one used for `init`. Check the URL and anon key in `ttf-sync status`, and paste the key again with `join`.

**"local file NOT written (WoW is running)".** WoW (or a stuck `WoW.exe` process) was still open. Close it fully and run `ttf-sync sync`. The upload still happened.

**"could not be parsed".** The save file is damaged. ttf-sync left it alone. Run `ttf-sync restore`, or move the file away and sync to download the server copy.

**"Supabase URL / anon key not set" or "WoW folder or account not set".** Run `ttf-sync setup` again.

**The wrong account folder was picked.** Run `setup` again and choose the folder whose `SavedVariables` contains `TaxTheFools.lua`.

**Another device pushed first.** Normal: two devices synced at the same moment. ttf-sync pulls and merges again (up to 3 times) and nothing is lost.
