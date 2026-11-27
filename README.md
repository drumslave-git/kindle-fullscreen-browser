# kindle-fullscreen-browser

Opens any web page fullscreen on a jailbroken Kindle. It uses the Kindle's own browser and removes the Kindle's status bar and browser toolbar, so the page gets the whole screen. Useful for a dashboard, a control panel such as [Macro Deck](#example-macro-deck), or a status page on a spare Kindle.

Each page is a library item with its own name and cover: tap it to open the page, and press the power button to leave. No system files are changed.

## Requirements

- **A jailbroken Kindle.**
  - Tested on a Kindle 11th gen (2022) with firmware 5.19.2 and the SpiderCat jailbreak.
  - Other recent models and firmware are untested.
- **[KOReader](https://koreader.rocks/)** installed on the Kindle.
  - Its LuaJIT runs the small helper that removes the top bars.
  - Without KOReader the page still opens, but below the Kindle's bars.
- **A web page the Kindle can reach** over Wi-Fi, usually a server on your network.
- **To install:** a Windows PC with PowerShell. For other systems, see [Manual install](#manual-install).

## Install

1. Connect the Kindle over USB.
2. In this folder, run:

   ```powershell
   .\deploy.ps1 -Name "My Dashboard" -Url http://192.168.1.50:8080/
   ```

3. Eject the Kindle. A **My Dashboard** item appears in the library.

`deploy.ps1`:
- fills the name and URL into `launcher.sh` and writes the result to `dist/MyDashboard.sh`;
- draws a cover showing the name, unless you pass your own;
- finds the Kindle by its drive label;
- copies the item to the Kindle's `documents` folder and `xname.lua` to its `fullscreen-browser` folder.

| Option | Meaning |
|---|---|
| `-Url` | The page to open. `http://` or `https://`; no spaces, quotes or `&`. |
| `-Port` | Instead of `-Url`, for a server on this PC: uses `http://<this PC's LAN IP>:<port>/`. |
| `-Name` | The item's name in the library. Default: `Fullscreen Browser`. |
| `-Cover` | A PNG to use as the cover, instead of the drawn one. 600×900 fits the library. |
| `-StayOpen` | The power button only puts the Kindle to sleep; the page is still open after waking. |
| `-Drive` | The Kindle's drive letter, if it is not found by its label. |
| `-BuildOnly` | Only write `dist/<Name>.sh`; copy nothing. |

**Several pages:** run `deploy.ps1` once per page, each with its own `-Name`. Deploying a name again replaces that item. One page is open at a time: opening another closes the first.

A DHCP reservation for the server keeps its IP, and so the page's URL, from changing.

### Example: Macro Deck

[Macro Deck](https://macrodeck.org/) turns a touch screen into a panel of buttons that run actions on a PC. Its web client is on port 8193 by default. With Macro Deck running on this PC:

```powershell
.\deploy.ps1 -Name "Macro Deck" -Port 8193 -Cover examples\macro-deck-cover.png
```

### Manual install

`launcher.sh` has three placeholders: `@NAME@` for the name, `@URL@` for the address and `@ICON@` for the cover image. To install by hand:

1. Replace `@NAME@` and `@URL@`.
2. Delete the `# Icon:` line. The library then shows a plain item instead of a cover.
3. Optionally, set `EXIT_ON_SLEEP=0` in the settings block (what `-StayOpen` does).
4. Save the file with LF line endings, and copy it to the Kindle's `documents` folder with a `.sh` name.
5. Copy `xname.lua` to `fullscreen-browser/xname.lua` on the Kindle.

For example, on Linux or macOS:

```sh
sed -e 's|@NAME@|My Dashboard|' -e 's|@URL@|http://192.168.1.50:8080/|' -e '/^# Icon:/d' \
    launcher.sh > /path/to/Kindle/documents/MyDashboard.sh
mkdir -p /path/to/Kindle/fullscreen-browser && cp xname.lua /path/to/Kindle/fullscreen-browser/
```

## Use

- **Open:** tap the item in the library.
  - Wi-Fi is turned on if needed.
  - If the page does not answer within about 30 seconds, a message says so and nothing opens.
- **While open:** the Kindle does not go to sleep on its own.
- **Leave:** press the power button. The Kindle sleeps and wakes up in the library.
  - With `-StayOpen`, connect USB to leave instead.
- **Also closes the page:** connecting USB, or another app taking the screen.

### Which pages work well

E-ink redraws slowly and in shades of gray. Pages that change little and have large touch targets suit it best. Busy animations are slow and leave ghosting.

`https://` addresses are untested. The launcher checks that the page answers using the Kindle's built-in `wget`, which may not support HTTPS.

## Troubleshooting

Each launch appends to `fullscreen-browser/log.txt` on the Kindle. It records:
- the page, the Wi-Fi state, and whether the page answered;
- each power state change;
- how often the fullscreen title had to be set (1 means the browser never reverted it);
- why the page closed.

Lines written while the Kindle is in USB mode are kept in memory and added at the next launch.

| Problem | Check |
|---|---|
| "*Name*: *URL* is not reachable" | The server is running, the URL is right, and its firewall allows the port. Open the URL in a phone's browser to test. |
| The Kindle's top bars are still shown | KOReader is installed (`koreader/luajit` exists on the Kindle) and `fullscreen-browser/xname.lua` is there. The log says if either is missing. |
| The page is stuck open | Connect USB: that closes it. Holding the power button for about 15 seconds restarts the Kindle. |

**To uninstall,** delete each item's `.sh` file from `documents`, and the `fullscreen-browser` folder, from the Kindle.

## How it works

Each item is a library *scriptlet*: a shell script in `documents` that the Kindle lists as a book and runs as root when tapped.

1. **Detach.** It copies itself to `/tmp` and detaches from the library, so nothing keeps the Kindle's storage busy and USB mode still works.
2. **Wait for the page.** It turns Wi-Fi on and waits until the URL answers. The browser would otherwise show a dead error page.
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

`xname.lua` also works on its own. On the Kindle, `/mnt/us/koreader/luajit /mnt/us/fullscreen-browser/xname.lua list` prints every window with its geometry and title.

## Files

| File | Purpose |
|---|---|
| `launcher.sh` | The launcher scriptlet, with `@NAME@`, `@URL@` and `@ICON@` placeholders. |
| `xname.lua` | Lists X windows and edits their titles (LuaJIT FFI + libX11). |
| `deploy.ps1` | Fills in the placeholders, draws a cover, writes `dist/<Name>.sh`, and copies the files to the Kindle. |
| `examples/macro-deck-cover.png` | A custom cover, used in the [Macro Deck example](#example-macro-deck). |

## License

[MIT](LICENSE). Copyright (c) 2026 Heorhii Tyslenko.

Use at your own risk. Jailbreaking and running scripts as root on a Kindle can void its warranty.
