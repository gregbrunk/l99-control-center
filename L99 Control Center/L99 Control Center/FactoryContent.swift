import Foundation
import L99Core

/// Pulls the factory pictures out of AULA's interface file (UartTFT-II_Flash.bin from the
/// official reset package), checks each one, and stores them in the library.
/// The file's offsets are the screen's own flash addresses (verified Nov 17, FINDINGS.md).
nonisolated enum FactoryContent {
    static let expectedFileSize = 127_599_044

    struct Piece: Sendable {
        let slot: ScreenProtocol.Slot
        let name: String
        let payload: [UInt8]
        let preview: [UInt16]
        let frameCount: Int?
    }

    /// Reads and verifies every piece. Throws if anything doesn't match the verified factory file.
    static func extract(from url: URL) throws -> [Piece] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size == expectedFileSize else {
            throw PipelineError("That isn't the verified UartTFT-II_Flash.bin (expected \(expectedFileSize) bytes, found \(size)).")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func read(_ offset: UInt32, _ count: Int) throws -> [UInt8] {
            try handle.seek(toOffset: UInt64(offset))
            return [UInt8](try handle.read(upToCount: count) ?? Data())
        }

        var pieces = [Piece]()

        let mascot = try read(ScreenProtocol.Slot.photo.base, ScreenProtocol.imageBytes)
        try ScreenProtocol.validateContainer(mascot)
        // CRC32 of the first region, as the screen reported it during the smoke test.
        guard Checksum.crc32Screen(mascot[0..<0x20000]) == 0x5819_88BE else {
            throw PipelineError("The mascot picture in this file doesn't match the verified factory copy.")
        }
        pieces.append(Piece(slot: .photo, name: "Factory mascot", payload: mascot,
                            preview: ColorConversion.pixels(fromLE: mascot[11...]), frameCount: nil))

        // The three built-in wallpapers, offered as backgrounds (the factory background slot itself is empty).
        for (n, base) in [UInt32(0x0400_0000), 0x0406_0000, 0x040C_0000].enumerated() {
            let wallpaper = try read(base, ScreenProtocol.imageBytes)
            try ScreenProtocol.validateContainer(wallpaper)
            pieces.append(Piece(slot: .background, name: "Factory wallpaper \(n + 1)", payload: wallpaper,
                                preview: ColorConversion.pixels(fromLE: wallpaper[11...]), frameCount: nil))
        }

        let animation = try read(ScreenProtocol.Slot.gif.base, ScreenProtocol.gifMaxBytes)
        let info = try GIFContainer.info(animation)
        guard info.frameCount == 171, info.byteCount == ScreenProtocol.gifMaxBytes else {
            throw PipelineError("The factory animation in this file isn't the verified 171-frame version.")
        }
        pieces.append(Piece(slot: .gif, name: "Factory animation", payload: animation,
                            preview: try GIFContainer.decodeFrame(animation, index: 0), frameCount: info.frameCount))
        return pieces
    }
}
