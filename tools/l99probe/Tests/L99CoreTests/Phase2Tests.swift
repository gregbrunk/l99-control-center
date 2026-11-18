import Foundation
import XCTest
@testable import L99Core

final class MusicAnalyzerTests: XCTestCase {
    private func sine(_ hz: Double, amplitude: Float = 0.5, count: Int = 2048, rate: Double = 48_000) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    func testSilenceGivesFlatZero() {
        let a = MusicAnalyzer()
        var levels = [Double]()
        for _ in 0..<5 { levels = a.process([Float](repeating: 0, count: 2048)) }
        XCTAssertEqual(levels.count, 21)
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
        XCTAssertLessThan(a.lastRMS, MusicAnalyzer.silenceRMS)
    }

    func testToneLightsTheRightBand() {
        for hz in [100.0, 1_000.0, 8_000.0] {
            let a = MusicAnalyzer()
            var levels = [Double]()
            for _ in 0..<10 { levels = a.process(sine(hz)) }
            let peak = levels.indices.max { levels[$0] < levels[$1] }!
            // Band centres are log-spaced from 40 Hz to 16 kHz.
            let expected = Int(log(hz / 40) / log(16_000 / 40.0) * 21)
            XCTAssertLessThanOrEqual(abs(peak - expected), 1, "\(hz) Hz peaked in band \(peak), expected about \(expected)")
            XCTAssertGreaterThan(levels[peak], 0.7)
            XCTAssertLessThanOrEqual(levels[peak], MusicAnalyzer.headroom + 0.01)   // headroom below the top
            XCTAssertTrue(levels.allSatisfy { (0...1).contains($0) })
        }
    }

    func testBarsFallSmoothlyAfterSound() {
        let a = MusicAnalyzer()
        for _ in 0..<10 { _ = a.process(sine(1_000)) }
        let loud = a.process(sine(1_000)).max()!
        let next = a.process([Float](repeating: 0, count: 2048)).max()!
        XCTAssertLessThan(next, loud)
        XCTAssertGreaterThan(next, 0.5 * loud)            // falls gradually, not at once
    }

    func testResample() {
        XCTAssertEqual(MusicAnalyzer.resample([0, 1], to: 3), [0, 0.5, 1])
        XCTAssertEqual(MusicAnalyzer.resample(Array(repeating: 0.3, count: 21), to: 18).count, 18)
    }

    func testRingKeepsNewestInOrder() {
        let ring = SampleRing(capacity: 4)
        [1, 2, 3, 4, 5, 6].map(Float.init).withUnsafeBufferPointer { ring.append($0) }
        XCTAssertEqual(ring.latest(3), [4, 5, 6])
        XCTAssertEqual(ring.latest(10), [3, 4, 5, 6])
    }
}

final class LiveStatsPacketTests: XCTestCase {
    func testPlus3PacketCarriesStatsAndWeather() throws {
        var r = Realtime(year: 2026, month: 11, day: 17, hour: 21, minute: 5, second: 9, weekday: 2)
        r.cpuLoad = 12; r.gpuLoad = 4; r.airTemp = -3; r.dayHigh = 2; r.nightLow = -7; r.condition = 5; r.humidity = 81
        let p = try DongleProtocol.clock(r, layout: .plus3)
        XCTAssertEqual(Array(p[0...2]), [0x0C, 0x10, 0x00])
        XCTAssertEqual(p[16], 12); XCTAssertEqual(p[18], 4)
        XCTAssertEqual(p[20], 0xFD)                      // -3 °C as a signed byte
        XCTAssertEqual(p[23], 5); XCTAssertEqual(p[24], 81)
        XCTAssertEqual(Array(p[25...26]), [0xAA, 0x55])
        XCTAssertTrue(DongleProtocol.checksumOK(p))
    }

    func testMusicPacketCarriesModes() {
        let p = DongleProtocol.music(levels: [1, 0.5], foreMode: 3, backMode: 1)
        XCTAssertEqual(Array(p[0...5]), [0x0B, 0x1C, 0x00, 3, 1, 35])
        XCTAssertEqual(p[6], 99); XCTAssertEqual(p[7], 50); XCTAssertEqual(p[8], 0)
        XCTAssertTrue(DongleProtocol.checksumOK(p))
    }
}
