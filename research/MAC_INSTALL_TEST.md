# Mac skin-install test (plan, not yet run)

**Question:** can the Mac write skin artwork straight into the screen's interface area, using the same upload command it already uses for photos? If it can, skins install in seconds from the Mac, and Windows is needed only for emergencies.

**Status:**
- Plan approved by Alison on Nov 18. That approval covers exactly the writes below.
- The tool is built and unit-tested, and dry runs pass. Nothing has been written yet.
- **Still waiting on the Windows restore test.** Don't run any step until it has passed.

## Why it might work

- The photo upload writes with command `0x64` at `0x041E0000`. That is the same offset where the photo sits in `UartTFT-II_Flash.bin`. So the screen's upload addresses are positions in the interface file (see FINDINGS.md, "Screen catalog").
- The vendor always writes whole, aligned 128 KiB blocks and checks each one with `0x66`. This test does exactly the same, just at a lower address.

## Unknowns this test answers

1. Does the screen accept `0x64` below `0x04000000`, or refuse it?
2. Does a rewritten block read back correctly (the `0x66` CRC matches)?
3. Does the new art show after leaving and re-entering the page, or only after a power cycle?

## Target: block `0x3B` (`0x00760000`–`0x0077FFFF`)

- It holds only Mini Numpad key art: icons 330–342, shared by the English and Chinese banks.
- No other page uses anything in it. The catalog checked every display and touch record.
- **Worst case if a write goes wrong:**
  - Most likely, the Numpad page looks wrong. Rewriting the stock block fixes that from the Mac.
  - If the screen won't start at all, the Windows restore fixes it.
- It is far from the page and touch records (block `0x01`) and from the home screen art (blocks `0x31`–`0x32`).

## Tool

`l99probe ui-block-test stock|blue`, built on `L99Core/InterfaceBlockTest.swift` and tested in `InterfaceBlockTests`. Hard rules, enforced in code:

- **Allowed address:** only block `0x3B`. It has its own one-entry allowlist; the photo, background and GIF slot list is untouched.
- **Write size:** exactly `0x20000` bytes, aligned to the block.
- **Source file:** it must be the stock file (SHA `4cb3fa5c…`).
- **Allowed changes:** the bytes may differ from stock only inside icon 341's pixel data (`0x77C446`, 8,978 bytes; the Numpad "1" key, normal state).
- **Sequence:** the same as an upload. 64 writes of 2048 bytes, then one `0x66` check of the block.
- **On a NAK, timeout or CRC mismatch:** stop. Never resume in the middle of a block.
- **No standalone `0x66`.**

## Steps

Run from `tools/l99probe`:
- **A:** `swift run l99probe ui-block-test stock`. Expected CRC `934FEC38`.
- **B:** `swift run l99probe ui-block-test blue`. Expected CRC `7228C127`.
- **C:** `swift run l99probe ui-block-test stock` again.

Add `--dry-run` to any of these to build the block and save a picture of the "1" key without touching the keyboard.

Before starting:
- Keyboard on the cable.
- AULA's driver closed.
- The Windows PC and the reset package within reach.

**A. Rewrite the block with its own stock bytes** (no visible change)
- **Pass:**
  - every write is acknowledged with OK;
  - the `0x66` CRC equals the stock block's CRC;
  - the Numpad, Home and Play pages look normal;
  - after a power cycle, they still look normal.
- **If the first write is refused:** the screen doesn't allow writes there. Stop. Nothing was changed, and the answer is "Windows only".

**B. Write the block with the "1" key tinted blue**
- **Pass:** the CRC equals the modified block's CRC, and the Numpad's "1" key turns blue.
- Note whether the change showed after re-entering the page or only after a power cycle.

**C. Put the stock block back**
- **Pass:** the "1" key is grey again and the CRC equals stock.

## If something goes wrong

| What you see | What to do |
|---|---|
| Screen frozen | Switch the keyboard off and on, then re-run C. |
| Numpad page garbled | Re-run C. |
| Screen doesn't start | Run the Windows restore, then re-send the photo and GIF from the Library. |

## What a pass unlocks

- The app can install skins by writing only the changed art blocks, after a preview and a proof that nothing else changed.
- Hiding apps also changes the page and touch records in block `0x01`. That block controls every page, so it gets its own separate test later. Until then, the hide/show feature would need a Windows install.
