import Foundation
import L99Core
import L99Link

// l99probe — AULA L99 hardware smoke test (PRD step 3). See research/SMOKE_TEST.md.
// Every subcommand does one fixed thing. There is deliberately no raw-send mode.

let usage = """
usage: l99probe <command> [options]

  list                          Show matching HID collections and the screen serial port (sends nothing)

  Cable:
  photo --testcard              Upload a generated test card to the photo-frame slot
  photo <image file>            Upload any image (aspect-fill to 320×480) to the photo-frame slot
  photo --factory               Re-upload the factory mascot from research/factory/UartTFT-II_Flash.bin
  check --factory|--testcard    Ask the screen (0x66 only, no writes) whether the photo slot holds that image
                                WARNING: a 0x66 on its own (not right after writes) can time out and freeze
                                the screen until the keyboard is switched off and on. Avoid.
  gif-test [--delay N]          Upload a 4-frame test animation (per-frame palettes, delay field N, default 400)
  gif --factory                 Re-upload the 171-frame factory animation, byte for byte (about a minute)
  ui-block-test stock|blue      Mac skin-install test (research/MAC_INSTALL_TEST.md). Rewrites ONLY block 0x3B
                                (Mini Numpad key art): "stock" = the stock bytes (steps A and C), "blue" = the
                                Numpad "1" key tinted blue (step B). Run only after the Windows restore test passed.
  memory-map                    READ-ONLY map of the screen's runtime memory (FINDINGS.md, "Mac-driven screen
                                research"). Reads words 0x0000–0x0FFF and 0x7000–0x703F (03 reads only, never a
                                write), before and after two stats packets with marker values, and reports where
                                each stats field lands. Saves l99probe-memory-map.json.
  skin-file blue-1|layout-test  OFFLINE: build an interface file from the stock one. blue-1 tints the Numpad "1"
            [--out F]           key blue in place; layout-test re-lays out the whole Numpad (new key sizes and
                                positions, new art after the project). Proves every other byte is unchanged and
                                prints the install command. Sends nothing.
  Bootloader (cable; keyboard in bootloader mode via Fn, X, 0, 6; research/ISP_PROTOCOL.md):
  isp-probe                     READ-ONLY: handshake + flash ID. Writes nothing. Checks the screen matches the capture.
                                Use --direct (with sudo) for every isp command: the serial path is unreliable and
                                allows only one isp command per bootloader entry
  isp-flash <file>|--factory    Install a whole interface file (UartTFT-II_Flash.bin format), about 5 minutes, then
                                restart the screen. Never touches the control program (HFD_Code). --dry-run builds
                                and checks every packet without opening the port; --setup-only runs the handshakes,
                                interface select and flash ID, then stops before writing
  isp-restart                   Leave bootloader mode (4F 08008000) without writing anything
  --direct                      (isp-*) Talk to the screen's USB endpoints directly instead of through macOS's
                                serial driver. Needs sudo; the device is handed back to macOS afterwards

  clock                         Set the keyboard clock (op 0x28, time only)
  stats                         Clock + distinctive test stats (CPU 42%/61°, GPU 17%/55°, 23° / 27° / 12°, 45%)
  music gavindi|axira           5-second test sweep on the Play page, in one of the two candidate layouts

  2.4 GHz dongle (cable unplugged):
  dongle-info                   Read-only: session-init (version byte) + battery query
  dongle-clock                  Clock-only packet in the prior-art layout (ACKed on the L99 per gavindi)
  dongle-stats plus3|plus4      Clock + test stats in one of the two candidate dongle layouts
  dongle-music                  Music sweep over the dongle (cmd 0x0B, from AULA's driver); --seconds N
  dongle-music-tour             Plays every music style value in turn (fore 0–9, then back 0–9), 4 s each with 2 s gaps, for filming

options:
  --offset-min N                Send the clock shifted by N minutes (to make a change visible)
  --verbose                     Print every frame sent and received
  --dry-run                     Build and print everything, open no devices (photo: also writes a preview PNG)
  --yes                         Skip the upload confirmation prompt
"""

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let verbose = flag("--verbose")
let dryRun = flag("--dry-run")
let assumeYes = flag("--yes")
let directUSB = flag("--direct")
let offsetMinutes = Int(option("--offset-min") ?? "0") ?? 0
let musicSeconds = min(30, max(1, Double(option("--seconds") ?? "5") ?? 5))

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let factoryFile = projectRoot.appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path

func now() -> Realtime { Realtime(date: Date().addingTimeInterval(Double(offsetMinutes) * 60)) }

func confirm(_ question: String) -> Bool {
    if assumeYes { print(question, "→ yes (--yes)"); return true }
    print(question, "[y/N] ", terminator: "")
    return readLine()?.lowercased() == "y"
}

func printReports(_ reports: [WiredReport]) {
    for (i, r) in reports.enumerated() { print("  \(i + 1)\(r.expectsAck ? " (ack)" : "      "):", Array(r.bytes.prefix(32)).hex, "…") }
}

// MARK: Commands

func list() {
    print("Wired keyboard 0C45:800A:")
    let w = HIDScan.collections(vendor: 0x0C45, product: 0x800A)
    w.isEmpty ? print("  (not connected)") : w.forEach { print("  " + $0.summary + ($0.usagePage == 0xFF13 && $0.featureSize == 64 ? "   ← settings channel" : "")) }
    print("2.4 GHz dongle 05AC:024F:")
    let d = HIDScan.collections(vendor: 0x05AC, product: 0x024F)
    d.isEmpty ? print("  (not connected)") : d.forEach { print("  " + $0.summary + ($0.usagePage >= 0xFF00 && (32...33).contains($0.outputSize) ? "   ← vendor channel" : "")) }
    let alt = HIDScan.collections(vendor: 0x0C45, product: 0xFEFE)
    if !alt.isEmpty { print("Note: a 0C45:FEFE receiver is present (S75-Pro-style dongle):"); alt.forEach { print("  " + $0.summary) } }
    print("Screen serial EEEF:268A:")
    let s = ScreenPort.paths()
    s.isEmpty ? print("  (not connected — needs the USB cable)") : s.forEach { print("  " + $0) }
}

func photo() throws {
    let container: [UInt8]
    let label: String
    if flag("--testcard") { container = try Images.testCard(); label = "test card" }
    else if flag("--factory") { container = try Images.factoryPhoto(flashFile: factoryFile); label = "factory mascot" }
    else if let path = args.first { container = try Images.container(fromFile: path); label = (path as NSString).lastPathComponent }
    else { throw LinkError("photo needs --testcard, --factory, or an image path") }
    try ScreenProtocol.validateContainer(container)
    let plan = try ScreenProtocol.uploadPlan(byteCount: container.count)
    let writes = plan.filter { if case .write = $0 { return true }; return false }.count
    print("Prepared \(label): \(container.count) bytes → photo-frame slot 0x041E0000, \(writes) writes + \(plan.count - writes) CRC checks.")

    if dryRun {
        let out = FileManager.default.currentDirectoryPath + "/l99probe-preview.png"
        try Images.preview(container, to: out)
        print("Dry run: preview written to \(out). First frame:")
        if case .write(let a, let r) = plan[0] { print("  ", Array(ScreenProtocol.requestFrame(command: 0x64, address: a, data: Array(container[r])).prefix(24)).hex, "…") }
        for case .check(let a, let r) in plan {
            print(String(format: "   check 0x%08X len 0x%X expect CRC32 %08X", a, r.count, Checksum.crc32Screen(container[r])))
        }
        return
    }
    guard confirm("Keep the cable plugged in and don't touch the screen during the upload. Start?") else { print("Cancelled."); return }

    let port = try ScreenPort()
    port.verbose = verbose
    print("Screen port: \(port.path)")
    var okCount = 0, done = 0
    let start = Date()
    for step in plan {
        switch step {
        case .write(let address, let range):
            let r = try port.request(ScreenProtocol.commandWrite, address: address, data: Array(container[range]))
            if r.count >= 7, r[5] == 0x4F, r[6] == 0x4B { okCount += 1 }   // "OK"
            done += 1
            if !verbose, done % 15 == 0 || done == writes { print("  \(done)/\(writes) chunks", terminator: "\r"); fflush(stdout) }
        case .check(let address, let range):
            let r = try port.request(ScreenProtocol.commandCheck, address: address, data: ScreenProtocol.checkData(length: range.count))
            let expected = Checksum.crc32Screen(container[range])
            guard r.count == 9 else { throw LinkError("Unexpected check reply length \(r.count): \(r.hex). Stopped.") }
            let got = ScreenProtocol.beValue(r[5..<9])
            print(String(format: "\n  check 0x%08X len 0x%05X  device CRC %08X  expected %08X  %@", address, range.count, got, expected, got == expected ? "✓" : "✗ MISMATCH"))
            guard got == expected else { throw LinkError("Region CRC mismatch. Stopped. Power-cycle the keyboard and run the same command again.") }
        }
    }
    print(String(format: "Upload complete in %.1f s. %d/%d write replies contained \"OK\".", Date().timeIntervalSince(start), okCount, writes))
    print("Now leave the Photo Frame page and open it again (or power-cycle the keyboard) to see the new image.")
}

func wired(_ reports: [WiredReport], _ what: String) throws {
    if dryRun || verbose { print("\(what):"); printReports(reports) }
    if dryRun { return }
    let kb = try WiredKeyboard()
    kb.verbose = verbose
    try kb.send(reports)
    print("\(what): sent and acknowledged.")
}

func music() throws {
    guard let name = args.first, let layout = KeyboardProtocol.MusicLayout(rawValue: name) else { throw LinkError("music needs gavindi or axira") }
    let bands = layout == .gavindi ? 23 : 18
    func frame(_ t: Double) -> [Double] { (0..<bands).map { i in 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.45) } }
    if dryRun { print("music \(name), first frame:"); printReports(KeyboardProtocol.music(levels: frame(0), layout: layout)); return }
    let kb = try WiredKeyboard()
    kb.verbose = verbose
    print("Open the Play (music) page on the screen. Sending a 5-second sweep in the \(name) layout…")
    let start = Date()
    var frames = 0
    let seconds = musicSeconds
    while Date().timeIntervalSince(start) < seconds {
        try kb.send(KeyboardProtocol.music(levels: frame(Date().timeIntervalSince(start)), layout: layout))
        frames += 1
    }
    print("Sent \(frames) frames (all acknowledged). Did the bars move as a smooth travelling wave?")
}

func dongleInfo() throws {
    if dryRun { print("session-init:", DongleProtocol.sessionInit.hex); print("battery:     ", DongleProtocol.batteryQuery.hex); return }
    let d = try Dongle(); d.verbose = verbose
    print("Dongle vendor collection: \(d.collection.summary)")
    if let r = try d.transact(DongleProtocol.sessionInit) {
        print("session-init reply:", r.hex)
        print(String(format: "  byte 11 (build/version): 0x%02X   (gavindi's L99 dongle: 0x29)   checksum %@", r[11], DongleProtocol.checksumOK(r) ? "ok" : "BAD"))
    } else { print("session-init: no reply") }
    if let r = try d.transact(DongleProtocol.batteryQuery) {
        print("battery reply:", r.hex)
        print("  battery: \(r[3])%")
    } else { print("battery: no reply — keyboard asleep or switched off? Press a key and retry.") }
}

func dongleClock(_ layout: DongleProtocol.ClockLayout, stats: Bool) throws {
    var r = now()
    if stats {
        r.applyTestStats()
        // Distinct values per layout, so a result can't be confused with the cable test's 42/17/23/45.
        switch layout {
        case .plus3: (r.cpuLoad, r.gpuLoad, r.airTemp, r.humidity) = (33, 66, 13, 31)
        case .plus4: (r.cpuLoad, r.gpuLoad, r.airTemp, r.humidity) = (44, 88, 14, 41)
        case .prior: break
        }
        print("Expect on the Real-time page: CPU \(r.cpuLoad)%, GPU \(r.gpuLoad)%, \(r.airTemp) °C, humidity \(r.humidity)%")
    }
    let frame = try DongleProtocol.clock(r, layout: layout)
    print("dongle clock (\(layout.rawValue))\(stats ? " + stats" : ""):", frame.hex)
    if dryRun { return }
    let d = try Dongle(); d.verbose = verbose
    if let reply = try d.transact(frame) {
        print("reply:", reply.hex, DongleProtocol.checksumOK(reply) ? "(checksum ok)" : "(checksum BAD)")
        print(stats ? "Acknowledged. Now check the Real-time page for the values above."
                    : "Acknowledged. Did the clock on the screen change to the Mac's time?")
    } else {
        print("No reply from the dongle. Keyboard asleep? Press a key and retry.")
    }
}

func dongleMusic() throws {
    func frame(_ t: Double) -> [Double] { (0..<DongleProtocol.musicBands).map { i in 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.45) } }
    if dryRun { print("dongle music, first frame:", DongleProtocol.music(levels: frame(0)).hex); return }
    let d = try Dongle(); d.verbose = verbose
    print("Open the Play (music) page. Sending a \(Int(musicSeconds))-second sweep over the dongle (cmd 0x0B, vendor layout)…")
    let start = Date()
    var frames = 0, replies = 0
    while Date().timeIntervalSince(start) < musicSeconds {
        // The vendor doesn't wait for a reply; we listen briefly only to log one if it comes.
        if try d.transact(DongleProtocol.music(levels: frame(Date().timeIntervalSince(start))), timeout: 0.05) != nil { replies += 1 }
        frames += 1
    }
    print("Sent \(frames) frames (\(replies) echoed a reply). Did the bars move?")
}

/// Maps the music packet's two style bytes: every value in turn, each a 4-second sweep, separated
/// by 2 seconds of nothing (the keys fall back to normal lighting, which marks the gaps on video).
/// Only the volatile music packet; nothing is saved on the keyboard.
func dongleMusicTour() throws {
    func frame(_ t: Double) -> [Double] { (0..<DongleProtocol.musicBands).map { i in 0.45 + 0.4 * sin(t * 6 + Double(i) * 0.45) } }
    var plan = [(label: String, fore: UInt8, back: UInt8)]()
    for f in 0...9 { plan.append(("bar style \(f) (key style 0)", UInt8(f), 0)) }
    for b in 0...9 { plan.append(("key style \(b) (bar style 2)", 2, UInt8(b))) }
    if dryRun { plan.forEach { print($0.label) }; return }
    let d = try Dongle(); d.verbose = verbose
    print("Open the Play page and start filming the keyboard and screen. Starting in 5 seconds…")
    Thread.sleep(forTimeInterval: 5)
    let tourStart = Date()
    for (n, step) in plan.enumerated() {
        Thread.sleep(forTimeInterval: 2)
        print(String(format: "%5.1f s  #%d  %@", Date().timeIntervalSince(tourStart), n + 1, step.label))
        let start = Date()
        while Date().timeIntervalSince(start) < 4 {
            try d.send(DongleProtocol.music(levels: frame(Date().timeIntervalSince(start)), foreMode: step.fore, backMode: step.back))
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
    }
    print("Done. All \(plan.count) styles played.")
}

func checkPhoto() throws {
    let container: [UInt8]
    if flag("--factory") { container = try Images.factoryPhoto(flashFile: factoryFile) }
    else if flag("--testcard") { container = try Images.testCard() }
    else { throw LinkError("check needs --factory or --testcard") }
    let port = try ScreenPort(); port.verbose = verbose
    let start = Date()
    let match = try ScreenTransfer.verify(container, in: .photo, port: port)
    print(String(format: "Photo slot %@ that image (%.2f s, region checks only, nothing written).",
                 match ? "MATCHES" : "does NOT match", Date().timeIntervalSince(start)))
}

func sendGIF(_ blob: [UInt8], label: String) throws {
    let info = try GIFContainer.info(blob)
    print("Prepared \(label): \(info.frameCount) frames, delay field \(info.delay), \(blob.count) bytes → GIF slot 0x04240000.")
    if dryRun { return }
    guard confirm("Keep the cable plugged in. Start?") else { print("Cancelled."); return }
    let port = try ScreenPort(); port.verbose = verbose
    let start = Date()
    let result = try ScreenTransfer.upload(blob, to: .gif, port: port) { p in
        if !verbose { print(String(format: "  %3.0f%%", p.fraction * 100), terminator: "\r"); fflush(stdout) }
        return true
    }
    print(String(format: "\n%@ in %.1f s, every region's CRC32 confirmed by the screen.", result == .completed ? "Upload complete" : "Stopped", Date().timeIntervalSince(start)))
    print("Now leave the GIF page and open it again to see it.")
}

func memoryMap() throws {
    let plan = RuntimeMemory.plan()
    var r = now()
    RuntimeMemory.applyMarkers(&r, second: false)
    let sendA = try KeyboardProtocol.realtime(r)
    RuntimeMemory.applyMarkers(&r, second: true)
    let sendB = try KeyboardProtocol.realtime(r)
    print("Memory map: \(plan.count) reads of up to \(RuntimeMemory.maxWords) words per snapshot, 3 snapshots. Reads only; nothing is written to the screen.")
    print("Marker values A / B:", RuntimeMemory.fields.map { "\($0.name) \($0.a)/\($0.b)" }.joined(separator: ", "))
    if dryRun {
        print("First read frame:", try RuntimeMemory.readFrame(address: plan[0].address, count: plan[0].count).hex)
        print("Last read frame: ", try RuntimeMemory.readFrame(address: plan.last!.address, count: plan.last!.count).hex)
        print("Stats packet A:"); printReports(sendA)
        return
    }
    guard confirm("Keyboard on the cable and switched on, Real-time Data page open on the screen, L99 Control Center and AULA's driver closed. Start?") else { print("Cancelled."); return }
    let port = try ScreenPort()
    port.verbose = verbose
    let kb = try WiredKeyboard()
    kb.verbose = verbose
    print("Screen port: \(port.path)")

    let frozenHint = "Nothing was written. If the screen is frozen, switch the keyboard off and on."
    do { _ = try port.readWords(address: 0, count: RuntimeMemory.maxWords) }
    catch { throw LinkError("The screen didn't answer the first memory read: \(error). \(frozenHint) Stopped before any more reads.") }
    print("First read answered. Mapping…")

    func snapshot(_ label: String) throws -> [UInt16: UInt16] {
        var s = [UInt16: UInt16]()
        for (i, step) in plan.enumerated() {
            do {
                let words = try port.readWords(address: step.address, count: step.count)
                for (k, v) in words.enumerated() { s[step.address + UInt16(k)] = v }
            } catch {
                throw LinkError(String(format: "Read %d of %d (%@, 0x%04X) failed: %@. %@", i + 1, plan.count, label, step.address, "\(error)", frozenHint))
            }
        }
        print("  \(label): \(s.count) words, \(s.values.filter { $0 != 0 }.count) non-zero")
        return s
    }
    let before = try snapshot("before")
    try kb.send(sendA); Thread.sleep(forTimeInterval: 2)
    let a = try snapshot("markers A")
    try kb.send(sendB); Thread.sleep(forTimeInterval: 2)
    let b = try snapshot("markers B")
    try kb.send(KeyboardProtocol.realtime(now()))          // back to the real time, no test stats

    let matches = RuntimeMemory.matches(a: a, b: b)
    print("\nWhere each stats field landed:")
    for f in RuntimeMemory.fields {
        let m = matches.filter { $0.field == f.name }
        print("  \(f.name):", m.isEmpty ? "not found" : m.map { String(format: "0x%04X (%@)", $0.address, $0.part) }.joined(separator: ", "))
    }
    let changedAB = a.keys.sorted().filter { a[$0] != b[$0] }
    let changedBefore = before.keys.sorted().filter { before[$0] != a[$0] }
    print("\nWords that changed between A and B: \(changedAB.count)")
    for k in changedAB.prefix(60) { print(String(format: "  0x%04X: %04X → %04X", k, a[k]!, b[k]!)) }
    print("Words that changed between before and A: \(changedBefore.count)")

    func hexMap(_ s: [UInt16: UInt16]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: s.filter { $0.value != 0 }.map { (String(format: "%04X", $0.key), String(format: "%04X", $0.value)) })
    }
    let report: [String: Any] = [
        "before": hexMap(before), "markersA": hexMap(a), "markersB": hexMap(b),
        "matches": matches.map { ["field": $0.field, "address": String(format: "%04X", $0.address), "part": $0.part] },
        "markers": RuntimeMemory.fields.map { ["field": $0.name, "a": $0.a, "b": $0.b] },
    ]
    let out = FileManager.default.currentDirectoryPath + "/l99probe-memory-map.json"
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: out))
    print("\nSaved \(out). The clock was set back to the real time.")
}

func uiBlockTest() throws {
    guard let name = args.first, let variant = InterfaceBlockTest.Variant(rawValue: name) else {
        throw LinkError("ui-block-test needs stock or blue")
    }
    let stock = try InterfaceBlockTest.stockBlock(flashFile: factoryFile)
    let block = try InterfaceBlockTest.block(variant, stock: stock)
    let plan = InterfaceBlockTest.plan()
    let expected = Checksum.crc32Screen(block)
    print(String(format: "Prepared block 0x3B (%@): 0x%08X–0x%08X, %d writes + 1 check, expected CRC32 %08X (stock %08X).",
                 variant.rawValue, InterfaceBlockTest.blockBase, InterfaceBlockTest.blockBase + UInt32(InterfaceBlockTest.blockSize) - 1,
                 plan.count - 1, expected, Checksum.crc32Screen(stock)))
    if dryRun {
        let out = FileManager.default.currentDirectoryPath + "/l99probe-numpad1-\(variant.rawValue).png"
        try Images.iconPreview(block, to: out)
        print("Dry run: nothing opened or sent. The \"1\" key as it would look: \(out)")
        return
    }
    print("""
    This writes to the screen's interface area, outside the photo/background/GIF slots.
    Only run it if the Windows restore test has passed and the Windows PC and reset package are at hand.
    Cable plugged in, AULA's driver closed, don't touch the screen.
    """)
    guard confirm("Write block 0x3B (\(variant.rawValue))?") else { print("Cancelled."); return }
    let port = try ScreenPort(); port.verbose = verbose
    print("Screen port: \(port.path)")
    let start = Date()
    var done = 0
    for step in plan {
        switch step {
        case .write(let address, let range):
            let r: [UInt8]
            do { r = try port.request(ScreenProtocol.commandWrite, address: address, data: Array(block[range])) }
            catch {
                throw LinkError(done == 0
                    ? "The screen refused the first write (\(error)). Nothing was changed: it doesn't accept writes here. Stop the test."
                    : "Write \(done + 1) failed (\(error)). Stopped mid-block: switch the keyboard off and on, then run ui-block-test stock.")
            }
            guard r.count >= 7, r[5] == 0x4F, r[6] == 0x4B else {
                throw LinkError("Write \(done + 1) wasn't confirmed with OK (\(r.hex)). Stopped: switch the keyboard off and on, then run ui-block-test stock.")
            }
            done += 1
            if !verbose { print("  \(done)/\(plan.count - 1) chunks", terminator: "\r"); fflush(stdout) }
        case .check(let address, let range):
            let got = try ScreenTransfer.regionCRC(port: port, address: address, length: range.count)
            print(String(format: "\n  check 0x%08X len 0x%05X  device CRC %08X  expected %08X  %@", address, range.count, got, expected, got == expected ? "✓" : "✗ MISMATCH"))
            guard got == expected else { throw LinkError("The screen holds different data than was sent. Stopped: run ui-block-test stock.") }
        }
    }
    print(String(format: "Block written in %.1f s, all %d writes OK, CRC confirmed.", Date().timeIntervalSince(start), done))
    print("Open the Mini Numpad page (leave and re-enter it if it was open). If nothing changed, switch the keyboard off and on and look again.")
}

// MARK: Interface-file writer (offline)

func skinFile() throws {
    switch args.first {
    case "blue-1": try skinBlue1()
    case "layout-test": try skinLayoutTest()
    default: throw LinkError("skin-file needs: blue-1 or layout-test")
    }
}

/// A deliberately different Numpad: a 4×4 grid of 74×70 keys plus a full-width 0, in the "soft dark"
/// style. Proves moved/resized touch areas and new-size art stored after the project.
func skinLayoutTest() throws {
    let out = option("--out") ?? projectRoot.appendingPathComponent("build/UartTFT-II_Flash-layout-test.bin").path
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: out).deletingLastPathComponent(), withIntermediateDirectories: true)
    var file = try InterfaceFile(stockFile: factoryFile)
    let page = 21
    let buttons = try file.touchButtons(page: page)
    // (code, label, kind, column, row); row 4 is the full-width 0.
    let plan: [(Int, String, SkinArt.Kind, Int, Int)] = [
        (48, "Num", .symbol, 0, 0), (49, "/", .symbol, 1, 0), (50, "*", .symbol, 2, 0), (51, "−", .symbol, 3, 0),
        (52, "7", .number, 0, 1), (53, "8", .number, 1, 1), (54, "9", .number, 2, 1), (55, "+", .symbol, 3, 1),
        (56, "4", .number, 0, 2), (57, "5", .number, 1, 2), (58, "6", .number, 2, 2), (64, "Del", .symbol, 3, 2),
        (59, "1", .number, 0, 3), (60, "2", .number, 1, 3), (61, "3", .number, 2, 3), (62, "Enter", .accent, 3, 3),
        (63, "0", .number, 0, 4),
    ]
    guard Set(plan.map(\.0)) == Set(buttons.filter { (48...64).contains($0.code) }.map(\.code)) else {
        throw LinkError("The Numpad's key codes aren't the 17 expected. Stopped.")
    }
    for (code, label, kind, col, row) in plan {
        let b = buttons.first { $0.code == code }!
        let (x, y, w, h) = row == 4 ? (3, 404, 314, 70) : (3 + col * 80, 100 + row * 76, 74, 70)
        try file.moveButton(page: page, code: code, x: x, y: y, width: w, height: h)
        for (id, pressed) in [(b.up, false), (b.down, true)] {
            try file.placeIcon(id, width: w, height: h,
                               pixels: SkinArt.key(label, kind: kind, pressed: pressed, width: w, height: h, style: SkinArt.softDark))
        }
    }
    let crc = try file.write(to: out)
    for line in file.log { print("  " + line) }
    let changed = file.changedRanges().reduce(0) { $0 + $1.count }
    print(String(format: "Project end 0x%08X → 0x%08X. %d bytes changed, all inside the planned edits.",
                 InterfaceFile.artRange.upperBound, file.projectEnd, changed))
    print("Size \(file.bytes.count) (unchanged), CRC32 \(String(format: "%08X", crc)).")
    print("Saved: \(out)")
    print("Install (bootloader mode, cable): sudo \(CommandLine.arguments[0]) isp-flash \"\(out)\" --direct")
}

func skinBlue1() throws {
    let out = option("--out") ?? projectRoot.appendingPathComponent("build/UartTFT-II_Flash-blue-1.bin").path
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: out).deletingLastPathComponent(), withIntermediateDirectories: true)
    var file = try InterfaceFile(stockFile: factoryFile)
    let id = InterfaceBlockTest.iconID
    let ic = try file.icon(id)
    let before = try file.pixels(id)
    try file.replaceIcon(id, pixels: before.map(Art4444.tintBlue))
    let crc = try file.write(to: out)
    let ranges = file.changedRanges()
    print(String(format: "Icon %d (%d×%d, format %d) at 0x%08X, both banks.", id, ic.width, ic.height, ic.format, ic.address))
    print("Changed ranges (all inside icon \(id)):")
    for r in ranges { print(String(format: "  0x%08X–0x%08X  (%d bytes)", r.lowerBound, r.upperBound - 1, r.count)) }
    print("Every other byte matches the stock file. Size \(file.bytes.count), CRC32 \(String(format: "%08X", crc)).")
    print("Saved: \(out)")
    let png = (out as NSString).deletingPathExtension + "-preview.png"
    try Images.iconPair(before, try file.pixels(id), width: ic.width, height: ic.height, to: png)
    print("Preview (stock | new): \(png)")
    print("Install (bootloader mode, cable): sudo \(CommandLine.arguments[0]) isp-flash \"\(out)\" --direct")
}

// MARK: Bootloader (ISP)

func bootloaderPrompt() -> Bool {
    print("The screen must show \"Bootloader V2.30.156, Flash ID: GD5F1GQ4\" (Fn, X, 0, 6 with the cable plugged in).")
    return confirm("Is it showing that now?")
}

func ispProbe() throws {
    guard bootloaderPrompt() else { print("Cancelled."); return }
    let port = try BootloaderPort(directUSB: directUSB); port.verbose = verbose
    if let t = option("--wait"), let s = Double(t) { port.handshakeTimeout = s }
    print("Port: \(port.path)")
    try port.probe()
    print(String(format: "OK: handshake authenticated with key %08X, info bytes and flash ID (GD5F1GQ4) match the capture.", ISP.key))
    print("Nothing was written. The screen is still in the bootloader; run isp-restart --direct to return it to normal.")
    if !directUSB { print("Serial path: unplug the cable for 5 s and plug it back in before the next isp command.") }
}

func ispRestart() throws {
    guard bootloaderPrompt() else { print("Cancelled."); return }
    let port = try BootloaderPort(directUSB: directUSB); port.verbose = verbose
    try port.restart()
    print("Sent restart (4F 08008000). The screen should return to normal within a few seconds.")
}

func ispFlash() throws {
    setvbuf(stdout, nil, _IOLBF, 0)     // progress shows up live when logged to a file
    let setupOnly = flag("--setup-only")
    let path: String
    if flag("--factory") { path = factoryFile }
    else if let p = args.first { path = (p as NSString).expandingTildeInPath }
    else { throw LinkError("isp-flash needs a file or --factory") }
    guard let data = FileManager.default.contents(atPath: path) else { throw LinkError("Cannot read \(path)") }
    let image = try ISP.Image(Array(data))
    let isStock = image.crc == 0x4DEE_F87B && image.bytes.count == 127_599_044
    print(String(format: "File: %@\n  %d bytes, CRC32 %08X, %d chunks of 2 KB%@", path, image.bytes.count, image.crc, image.chunkCount,
                 isStock ? " (the stock factory file)" : ""))
    if dryRun {
        var total = 0
        for i in 0..<image.chunkCount { total += image.packet(i).count }
        print("Dry run: built all \(image.chunkCount) data packets (\(total) bytes). Nothing opened or sent.")
        print("Sequence: 4B 30, 4B 32, 6D, 6F 02, 6C × \(image.chunkCount), 6E, 4F")
        return
    }
    print("""
    This replaces the screen's whole interface area (about 5 minutes). Keyboard functions and the
    control program are not touched. Keep the cable in and don't touch the screen until it says done.
    If it fails, the screen stays in bootloader mode: run this again, or use the PC reset tool.
    """)
    guard bootloaderPrompt(), confirm("Install this file now?") else { print("Cancelled."); return }
    let port = try BootloaderPort(directUSB: directUSB); port.verbose = verbose
    print("Port: \(port.path)")
    if !port.info.isEmpty { print("  \(port.info)") }
    let start = Date()
    var lastShown = -1
    let result = try port.install(image, setupOnly: setupOnly) { phase, done, total in
        let pct = done * 100 / max(total, 1)
        guard pct != lastShown else { return }
        lastShown = pct
        print(String(format: "  %@ %3d%%  (%.0f s)", phase == .writing ? "writing  " : "verifying", pct, Date().timeIntervalSince(start)))
    }
    guard let final = result else {
        print("Setup-only: handshakes, interface select and flash ID all OK. Stopped before 6F and before writing. Nothing was written.")
        print("The screen is still in the bootloader; run isp-restart --direct to return it to normal.")
        if !directUSB { print("Serial path: unplug the cable for 5 s and plug it back in before the next run.") }
        return
    }
    print(String(format: "Done in %.0f s. Every read-back report matched the file. Final screen value %08X%@.", Date().timeIntervalSince(start), final,
                 isStock ? (final == ISP.stockFinalValue ? " (same as the PC restore)" : String(format: " (the PC restore gave %08X)", ISP.stockFinalValue)) : ""))
    print("Sent restart. The screen should come back on its own; if it stays dark, switch the keyboard off and on.")
}

// MARK: Dispatch

do {
    guard let cmd = args.first else { print(usage); exit(0) }
    args.removeFirst()
    switch cmd {
    case "list": list()
    case "photo": try photo()
    case "clock": try wired(KeyboardProtocol.realtime(now()), "clock")
    case "stats":
        var r = now(); r.applyTestStats()
        print("Open the Real-time page on the screen to see the values.")
        try wired(KeyboardProtocol.realtime(r), "stats")
    case "music": try music()
    case "check": try checkPhoto()
    case "gif-test":
        let delay = Int(option("--delay") ?? "400") ?? 400
        try sendGIF(try Images.gifTest(delay: delay, previewTo: dryRun ? FileManager.default.currentDirectoryPath : nil), label: "test animation")
    case "gif":
        guard flag("--factory") else { throw LinkError("gif needs --factory") }
        try sendGIF(try Images.factoryGIF(flashFile: factoryFile), label: "factory animation")
    case "ui-block-test": try uiBlockTest()
    case "memory-map": try memoryMap()
    case "skin-file": try skinFile()
    case "isp-probe": try ispProbe()
    case "isp-flash": try ispFlash()
    case "isp-restart": try ispRestart()
    case "dongle-info": try dongleInfo()
    case "dongle-clock": try dongleClock(.prior, stats: false)
    case "dongle-stats":
        guard let name = args.first, let layout = DongleProtocol.ClockLayout(rawValue: name), layout != .prior else {
            throw LinkError("dongle-stats needs plus3 or plus4")
        }
        try dongleClock(layout, stats: true)
    case "dongle-music": try dongleMusic()
    case "dongle-music-tour": try dongleMusicTour()
    case "-h", "--help", "help": print(usage)
    default: print(usage); exit(2)
    }
} catch {
    FileHandle.standardError.write("ERROR: \(error)\n".data(using: .utf8)!)
    exit(1)
}
