import XCTest
@testable import L99Core

private let factoryFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("research/factory/UartTFT-II_Flash.bin").path

private func factorySlice(_ offset: UInt32, _ count: Int) throws -> [UInt8] {
    guard let fh = FileHandle(forReadingAtPath: factoryFile) else { throw XCTSkip("factory file not present") }
    defer { try? fh.close() }
    try fh.seek(toOffset: UInt64(offset))
    return [UInt8](try fh.read(upToCount: count)!)
}

final class SlotTests: XCTestCase {
    func testEachSlotPlansInsideItsBounds() throws {
        for slot in [ScreenProtocol.Slot.background, .photo] {
            let plan = try ScreenProtocol.uploadPlan(slot: slot, byteCount: ScreenProtocol.imageBytes)
            guard case .write(let first, _) = plan.first! else { return XCTFail() }
            XCTAssertEqual(first, slot.base)
            XCTAssertEqual(plan.count, 151 + 3)
        }
        let gif = try ScreenProtocol.uploadPlan(slot: .gif, byteCount: ScreenProtocol.gifMaxBytes)
        guard case .check(let lastAddress, let lastRange) = gif.last! else { return XCTFail() }
        XCTAssertEqual(Int(lastAddress) - 0x0424_0000 + lastRange.count, ScreenProtocol.gifMaxBytes)
        XCTAssertEqual(Int(lastAddress) + lastRange.count, 0x05B0_D07C)          // end of the factory blob
    }
    func testRefusesWrongSizes() {
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(slot: .background, byteCount: ScreenProtocol.imageBytes - 1))
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(slot: .photo, byteCount: 0x60001))
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(slot: .gif, byteCount: ScreenProtocol.gifMaxBytes + 1))
        XCTAssertThrowsError(try ScreenProtocol.uploadPlan(slot: .gif, byteCount: 0))
    }
    func testVerifyPlanHasNoWrites() throws {
        let plan = try ScreenProtocol.verifyPlan(slot: .photo, byteCount: ScreenProtocol.imageBytes)
        XCTAssertEqual(plan.count, 3)
        XCTAssertTrue(plan.allSatisfy { if case .check = $0 { return true }; return false })
    }
}

final class GIFTests: XCTestCase {
    func testSmallRoundTrip() throws {
        let n = 320 * 480
        let red: UInt16 = 0xF800, blue: UInt16 = 0x001F
        let a = [UInt16](repeating: red, count: n)
        var b = a; for i in 0..<(n / 2) { b[i] = blue }
        let blob = try GIFContainer.encode(frames: [a, b], delay: 50)
        let info = try GIFContainer.info(blob)
        XCTAssertEqual(info, .init(frameCount: 2, width: 320, height: 480, delay: 50, byteCount: blob.count))
        XCTAssertEqual(try GIFContainer.decodeAll(blob), [a, b])
        // Solid red: 600 tokens of 256 px → 1200 content bytes, like gavindi's red reference capture.
        XCTAssertEqual(Int(blob[40 + 12]) | Int(blob[40 + 13]) << 8, 1200)
    }
    func testNoisyFrameFallsBackToRaw() throws {
        let frame = (0..<(320 * 480)).map { UInt16($0 % 2 == 0 ? 0xFFFF : 0x0000) }
        let blob = try GIFContainer.encode(frames: [frame], delay: 50)
        XCTAssertEqual(Int(blob[20 + 14]) | Int(blob[20 + 15]) << 8, Int(GIFContainer.modeRaw))
        XCTAssertEqual(try GIFContainer.decodeAll(blob), [frame])
    }
    func testRejectsTooManyColoursAndFrames() {
        let colourful = (0..<(320 * 480)).map { UInt16($0 % 300) }
        XCTAssertThrowsError(try GIFContainer.encode(frames: [colourful], delay: 50))
        let tiny = [UInt16](repeating: 0, count: 320 * 480)
        XCTAssertThrowsError(try GIFContainer.encode(frames: Array(repeating: tiny, count: 201), delay: 50))
    }
    /// Decodes AULA's own 26 MB factory animation (raw frames, RLE frames longer than 0xFFFF bytes,
    /// and mode 0x0101), then round-trips a sample of its frames through our encoder.
    /// Our encoder picks raw vs RLE by gavindi's hardware-proven rule, so the bytes differ from the
    /// vendor's; the factory restore always sends the original bytes unchanged.
    func testFactoryAnimationDecodesAndRoundTrips() throws {
        let blob = try factorySlice(0x0424_0000, ScreenProtocol.gifMaxBytes)
        let info = try GIFContainer.info(blob)
        XCTAssertEqual(info.frameCount, 171)
        XCTAssertEqual(info.delay, 50)
        XCTAssertEqual(info.byteCount, ScreenProtocol.gifMaxBytes)
        let frames = try GIFContainer.decodeAll(blob)
        let sample = Array(frames.prefix(12))
        let again = try GIFContainer.encode(frames: sample, delay: info.delay)
        XCTAssertEqual(try GIFContainer.decodeAll(again), sample)
        let colours = Set(frames.joined())
        let offRamp = colours.filter { !ColorConversion.isRampLegal($0) }.count
        print("factory animation: \(colours.count) distinct colours, \(offRamp) off the 252-colour ramp")
    }
}

final class ColorTests: XCTestCase {
    private func gradient() -> [UInt8] {
        var rgba = [UInt8](repeating: 255, count: 320 * 480 * 4)
        for y in 0..<480 { for x in 0..<320 {
            let i = 4 * (y * 320 + x)
            rgba[i] = UInt8(x * 255 / 319); rgba[i + 1] = UInt8(y * 255 / 479); rgba[i + 2] = 128
        } }
        return rgba
    }
    func testRampDitherIsAlwaysRampLegal() {
        let out = ColorConversion.convert(rgba: gradient(), width: 320, height: 480, method: .ramp)
        XCTAssertTrue(out.allSatisfy(ColorConversion.isRampLegal))
        XCTAssertLessThanOrEqual(Set(out).count, 252)
    }
    func testTruncateMatchesVendor() {
        let rgba: [UInt8] = [0xFF, 0x80, 0x07, 0xFF]
        XCTAssertEqual(ColorConversion.convert(rgba: rgba, width: 1, height: 1, method: .truncate), [0xFC00])
        XCTAssertEqual(ScreenProtocol.rgb565(fromRGBA: rgba), [0x00, 0xFC])
    }
    func testDitherKeepsAverageBrightness() {
        let grey: [UInt8] = (0..<(64 * 64 * 4)).map { $0 % 4 == 3 ? 255 : 100 }
        let out = ColorConversion.convert(rgba: grey, width: 64, height: 64, method: .dither565)
        let mean = out.map { Double(ColorConversion.rgb888($0).1) }.reduce(0, +) / Double(out.count)
        XCTAssertEqual(mean, 100, accuracy: 1.5)
    }
}

final class PaletteTests: XCTestCase {
    func testSharedPaletteFitsTheContainer() throws {
        var frames = [[UInt8]]()
        for f in 0..<3 {
            var rgba = [UInt8](repeating: 255, count: 320 * 480 * 4)
            for y in 0..<480 { for x in 0..<320 {
                let i = 4 * (y * 320 + x)
                rgba[i] = UInt8((x + f * 40) % 256); rgba[i + 1] = UInt8(y * 255 / 479); rgba[i + 2] = UInt8((x * y) % 256)
            } }
            frames.append(rgba)
        }
        let q = PaletteQuantizer(frames: frames)
        XCTAssertLessThanOrEqual(q.palette.count, 256)
        XCTAssertGreaterThan(q.palette.count, 200)
        let encoded = frames.map { q.dither(rgba: $0, width: 320, height: 480) }
        XCTAssertTrue(encoded.allSatisfy { Set($0).isSubset(of: Set(q.palette)) })
        let blob = try GIFContainer.encode(frames: encoded, delay: 10)
        XCTAssertEqual(try GIFContainer.decodeAll(blob), encoded)
    }
}
