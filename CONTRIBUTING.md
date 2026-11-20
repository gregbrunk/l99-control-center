# Contributing

Thanks for helping out. L99 Control Center talks to real hardware, so a few rules matter more here than in most projects.

## Ground rules

- **Never write the keyboard's firmware or the screen's control program.** Only volatile HID commands are sent. A change that writes keymaps, lighting or persistent settings won't be merged.
- **Skins edit only the screen's interface file,** inside the planned byte ranges. `SkinBuilder` checks this before saving; keep that check passing.
- **Don't commit vendor files.** AULA's driver, firmware dumps and `UartTFT-II_Flash.bin` stay out of git (see `.gitignore`).
- **No telemetry, accounts or auto-updates.**

## Building and testing

```bash
cd tools/l99probe && swift build && swift test
```

Then open `L99 Control Center/L99 Control Center.xcodeproj` in Xcode and run the app. Debug builds can draw any tab into a PNG without a keyboard attached; see "Building" in the README.

If your change touches anything that talks to the keyboard, say in the pull request what you tested on hardware (cable, dongle or both) and what you couldn't.

## Reporting bugs

Open an issue with your macOS version, how the keyboard was connected (cable or 2.4 GHz dongle) and what the screen showed. If the screen won't start, see the Recovery tab first.
