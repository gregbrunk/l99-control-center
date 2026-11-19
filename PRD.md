# AULA L99 Menu Bar App — PRD & Process

Nov 17, 2026 · @Alison · **Revision 2**, updated after the code study (`research/FINDINGS.md`) and the hardware smoke test (`research/SMOKE_TEST.md`).

## Overview

We will build a private, lightweight macOS menu bar app that does for the AULA L99's touchscreen what AULA's Windows-only software does. It comes in three phases: uploads and recovery first, then live data, then reskinning the screen's interface.

**Problem.** The L99 works on a Mac as a keyboard, but its 3.98" 320×480 screen can only be configured from AULA's Windows driver. Images, GIFs, live stats and the music visualizer are all out of reach on macOS.

**What this app is.** A quiet companion for the keyboard's own features. The screen stays a keyboard command center: lighting controls, Caps/Num Lock status, connection and battery, and the mini numpad.

**What this app is not.** Not a Stream Deck replacement or an app platform. A Stream Deck already handles computer-wide buttons, so adding new apps to the screen is out of scope. If anything, the goal is a lighter screen, with unused pages (touchpad, calculator) removed in Phase 3.

**Success looks like:**

- Custom GIFs, backgrounds and photos on the screen, uploaded from the Mac.
- A one-click way to recover from a bad upload, without needing Windows.
- Live stats and the music wave fed from the Mac **over the 2.4 GHz dongle**, with no cable needed. *(Proven on hardware.)*
- (Phase 3) A reskinned mini numpad and a cleaner screen, with every keyboard function still working.

## Status

| Step | Status |
|---|---|
| 1. Write the PRD | ✅ |
| 2. Code study | ✅ `research/FINDINGS.md`, with a safety review of each repo |
| 3. Hardware smoke test | ✅ `research/SMOKE_TEST.md`, run with `tools/l99probe` |
| 4. Update the PRD | ✅ this revision |
| 5. Design mockup | ✅ [Design canvas](https://claude.ai/artifact/VP7EhyfWaAtZGSqiu8QyV6), approved |
| 6. Xcode project | ✅ `L99 Control Center/`, builds and runs |
| 7. Build Phase 1 | ✅ built and tested on the keyboard (Nov 17) |
| 8. Build Phase 2 | **built**, hardware test next |

**Headline results:**
- **Uploads work.** A full photo-frame upload takes 0.8 s, and the screen confirms every block with its own checksum.
- **Phase 2 is GO and fully wireless.** Clock, stats, the music wave and battery all work over the 2.4 GHz dongle. Music is smoother over the dongle (≈75 fps) than over the cable.
- **The Mac can install whole interface files (Nov 18).** `l99probe isp-flash --direct` wrote the stock file through the screen's bootloader in about 4½ minutes, with every read-back check matching (research/ISP_PROTOCOL.md). So a full restore and every skin install now work from the Mac, on the cable. The slots still can't be read back.

## What we know

The L99 exposes two separate USB devices. The screen runs on its own controller (an LT168-family chip) with a large interface file, so screen content can be changed without touching keyboard firmware.

### Devices (confirmed on Alison's keyboard)

| Device | ID | macOS access | Used for |
|---|---|---|---|
| Keyboard, wired | `0C45:800A` "AULA L99" | IOKit HID, vendor collection `FF13:0001`, 64-byte feature reports, report ID 0. Opened without seizing, so typing is unaffected. | Clock/stats, music |
| 2.4 GHz dongle | `05AC:024F` "2.4G Dongle", build byte `0x31` | IOKit HID, vendor collection `FF60:0061`, 32-byte output/input reports, sum checksum | Clock/stats, music, battery % |
| Touchscreen (cable only) | `EEEF:268A` "Generic CDC" | USB serial `/dev/cu.usbmodem…`, raw 8N1 | Image and GIF uploads |

No drivers are needed. In testing, no special macOS permission was needed either.

### Uploads (Phase 1)

- **Framing:** `5A A5 | len u24 | 0x64 write | addr | ≤2048 B | CRC16/MODBUS`.
- **Checking:** after each 128 KiB block, a `0x66` request returns the screen's CRC32 of what it stored, and we compare it with our own. This was confirmed byte for byte on hardware.
- **Slots:**

  | Slot | Address | Size | Format |
  |---|---|---|---|
  | Background | `0x04180000` | `0x60000` | 11-byte header + RGB565, 307,211 B |
  | Photo frame | `0x041E0000` | `0x60000` | 11-byte header + RGB565, 307,211 B |
  | GIF | `0x04240000` | factory animation is 26.0 MB, 171 frames | proprietary "LT" container: per-frame palette, run-length encoded |

- **Showing new content:** there is no refresh command. The new image shows after leaving and re-entering the page.
- **GIF rules** (found by experiment):
  - every frame must have the same delay;
  - 255 frames at most (the vendor caps at 200);
  - two adjacent runs must not share a palette index;
  - a GIF that breaks a rule is still acknowledged, then plays a cached fallback.
- **GIF colour:** the vendor's factory animation uses colours off the fixed 252-colour ramp, so arbitrary RGB565 palettes display. The app uses one best-fit palette per animation, with the ramp as a fallback.
- **No read-back:** the slots cannot be read back from the screen.

### Live data (Phase 2), all confirmed on hardware

**Clock and stats.** Over the cable: op `0x28`. Over the dongle: `0C 10 00` followed by the cable block shifted +3. The stock Real-time page shows:
- time, date and weekday;
- CPU %;
- GPU %;
- air temperature;
- humidity.

It has no fields for CPU/GPU temperature, the day's high and low, or a weather icon.

**Music wave.**
- **Cable:** `04 18 → 04 78 → block → 04 02`.
- **Dongle:** `0B 1C 00 | fore back amplitude | 21 levels | checksum`. Found in AULA's `DeviceDriver.exe`.
- **Key LEDs:** the music data also drives the key lighting (a rainbow or wave pattern), which returns to normal when frames stop.

**Battery %.** Over the dongle, query `20 01`.

### Screen architecture (Phase 3)

- **Three separate pieces:** the screen's control program (`HFD_Code`), the interface file `UartTFT-II_Flash.bin` (127.6 MB), and the keyboard firmware.
- **The interface file has a fixed layout:**
  - 30 page records;
  - display and touch records;
  - type-3 "variable → icon" widgets;
  - 2 × 569 icons (English and Chinese banks), in RGB565, ARGB4444 or "LT" palette formats.
- **The official reset package was obtained and verified**, with SHA-256s matching the researchers'. The factory files were extracted offline to `research/factory/` and are kept read-only.
- **Page 21 (Mini Numpad):** 17 touch zones (codes `0x30–0x40`) plus Home.

### Existing Mac app

[AxiraDev/L99ForMac](https://github.com/AxiraDev/L99ForMac) (v0.10.1, GPLv3) was the most useful macOS reference. It is wired-only. Its ≈61 MB GIF size limit is unsafe; we won't copy it.

## Constraints and principles

The app is personal, local and quiet. It is built for one Mac and one keyboard and is never distributed.

- **Private.** Network calls are fine where a feature needs them, such as weather. No telemetry, accounts or auto-updates. Built from source on Alison's Mac, so no notarization is needed.
- **Platform.** Brand-new M5 Mac on the latest macOS. Apple Silicon only, no Intel build.
- **Native menu bar app.** Swift and SwiftUI, launching at login, with no Dock icon. One language, so it stays approachable for a non-full-time developer working in Claude Code.
- **Connection reality (hard constraint, restated by Alison Nov 18).**
  - Day to day, the keyboard runs wireless over the 2.4 GHz dongle. It is never on the cable all day.
  - **Bluetooth is not supported** (Alison, Nov 18). No feature is designed or tested for it.
  - Plugging into the Mac occasionally, to install or upload things, is fine. A Windows PC is for rarer jobs still.
  - So **every everyday feature must work wirelessly**. Anything cable-only is limited to install or setup steps. This includes Phase 3's live screen ideas: the screen's direct serial link only exists on the cable, so it can't be the everyday path.
  - *Phases 1–2 meet this: everything except uploads works over the dongle.*
- **Windows is a fallback only.** A Windows machine is available for rare jobs such as a factory restore or a firmware update. It is never part of the normal workflow.
  - It must be a **real PC**. Parallels on this Apple Silicon Mac can't run AULA's screen reset tool (tried Nov 18, see FINDINGS.md).
  - **The screen restore was proven on a real PC on Nov 18:** about 2–3 minutes, with the final message "OK".
  - **Skins and layouts no longer need the PC.** The upload command can't write the interface area, but the Mac now talks to the screen's bootloader directly and installs the whole file itself (Nov 18). Each skin change is one cable install of about 4½ minutes. The PC stays as a fallback.
- **Never touch the control programs.** No changes to the keyboard firmware or the screen's control program. Phase 3 changes only the interface file.
- **Keyboard functions come first.** Lighting controls, Caps/Num Lock, connection and battery status, and the mini numpad must keep working after every change.
- **Learn from the existing projects; don't depend on them.** Protocol knowledge comes from the open-source repos and AULA's own driver, reimplemented in Swift. `tools/l99probe/Sources/L99Core` is the start of that, with 18 tests checked against captures and the factory file.
- **Hard write limits in code.**
  - Only the three slot addresses can be written. Every write must stay inside its slot.
  - Images must be exactly 307,211 B. GIFs are capped at the factory size, 26,005,628 B.
  - Only volatile HID commands are allowed: clock/stats, music, and the dongle queries. No keymap, lighting, settings or "save to flash" commands.
  - Stop at the first unexpected reply.

## Phased scope

Each phase ships on its own.

### Phase 1 — Uploads and recovery

Goal: put any image or GIF on the screen from the Mac, and recover from anything that goes wrong.

- Menu bar icon showing connection status:
  - cable, dongle, Bluetooth or none;
  - battery % from the dongle.

  When an upload needs it, prompt to plug in the cable.
- Upload a **photo-frame image**, a **background** and a **GIF**. Drag and drop PNG, JPEG, HEIC or GIF.
- Fit, fill and crop with a live preview at the real 320×480 size, including how colours will look after RGB565 conversion. Offer optional dithering to avoid banding; the vendor has none.
- **GIF handling:**
  - frame count and timing preview;
  - warnings for frame or size limits;
  - automatic fixes for the validator rules, such as equalizing frame delays;
  - best-quality colour conversion: error-diffusion dithering onto the proven 252-colour ramp.
- Upload progress, with safe cancel and automatic retry. Retries restart from the beginning of the slot, never mid-stream. After an upload, show "leave and re-open the page to see it".
- Clock sync whenever the keyboard is connected, **by cable or dongle**.
- A library of past uploads for one-click re-sends. It keeps the source file and the exact bytes sent.
- **Recovery, built in:**
  - Detect an interrupted upload, then guide a screen restart and resend.
  - **Restore factory content**, from the verified factory file:
    - re-upload the mascot photo;
    - re-upload the 171-frame factory GIF, byte for byte;
    - guide resetting the background to a built-in wallpaper. The factory background slot is empty.
  - ~~Back up current slot content before overwriting.~~ **Dropped:** the slots can't be read back. Replaced by the library, plus an optional "verify slot", which uses the screen's CRC32 to confirm it still holds a given library item.
  - A documented Windows fallback for a full factory reset or firmware update:
    - the package is `research/L99 reset firmware 2026.5.25/`;
    - enter upgrade mode with Fn + X → 0 → 6, or hold Fn + Space for about 5 s with USB connected.

### Phase 2 — Live data (GO: fully wireless)

Goal: feed the Real-time Data and Play pages from the Mac, over the dongle or the cable, whichever is connected.

- **Go/no-go:** ✅ passed. Clock, stats and music all work over the 2.4 GHz dongle.
- **System stats:**
  - CPU % from `host_statistics`;
  - GPU % from IORegistry `IOAccelerator`;
  - the temperature sensors are private APIs, and the M5 sensor names must be verified on the machine.

  The stock page shows CPU % and GPU %. Its temperature and humidity fields show local weather (below). Send about once a second (the vendor's rate). One packet persists, so slower is fine.
- **Music wave** from system audio:
  - Uses a Core Audio process tap, which needs a one-time "System Audio Recording" permission. Audio is processed in memory and never saved.
  - About 75 updates a second over the dongle; 21 bands over the dongle, 18–25 over the cable.
  - **Key-lighting setting:** the music data also drives the key LEDs. Expose the fore and back mode bytes as a setting ("keys follow the music" or "screen only"), once their values are mapped.
- **Weather (Apple WeatherKit):** fill the Real-time page's temperature and humidity fields, plus the stats packet's high/low and condition bytes, from current conditions and the daily forecast. If weather is unavailable, fall back to blank or last-known values.
  - **Setup:** sign with Alison's paid developer team and enable the WeatherKit capability on the app's App ID; Xcode adds the entitlement.
  - **Location:** use Core Location with a one-time location permission (decided).
  - **Usage:** refresh every 15–30 minutes, well within the included quota.
  - **Attribution:** show the Apple Weather mark and legal link somewhere in the app, such as the menu dropdown, as Apple requires.
  - **Condition codes:** map WeatherKit conditions to the keyboard's 0–5 range (sunny, cloudy, light snow, thunder, rain, heavy snow, per gavindi).
- Runs quietly in the background, with negligible CPU and battery use. Pause streaming when the screen isn't on the relevant page, if that can be detected; otherwise keep rates modest.
- **Bluetooth:** no data channel is known. Show "live data paused (Bluetooth)".

### Phase 3 — Slim and reskin the screen

Goal: make the screen look better and carry less, with every keyboard function intact.

**Custom layouts are proven (Nov 19).** A fully re-laid-out Numpad, with new key sizes, positions and art, installed from the Mac and works (FINDINGS.md, "Custom layouts from the Mac"). Designs aren't limited to the stock sizes and positions, only to the screen's existing key actions.

**Direction (Alison, Nov 18): themes, not hyper-specific edits.**
- **Skins by area**, each chosen from a small set in the app:
  - home-screen icons;
  - home-screen media bar;
  - app top bar;
  - Calculator;
  - Numpad;
  - Play page: media controls and visualiser style (the stock rainbow rectangles are to be replaced if they're artwork);
  - Real-time Data page.
- **Hide or show whole apps** on the home screen (e.g. hide Touchpad).
- **Skins are made by Claude and added to the app's skin library**, e.g. a folder per skin with a manifest and exact-size artwork. New ones are generated on request later, the same way.
- The app combines the chosen skins and hidden apps into one interface file, previews every changed page, proves nothing else changed, and installs it from the Mac through the bootloader (cable, about 4½ minutes).
- **Screen catalog done (Nov 18)** (see FINDINGS.md, "Screen catalog"):
  - Every area listed is made of plain artwork, except the Play visualiser bars. The control program draws those bars, so they can't be reskinned. Everything around them can.
  - The Calculator's result digits use a built-in font.
  - Home tiles are one picture with separate tap areas, so apps can be hidden and the grid closed up without a gap.
- **Installing without Windows: done (Nov 18).** The upload command can't write the interface area (MAC_INSTALL_TEST.md), but the Mac bootloader flasher can (ISP_PROTOCOL.md). Writing only changed blocks may be possible later; version 1 writes the whole file.

- **Prerequisite met:** the Windows restore and the Mac restore of the stock file both passed (Nov 18).
  - An in-app full restore is **out of scope**. The ISP erase/program sequence hasn't been reverse-engineered, it writes the whole 127.6 MB image, and no recovery from a half-written flash has been proven.
- **Writing the reskinned file:** `InterfaceFile` (L99Core) replaces icon art in place and refuses any change outside the replaced icons; `l99probe isp-flash <file> --direct` installs it. First test file: `skin-file blue-1` (the Numpad "1" key tinted blue). **Installed from the Mac and confirmed on the screen (Nov 19):** the key turned blue and nothing else changed.
  - softce proved that a UI-only flash with `HFD_ISP_TOOL_V1.31.exe` + `UartTFT-II_Flash.bin` works.
- **Mini Numpad (page 21):** new normal and pressed artwork for all 17 buttons, with the same touch zones and codes.
  - Replace images in place at the same size, as raw ARGB4444.
  - Patch both language banks.
  - softce's "LT" encoder caused stripes, so avoid it.
- **Top status bar:** the indicators are type-3 widgets repeated in each page's records, so their artwork and positions can change.
  - The bar shows the time, a `MAC` mode badge, the connection icon, a lock, `A` for Caps Lock, `1` for Num Lock, and battery.
  - Keep the variable numbers and icon counts unchanged.
- **Bottom volume module:** still unresolved; it needs our own parse of the factory file.
- **Remove or hide unused pages** (touchpad, calculator):
  - Keep all 30 page records.
  - Hide a page by redirecting every touch record that points to it (`goto_page`). This method is proven on hardware.
  - Never delete or renumber pages.
- Later, if the research supports it, layout changes such as moving or resizing elements and changing navigation.
- **Design workflow:** export button art from a design tool at exact pixel sizes; the app packs it into the interface file and previews the result before writing.

## Research questions — answers

| # | Question | Answer | Status |
|---|---|---|---|
| 1 | What gets through the 2.4 GHz dongle? | Clock ✅, stats ✅ (+3 layout), music ✅ (`0x0B`, from AULA's driver), battery ✅. Uploads need the cable. | **Answered on hardware** |
| 2 | How is the interface file written, and can it be restored from a Mac? | AULA's Qt ISP tool over USB serial writes the whole 127.6 MB image. There's no Mac path today, so restores use Windows. The package is verified and the factory files are extracted. | Answered |
| 3 | Can slots be read back? | No. The screen's CRC32 can verify a slot against a known file. | Answered |
| 4 | Top status bar | Type-3 widgets in each page's records, so they can be moved. Which variable drives which indicator is unknown. | Mostly answered |
| 5 | Bottom volume module | Artwork is icon bitmaps; overlay versus per-page is unknown. | **Open**: our own parse, before Phase 3 |
| 6 | Removing pages | Unlinking is proven; deleting isn't. Keep 30 records. | Answered (unlink only) |
| 7 | Artwork limits | RGB565 / ARGB4444 / LT; 12-byte descriptors; both banks; no global checksum found. | Answered |
| 8 | Upload protocol and firmware version | 5A A5 v1.06 protocol confirmed on hardware. Version: dongle build byte `0x31`; screen About page (to record). | Answered |
| 9 | GIF colour conversion | Arbitrary RGB565 palettes display, confirmed with our own GIFs. Exact colours when a frame has ≤256, otherwise a per-frame palette with damped serpentine dithering. Delay unit is milliseconds. | **Answered on hardware** |
| 10 | CPU/GPU on M5 | CPU and GPU % via public/IORegistry APIs. Temperatures via private APIs. | **Open**: list M5 sensors on the machine |
| 11 | *(new)* Music fore/back mode values | Same key-light visualiser in two directions: `fore` up from the bottom, `back` down from the top; the value picks one of 9 colour sets, 0 = off. Neither changes the screen's bars. | Answered on hardware (FINDINGS.md) |
| 12 | *(new)* Bluetooth | Not supported (Alison, Nov 18). | Out of scope |

## Process

The work moves from research to a hardware proof, then design, then build.

**In Claude chat**

1. ✅ **Write the PRD.**

**In Claude Code, on the Mac**

2. ✅ **Study the existing projects.** Repos in `research/`, results in `research/FINDINGS.md`.
3. ✅ **Run the hardware smoke test.** `tools/l99probe` and `research/SMOKE_TEST.md`. Done over both the cable and the dongle, plus an offline read of AULA's driver for the dongle music packet.
4. ✅ **Update the PRD** (this revision).

**In Claude chat (design)**

5. ✅ **Design mockup.** [Design canvas](https://claude.ai/artifact/VP7EhyfWaAtZGSqiu8QyV6), approved Nov 17. A visual design of:
   - the menu bar dropdown: connection, battery and live-data toggles;
   - the upload window with 320×480 preview;
   - the library;
   - the recovery screens;
   - the Phase 2 music settings, including key lighting.

   Design feedback only, no working code.

**In Claude Code, on the Mac**

6. ✅ **Set up the Xcode project.** A SwiftUI menu bar app, launch at login, a git repo, and `PRD.md` and `FINDINGS.md` in the project. Sign it with Alison's developer team, so WeatherKit can be enabled in Phase 2. Bring in `L99Core` from `tools/l99probe` as the protocol layer.
   - **Done:** `L99 Control Center/L99 Control Center.xcodeproj` is a menu-bar-only app (`LSUIElement`). It has device detection over USB (read-only), an "Open at login" switch (`SMAppService`) and Quit. Bundle ID `com.brunk.l99controlcenter`, team `3AG2ZLH228`, automatic signing.
   - **No App Sandbox.** The app needs raw HID, the screen's serial port and the private temperature-sensor API, which the sandbox blocks or makes awkward. It's a private app that isn't on the App Store, so it uses the hardened runtime instead.
   - **Git:** the repo root is the top project folder, so it covers the app, `PRD.md`, `research/*.md` and `tools/l99probe`. `.gitignore` keeps firmware dumps, the driver, the reset package and third-party repos out.
   - **L99Core** is linked as a local package product (`tools/l99probe`, product `L99Core`). It gained `L99Device` USB IDs.
   - **WeatherKit capability and location permission** are added in Phase 2, when weather is built.
7. **Build Phase 1:** uploads and recovery. *Built Nov 17. Tested in the app Nov 17: photo upload, factory import and factory GIF restore work. Standalone Check froze the screen and was removed (FINDINGS.md, Phase 1 hardware results).*
   - Upload window: photo frame, background or GIF; drag and drop; Fill/Fit, zoom and drag to move; a 1:1 preview in the screen's real colours; optional dithering for stills; "Best colours" (shared palette) or "Safe colours" (ramp) for GIFs, with automatic frame and timing fixes.
   - Uploads with progress, safe cancel between writes, and one automatic retry from the start of the slot.
   - Library of everything sent (exact bytes kept) with Send. No standalone Check: a `0x66` outside an upload can freeze the screen. Each upload is still checked block by block.
   - Recovery: resend after an interrupted upload, import the factory pictures from `UartTFT-II_Flash.bin` (each piece checked), restore the mascot, animation or a factory wallpaper, and the Windows fallback steps.
   - Clock sync on connect, on wake and every 6 hours (dongle first, cable otherwise), and battery % from the dongle.
   - Shared code: `L99Core` gained the slot table, the GIF container, colour conversion and the palette quantizer (29 tests); device I/O moved into a new `L99Link` library shared with `l99probe`.
8. **Build Phase 2:** live data over the dongle and the cable. *Built Nov 17. Tested on the keyboard over 2.4 GHz: clock, CPU/GPU load, battery and weather work. Music still to test.*
   - **WeatherKit setup that was needed:** register this Mac in the developer account (for the provisioning profile), and tick WeatherKit under the App ID's **App Services** tab. The capability alone gave `WDSJWTAuthenticatorServiceListener.Errors error 2`.
   - One background sender owns the dongle and cable. It uses the dongle while the keyboard answers there, else the cable, and pauses while the Mac's displays sleep. It never sends over the cable during an upload.
   - Clock, CPU % and GPU % (public APIs: host CPU ticks, the GPU's own utilisation in the IORegistry) once a second in the `plus3` packet; weather alone every 30 s; the clock alone every 6 hours. About 1% CPU.
   - Weather from WeatherKit plus Core Location (approximate), every 20 minutes and on wake, with the Apple Weather mark and data-sources link in the menu. Needs this Mac registered in the developer account for the WeatherKit provisioning profile.
   - Music: Core Audio process tap of all Mac sound, 2048-point FFT into 21 log bands with automatic gain, about 60 frames/s over the dongle (4/s over the cable). Stops 1.5 s after the sound stops. "One app only" from the design is deferred.
   - CPU/GPU temperatures are skipped: the stock Real-time page has no field for them, so no private sensor API is used.
   - Q11 (music style bytes): mapped on hardware with Alison. The Music window offers Key lights (up from the bottom, down from the top, or off) and 9 named colour sets.
   - Clock, stats and battery packets pause while music streams: each one made the top key row blink green.
9. **Build Phase 3:** first confirm the Windows restore works end to end, then reskin and slim the screen.

## Risks and mitigations

| Risk | Phase | Impact | Mitigation |
|---|---|---|---|
| A bad interface-file write leaves the screen unusable | 3 | High: screen down until restored; bootloader recovery is unproven | Confirm the Windows restore before any write. Flash only through AULA's tool. Change only images in place and `goto_page` links. Preview before writing. Never touch the control programs. |
| An oversized write overwrites neighbouring flash (the panel acknowledges it anyway) | 1 | High | Hard slot bounds in code. Exact image size. GIF cap at the factory size. Only three addresses can be written. |
| Upload interrupted mid-transfer | 1 | Low: the screen freezes until restarted | Stop at the first error, guide a power cycle, resend from the start of the slot. Uploads take under a second for images. |
| An invalid GIF is acknowledged but plays the fallback animation | 1 | Low | Validate against every known rule before sending. Re-sending a good GIF fixes it. |
| A firmware update changes the protocol | All | Medium: features stop working | Record the dongle build byte (`0x31`) and the About-page version. Keep the factory files. Don't update firmware without checking. |
| Music mode changes the key lighting unexpectedly | 2 | Low: lighting returns to normal when frames stop | Make it a visible setting. Default to the least surprising option once the mode values are mapped. |
| Stats interfaces break with a macOS update | 2 | Low: stats stop updating | Isolate the stats code. Fail quietly. |
| GIF colour quality is poor | 1 | Low | Error-diffusion dithering with a preview. Later, test arbitrary palettes. |
| The open-source projects or vendor files contain unsafe code | Research | Low if read-only | Done read-only. Nothing from the repos or AULA's packages was run. `l99probe` is our own code. |

## Sources

Repos studied (cloned in `research/`; per-repo notes in `research/notes/`):

| Repo | What it covers |
|---|---|
| [gavindi/Aula_L99_Linux](https://github.com/gavindi/Aula_L99_Linux) | Keyboard HID channel, image and GIF upload, GIF container and validator rules, flash slots, music and stats layout |
| [miniz3210/aula-l99-controller](https://github.com/miniz3210/aula-l99-controller) | Interface-file structure, Page 21 touch zones, recovery matrix |
| [softce/aula-l99-research](https://github.com/softce/aula-l99-research) | Custom UI via the interface file (proven on hardware), image formats, reset-package extractor |
| [AxiraDev/L99ForMac](https://github.com/AxiraDev/L99ForMac) | Working Mac app: uploads, live stats, music (wired) |
| [Revisory676/aula-l99-linux](https://github.com/Revisory676/aula-l99-linux) | gavindi fork. Its +3 dongle stats layout is the one that worked. |
| [Salamor/aula-l99-open-widgets](https://github.com/Salamor/aula-l99-open-widgets) | [Issue #3](https://github.com/Salamor/aula-l99-open-widgets/issues/3): v1.06 framing. (Its README protocol belongs to a different device.) |
| [livvaa/AulaToolkit](https://github.com/livvaa/AulaToolkit) | Dongle framing and battery query |

AULA official downloads (verified; kept in `research/`, never run):

| File | SHA-256 | Used for |
|---|---|---|
| L99 reset firmware 2026.5.25 (screen reset EXE) | `8d52849a…` | Factory files (`research/factory/`); Windows fallback |
| L99 reset firmware 2026.5.25 (keyboard reset EXE) | `0a946a5d…` | Windows fallback |
| AULA L99-EN Driver-1.0.1.6.exe | `8090266d…` | Dongle music packet (`DeviceDriver.exe`, read offline) |

Background: [Home Assistant forum post on the L99 custom screen](https://community.home-assistant.io/t/aula-l99-keyboard-touchscreen-as-a-home-assistant-control-panel-and-energy-display/1027079).
