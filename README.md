# kindle-fullscreen-browser

Turns a jailbroken Kindle into a fullscreen **[Macro Deck](https://macrodeck.org/)** panel. It opens the Kindle's own browser on the Macro Deck web client and removes the Kindle's status bar and browser toolbar, so the deck gets the whole screen.

It is one library item: tap **Macro Deck** to open the deck, and press the power button to leave. No system files are changed and nothing is installed on the Kindle beyond two small files.

## Requirements

- **A jailbroken Kindle.**
  - Tested on a Kindle 11th gen (2022) with firmware 5.19.2 and the SpiderCat jailbreak.
  - Other recent models and firmware are untested.
- **[KOReader](https://koreader.rocks/)** installed on the Kindle.
  - Its LuaJIT runs the small helper that removes the top bars.
  - Without KOReader the deck still opens, but below the Kindle's bars.
- **Macro Deck 3** running on a PC on the same Wi-Fi network.
  - Its web client is on port 8193 by default.
- **To install:** a Windows PC with PowerShell. For other systems, see [Manual install](#manual-install).

## Install

1. Connect the Kindle over USB.
2. In this folder, run:

   ```powershell
   .\deploy.ps1
   ```

   - It finds this PC's LAN IP and uses `http://<that IP>:8193/`.
   - It finds the Kindle by its drive label.
   - It copies `MacroDeck.sh` to the Kindle's `documents` folder and `xname.lua` to its `macrodeck` folder.
3. Eject the Kindle. A **Macro Deck** item with a deck cover appears in the library.

To use another address or drive:

```powershell
.\deploy.ps1 -Url http://192.168.1.50:8193/ -Drive H
```

A DHCP reservation for the PC keeps its IP, and so the deck's URL, from changing.

### Manual install

`MacroDeck.sh` contains two placeholders: `@URL@` for the address and `@ICON@` for the cover image. To install by hand:

1. Replace `@URL@` with the deck's address.
2. Delete the `# Icon:` line. The library then shows a plain item instead of the cover.
3. Save the file with LF line endings.
4. Copy it to `documents/MacroDeck.sh` on the Kindle, and `xname.lua` to `macrodeck/xname.lua`.

For example, on Linux or macOS:

```sh
sed -e 's|@URL@|http://192.168.1.50:8193/|' -e '/^# Icon:/d' MacroDeck.sh > /path/to/Kindle/documents/MacroDeck.sh
mkdir -p /path/to/Kindle/macrodeck && cp xname.lua /path/to/Kindle/macrodeck/
```

## Use

- **Open:** tap **Macro Deck** in the library.
  - Wi-Fi is turned on if needed.
  - If Macro Deck does not answer within about 30 seconds, a message says so and nothing opens.
- **While open:** the Kindle does not go to sleep on its own.
- **Leave:** press the power button. The Kindle sleeps and wakes up in the library.
- **Also closes the deck:** connecting USB, or another app taking the screen.

### Settings

Settings are at the top of `MacroDeck.sh`. Change them there, then run `deploy.ps1` again.

| Setting | Default | Meaning |
|---|---|---|
| `EXIT_ON_SLEEP` | `1` | `1`: the power button closes the deck. `0`: the deck stays open across sleep. |

### Other web pages

Nothing here depends on Macro Deck itself: `deploy.ps1 -Url` accepts any `http://` page on your network. Only the item name, the cover and the messages say "Macro Deck".

`https://` addresses are untested. The reachability check uses the Kindle's built-in `wget`, which may not support HTTPS.

## Troubleshooting

Each launch appends to `macrodeck.log` in the Kindle's root folder. It records:
- the Wi-Fi state, and whether Macro Deck answered;
- each power state change;
- how often the fullscreen title had to be set (1 means the browser never reverted it);
- why the deck closed.

Lines written while the Kindle is in USB mode are kept in memory and added at the next launch.

| Problem | Check |
|---|---|
| "Macro Deck not reachable" | Macro Deck is running, the URL is right, and the PC's firewall allows the port. Open the URL in a phone's browser to test. |
| The Kindle's top bars are still shown | KOReader is installed (`koreader/luajit` exists on the Kindle) and `macrodeck/xname.lua` is there. The log says if either is missing. |
| The deck is stuck open | Connect USB: that closes it. Holding the power button for about 15 seconds restarts the Kindle. |

To remove everything, delete `documents/MacroDeck.sh`, the `macrodeck` folder and `macrodeck.log` from the Kindle.

## How it works

`MacroDeck.sh` is a library *scriptlet*: a shell script in `documents` that the Kindle lists as a book and runs as root when tapped.

1. **Detach.** It copies itself to `/tmp` and detaches from the library, so nothing keeps the Kindle's storage busy and USB mode still works.
2. **Wait for the deck.** It turns Wi-Fi on and waits until the URL answers. The browser would otherwise show a dead error page.
3. **Open the page** in the Kindle's own browser:

   ```sh
   lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser?view=<URL>"
   ```

4. **Make it fullscreen.**
   - The Kindle's window manager reads layout tags from each window's title. The browser's title is `L:A_N:application_PC:TS_ID:com.lab126.browser_WT:true`, and `PC:TS` asks for the status bar and the browser toolbar.
   - `xname.lua` changes that tag to `PC:N`, and the window manager then gives the browser the whole screen.
   - It runs on KOReader's LuaJIT and calls libX11 through the FFI.
   - It keeps running and sets the tag again whenever the browser reverts it.
   - If the launcher dies, the helper puts the tag back, so the browser is never left without its close button.
5. **Stay awake.** Every 30 seconds it restarts the idle timer, as KOReader does:

   ```sh
   lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 1
   ```

   It does not use `preventScreenSaver 1`, which would also disable the power button.
6. **Clean up.** It watches for the power button (`goingToScreenSaver`), USB mode and other apps. On any of those it:
   - returns to the library;
   - restores the browser's title;
   - closes the browser.

`xname.lua` also works on its own. On the Kindle, `/mnt/us/koreader/luajit /mnt/us/macrodeck/xname.lua list` prints every window with its geometry and title.

## Files

| File | Purpose |
|---|---|
| `MacroDeck.sh` | The launcher scriptlet, with `@URL@` and `@ICON@` placeholders. |
| `xname.lua` | Lists X windows and edits their titles (LuaJIT FFI + libX11). |
| `deploy.ps1` | Fills in the placeholders, writes `dist/MacroDeck.sh`, and copies both files to the Kindle. |
| `cover.png` | The library cover. `deploy.ps1` draws a new one if it is missing. |
