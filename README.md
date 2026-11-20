# L99 Control Center

A private macOS menu bar app for the **AULA L99** keyboard's 320×480 touchscreen. It does on a Mac what AULA's Windows-only software does, and then some:

- **Uploads:** photos, backgrounds and GIFs, with recovery to the factory content. No Windows needed.
- **Live data over the 2.4 GHz dongle:** clock, weather, CPU/GPU load, battery, and the music visualiser. US (12-hour, °F) or metric units.
- **Skins:** six styles for the screen's own pages, picked per page, built and installed from the Mac.

The screen stays a keyboard command center. The app never touches the keyboard's firmware or the screen's control program.

## Status

| Phase | What | State |
|---|---|---|
| 1 | Uploads and recovery (cable) | ✅ Built and tested on hardware |
| 2 | Live data and music over the dongle | ✅ Built and tested on hardware |
| 3 | Skins | ✅ Skin maker and the app's Skins tab, both proven on hardware |
| 4 | One window | ✅ All five sections in a single window with a side rail |

## The app

The menu bar icon opens a small panel: connection, live data toggles, units, and links. Everything else is in **one window** with a rail down the left side. The menu bar's links open the window on the right tab.

| Tab | What it does |
|---|---|
| **Upload** | Drop or choose a picture or GIF, frame it (Fill/Fit, zoom, drag) on a full-size preview of the screen, and send it to the background, photo frame or GIF slot over the cable. |
| **Library** | Everything you've sent, filterable by slot and searchable. Shows what's on the screen now and resends with one click. Backgrounds show as off while a Home skin is installed. |
| **Skins** | A style for each page, which apps show on Home, the top bar, live previews, and the guided install or **Back to stock**. Shows the skin that's on the keyboard. |
| **Effects** | The music visualiser on the screen and the key lights: on/off, sensitivity, direction and colours. |
| **Recovery** | Puts the factory photo, GIF or wallpaper back, retries an interrupted upload, and explains the Windows reset if the screen won't start. |

In wide windows, Library, Effects and Recovery also show a keyboard panel: connection, what's on the screen, the installed skin, live readings and shortcuts. The rail's bottom tile shows whether the USB cable is in (uploads and skins need it; everyday live data goes over the dongle).

The app's logo and icon are the screen with four equaliser bars. In the rail, the bars move with the music while it plays.

### Skins

Each part of the screen takes its own style:

- **Pages:** Home, Play, Real-time Data, Numpad, Calculator, plus the timer pages that replace Home while a timer runs.
- **Top bar:** one shared bar over every restyled page.
- **Styles:** Liquid Glass Night, Liquid Glass Day, Cyberpunk, Ceramic, Ember, Midnight LED.
- **Hiding apps:** Home apps you don't use can be hidden; the remaining tiles re-flow to fill the grid.

In the app, the **Skins** tab is the picker: a style for each page, a tappable miniature of the Home grid for hiding apps, live previews, a warning when the top bar would be hard to read, and a guided install (cable, Fn+X, 0, 6, then the Mac's admin password). **Back to stock…** restores the factory interface the same way. Installs keep the photo and GIF on the screen. The first time, the app asks for `UartTFT-II_Flash.bin` from AULA's reset package and checks it.

The skin maker renders the art and lays it out. It builds one interface file from the stock file, which the Mac installs through the screen's bootloader over the cable (about 4½ minutes). Every read-back is checked against the file.

## Repository layout

```
L99 Control Center/        The menu bar app (Xcode project, SwiftUI, macOS 26): menu panel plus one
                           main window (MainWindow.swift: rail, theme and shared controls)
tools/l99probe/            Swift package shared by the app and the command-line tool
  Sources/L99Core/         Protocols and file formats: HID packets, screen uploads, ISP,
                           LT images, GIF container, interface-file editor
  Sources/L99Link/         USB/HID/serial links to the keyboard, dongle, screen and bootloader
  Sources/L99Skins/        Skin renderer (six styles), bundled fonts, and the SkinBuilder
  Sources/L99USB/          Small C shim for USB access
  Sources/l99probe/        Command-line tool for hardware tests, previews and installs
research/                  Our notes only (third-party repos, firmware and vendor files are not tracked)
  FINDINGS.md              Everything learned, with what's proven on hardware marked [HW]
  ISP_PROTOCOL.md          The screen bootloader's install protocol
  SMOKE_TEST.md            The first hardware test plan and results
PRD.md                     Product requirements and process
```

## Building

- **App:** open `L99 Control Center/L99 Control Center.xcodeproj` in Xcode and run. It uses the `tools/l99probe` package as a local dependency.
- **Checking the layout without the menu bar (Debug builds):** `--render-skins <file.png> --tab <upload|library|skins|music|recovery> [--size 1000x680]` draws the window into a PNG and quits. `--render-icon <folder>` redraws the app icon PNGs (they live in `Assets.xcassets/AppIcon.appiconset`).
- **Command-line tool:**

  ```bash
  cd tools/l99probe && swift build
  ```

  The tool needs the stock interface file at `research/factory/UartTFT-II_Flash.bin`. It isn't in the repo; it comes from AULA's reset package. Its SHA-256 is checked before any edit.

## Making a skin from the command line

```bash
.build/debug/l99probe skin-file preview --out /tmp/previews
```

```bash
.build/debug/l99probe skin-file mix --home midnight-led --play liquid-glass-night --data ember --numpad cyberpunk --calculator ceramic --top-bar cyberpunk --hide photos,touchpad --preview /tmp/mix.png
```

`preview` renders every page in every style. `mix` builds `build/UartTFT-II_Flash-mix.bin` and prints what changed. Pages you leave out stay stock. To install, plug in the cable, press Fn+X, 0, 6 to put the screen in bootloader mode, then:

```bash
sudo .build/debug/l99probe isp-flash "../../build/UartTFT-II_Flash-mix.bin" --direct
```

Installing the stock file the same way restores the factory interface.

## Safety rules

- Keyboard functions come first. The keyboard firmware and the screen's control program are never written.
- Only volatile HID commands are sent: clock/stats, music, and read-only dongle queries. No keymap, lighting or persistent-settings writes.
- A skin only edits the screen's interface file, inside planned byte ranges; each build checks this before saving.
- No telemetry, accounts or auto-updates.

## Credits and licences

- **Fonts:** Inter and JetBrains Mono, under the SIL Open Font License 1.1 (texts in `tools/l99probe/Sources/L99Skins/Fonts/`).
- **Prior work:** the research builds on community projects studied read-only. They're credited in `research/FINDINGS.md` and `research/notes/`. No code from them is included or run.
- AULA and L99 are trademarks of their owner. This project isn't affiliated with AULA.
