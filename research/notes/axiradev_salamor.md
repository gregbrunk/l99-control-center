# Agent report: AxiraDev L99ForMac + Salamor (condensed key facts)

- AxiraDev screen upload == issue #3 v1.06 5A A5 protocol byte-for-byte. Salamor's own pcap contains the 5A A5 upload; Salamor README "12 34 56 78 + JPEG" protocol goes to a different USB device (87AD:70DB, 480x480 LCD, likely a cooler) — misattribution, NOT an older L99 protocol.
- No project does anything over the 2.4 GHz dongle. No firmware-version detection anywhere.

## CDC upload (macos/DisplayTransport.swift)
- Find IOSerialBSDClient whose USB ancestor is EEEF:268A, use /dev/cu.*; 115200 8N1 raw, no flow control.
- Request: 5A A5 | len u24 BE (cmd+params+crc) | cmd | addr u32 BE | data | CRC16/MODBUS LE (over cmd+params).
- Response: 5A A5 | len u8 | body | CRC16 LE. ACK body [cmd, FF]; result body [cmd, addr4, ...] ("OK" ascii seen). 3 s timeout, abort on mismatch, no retry.
- 0x64 addr data: write <=2048 B. 0x66 addr len u32: device returns CRC32 of region (sent after each 128 KiB); CRC32 reflected 0xEDB88320, init 0, no final xor; 9-byte result, crc in bytes 5..8.
- Slots: Photo 0x041E0000, Background 0x04180000, GIF 0x04240000 (0x60000 apart).
- Static image: 11-byte header (pixel len u32, w u16, h u16, type 0, CRC16 of pixels) + RGB565 LE; 320x480 = 307211 B.
- No refresh/commit command: user leaves and reopens Photo Frame page.
- GIF: per-frame ImageIO GIF quantize, then RGB565 truncation; per-frame palette of exact unique 565 colours (<=256). "LT" frame container: "LT" w h 01 03 size u32 + 516-byte table (len|0x01000000 RLE flag + 256 RGB565 LE) + indices or RLE (run-1, idx) runs<=256, RLE only if smaller. 20 B/frame GIF table; delays clamped 30–500 ms; max 200 frames. No dithering control. Static images truncated, no dither.
- RISK: GIF capacity bound 200*307220 ≈ 61 MB from 0x04240000; true region end unknown → overrun risk. 0x64 accepts any address. Cap GIF size conservatively.

## HID (keyboard 0C45:800A)
- IOHIDDevice match usagePage 0xFF13 usage 1 featureSize 64; open non-seized. Feature report ID 0, 64 B; leading 04 is a command. ACK: bytes 0–1 echo cmd, byte 3 = 01. 35 ms between reports.
- Transaction: 04 18 (enter) → 04 <op> with block count in byte 8 → raw blocks (no ACK) → 04 02 (end). Persistent writes add 04 F0.
- Clock/stats: op 04 28. Data: [1]=01 [2]=5A [3]=year-2000 [4..8]=mon day hr min sec [10]=weekday Sun=0 [13]=CPU% [14]=CPU°C [15]=GPU% [16]=GPU°C [17..19]=weather temps [20]=weather code [21]=humidity [62..63]=AA 55. Every 5 s; only shown while Real-time page open.
- Music: op 04 78. Data: [0]=spectrum scheme 0–11 [1]=bg scheme 0–11 [2]=brightness 0–100 [3..20]=18 levels 0–99. Sent every 80 ms.
- Hint: in kbd firmware 1.03 the keyboard MCU itself emits the screen UART spectrum frame 5A A5 17 62 00 12 [18 levels] CRC → HID commands may work via dongle if it forwards feature reports (speculative). Uploads need CDC = cable only.
- Dongle 05AC:024F MI_03 noted only as "unresearched; Apple VID, never VID-only match".

## Stats (macos/SystemMetrics.swift)
- CPU: host_statistics HOST_CPU_LOAD_INFO deltas. GPU: IORegistry IOAccelerator PerformanceStatistics "Device Utilization %". Temps: private IOHIDEventSystemClient via dlsym, usagePage 0xFF00 usage 5, sensor names pACC/eACC, PMGR SOC Die Temp, GPU MTR Temp (M1/M2 era; M5 unverified).
## Audio: Core Audio process tap (macOS 14.2+) CATapDescription global, private aggregate device; NSAudioCaptureUsageDescription; 2048 FFT Hann, 18 log bands 60 Hz–16 kHz.
## Safety: AxiraDev — no network/telemetry/updater/helpers; Boosty donation link only. Persistent keymap writes (with readback). Salamor — docs + pcaps only, nothing executable. GPLv3.
