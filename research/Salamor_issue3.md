# L99 + AULA driver v1.06: image upload uses a different protocol (5A A5 framing, CRC16, no JPEG)

Hi, I have an AULA L99 and captured the official driver (v1.06, Windows) with Wireshark + USBPcap while uploading a picture to the screen. My capture does not match the format in the README, so I'm sharing what I found.

l99_screen_only_5aa5.pcapng.zip

[l99_screen_only_5aa5.zip](https://github.com/user-attachments/files/33702156/l99_screen_only_5aa5.zip)

Setup
- Keyboard: 0C45:800A (HID). Screen: EEEF:268A (CDC serial). Both confirmed in the captured descriptors, on the same USB controller.
- Capture attached: l99_screen_only_5aa5.pcapng (filtered to the screen device and the keyboard's non-boot interface; no typed keys).

What I saw on the screen's COM port (bulk OUT)
- Searching the capture for 12 34 56 78 finds nothing. Every packet starts with 5A A5.
- Frame layout: 5A A5 | length (3 bytes, big-endian, = bytes after the length field) | command | payload | CRC16
- CRC16 is CRC-16/MODBUS (poly 0x8005, init 0xFFFF, reflected, xorout 0), computed over command + payload, stored little-endian. It matched 540 of 540 outgoing packets.
- Command 0x64 (write): payload = 04 | 3-byte big-endian address | 2048 bytes of data. The address goes up by 0x800 per chunk, which looks like writes into on-device memory rather than a live frame push. That is my interpretation, not confirmed.
- Command 0x66: short 16-byte control frames between writes. I don't know what they do yet (maybe erase/finalize).
- The screen replies after every chunk, and the replies contain ASCII "OK".
- The first data bytes contain 40 01 and e0 01 (320 and 480). The rest does not look like plain JPEG.

Keyboard side (HID, 0C45:800A)
- When the driver starts it sends 64-byte feature reports (SET_REPORT, report ID 3). One of them contains 5A 1A 0A 14 05 1E 3B ... AA 55, which looks like a date/time sync (26-10-20 05:30:59, matching when I captured it).

Touch
- In a separate capture with the driver open and me tapping the screen, the COM port carried no data from the screen (only empty polls). No touch events there.
- The L99 also has a mouse option for the screen. In my capture the keyboard's interface sent 207 small relative-movement style reports (report ID 6). I think this is touch sent as mouse movement over HID, but I haven't confirmed it and will capture it separately.

Questions
- Which driver/firmware version did the 12 34 56 78 captures come from? Mine is driver v1.06. Maybe the protocol changed between versions, or this is the "upload to keyboard" feature and the other is the live push.
- Is there a capture of the live push I could compare against?

Happy to run more captures (brightness, screen on/off, mouse mode touch). Tell me what's most useful.

