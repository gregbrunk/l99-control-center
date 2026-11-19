# L99 screen bootloader (ISP) protocol

This is the route for installing interface files from the Mac.

**Sources:**
- The disassembly of AULA's `L99 keyboard Screen reset firmware (…).exe` (2026.5.25 build), read offline and never run. Its `.text` is byte-identical to Revisory676's `documentation/Firmware/.text`.
- **A USBPcap capture of a full restore on Alison's real PC (Nov 18).** The file is `l99-restore.pcapng`, 168 MB, in Alison's Google Drive and not copied into the repo. It is the authority wherever it and the disassembly disagree.

**Status:** the protocol is confirmed byte for byte by the capture. The Mac's read-only probe and restart work (Nov 18). The Mac hasn't written to flash yet.

## Link

- **Bootloader mode:** Fn, X, 0, 6. The screen shows "Bootloader V2.30.156, Flash ID: GD5F1GQ4". The device is USB CDC serial `EEEF:268A`, the same IDs as normal mode.
  - Bulk OUT is endpoint `0x03`; bulk IN is `0x82`.
  - The baud setting is virtual. The tool first opens at 115200, then reopens at 921600 (handshake byte 16 changes from `08` to `7F`).
- **Replies are 63 bytes.** Byte 0 is the reply type.
- **CRC32** uses the standard reflected table (poly `0xEDB88320`), but with **init 0 and no final XOR**. In Python that is `zlib.crc32(d, 0xFFFFFFFF) ^ 0xFFFFFFFF`. All multi-byte fields are little-endian.
- Commands are 64-byte zero-padded packets, except the data packets.
- The keyboard runs one command at a time. Each packet gets its own reply, normally within 3–6 ms.

## Commands

| Cmd | Packet | Reply | Meaning |
|---|---|---|---|
| `4B` | `4B cc 4C 54 · nonce(4) · auth(4) · E8 17 00 00 · 7F`, then pad to 64 | `4B · auth(4) · … · info` | Handshake and target select. `cc`: `30` = hello, `31` = control-program flash (**never**), `32` = interface flash. |
| `6D` | `6D 01 00` | `7D C8 D1 C8 00 68 97 …` | Read the flash ID (GD5F1GQ4). |
| `6F` | `6F 02` | `7F` | Flash addressing mode for the 128 MB chip. |
| `6C` | `6C · offset(4) · toggle(1) · len(2) · data(len) · CRC32(4)` | `7C tt` | **Write data.** Not padded: `len+12` bytes. The CRC covers bytes `0 … 8+len`. `tt` echoes the toggle byte. |
| `6E` | `6E 00 00 00 00 · size(4) · fileCRC(4) · CRC32(bytes 0–12)` | `7E 30 · pos(4) · runCRC(4)`, repeated, then `7E 31 …` | **Read-back check** of the whole interface area. |
| `4F` | `4F · 00 80 00 08` + zeros · `CRC32(bytes 0–11)` at byte 12 | none (the screen restarts and enumerates again) | Run the firmware at `0x08008000`. |
| `4C`/`4A`/`4E` | | | **Control-program phase only.** It prepares (size `0x4C934`), writes 2 KB `4A 30` packets and finishes. We never send these. |

### Handshake (`4B`)

- **Request:** `auth` = CRC32(`4B cc 4C 54 nonce key`), where `key` is LE32. The nonce is any 32-bit value; the tool derives it from the clock.
- **Reply:** bytes 1–4 = CRC32(`4B cc 4C 54 nonce key "POTL"`).
- **Alison's keyboard uses key `0x1971168B`.** That is not `…268A`, as the disassembly had suggested. In the capture, the tool sent its first guess (`1971168A`) and the screen answered authenticated with `1971168B`. The tool then used `1971168B` for every later command, so the reply tells you the right key.
- **Reply bytes 9–18** were the same in every reply: `01 16 09 25 · 81 00 BA EE · 50 4F`.
  - **Timing mode `EEBA0081`:** the tool waits 50 µs after each data packet.
  - **Bytes 17–18 are not `56 76`,** so the plain `6C` write format is used. This is confirmed.
  - Bytes 30–31 = `78 87`.

## Interface install, exactly as captured

| Time (s) | Step |
|---|---|
| 0 – 14.3 | Hello, then the control-program phase (`4B 31`, `4C`, 153 × `4A`, `4E`). **We skip all of this.** |
| 14.60 | `4B 30` hello, authenticated with `1971168B`. |
| 14.66 | `4B 32`: select the interface flash. |
| 14.72 | `6D 01 00`: flash ID. |
| 14.72 | `6F 02`: reply `7F`. |
| 14.75 – 286 | 62,305 × `6C` from offset 0 in 2048-byte steps, toggle 0/1/0/1… The last chunk is 452 bytes. Each one was answered `7C`; no retries. |
| 286.3 | `6E`: size `0x079B01C4` (127,599,044), file CRC `0x4DEEF87B`. |
| 286 – 309.5 | 975 progress replies, then `7E 31`. |
| 309.55 | `4F 08008000`: restart. |

- **Duration:** about 4.5 minutes of writing plus 23 s of checking. With the control program skipped, a Mac install should take about 5 minutes.
- **The data written is byte-identical to `research/factory/UartTFT-II_Flash.bin`** (SHA-256 `4cb3fa5c77eea973…`, the same size). So the file offset is the flash offset, and nothing is transformed on the way.

### The read-back check

- In each `7E 30` reply, `pos` is the read position, and `runCRC` = CRC32 of the file's first `pos − 0x20000` bytes. It runs one 128 KB block behind.
- **All 974 progress replies match the file.** The only exception is the final tail value, `0x6209D25F`, which isn't a plain CRC of the file. It is probably read past the end of the file inside the last flash block.
- The PC tool reported OK with that value. A Mac flasher should:
  - check every progress `runCRC` against the file (this covers everything except the last block);
  - treat `7E 31` as done.
  - For the stock file, the final value to expect is `0x6209D25F`.

## Mac tests (Nov 18)

- **Probe 1: handshake OK, then silence.** The port was left at 115200 while the handshake carried byte 16 = `7F`.
  - The screen answered that first handshake correctly, then never replied to `6D` or to any later command.
  - It recovered after a power cycle and bootloader re-entry. Nothing was written.
  - The PC tool sets the line to 921600 (SET_LINE_CODING) before any `7F` handshake. **Do the same.** On macOS that means `IOSSIOSPEED`, since there is no `B921600`.
- **Probe 2 at 921600: passed.** The handshake authenticated with `1971168B`, the info bytes matched, and the `6D` flash ID matched GD5F1GQ4.
- **Restart:**
  - A bare `4F` on a fresh connection was **ignored**: the port stayed `cu.usbmodemTEST_1_01`.
  - `4B 30` followed by `4F` on the same connection **worked**: the screen left the bootloader and normal mode came back (`cu.usbmodem11201`).
- **The port name tells you the mode:**
  - bootloader: `cu.usbmodemTEST_1_01`, product `USB_VCOM`, serial `TEST_1.0`;
  - normal mode: `cu.usbmodem11201`.
- **Install attempts: all stopped during setup; nothing written.**
  - Attempt 1 (bootloader re-entered after a `4F` restart): the very first `7F` handshake at 921600 got no reply.
  - Attempt 2 (a second connection after a probe in the same bootloader session): stopped at `6D`.
  - Attempt 3 (fresh entry, one connection): `08` hello at 115200 OK → `7F` hello at 921600 OK → `4B 32` OK → **no reply to `6D`**.
  - So `6D` answers after a plain hello, but not after `4B 32`. In the PC capture, it answers in both cases.
  - Each failure left the screen silent until a power cycle.
  - **Differences still to rule out:**
    - the Mac reused the same nonce across the handshakes in a session, while every PC nonce was different;
    - the line speed handling;
    - the timing.
  - Changed for the next try:
    - a fresh nonce for every handshake;
    - 10 s to wait for `6D`.
  - Attempt 4 (fresh entry, fresh nonce per handshake): `08` hello at 115200 OK → after switching the line to 921600, the `7F` hello with a new nonce got **no reply**. In attempt 3 the same step worked, but it reused the nonce, so its reply bytes were identical to the slow one.
  - Reading so far: the Mac's handling right after the line-speed switch is unreliable. Windows also differs in two ways:
    - it sets DTR/RTS low (`SET_CONTROL_LINE_STATE 0`);
    - it closes and reopens the port when it changes speed.
  - Next: capture the Mac side, or copy those two exactly. Stopped for the night with the screen in bootloader mode; a power cycle restores it.
  - Attempt 5 (Windows-style port: DTR/RTS low, reopened at 921600, clock nonces like AULA's): two `08` hellos at 115200 OK → reopened at 921600 → the `7F` hello got no reply.
  - Attempt 6 (slow speed only, `08` throughout, never switching): hello OK → **`4B 32` got no reply.** Listening for 4 s afterwards brought nothing, and a new hello with a 10 s wait got no answer either.
  - **Conclusion:** the line speed isn't the cause.
    - On the Mac, the bootloader answers the first one or two commands of a session, then randomly goes deaf until a power cycle.
    - Which command it dies on varies: `6D`, `7F` hello or `4B 32`.
    - The same sequence works on Windows.
  - **Main suspect: Apple's CDC serial driver** (`com.apple.driver.usb.cdc`) and how it frames or handles USB transfers. Examples: splitting a 64-byte command across USB packets, line-state requests, or IN-pipe handling. Without a USB capture of the Mac side, this is unproven.
  - **Proposed next step:** talk to the bulk endpoints directly through IOKit, bypassing the serial driver. The Mac would capture the device, which needs `sudo` once per install. That way every USB transfer is exactly 64 bytes, one per command, like the PC's.
- **Direct USB (`--direct`, L99USB C target, run with sudo):**
  - The device is captured from `com.apple.driver.usb.cdc` (`USBDeviceReEnumerate` with the capture bit, root only) and handed back afterwards. The screen stays in bootloader mode through the capture.
  - The link uses config 1. The comm interface is 0 and the data interface is 1. Bulk OUT is `0x03` and bulk IN is `0x82`.
  - It sends SET_LINE_CODING 115200 8N1 and SET_CONTROL_LINE_STATE 0, as Windows did. Every command goes out as one bulk transfer.
  - **First try, with a read issued only after each write: no reply** to the first handshake, even after a cold power cycle.
  - **Second try, with a bulk IN read always pending** (asynchronous, re-armed on completion), as Windows and AppleUSBCDC both do: **setup passed.** `08` hello OK → `4B 32` OK → `6D` = GD5F1GQ4. This is the first time `6D` has answered after `4B 32` on the Mac.
  - Takeaway: the bootloader seems to need the host's IN request already queued when it replies. It isn't certain why the serial-driver path was flaky, but the direct path with a pending IN works.
  - A second setup-only pass in the same bootloader session also worked, so the "one session per bootloader entry" limit was a serial-driver problem only.
- **Full stock install over direct USB: succeeded.**
  - Setup: `08` hello → `4B 32` → `6D` → `6F 02` → `7F`.
  - All 62,305 chunks were accepted on the first try: about 250 s to write, about 11 s to check (the PC took about 271 s and 23 s).
  - Every read-back progress report matched the file. The last report arrives at `pos = size + 0x20000` and carries `0x6209D25F`, the same final value the PC got. That value is **not** CRC32(file) (`0x4DEEF87B`), so the checker must skip that report (`end < size`, not `<=`). An off-by-one here made the first run stop with a false "mismatch" before sending `4F`; it's now fixed and tested.
  - The restart (`isp-restart --direct`: handshake, then `4F`) brought the screen back to normal mode (`Generic CDC`, `cu.usbmodem11201`).
  - **Use `--direct` for every install.** The serial-driver path isn't reliable.
- **First modified file (Nov 19): succeeded.** `skin-file blue-1` changed only icon 341 (the Numpad "1" key, 8,978 bytes, tinted blue) and left every other byte stock.
  - Installed with `isp-flash <file> --direct` in 262 s; every read-back report matched. Final value `E3584A70`; it differs from stock, as expected.
  - The screen restarted to normal mode by itself. Alison confirmed the "1" key is blue on the Numpad page and everything else is unchanged.
  - **So the control program accepts an edited interface file, with no checksum inside the file to update.** Skins can be built and installed entirely on the Mac.
- **Leave a gap between commands.** The Mac waits 60 ms before each command, matching the PC tool's spacing.

## Rules for the Mac flasher

- **Send only `4B 30`, `4B 32`, `6D`, `6F 02`, `6C`, `6E` and `4F`.**
  - Never send `4B 31`, `4C`, `4A` or `4E` (control program).
  - Never send `68` (an erase that the tool has but never uses).
- **Refuse to go on if any of these happen:**
  - the handshake doesn't authenticate;
  - the flash ID isn't `C8 D1 C8 00 68 97`;
  - the handshake info bytes differ from the capture;
  - `6F 02` doesn't get `7F`.
- **Write failures:** retry a chunk up to 3 times if the reply is missing, or isn't `7C` with the right toggle, then stop. Unlike the PC tool, the Mac version won't treat a timeout as success.
- **If anything fails,** the screen stays in the bootloader and the PC reset tool restores it (proven Nov 18).
- **Partial updates** (changed chunks only) may be possible, because offsets are free and the screen erases on its own, but they are untested. Version 1 writes the whole file.

## Where it lives in the EXE (image base `0x400000`)

| Address | Role |
|---|---|
| `0x402c60` | Open the port, key loop |
| `0x402880` | `4B` |
| `0x408190` | `6D` |
| `0x404680` | `6F` |
| `0x404750` | `68` (unused) |
| `0x4050e0` | `6C` |
| `0x404830` | Alternate format (unused on ours) |
| `0x407950` | `6E` |
| `0x403590` | `4F` |
| `0x408370` | Interface write loop |
| `0x408aa0` | Interface phase |
| `0x407100` | Control-program phase |
| `0x409570` | Start button |

Key table at `0x40e060` (`.data`). CRC table at `0x40f500`.
