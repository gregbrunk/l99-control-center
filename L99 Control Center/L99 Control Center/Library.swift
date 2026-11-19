import AppKit
import Foundation
import L99Core
import Observation

/// Everything ever sent to the screen, kept on the Mac so it can be sent again or checked.
/// Each item is a folder in ~/Library/Application Support/L99 Control Center/Library/:
///   item.json, payload.bin (the exact bytes sent), thumb.png, and the original file when there is one.
nonisolated struct LibraryItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var slot: ScreenProtocol.Slot
    var name: String
    var created: Date
    var lastSent: Date?
    var byteCount: Int
    var isFactory: Bool
    var frameCount: Int?
    var sourceFileName: String?
}

@Observable
final class Library {
    private(set) var items: [LibraryItem] = []
    /// Which item each slot holds, as far as this Mac knows (set after a completed upload or a passing check).
    private(set) var onScreen: [ScreenProtocol.Slot: UUID] = [:]
    private(set) var thumbnails: [UUID: NSImage] = [:]

    let root: URL

    init(root: URL = Library.defaultRoot) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("L99 Control Center/Library", isDirectory: true)
    }

    private var onScreenFile: URL { root.appendingPathComponent("on-screen.json") }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("item.json")) else { return nil }
            return try? decoder.decode(LibraryItem.self, from: data)
        }
        .sorted { ($0.lastSent ?? $0.created) > ($1.lastSent ?? $1.created) }
        for item in items where thumbnails[item.id] == nil {
            thumbnails[item.id] = NSImage(contentsOf: folder(item.id).appendingPathComponent("thumb.png"))
        }
        if let data = try? Data(contentsOf: onScreenFile),
           let map = try? JSONDecoder().decode([String: UUID].self, from: data) {
            onScreen = Dictionary(uniqueKeysWithValues: map.compactMap { key, value in
                ScreenProtocol.Slot(rawValue: key).map { ($0, value) }
            })
        }
    }

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func payload(of item: LibraryItem) throws -> [UInt8] {
        let bytes = [UInt8](try Data(contentsOf: folder(item.id).appendingPathComponent("payload.bin")))
        guard bytes.count == item.byteCount else { throw PipelineError("The stored copy of “\(item.name)” is damaged.") }
        return bytes
    }

    /// Stores a new item. `payload` is exactly what will be sent; `source` is copied when given.
    @discardableResult
    func add(slot: ScreenProtocol.Slot, name: String, payload: [UInt8], preview: CGImage?,
             source: URL? = nil, isFactory: Bool = false, frameCount: Int? = nil) throws -> LibraryItem {
        let item = LibraryItem(id: UUID(), slot: slot, name: name, created: Date(), lastSent: nil,
                               byteCount: payload.count, isFactory: isFactory, frameCount: frameCount,
                               sourceFileName: source?.lastPathComponent)
        let dir = folder(item.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(payload).write(to: dir.appendingPathComponent("payload.bin"), options: .atomic)
        if let preview, let png = ImagePipeline.pngData(preview) {
            try png.write(to: dir.appendingPathComponent("thumb.png"), options: .atomic)
            thumbnails[item.id] = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        }
        if let source {
            try? FileManager.default.copyItem(at: source, to: dir.appendingPathComponent("source-" + source.lastPathComponent))
        }
        try save(item)
        items.insert(item, at: 0)
        return item
    }

    func markSent(_ item: LibraryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastSent = Date()
        try? save(items[index])
        setOnScreen(item.slot, item.id)
    }

    /// An interface install (skin or stock) rewrites all three slots: the factory photo and GIF come back,
    /// and the background holds the skin's Home picture (or nothing, for stock).
    func interfaceInstalled() {
        for slot in [ScreenProtocol.Slot.photo, .gif] {
            setOnScreen(slot, items.first(where: { $0.isFactory && $0.slot == slot })?.id)
        }
        setOnScreen(.background, nil)
    }

    func setOnScreen(_ slot: ScreenProtocol.Slot, _ id: UUID?) {
        onScreen[slot] = id
        let map = Dictionary(uniqueKeysWithValues: onScreen.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: onScreenFile, options: .atomic) }
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.trashItem(at: folder(item.id), resultingItemURL: nil)
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        if onScreen[item.slot] == item.id { setOnScreen(item.slot, nil) }
    }

    func revealInFinder(_ item: LibraryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([folder(item.id).appendingPathComponent("payload.bin")])
    }

    func item(_ id: UUID?) -> LibraryItem? { items.first { $0.id == id } }

    var hasFactoryContent: Bool { items.contains { $0.isFactory } }

    private func save(_ item: LibraryItem) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(item).write(to: folder(item.id).appendingPathComponent("item.json"), options: .atomic)
    }
}
