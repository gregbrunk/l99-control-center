# Hardware Smoke Test (PRD step 3)

**Goal:** answer Q1 (what works over the 2.4 GHz dongle) and Q8 (which upload protocol *this* keyboard uses) on real hardware, at the lowest possible risk. Protocol details are in `FINDINGS.md`. Allow about 30 minutes.

## Before starting
- [ ] Keep the Windows machine available as a fallback. It isn't needed unless something goes wrong.
- [ ] Note the version shown on the screen's About page (expected "V1.31").
- [x] AULA reset package downloaded, checksums verified, and factory files extracted to `research/factory/`.
- [ ] Charge the battery above 50%, so a power cycle never happens on a flat battery.
- [ ] Quit any other keyboard software.

## The tool: `tools/l99probe`

`l99probe` is a small Swift command-line tool written for this project. No code was copied from the research repos. Every command does one fixed job, and there is no way to send arbitrary bytes.

**Hard limits in the code:**
- **Screen:** the only address it can write is the photo-frame slot (`0x041E0000`), and only a complete 307,211-byte image. It stops on the first unexpected reply. After each 128 KiB, it compares its own CRC32 with the screen's CRC32.
- **Keyboard:** it sends only clock/stats (`0x28`) and music (`0x78`), plus the session begin/commit around them. All of these are temporary and survive no restart. There are no keymap, lighting, settings or "save to flash" commands.
- **Dongle:** it sends only the read-only version and battery queries, plus the temporary clock packet.

17 offline unit tests check the packets byte for byte against the captures, the fixtures and the verified factory image.

To build it once, open Terminal:
```bash
cd "/Users/greg/Documents/L99 Control Center/tools/l99probe" && swift build -c release
```
Then run commands from that folder as `.build/release/l99probe <command>`. Add `--verbose` to see every byte. Add `--dry-run` to see what would be sent without touching the keyboard.

> If macOS refuses to open the keyboard, an error will mention Input Monitoring. Grant it to Terminal in System Settings → Privacy & Security → Input Monitoring, then rerun.

## Part A: USB cable connected, keyboard switched on

**A1. See what's connected.** This sends nothing.
```bash
.build/release/l99probe list
```
✅ Expect the `0C45:800A` keyboard with a line marked `← settings channel`, and a screen port like `/dev/cu.usbmodem…`.

**A2. Upload the test card to the photo frame.** It asks you to confirm first and takes about 20–60 s.
```bash
.build/release/l99probe photo --testcard
```
✅ Expect three `check … ✓` lines and "Upload complete". Then leave the Photo Frame page and open it again: you should see the colour bars, "L99 PROBE" and the time of the upload.

Record how many write replies contained "OK", and whether the image appeared without a power cycle.

**A3. Clock.** First set it deliberately wrong, then correct it:
```bash
.build/release/l99probe clock --offset-min 123
```
```bash
.build/release/l99probe clock
```
✅ The screen's clock jumps forward about 2 hours, then returns to the correct time.

**A4. Stats.** Open the Real-time page on the screen first.
```bash
.build/release/l99probe stats
```
✅ Expect CPU 42% / 61°, GPU 17% / 55°, and weather 23° (high 27°, low 12°, humidity 45%).

**A5. Music.** Open the Play page first. Run each layout:
```bash
.build/release/l99probe music gavindi
```
```bash
.build/release/l99probe music axira
```
For each, note whether the bars moved as a smooth travelling wave, and how many bars moved.

## Part B: cable unplugged, keyboard on the 2.4 GHz dongle

Before starting, run A3's `--offset-min 123` command so the clock is visibly wrong. Then unplug the cable and switch the keyboard to 2.4 GHz. Press a key so it's awake.

**B1. Check connections:**
```bash
.build/release/l99probe list
```
✅ Expect `05AC:024F` with a line marked `← vendor channel`. The screen port should be gone.

**B2. Version and battery** (read-only):
```bash
.build/release/l99probe dongle-info
```
Record byte 11 (gavindi saw `0x29`) and the battery %.

**B3. Clock over the dongle:**
```bash
.build/release/l99probe dongle-clock
```
❓ Does the screen's clock snap back to the correct time? **This decides whether a minimal Phase 2 (clock sync without the cable) is possible.**

**B4. Stats over the dongle.** Open the Real-time page first, then try both candidate layouts:
```bash
.build/release/l99probe dongle-stats plus3
```
```bash
.build/release/l99probe dongle-stats plus4
```
❓ Do the test values (CPU 42%, GPU 17%…) appear with either layout? **This is the Phase 2 go/no-go.**

**B5. Music over the dongle.** No candidate packet exists, so record it as "cable-only (no known path)".

## Part C: Restore

Plug the cable back in. Either keep the test card or restore the factory mascot:
```bash
.build/release/l99probe photo --factory
```
Nothing else was changed permanently. Everything sent in A3–B4 is temporary.

## If something goes wrong
- **Upload stops with an error, or the screen freezes:** switch the keyboard off, unplug the cable, wait 5 s, plug it back in, switch on, and rerun the same command. The tool stops at the first problem, so at worst the photo slot is half-written, and a resend fixes it.
- **The photo frame looks garbled:** run `photo --factory` or `photo --testcard` again.
- **Anything worse:** use the Windows fallback. Run AULA's screen reset program from `research/L99 reset firmware 2026.5.25/` with the keyboard in upgrade mode. Hold Fn and press X, 0, 6; if that fails, hold Fn + Space for about 5 s with USB connected.

## Results
Paste the terminal output from each step, or fill this in, and I'll update the PRD (step 4).

| Step | Result |
|---|---|
| A1 devices (Nov 17) | ✅ Keyboard `0C45:800A` ("AULA L99", SONiX) with four HID collections: keyboard `0001:0006`, consumer `000C:0001`, **settings `FF13:0001` (64-byte feature)**, and `FF68:0061` (4096-byte output, unused). Screen `EEEF:268A` "Generic CDC" at `/dev/cu.usbmodem1201`. All match the research. Works through the USB hub (1A86:8091) once connected properly. |
| About-page version | |
| A2 photo upload: checks ✓? "OK" count? shown without power cycle? | ✅ Protocol confirmed: 151/151 writes answered "OK"; all 3 device CRC32s matched (D169AA14, F85C6E7F, D04370B9); 0.8 s total. Display: ✅ test card shown after leaving and re-opening the Photo Frame page (no power cycle needed). |
| A3 wired clock | ✅ Sending a clock 123 minutes ahead made the screen show 23:09; sending the correct time set it back. All ACKs were `04 xx 00 01`. Op 0x28 with view 1 confirmed. |
| A4 wired stats | ✅ Every field the page has updated: time, date (2026/11/17), weekday (Tue), **air temp 23 °C (byte 17)**, **humidity 45% (byte 21)**, **CPU 42% (byte 13)**, **GPU 17% (byte 15)**. The stock Real-time page has no fields for CPU/GPU temperature, high/low or a weather icon, so bytes 14, 16, 18–20 are not displayed. Values persist from a single packet; no streaming needed. Top bar (Q4): time · `MAC` mode · connection icon (cable/wave) · lock · `A` Caps · `1` Num · battery 78% with charging bolt. |
| A5 music: gavindi / axira, number of bars | **gavindi ✗**: its leading bare commit (`04 02` with no session open) was answered `04 02 00 FF` (busy/refused), so the tool stopped. **axira ✅**: `04 18` → `04 78 [8]=1` → block → `04 02` all ACKed. All bars moved as a travelling wave. It looked a little jumpy at about 3.5 frames/s (four reports per frame with 35 ms gaps); the app needs a faster path. **Side effect:** the key LEDs switched to an audio-reactive rainbow while frames were arriving. Block bytes 0–2 (`02 00 23`) probably select the key-lighting music scheme and brightness, not only the panel's. The LEDs returned to the user's normal effect on their own once frames stopped. |
| B1 dongle devices | ✅ `05AC:024F` "2.4G Dongle" with five collections: keyboard `0001:0006`, mouse `0001:0002`, consumer `000C:0001`, `FF59:0061` (64/64), **`FF60:0061` (32-byte input/output) = vendor channel**. Screen serial absent, as expected. |
| B2 dongle byte 11 / battery % | ✅ Session-init reply `02 00 00 40 30 00 00 45 0c 0a 80 31 01 ff ff …`; **byte 11 = 0x31** (gavindi's unit: 0x29), so this receiver is a newer build. Battery query works: **80%**. |
| B3 dongle clock | ✅ **Works without the cable.** The prior-art packet `0c 10 00 00 01 5a YY MM DD hh mm ss 00 WD 00 00 00 aa 55 …` was ACKed (`0c 10 00 … 1c`), and the screen's clock jumped from about 23:2x back to 21:20. |
| B4 dongle stats: plus3 / plus4 | ✅ **plus3 works.** Packet `0c 10 00 | 00 01 5a YY MM DD hh mm ss 00 WD 00 00 | CPU% CPU° GPU% GPU° AIR HI LO COND HUM | aa 55 | 00… | cksum`, i.e. the cable block shifted +3 with the trailer at 25–26. The page showed CPU 33%, GPU 66%, 13 °C and humidity 31%, exactly as sent. plus4 not needed, so not tried. |
| B5 dongle music | ✅ **Works.** Packet found offline in AULA's `DeviceDriver.exe`: `0B 1C 00 \| fore back amp \| 21 levels \| 00×4 \| cksum`. `l99probe dongle-music --seconds 30` sent 2,242 frames (≈75 fps); all bars moved, very smooth; the key LEDs showed a wave and then returned to normal. |
| **Verdict** | **Phase 2 is GO over 2.4 GHz for clock and stats.** Music over the dongle also works (B5), smoother than the cable. Battery % is readable wirelessly. |
