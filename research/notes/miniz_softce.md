# Agent report: miniz3210 + softce (condensed key facts)

- Vendor .bin/.exe/captures NOT in either repo (hash manifests only); claims come from their docs/parsers.
- Controller: Levetop LT168-family strong inference (HFD_Code disassembles as M*Core LT168 map, V2.3 base 0x60010000). Not vendor-confirmed. (gavindi says LT168B from schematic.)
- Three firmware parts: keyboard MCU SN32F290-class; screen MCU HFD_Code_V2.2/2.3; screen resources UartTFT-II_Flash.bin.

## Q2 interface write / recovery
- Official tools Windows-only: screen reset EXE (194,946,048 B Enigma Virtual Box) containing MinGW Qt5.12 ISP tools (L99 ISP V1.23.exe, HFD_ISP_TOOL_V1.31.exe), Qt5SerialPort, VID/PID filter.
- Transport = CDC serial EEEF:268A, not DFU. ISP packet: 4A 30 | offset LE32 | len LE16 | payload<=2048 | CRC32 LE (reflected IEEE, init 0, xorout 0). Boot packet 6C… unverified. 6D 01 flash-ID query (0x00EFAA21 = W25N01GV) picks HFD V2.2/2.3 (disputed by miniz).
- Update mode: AULA says Fn+X→0→6 (failed for softce); Fn+Space ~5 s with USB connected worked.
- Updater sends whole 127,599,044-byte image; host FileCRC vs device FlashCRC. No arbitrary readback.
- softce flashed UI-only (HFD_ISP_TOOL_V1.31.exe + UartTFT-II_Flash.bin, no HFD_Code) successfully on hardware.
- No native/open re-implementation of ISP erase/program/finish. Mac route today = Windows EXE (VM w/ USB passthrough untested).
- Reset package ZIP 45,080,624 B (sha e854bebb…): screen reset EXE (UartTFT-II_Flash.bin + HFD_Code_V2.2/2.3 at fixed offsets) + keyboard reset EXE (SN32F290.hex + PE resource 4000, 256 KiB). softce has an offline hash-locked extractor. Not a NAND dump.
- Recovery after failed screen write: NONE proven. Only data point: keyboard reset EXE fixed garbled typing.
- Full image includes user slot region → full restore likely overwrites user photos/GIF (inference).

## Interface file structure (sha 4cb3fa5c…)
- Header 22×u32; variables 0x11DD0; 30 page records 0x21DD0 (12 B <IHIH); display/touch blocks [0x21F38,0x251A5); fonts 0x251A5; sounds 0x2F4349; animations 0x34551C; 30 bg descriptors 0x5C008E (all empty: size 0 fmt 16 — artwork comes from icons); 2 banks × 569 icon descriptors 0x622A84 (EN + CN); project 0 ends 0xA355EC; 56 MB zero gap to 0x04000000; four 320×480 images at 0x04000000/0x04060000/0x040C0000/0x041E0000; 171-frame animation 0x04240000–0x05B0D07C; three identical extra projects to EOF (purpose unknown).
- Display record: u16 type, u16 param_addr, u8 len_flags, payload. Touch record: u16 type_flags, u8 len_flags, payload; type 1 = x1,y1,x2,y2,return,icon_up,icon_down,goto_page.
- Widget type 3 = variable→icon range (var,x,y,first_icon,last_icon,min,max): 310 records on 28 pages. Type 5 = animation. Type 4 unresolved.
- Page 21 Mini Numpad: 11 display + 18 touch records: 17× 0xC001 return codes 0x0030–0x0040 goto 65535, + 1× 0x8001 Home (0x0020, goto page 1). E.g. NumPad 1 = 0x003B rect [13,337,79,403] icons 341/342. Keyboard maps code→HID usage via table 0x19D7C in resource 4000.

## Q4 top bar: likely live type-3 widgets stored per page (movable layout data). Page 1 var 8 at (277,11) icons 14–20 values 0–6 repeated on most pages = likely battery. Two-state ranges [1–2],[3–4],[5–6],[7–8],[9–13] consistent with connection/Caps/Num. Which variables drive them: unknown (set by control program). softce moved analog clock (page 26) via page data → positions live in records.
## Q5 volume module: unresolved; softce edited its artwork as icon bitmaps. Volume keys likely consumer 0xE9/0xEA/0xE2.
## Q6 pages: count fixed at 30, referenced by index. Only unlinking proven (softce changed goto at 0x22088 from 21→15, repurposed page 21). Recommendation: keep all 30 records, redirect goto_page only.
## Q7 artwork: descriptor 12 B (u32 offset, u16 w, u16 h, u24 size, u8 fmt). Formats 0/1 RGB565 LE, 2 ARGB4444 LE, 3 "LT" palette container. No PNG/JPEG. Patch both language banks. No global checksum found; CRC16/MODBUS only on 4 user images + animation. softce's LT encoder → stripes on device, prefer raw ARGB4444. Equal-size in-place replacement needs no table edits. New art into reclaimed unreferenced pools.

## Runtime widget protocol (short 5A A5): 5A A5 | len u8 | body | CRC16/MODBUS LE, 115200 8N1 DTR/RTS off. Read 03 addr BE16 count BE16; write 10 addr BE16 words…, <=8 words/frame. softce used it on hardware with custom UI vars 0x0600–0x0639. Only variables the UI defines.
## Q3 readback: candidate SDK opcode 0x65 (extended read 1–2048 B) — not tested on L99.
## Q8 captures: extended frame 5A A5 00 | len BE16 | op | addr BE32 | data | CRC16 (1269 packets validated). Photo upload: 150× 0x64 2048 B at 0x041E0000+i·0x800; 0x66 arg 0x20000 at 0x041E0000 and 0x04200000; 11-byte 0x64 at 0x0422B000; final 0x66 at 0x04220000 len 0xB00B. No firmware-version method; About page shows "V1.31".
## Safety: softce offline tools only, low risk. miniz: device-writing scripts (push_solid_color.py, replay_*) hard-coded addresses, COM8 — don't run. Oversized writes ACKed and overwrite adjacent flash. Write timeout wedges endpoint until power-cycle. Companion HTTP 127.0.0.1 only. A staging script runs rm -rf $EVIDENCE_DIR. No outbound network.
