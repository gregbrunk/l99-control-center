# AULA L99 — Code Study Findings

Nov 17, 2026 · PRD Process step 2 (read-only study)

**Method.** Seven repos were shallow-cloned into `research/` with git hooks, submodules and LFS disabled. Nothing was built, installed or run. No keyboard was connected. Each repo was read by a separate study pass. The detailed per-repo notes, with file:line citations, are in `research/notes/`. Salamor issue #3 is saved as `research/Salamor_issue3.md`.

Commits studied:

| Repo | Commit | Date |
|---|---|---|
| gavindi | `30f170a` | 2026-10-23 |
| miniz3210 | `5ee8c0a` | 2026-11-17 |
| softce | `88e86f7` | 2026-10-01 |
| AxiraDev | `3173018` | 2026-10-23 |
| Revisory676 | `ddcdc9a` | 2026-10-18 |
| Salamor | `d805871` | 2026-04-18 |
| AulaToolkit | `db2f419` | 2026-11-14 |

**Confidence tags** used throughout:
- **[HW]**: a project author confirmed it on real hardware.
- **[2×]**: two independent projects agree byte for byte.
- **[INF]**: inferred, not tested.

---

## Hardware smoke test results (Nov 17, 2026)

Run with `tools/l99probe` on Alison's L99. The full log is in `SMOKE_TEST.md`. These results override the "untested" notes further down.

| Question | Result |
|---|---|
| Q8: upload protocol | ✅ 5A A5 v1.06 protocol confirmed. A photo-frame upload took 0.8 s; 151/151 writes were answered "OK"; all three device CRC32s matched. The image shows after leaving and re-opening the page; no power cycle needed. |
| Wired clock and stats (op `0x28`) | ✅ Every field on the stock Real-time page displays: time, date, weekday, air temperature (byte 17), humidity (21), CPU % (13), GPU % (15). The page has no fields for CPU/GPU temperature, high/low or a weather icon. One packet is enough; no streaming needed. |
| Wired music (op `0x78`) | ✅ AxiraDev's sequence (`04 18 → 04 78 → block → 04 02`, 18 levels) works. ✗ gavindi's sequence (a bare `04 02` first) is refused with `FF`. Side effect: the key LEDs switch to an audio-reactive rainbow while frames arrive, then return to normal. Block bytes 0–2 likely set the key-light scheme and brightness. |
| **Q1: clock over 2.4 GHz** | ✅ **Works.** The prior-art `0x0C` packet set the screen's clock. |
| **Q1: stats over 2.4 GHz** | ✅ **Works with the +3 layout** (Revisory676): CPU 33%, GPU 66%, 13 °C and 31% displayed. |
| Q1: music over 2.4 GHz | **AULA's driver has a dongle music path.** It was found offline in `DeviceDriver.exe` v1.0.1.6. The installer was unpacked with Python `lzma` and nothing was run. The music function branches on connection type (`cmp [edi+0x7a4], 2` at `0x43b818`) and, for the dongle, builds `0B 1C 00 \| fore back amplitude \| 21 levels \| 00×4 \| checksum`, sent without waiting for a reply. The cable branch of the same function is `04 78 [8]=1` → `fore back amp + 25 levels` → `04 02`. The vendor's dongle clock builder (`0x42c150`) produces exactly the prior-art packet that worked in B3, which confirms that reading of the driver. ✅ **Confirmed on hardware:** 2,242 frames in 30 s (≈75 fps; 2,234 echoed by the dongle). All bars moved, very smooth. The key LEDs showed a wave too, then returned to normal. |
| Battery over 2.4 GHz | ✅ The `20 01` query returns battery % (80%). |
| Dongle version | Session-init byte 11 = **`0x31`** (gavindi's unit: `0x29`). The dongle's vendor channel is `FF60:0061` (32-byte reports). |
| Q4 top bar (from a photo) | Time · `MAC` mode · connection icon · lock · `A` Caps · `1` Num · battery % with charging bolt. |

**Phase 2 decision: GO** for clock, stats and battery over the 2.4 GHz dongle. **Music works over the dongle too**, and is smoother than over the cable. Phase 2 is fully wireless: clock, stats, music and battery.

---

## Phase 1 hardware results (Nov 17, 2026, cable)

| Test | Result |
|---|---|
| Factory mascot re-upload (`photo --factory`) | ✅ 0.7 s, all three region CRCs matched. Mascot displays correctly. |
| Slot check (`0x66` only, no writes) | ⚠️ **Not safe on its own.** From the CLI it matched the mascot and rejected the test card (0.05 s), but the first standalone check timed out. In the app (Nov 17), Check on the photo frame while it was displayed timed out and **froze the screen until the keyboard was switched off and on**. The slot data was unharmed. The vendor only sends `0x66` inside an upload, straight after the writes, so a standalone `0x66` is outside what the firmware expects. **Removed from the app.** Uploads keep their in-session `0x66` checks, which have always worked. |
| GIF with one palette shared by 4 very different frames (205 colours, 202 off the ramp) | ⚠️ Plays, colours correct, but rows of isolated light dots in flat areas: Floyd–Steinberg with too few nearby palette colours. |
| Same frames, exact colours (≤256 per frame) plus a 5th frame dithered onto its own 256-colour palette, serpentine, damped | ✅ Smooth, no dots. **Arbitrary RGB565 palettes display correctly with our own encoder** (Q9 answered). |
| GIF delay unit | ✅ **Milliseconds.** Delay 100 → ~0.13 s per frame, delay 400 → ~0.43 s. Drawing adds ~30 ms; full-screen frames top out around 7.5 frames/s. |
| Tearing | The screen redraws top to bottom with no double buffering, so a whole-screen change shows a horizontal seam for one camera frame. Inherent to the panel; worst with full-screen changes. |

### Music style bytes (Q11), mapped Nov 18, 2026 (dongle, style tour)

`l99probe dongle-music-tour` played each value of the two style bytes (`0B 1C 00 | fore back amp | …`) for 4 s with 2 s gaps, filmed (IMG_9777).

- **The two bytes are the same key-light visualiser in two directions** (corrected by Alison on hardware, Nov 18): **fore** draws it **up from the bottom**, **back** **down from the top**. The value picks the colours; 0 is off. Both at once work but clash.
- Colours, fore / back value: green-yellow-red 1/1, rainbow 2/3, unicorn rainbow 3/2, rotating rainbow 4/4, pulsing colour cycle 5/5, lavender 6/6, red 7/7, amber 8/8, yellow 9/9. AULA's default (2/0) is the rainbow, bottom up.
- The earlier readings in this section (from the tour video and IMG_9778/9780) mixed up colours and directions; this list is Alison's direct observation.
- **Neither byte changes the screen's bars.** 0/0 gives a "screen only" mode.
- Every burst starts with about a second of a fixed green/white/red level-meter pattern, then the chosen colours.
- **Stats packets interrupt the music lighting.** Each `0C` clock/stats packet sent while music frames stream makes the top (F-key) row blink green for one video frame. Measured in the tour video: blinks every 1.03 s, the app's stats period. The app now holds clock, stats and battery packets while music plays and resumes them when it stops.

## Summary

1. **Phase 1 is well understood and low risk.** Image, background and GIF uploads use the 5A A5 serial protocol. It is now understood end to end and two projects agree on it byte for byte [HW][2×]. Uploads always need the cable.
2. **Only one upload protocol exists for this keyboard.** The "older" `12 34 56 78` + JPEG protocol in Salamor's README actually belongs to a different USB display (`87AD:70DB`) that was in the same capture. gavindi and AxiraDev both found this independently [2×].
3. **Phase 2 is undecided, so the smoke test is decisive.**
   - Clock set over the 2.4 GHz dongle is acknowledged [HW].
   - CPU/GPU stats over the dongle have never been tested. Two layouts compete.
   - The music spectrum has no known dongle path. Expect it to be cable-only.
   - Battery and presence over the dongle are easy and solid.
4. **Recovery is weaker than the PRD assumed.**
   - The slots cannot be read back, so they cannot be backed up.
   - Writing the full interface file, which is the factory restore, works only with AULA's Windows ISP tool.
   - Nobody has proven recovery from a half-written interface flash.
   - Content-slot problems (bad upload, bad GIF) are recoverable by power-cycling and resending.
5. **The Phase 3 reskin is feasible, but only through Windows for now.**
   - softce reskinned the UI and unlinked a page on hardware [HW], then flashed the result with the official Windows tool.
   - The safe pattern is to replace images in place at the same size and redirect `goto_page`. Never delete pages.
6. **The biggest bricking risk in Phase 1 is oversized GIFs.** The panel acknowledges writes past the end of a slot and silently overwrites the flash next to it. Our app must enforce hard address and size limits.

---

## Answers to the open research questions

### Q1: What gets through the 2.4 GHz dongle?

| Data | Over the dongle | Confidence |
|---|---|---|
| Clock set | Acknowledged. Not yet shown to update the panel. | [HW] ack only |
| CPU/GPU load and temperature, weather | Unknown. The offsets come from disassembly only. Revisory676 uses "+3" (trailer at 25..26); the prior art implies "+4". | untested |
| Music spectrum | No dongle opcode exists in any repo. | expect cable-only [INF] |
| Image / GIF upload | No. The screen is a separate USB serial device that exists only over the cable. | [INF], effectively certain |
| Battery and presence | Yes. Send query `20 01 00 … 21`; the reply is `20 01 00 <pct>`. No reply means the keyboard is asleep or off. | [HW] |
| Lighting and settings | Implemented over the dongle in AulaToolkit. Tested on the S75 Pro, not the L99. | [INF] for L99 |

AxiraDev adds one useful lead. In keyboard firmware 1.03, the *keyboard's* microcontroller is what sends the spectrum frame to the screen (`5A A5 17 62 00 12 [18 levels] CRC`). The screen data therefore travels keyboard → screen inside the keyboard. A dongle path for stats or music is plausible if the dongle forwards the right reports, but nobody has found one.

**Dongle transport:**
- Interface 3, vendor collection.
- **32-byte output and input reports**, not feature reports.
- Frame: `cmd len seq data[28] checksum`, where checksum = sum of bytes 0..30 & 0xFF.
- Command bytes: TIME `0x0C`, BATTERY `0x20`, session-init `0x02`, LIGHT `0x05`, SETTINGS `0x07`.

Dongle clock packet (acknowledged on hardware):
```
0C 10 00 | 00 01 5A YY MM DD hh mm ss 00 WD 00 00 00 | AA 55 | 00… | cksum
```

**Phase 2 decision rule:** run the smoke test. If stats show up over the dongle, Phase 2 goes ahead with clock and stats, and music stays cable-only. If only the clock works, consider a smaller Phase 2: clock sync plus a dongle battery indicator in the menu bar.

### Q2: How is the full interface file written? Can the reset package be applied from a Mac?

- **Tool.** AULA's screen reset EXE is a 195 MB Enigma Virtual Box container. Inside it is a Qt5 ISP tool (`HFD_ISP_TOOL_V1.31.exe`, `L99 ISP V1.23.exe`) that uses `Qt5SerialPort`.
- **Transport.** Plain USB serial to `EEEF:268A`, not DFU.
  - The ISP packet, according to softce, is `4A 30 | offset LE32 | len LE16 | payload ≤2048 | CRC32 LE`. The erase, program and finish sequence has *not* been reverse-engineered.
- **Upload mode.** It is entered by hand on the keyboard. AULA documents Fn + X → 0 → 6, which failed on softce's unit. Fn + Space held for about 5 s with USB connected worked [HW].
- **Image size.** The updater writes the whole 127.6 MB image, even for a 2-pixel change. It then checks the host file CRC against the device flash CRC.
- **UI-only reflash works.** softce flashed `HFD_ISP_TOOL_V1.31.exe` + `UartTFT-II_Flash.bin` without the control program [HW].
- **From a Mac:** **not possible today.** The realistic paths are:
  - the Windows machine (the PRD's fallback), or
  - a Windows VM with USB passthrough [INF, untested].
  A native Mac flasher would mean reverse-engineering the ISP flow ourselves, with no proven recovery if it goes wrong.
- **Reset package contents.** The ZIP is 45,080,624 B, sha `e854bebb…`. It holds:
  - the screen reset EXE, which contains `UartTFT-II_Flash.bin`, `HFD_Code_V2.2.bin` and `HFD_Code_V2.3.bin`;
  - the keyboard reset EXE, which contains `SN32F290.hex`.

  softce's `extract_l99_reset_assets.py` pulls these out offline after a SHA check, without running anything. **None of the repos ship the binaries**, so we must download the official package ourselves.
- **Restoring after a failed interface write: no project has proven it.** The only real data point is the *keyboard* reset EXE fixing garbled typing.
- **Side effect [INF].** The full interface image includes the user photo, background and GIF areas. A full restore will therefore overwrite user uploads, which can simply be re-sent from the library afterwards.

**Effect on the PRD:**
- The Phase 1 "restore factory content" feature becomes: extract the factory photo, background and GIF from `UartTFT-II_Flash.bin` (offsets below) and re-upload them through the normal slot protocol. This is safe and Mac-native.
- The Phase 3 prerequisite becomes "a confirmed Windows restore". The "in-app factory restore of the full interface file" stays out of scope unless we take on ISP reverse-engineering.

### Q3: Can slots be read back?

**No.** No project has a working read command.
- The Levetop SDK lists an extended read opcode `0x65`, but it is untested on the L99.
- The panel's reply to `0x66` returns a CRC32 of a flash region [2×]. That lets us *verify* a slot against a known file, without reading it.

**Effect on the PRD:** drop "back up slot content before overwriting". Instead:
- the library keeps every uploaded source file and the exact bytes sent;
- the factory images are extracted from the reset package;
- an optional "verify slot" uses the CRC32 query to report whether the screen still holds library item X.

### Q4: Top status bar

The evidence points to live widgets stored per page as layout records, which means they can be moved.
- Type-3 "variable → icon range" widgets are repeated on most pages. Page 1 has variable 8 at (277, 11) using icons 14–20 for values 0–6, which is probably battery [INF].
- Two-state icon pairs [1–2], [3–4], [5–6], [7–8] and range [9–13] fit connection, Caps and Num Lock [INF].
- softce moved the analog clock's position through page data [HW].
- The control program sets the values. Which variable drives which indicator is still unknown.

**Reskin depth:** artwork and positions can be changed. Keep the variable numbers and icon counts unchanged.

### Q5: Bottom volume module

**Unresolved.**
- softce edited its artwork as icon bitmaps (removing dark rectangles) [HW].
- Whether it is per-page records or a shared overlay is unknown.
- The volume keys probably send consumer usages `0xE9/0xEA/0xE2` [INF].

This needs our own parse of the factory file before Phase 3.

### Q6: Removing pages

- The page count is fixed at **30**, and pages are referenced by index (`goto_page`).
- **Unlinking is the only method proven on hardware.** softce changed one menu record's goto from 21 to 15.
- Nobody has tried deleting or renumbering pages. Whether the control program hard-codes page indices is unknown.

**Rule for Phase 3:** keep all 30 page records. Hide a page by redirecting every touch record that points to it.

### Q7: Artwork limits in the interface file

- **Image descriptor**, 12 bytes: `u32 offset, u16 w, u16 h, u24 size, u8 fmt`.
- **Formats:**
  - 0/1 = RGB565 LE
  - 2 = ARGB4444 LE
  - 3 = proprietary "LT" palette container (256-colour RGB565 palette, raw or run-length encoded)
  - No PNG, JPEG or GIF.
- **Both language banks** must be patched: 2 × 569 icons, English and Chinese.
- **Checksums:** no global checksum was found. Only the four 320×480 images and the factory animation carry a CRC16/MODBUS. Icon descriptors have none.
- **Lessons from failures:**
  - softce's homemade LT encoder produced stripes on the device, so **use raw ARGB4444 for new art**.
  - Replacing an image in place at the same size needs no table edits.
  - Put new art in pools that no other page references, never in "empty" flash.
- **Page backgrounds:** all 30 background descriptors are empty. Page artwork is made up of icons and display records.

### Q8: Upload protocol and firmware version

**Request frame (5A A5)** [HW][2×]:
```
5A A5 | len u24 BE | CMD | addr u32 BE | data | CRC16 LE
```
- `len` = 1 + 4 + N + 2 = N + 7. It counts everything after the length field.
- The CRC is CRC-16/MODBUS (reflected `0xA001`, init `0xFFFF`) over CMD..data.
- gavindi's per-length CRC lookup table collapses to exactly this. The study verified all 14 table entries against it.

**Commands:**
- `0x64`: write ≤2048 B at `addr`.
- `0x66`: `addr` + `len u32 BE`. The device replies with a CRC32 of that region (reflected `0xEDB88320`, init 0, no final XOR).
  - Send it after each 128 KiB region and after the last chunk.
  - Projects disagree on whether it also commits or erases. The vendor driver sends it at those points, so we copy the vendor sequence exactly.

**Responses:** `5A A5 | len u8 | body | CRC16 LE`.
- First an ACK body `[cmd, FF]`.
- Then a result body `[cmd, addr(4), …]`, which contains ASCII `OK` for writes.
- AxiraDev uses a 3 s timeout and aborts on any mismatch, which is safe.

**No refresh or commit command exists.** The screen shows new content after you leave and re-enter the page, or after a power cycle.

**Firmware version:**
- No version query exists on the wired keyboard or the screen.
- The dongle's session-init reply byte 11 (`0x29` on the tested L99) is probably the *receiver's* version.
- The screen's About page shows "V1.31".

**Plan:** record the About-page version and the dongle byte by hand at smoke-test time, and keep the factory files.

### Q9: GIF colour conversion

| | gavindi | AxiraDev | vendor (as observed) |
|---|---|---|---|
| Static images | truncate to RGB565 | truncate to RGB565 | truncate, no dither |
| GIF palette | fixed 6×7×6 = 252-colour ramp | per-frame exact palette ≤256 | own slot only if max(R,G,B) ∈ {0,255}; else dithered onto the ramp |
| Dithering | Floyd–Steinberg per channel [HW] | whatever ImageIO's GIF encoder does (opaque) | unknown algorithm |
| Notes | works on hardware; avoids validator traps | adjacent frames can flicker; no dither control | — |

**Validator traps** in the GIF container, found by experiment [HW]:
- every frame must have the same delay;
- 255 frames at most (the vendor caps at 200);
- the 528-byte frame prefix tolerates at most 8 non-zero padding bytes;
- two adjacent run-length runs must not share a palette index.

A GIF that fails validation is still acknowledged, and the panel then plays a cached fallback animation.

**Recommendation for best quality:**
1. Build our own converter: error-diffusion dithering (Floyd–Steinberg or Sierra-lite) onto the 252-colour ramp, which is proven on hardware.
2. Enforce all the validator rules.
3. **Answered by the factory animation (Nov 17):** its frames use 256 distinct RGB565 colours, 253 of them *off* the 252-colour ramp, and it plays correctly. So arbitrary palette entries display. The app's default is now one shared median-cut palette per animation with Floyd–Steinberg dithering ("Best colours"); the ramp stays as "Safe colours". Still to confirm with one of *our* GIFs on hardware. Originally: test whether *arbitrary* RGB565 palette entries display correctly. Only up to 11 ramp-legal slots had been tested. If they do, switch to per-GIF palettes with median-cut or k-means quantization shared across frames, which avoids flicker. That would be a large quality gain.
4. For static images, add optional ordered or error-diffusion dithering to RGB565 to remove gradient banding. The vendor does not do this.

**GIF blob format at `0x04240000`:**
- A table of contents with one 20-byte LE entry per frame: `[0:4]` frame offset, `[4:8]` total size, `[8:10]` w, `[10:12]` h, `[12]`=3, `[13]` frame count, `[14:16]`=0, `[16:18]` delay (centiseconds?), `[18:20]` CRC16/MODBUS over all frames.
- Each frame: `"LT" w h 01 03`, `[8:12]` frame size, `[12:14]` content length mod 65536, `[14:16]` mode (`0x0100` RLE / `0x0002` raw), then the palette (RGB565 LE, ≤256), zero-padded to 528 B.
- Then the content: RLE `(len-1, idx)` pairs, or raw 1 B per pixel when RLE content would exceed `0xFFFF`.

### Q10: CPU/GPU stats on Apple Silicon (M5)

- **CPU %:** `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas. Public, stable.
- **GPU %:** IORegistry `IOAccelerator` → `PerformanceStatistics` → `"Device Utilization %"`. Undocumented but long-lived.
- **Temperatures:** the private `IOHIDEventSystemClient` API, loaded with `dlsym`: usage page `0xFF00` usage 5, event type 15.
  - The sensor-name filters (`pACC*`/`eACC*`, `PMGR SOC Die Temp*`, `GPU MTR Temp*`) are from the M1/M2 era. **M5 names need checking on the real machine.** We should list all sensors once and pick the names from that.
  - The alternatives are SMC keys or IOReport. Neither project uses them.
- **Audio for the music wave:** a Core Audio process tap (macOS 14.2+, `CATapDescription` global tap plus a private aggregate device).
  - It needs `NSAudioCaptureUsageDescription` and the "System Audio Recording" permission.
  - Then a 2048-point FFT and log bands. No BlackHole or ScreenCaptureKit needed.

---

## Screen catalog (Phase 3, Nov 18): our own parse of the interface file

Done offline with our own read-only parser, `tools/screen-catalog/catalog.py`. It opens only the file and checks its SHA first. It reads all 30 pages, every display and touch record, both icon banks and the three built-in animations, and renders every page. The renders match the real screens.

**Page map:**

| Page | Content |
|---|---|
| 0 | Boot animation |
| 1, 2, 3 | Home: normal, work timer running, rest timer running |
| 4 | Settings |
| 5–14 | The settings sub-pages |
| 15 | About |
| 16 | Screen customisations |
| 17 | Colour (lighting) |
| 18 | Play |
| 19 | Real-time Data |
| 20 | Photo frame |
| 21 | Mini Numpad |
| 22 | Calculator |
| 23 | Touchpad |
| 25 | Loading |
| 26 | Clock |
| 27 | "Colour NG!" |

**What each skin area is made of** (English bank; the Chinese bank shares most art):

| Area | Made of | Skinnable? |
|---|---|---|
| Home icons | **One 287×272 ARGB4444 image** (icon 0 at `0x625FDC`, both banks differ) plus 10 touch records on page 1 that hold only rectangles and `goto` page. | ✅ Redraw the image. Touch areas are plain data, so apps can be **re-laid out or hidden without leaving a gap**. Touchpad is the last tile, so hiding it leaves no hole even without re-layout. |
| Home media bar | Icons 560/561/562, 287×67 ARGB4444: one per home state (normal, work timer, rest timer). Four touch records: volume down/mute/up (`0x22`–`0x24`) and the alarm button (`0xF120`, goto 2). | ✅ |
| App top bar | Shared indicator icons 1–20: connection, Caps, Num, battery (type-3 widgets, same positions on every page), digit icons 30–43 for the battery %, back button 119, and one title image per page. | ✅ Art and positions. |
| Calculator | 18 touch buttons, each with an up and a down image (icons 400–435). The result line is a type-1 text widget drawn with a built-in font. | ✅ Buttons. ⚠️ The result digits use a font table, not icons. |
| Numpad | 17 touch buttons with up/down images (icons 318–352). | ✅ |
| Play | Play/pause (210/211), previous/next (208/209), volume pill (207). | ✅ Controls. ❌ **Visualiser: no record and no artwork for it anywhere in the file.** The bars are drawn by the screen's control program, so they can't be restyled through the interface file. |
| Real-time Data | Everything is bitmap: three digit sets (213–226 large, 260–269, 280–289), units, labels. | ✅ Including the digit "font". |

Other facts:
- All 30 page-background descriptors are empty. The black backgrounds are drawn by the control program. Adding real page backgrounds would mean filling those descriptors, which is untested.
- The active art for the user-visible areas sits between `0x625000` and `0x940000`. The page and touch records sit in `0x21DD0`–`0x251A5`.
- **The upload command's address is the file offset.** Photo uploads write at `0x041E0000`, the same offset as the photo in the file. So the Mac upload command `0x64` might be able to rewrite single 128 KiB blocks of the interface art directly, which would install a skin without Windows. **Untested.** Open questions: does the screen accept `0x64` below `0x04000000`; does it erase and rewrite partial blocks correctly; does it cache art until a power cycle. Recovery from a bad write needs the Windows ISP tool, so this waits until the Windows restore test has passed.

## Mac-install test (Nov 18): screen ignores writes to the interface area [HW]

The upload command `0x64` at `0x00760000` (block `0x3B`, Numpad art) gets no reply at all, on two tries. The photo slot right afterwards takes 151/151 writes with matching CRCs. **Interface-file changes (skins, layouts) install only through AULA's Windows tool.** Details are in MAC_INSTALL_TEST.md. This answers the "upload address = file offset" hypothesis in the screen catalog section: the addresses match, but the firmware only accepts writes into its slots.

## Windows restore on a real PC (Nov 18): PASSED [HW]

- **Tool:** AULA's "L99 keyboard Screen reset firmware" EXE, run on a real Windows PC with the cable plugged in. The screen was in upgrade mode (Fn, X, 0, 6).
- **Start button:** it stayed disabled for a long time, then "randomly" turned active. Before that, Alison had checked the hardware ID (`USB\VID_EEEF&PID_268A`) and power-cycled several times. The cause is unknown. **Next time, expect to wait or retry, and end any AULA driver process first.**
- **Progress:** two progress bars ran. The first was fast (the screen's control program). The second took about 2–3 minutes (the 127 MB interface file). The final message was "OK".
- **Result:** the screen works fully, back to factory content. The language reset to Chinese; it's set on the screen's Settings page. All keyboard settings are gone, because the keyboard reset tool was also run.
- **So the Windows restore is a proven recovery route.** The screen now holds the stock interface file, which is the baseline the Mac-install test expects.

## Windows restore attempt in Parallels (Nov 18): does not work

- **Setup:** Parallels 26.5 with Windows 11 on ARM, on an M1 Max. The cable was plugged straight in.
- **What worked:**
  - The screen entered upgrade mode with Fn, X, 0, 6. It showed "Bootloader V2.30.156, Flash ID GD5F1GQ4".
  - Parallels passed it to Windows as "Vendor EEEF – Communication". It appeared as COM4 (`\Device\USBSER000`).
- **What failed:** the screen reset tool's Start button stayed disabled.
- **Why, from AULA's ISP tool code** (Revisory676's unpacked `.text`; disassembled offline, nothing run):
  - A timer slot (`getDevice`) scans `QSerialPortInfo::availablePorts()` for VID `0xEEEF` / PID `0x268A`.
  - It opens the port, 8N1 with no flow control, and sends a `0x30` connect command (routine `0x402c60` → `0x402880`).
  - It enables the button (`setDisabled(false)`) only when the screen answers.
  - A separate routine reads `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` for the value `\Device\USBSER000`.
  - So the screen's reply never reached the tool. The cause is either Parallels' USB passthrough or the x86 tool running under Windows-on-ARM emulation.
- **No workaround:** Apple Silicon Parallels VMs are fixed at USB 3.0 (`prlctl list -i`: "Support USB 3.0: on", with no UI toggle).
- **Decision (Alison):** use a real Windows PC for the restore.
- **Nothing was written.** Switching the keyboard off and on leaves upgrade mode.
- **Flash chip:** this unit has **GD5F1GQ4** (GigaDevice SPI NAND), not the W25N01GV that softce saw. The reset tool chooses the control-program version by flash ID.

## Mac-driven screen research (Phase 3, Nov 18)

Question: can the Mac drive more of the screen live, instead of only swapping art in fixed positions? Sources: softce `docs/architecture.md` and `docs/protocol.md`, miniz's evidence inventory, and AxiraDev `reverse/PROTOCOL.md`. Also the sample UI_Editor-II project in gavindi's `LT168A_UIEditor-II_Function_NOR_320x240_V2.30.rar`. Only its text files (`DisplayWidget.csv`, `TouchWidget.csv`, `SerialPortCommands.csv`, `Plugin/*.cfg`) were extracted, to the scratchpad; nothing was run. Levetop's `LT_UartTFT_AP Note_V10_ENG.pdf` turned out to describe the first-generation system (`AA … E4 1B 11 EE` frames), so it is lineage only.

**Correction:** on the cable, the Mac *does* talk to the screen directly. The screen is its own USB serial device (`EEEF:268A`), and the photo uploads already use it. Only taps go through the keyboard.

**Runtime variables (RAM, no flash writes)** [softce HW on a modified UI; sample-project CRCs match our CRC16]:
- Short frame: `5A A5 | len u8 | body | CRC16/MODBUS LE`, where `len = len(body) + 2`.
  - Read body: `03 | word_addr BE16 | count BE16`.
  - Write body: `10 | word_addr BE16 | words BE16…`.
- softce wrote ASCII strings (8 words each) into text widgets. The values updated live on the screen without reopening the page, and the readback was verified.
- **System variables** (from the UI_Editor-II sample's `SerialPortCommands.csv`; not yet tried on the L99):

  | Address | Function |
  |---|---|
  | `0x7000` | Switch page |
  | `0x7001` | Brightness |
  | `0x7002`–`0x7008` | RTC year…second, refresh |
  | `0x700A` / `0x700B` | Play music / volume |
  | `0x700D` | Open popup window |
  | `0x700E` / `0x700F` | Auto-dimming / dimming level |
  | `0x7010` | Time to sleep |
  | `0x703F` | Language |

- UI_Editor-II widget kinds seen in the sample: icon (a variable picks the image), GIF, scrolling text, label (text from a variable), progress bar, and autoVar (a timer-driven variable that counts). Each is bound to a variable address. Touch widgets have a `WriteAddr` column, so buttons may be able to write variables. That's unverified.
- **No live pixel or framebuffer command is known** in either generation. Arbitrary live drawing isn't possible; live content means variables feeding widgets placed in the interface file.

**Taps** [softce: static analysis of HFD V2.3 and keyboard resource 4000, plus HW]:
- The screen sends `41 FF FF code_hi code_lo` over its internal UART to the keyboard.
- The keyboard's table (resource 4000 at `0x19D7C`) turns known codes into HID keys. Codes `0x30`–`0x40` become numpad keys (`0x3B` → usage `0x59`, NumPad 1, and so on). Media codes (`0x22`–`0x24`, play/pause, next/previous) become consumer keys (AxiraDev HW).
- Codes not in the table produce nothing. Getting F13-style keys would need a keyboard firmware change, which is ruled out.
- softce's working pattern keeps the numpad codes, draws new button art, and has a PC app catch those keys and run actions. That gives up the numpad keys on other keyboards while the app is active.
- If touch widgets can write variables, the Mac could instead poll them over serial (`03` reads) with no keystrokes at all. This is untested.

**What this means for Phase 3:**
- A custom interface file can use any layout and any tap areas.
- On the cable, the Mac can feed live values to it: text, numbers, image choice, bars, page switching and brightness.
- Taps reach the Mac as numpad or media keys, or possibly through variables.
- Everything still works without the Mac, minus the live values.
- Over the dongle there is no screen serial port, so only the stock relays (clock and stats) work.

**Revised for wireless daily use (Alison, Nov 18: the dongle day to day; the cable only for occasional installs; Bluetooth not supported).** The direct serial link exists only on the cable, so live RAM writes from the Mac can't be the everyday path. What still works wirelessly:
- **Mac → screen over the dongle:** only what the keyboard relays.
  - The clock and stats packet: CPU %, CPU °C, GPU %, GPU °C, three weather temperatures, weather code, humidity.
  - Music levels: 21 bands at about 75 frames/s.
  - The stock UI shows only some of these. A custom interface file could show all of them anywhere, in any style, if we know where the screen stores them in memory.
  - A spare field (for example the weather code, if it drives an image set) could carry our own states, such as focus or meeting, as long as both ends agree.
- **Screen → Mac:** taps turn into numpad and media key presses inside the keyboard, so they should travel over the dongle. That is unverified wirelessly.
- **Unchanged:** a custom interface file (layout, tap areas, pages) installs occasionally over the cable, or through Windows.

**Next tests (need approval):**
1. **Tap test, no writes at all.** On the dongle: open the Numpad page and tap keys into a text editor. Note which keys arrive, and whether the media buttons work.
2. **Memory map, one-time on the cable, read-only on the screen.** Send one stats packet with distinctive values for every field, including the ones the stock UI hides. Then read the screen's runtime memory (`03` reads) to find where each field lands. This tells a custom interface file which addresses it can bind to, for use wirelessly.
- **Both tests approved by Alison, Nov 18.**
  - Test 2's tool is built: `swift run l99probe memory-map` (with `--dry-run` to build frames only).
    - It sends only `03` reads, of words `0x0000`–`0x0FFF` and `0x7000`–`0x703F`, 16 words at a time. `L99Core/RuntimeMemory` has no write builder.
    - It takes snapshots before, after marker set A, and after marker set B, then sets the clock back.
    - It saves `l99probe-memory-map.json`.
    - Covered by `RuntimeMemoryTests`; all 49 tests pass.
  - **Run Nov 18 on the cable, stock UI, Real-time page open.**
    - Every read was answered; there were no errors and no freeze.
    - Raw snapshots are in `research/memory-map-2026-11-18.json`.

**Tap test results (Nov 18, 2.4 GHz dongle, stock UI)** [HW]:
- **Every Numpad key tapped arrived on the Mac over the dongle as a real numpad key**, logged in a browser key viewer: `Numpad0`–`Numpad9`, `NumpadDecimal`, `NumpadDivide`, `NumpadMultiply`, `NumpadSubtract`, `NumpadAdd`, `NumpadEnter`. That's 16 keys, all with location NUMPAD, so the Mac can tell them from the number row. A tap is about 80–100 ms from key-down to key-up.
- The page's 17th key (probably Num Lock or Clear, which browsers don't report) wasn't tested.
- Volume down, mute, volume up, play/pause, previous and next all worked on the Mac over the dongle (Alison). Those are consumer keys, so the browser viewer didn't log them, as expected.
- **So screen buttons can trigger Mac actions wirelessly.** A custom layout can reuse the 17 numpad codes and the media codes as its buttons. The Mac app catches the numpad keys and maps them to actions; the media codes keep their normal meaning.

**Memory map results (Nov 18)** [HW]:
- **A widget's variable number is its RAM word address.** The stats land at exactly the variables the catalog found on page 19. So any variable in the interface file can be read, and a custom layout can bind to any of them.
- **Stats from the clock/stats packet:**

  | Word | Field | Note |
  |---|---|---|
  | `0x0101` | Weather code | **Stored, but no stock widget shows it.** A custom layout can show a weather icon. |
  | `0x0103` | Air temperature | |
  | `0x0104` | Humidity % | |
  | `0x0106` | CPU load % | |
  | `0x0108` | GPU load % | |

  - CPU °C, GPU °C, day high and night low **are not stored** in either range, so the keyboard doesn't pass them on.
  - `0x0102` held `0x1B` (27) throughout and didn't follow the markers. That matches day high 27 from the earlier smoke test, but its meaning is unknown.
- **System variables match the UI_Editor-II sample:**

  | Word | Value read | Meaning |
  |---|---|---|
  | `0x7000` | 19 | Current page (Real-time Data) |
  | `0x7001` | 63 | Brightness |
  | `0x7002`–`0x7007` | 26-11-18 11:32:xx | Screen clock (year…second) |
  | `0x7008` | 3 | Weekday, Wednesday (inference) |
  | `0x700B` | 10 | Volume |
  | `0x700F` | 10 | Dim level |
  | `0x7010` | 60 | Sleep time |
  | `0x703F` | 1 | Language |

- **Top-bar status:** words `0x0001`–`0x0008` match the top-bar variables 1–8 (Win/Mac mode, connection, Caps, Num, battery level 0–6). Values read on the cable were: `0x0001` = 1, `0x0003` = 1, `0x0008` = 6.
- **Strings:** `0x004A`–`0x004D` hold "AULA L99", and `0x008A`–`0x008C` hold "V1.31".
- Other non-zero words are not yet understood (`0x0000`–`0x0029`, `0x00AB`–`0x00D0`, `0x0300`–`0x0310`).
- **Wireless data budget for a custom layout:**
  - from the Mac: the clock plus five values (weather code, air temperature, humidity, CPU %, GPU %), and the music spectrum;
  - from the keyboard and screen themselves: battery, connection, Caps/Num, Win/Mac mode, brightness and page.
- Dropped: the page-switch and brightness write tests. They only work on the cable, so they don't help daily use.

## Protocol reference (for the build)

### Devices

| Device | ID | macOS access | Notes |
|---|---|---|---|
| Keyboard, wired | `0C45:800A` | IOHIDManager. Match usage page `0xFF13` usage 1 with 64-byte feature reports (or probe for usage page ≥ `0xFF00`). Open **without** seizing. | Feature report ID 0, 64 B. The leading `04` is a command byte. |
| Dongle | `05AC:024F` | IOHIDManager, interface 3 vendor collection | 32-byte output/input reports. **Never match on VID alone** (05AC is Apple's VID). Product string "2.4G Dongle". |
| Screen | `EEEF:268A` | Find the `IOSerialBSDClient` whose USB ancestor has this VID:PID; use its `/dev/cu.*` | Raw mode, 8N1, no flow control. Baud is ignored (use 115200). |

Input Monitoring permission should not be needed for the vendor HID page [INF].

### Wired keyboard session (64-byte feature reports)
- Sequence: `04 18` (begin) → `04 <op> … [8]=nblocks` → data blocks (no ACK) → `04 02` → `04 F0` (only for persistent writes).
- ACK: bytes 0–1 echo the command, byte 3 = `01` (`FF` = busy).
- Leave about 35 ms between reports.

**Clock + stats, op `0x28`** (one block) [HW]:

| Byte | Field |
|---|---|
| 0 | `00` |
| 1 | view, must be ≥ 1 |
| 2 | `5A` |
| 3–8 | year − 2000, month, day, hour, minute, second |
| 10 | weekday, Sunday = 0 |
| 13 / 14 | CPU %, CPU °C |
| 15 / 16 | GPU %, GPU °C |
| 17 / 18 / 19 | air temperature, high, low |
| 20 | weather condition, 0–5 |
| 21 | humidity |
| 62–63 | `AA 55` |

The screen only shows the stats while the Real-time page is open. The vendor app streams the packet at about 1 Hz.

**Music, op `0x78`.** ⚠ The projects disagree, so the smoke test must settle it:

| Byte | gavindi [HW] | AxiraDev [HW] |
|---|---|---|
| 0 | rhythm style | spectrum scheme 0–11 |
| 1 | background mode | background scheme 0–11 |
| 2 | scale `0x64` | brightness 0–100 |
| 3 onward | 23 levels, 0–100 (panel shows 17) | 18 levels, 0–99 |
| 26 | background brightness | — |
| Frame interval | about 47 ms | 80 ms |

Both are plausible. 23 levels written in place of 18 just leaves trailing bands unused.

### Screen slots (serial)

| Base | Use | Size |
|---|---|---|
| `0x04060000`, `0x040C0000`, `0x04120000` | unknown | **never write** |
| `0x04180000` | Background | `0x60000` |
| `0x041E0000` | Photo frame | `0x60000` |
| `0x04240000` | GIF | factory blob is **26,005,628 B** (to `0x05B0D07C`), corrected Nov 17 (see below). **Our app caps at the factory size.** |

Static image format: an 11-byte header (`u32 LE pixel bytes`, `u16 w`, `u16 h`, `00`, `CRC16/MODBUS LE` of the pixels), followed by RGB565 LE row-major pixels. A 320×480 image is 307,211 B.

The vendor's photo upload, from the capture:
1. 150 × `0x64` writes of 2048 B at `0x041E0000 + i·0x800`;
2. `0x66` at `0x041E0000` with length `0x20000`, and again at `0x04200000` with length `0x20000`;
3. an 11-byte `0x64` write at `0x0422B000`;
4. `0x66` at `0x04220000` with length `0xB00B`.

### Factory content inside `UartTFT-II_Flash.bin` (for "Restore factory") — verified Nov 17

**Source.** Official package "L99 reset firmware 2026.5.25", downloaded from aulastar.com. Safari auto-unzipped it. Both EXEs match the researchers' SHA-256 hashes exactly:
- screen EXE `8d52849a…`
- keyboard EXE `0a946a5d…`

**Extraction.** The three payloads were sliced out of the screen EXE at softce's offsets, offline, without running anything. All hashes match. The files are stored read-only in `research/factory/`:
- `UartTFT-II_Flash.bin` (127,599,044 B, `4cb3fa5c…`)
- `HFD_Code_V2.2.bin`
- `HFD_Code_V2.3.bin`

Our own parse of the slot area:

| Base | Content | Header CRC |
|---|---|---|
| `0x04000000` | 320×480 wallpaper (red/blue texture) | ✅ |
| `0x04060000` | 320×480 wallpaper (blue/red gradient) | ✅ |
| `0x040C0000` | 320×480 wallpaper (red/navy arcs) | ✅ |
| `0x04120000` | empty | — |
| `0x04180000` (background) | **empty**: the factory default is a built-in preset, not this slot | — |
| `0x041E0000` (photo frame) | 320×480 AULA mascot (blue hair, goggles) | ✅ |
| `0x04240000` (GIF) | 171 frames, 320×480, fmt 3, delay field 50. **26,005,628 B (26.0 MB)**, ending at `0x05B0D07C` | ✅ TOC CRC16 |

PNG previews are in `research/factory/previews/`.

**Notes from the parse:**
- The header's size field counts pixels only (307,200), so 307,211 B per image includes the 11-byte header.
- `0x04000000–0x040C0000` are probably the wallpapers the screen's own background picker offers. That fits the slot table's "unknown" bases [INF].
- **Correction (Nov 17, Phase 1 build).** The first parse took the TOC's size field (26,002,208) as the blob size. That field counts the frames only; the 3,420-byte TOC (171 × 20) comes on top. The last frame ends at `0x05B0D07C`, and the TOC's CRC16 matches the frames over exactly that length. So the factory blob, and our GIF cap, is **26,005,628 B**. gavindi's reading of the field (frames only) was right.
- **The vendor's frame modes differ from gavindi's rule.** 167 frames are raw (`0x0002`), 2 are RLE (`0x0100`), and 2 use an unknown `0x0101`. Two RLE frames have content longer than `0xFFFF` (127,700 B), with the length field holding it mod 65536. Our decoder reads all of them. Our encoder keeps gavindi's hardware-proven rule (raw when RLE would exceed `0xFFFF`), so a re-encode isn't byte-identical; factory restore always sends the original bytes.
- **GIF region size.** The factory animation proves the panel stores and plays a 26.0 MB blob from `0x04240000`. That contradicts the ≈13.2 MB "vendor maximum" in gavindi's notes. The safe GIF cap is therefore the factory blob size, not 13 MB (see safety rule 1).

**"Restore factory" in Phase 1** = re-upload the photo-frame mascot and the 26 MB factory GIF blob byte for byte, through the normal slot protocol. Reset the background to the built-in preset. Fully Mac-native.

---

## Safety rules for our app (derived from the study)

1. **Allow only three write addresses**: the background, photo and GIF bases. Every write must satisfy `addr + len ≤ slot end`. Background and photo images must be exactly 307,211 B. GIF blobs are capped at 26,005,628 B, the size of the factory blob that is proven to fit and play.
2. **Never send arbitrary HID commands.** Allow only `0x28` (clock/stats), `0x78` (music) and the read-only dongle queries (`0x02`, `0x20`). No keymap (`0x11`), per-key RGB (`0x23`), settings (`0x17`) or `04 F0` persistent writes in Phases 1–2.
3. **Stop on any NAK or timeout.** Retry from the start of the slot, never mid-stream. If the port stops responding, guide the user to power-cycle the keyboard.
4. Before sending a GIF, **validate it against every known validator rule**.
5. **Never run the vendor EXEs on the Mac.** Never use AulaToolkit's S75 Pro screen path (op `0x72`), which writes 4096 × `FF` to probe collections.

---

## Safety review of each repo

| Repo | Verdict | Notes |
|---|---|---|
| **gavindi/Aula_L99_Linux** | Safe to read; don't run its packaging. | No network calls in the Python tools. `make_deb.sh` installs udev rules and runs `udevadm`. `make_appimage.sh` curls appimagetool. CI pipes `curl … \| sh`. `documentation/*.zip/*.rar` contain untrusted Windows EXEs and DLLs (Levetop UI editor). **Dangerous CLI flags:** `--force-address`, `--force-size`, `--ignore-nak`, `--send-hex` (persistent keyboard opcodes `0x23/0x11/0x17`). |
| **miniz3210/aula-l99-controller** | Reading is fine. **Don't run** its device scripts. | `push_solid_color.py`, `replay_captured_screen.py` and `replay_solid_*` write raw flash at hard-coded addresses (COM8 default). A staging script runs `rm -rf "$EVIDENCE_DIR"`. The local companion HTTP server is bound to 127.0.0.1. No outbound network, no binaries. |
| **softce/aula-l99-research** | Low risk. | Offline tools only: a hash-locked extractor, parser and codecs. No serial, USB or network access. |
| **AxiraDev/L99ForMac** | Low risk; best reference for macOS. | No network, telemetry, updater or privileged helper. Only external link is a Boosty donation link. Persistent keymap writes are guarded by read-back. Hidden CLI flags write without the UI (`--upload-screen`, etc.). The GIF capacity bound (≈61 MB) is unsafe; don't copy it. GPLv3 (fine for private use). |
| **Revisory676/aula-l99-linux** | Mostly a gavindi fork; low value beyond dongle hints. | Same risks as gavindi. Its own dongle additions are untested and have bugs: settings packets clobber other state, and the "online" check gives false positives. `re_notes/system_monitor_block.md:100` contains a vendor weather API URL with an embedded token. **Do not call it.** `documentation/Firmware/.enigma2` is a PE fragment; don't run it. |
| **Salamor/aula-l99-open-widgets** | Harmless. | Docs and pcaps only, no code. Its README protocol belongs to another device. |
| **livvaa/AulaToolkit** | Read only; never install. | Windows Electron app with auto-update from GitHub. Runs PowerShell, `taskkill`s vendor processes, **renames vendor EXEs in Program Files via an elevated helper**, and creates a Task Scheduler autostart. `factoryReset` overwrites keymaps, macros and lighting. Its S75 Pro screen path is destructive on other HID collections. |

---

## Open items carried into the smoke test (PRD step 3)

1. Does a static upload to the photo slot render after leaving and re-entering the page? Do the CRC32 replies match?
2. Record the screen's About-page version (expected "V1.31") and the dongle's session-init byte 11.
3. Over the dongle:
   - Does the clock-only packet actually change the panel?
   - Do the stats show up with the "+3" layout, and with the "+4" layout?
   - Does any music path exist?
4. Battery query over the dongle.
5. Which music block layout (gavindi's 23 levels or AxiraDev's 18) renders correctly over the cable.
6. ~~Obtain AULA's official L99 reset package.~~ Done Nov 17: the package is verified and the factory files are extracted (see "Factory content").
