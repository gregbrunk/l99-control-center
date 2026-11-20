import AppKit
import Foundation
import L99Core

/// Moving to another Mac: one .zip with the Library, the verified stock interface file and the settings
/// (including which skin is on the keyboard). Things that belong to one Mac stay behind: window sizes,
/// launch at login, the weather location and permissions.
nonisolated enum Migration {
    static let format = 1

    /// UserDefaults keys that travel.
    static let settingsKeys = [
        "skinPlan", "installedSkinPlan", "installedSkinDate",
        "units.us", "live.clock", "live.load", "live.weather",
        "music.enabled", "music.sensitivity", "music.foreMode", "music.backMode", "music.direction", "music.palette",
    ]

    struct Manifest: Codable {
        var format: Int
        var created: Date
        var libraryItems: Int
        var hasStockFile: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("L99 Control Center", isDirectory: true)
    }
    static var libraryFolder: URL { appSupport.appendingPathComponent("Library", isDirectory: true) }
    static var stockFile: URL { appSupport.appendingPathComponent("Skins/UartTFT-II_Flash.bin") }

    // MARK: Export

    /// Writes the transfer file. Returns what went in.
    static func export(to zip: URL) throws -> Manifest {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("L99 export \(UUID().uuidString)", isDirectory: true)
        let bundle = stage.appendingPathComponent("L99 Control Center Transfer", isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)

        var items = 0
        if fm.fileExists(atPath: libraryFolder.path) {
            try fm.copyItem(at: libraryFolder, to: bundle.appendingPathComponent("Library"))
            items = ((try? fm.contentsOfDirectory(atPath: libraryFolder.path)) ?? [])
                .filter { fm.fileExists(atPath: libraryFolder.appendingPathComponent("\($0)/item.json").path) }.count
        }
        let hasStock = fm.fileExists(atPath: stockFile.path)
        if hasStock {
            try fm.copyItem(at: stockFile, to: bundle.appendingPathComponent("UartTFT-II_Flash.bin"))
        }

        var settings: [String: Any] = [:]
        for key in settingsKeys { if let value = UserDefaults.standard.object(forKey: key) { settings[key] = value } }
        let plist = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("settings.plist"))

        let manifest = Manifest(format: format, created: Date(), libraryItems: items, hasStockFile: hasStock)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: bundle.appendingPathComponent("manifest.json"))

        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        try ditto(["-c", "-k", "--norsrc", "--keepParent", bundle.path, zip.path])
        return manifest
    }

    // MARK: Import

    /// Checks a transfer file, moves this Mac's current Library to the Trash, and puts the transferred
    /// Library, stock file and settings in place. The app should relaunch afterwards.
    static func importArchive(_ zip: URL) throws -> Manifest {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("L99 import \(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try ditto(["-x", "-k", zip.path, stage.path])

        let bundle = stage.appendingPathComponent("L99 Control Center Transfer", isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("manifest.json")),
              let manifest = try? decoder.decode(Manifest.self, from: data) else {
            throw Failure("That isn't an L99 Control Center transfer file.")
        }
        guard manifest.format <= format else {
            throw Failure("This transfer file comes from a newer version of L99 Control Center. Update the app first.")
        }

        // Check everything before changing anything.
        let newStock = bundle.appendingPathComponent("UartTFT-II_Flash.bin")
        if manifest.hasStockFile {
            do { _ = try InterfaceFile(stockFile: newStock.path) } catch {
                throw Failure("The stock interface file in the transfer is damaged. Export it again.")
            }
        }
        var settings: [String: Any] = [:]
        if let plist = try? Data(contentsOf: bundle.appendingPathComponent("settings.plist")) {
            settings = (try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]) ?? [:]
        }

        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let newLibrary = bundle.appendingPathComponent("Library", isDirectory: true)
        if fm.fileExists(atPath: newLibrary.path) {
            if fm.fileExists(atPath: libraryFolder.path) { try fm.trashItem(at: libraryFolder, resultingItemURL: nil) }
            try fm.moveItem(at: newLibrary, to: libraryFolder)
        }
        if manifest.hasStockFile {
            try fm.createDirectory(at: stockFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: stockFile.path) { try fm.removeItem(at: stockFile) }
            try fm.moveItem(at: newStock, to: stockFile)
        }
        for key in settingsKeys {
            if let value = settings[key] { UserDefaults.standard.set(value, forKey: key) }
        }
        return manifest
    }

    // MARK: Helpers

    private static func ditto(_ arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = arguments
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if arguments.first == "-x" { throw Failure("That isn't an L99 Control Center transfer file, or it didn't copy completely.") }
            throw Failure("Couldn't write the transfer file. \(text)")
        }
    }

    /// Quits and opens the app again, so every part reads the imported files.
    @MainActor static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

#if DEBUG
/// Debug builds: `--export-transfer <zip>` / `--import-transfer <zip>` run the move without the window, then quit.
enum MigrationCommand {
    static func runIfRequested() {
        let args = CommandLine.arguments
        for (flag, run) in [("--export-transfer", Migration.export(to:)), ("--import-transfer", Migration.importArchive)] {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { continue }
            do {
                let m = try run(URL(fileURLWithPath: args[i + 1]))
                print("\(flag): ok, \(m.libraryItems) items, stock file: \(m.hasStockFile)")
                exit(0)
            } catch {
                print("\(flag): failed: \(error.localizedDescription)")
                exit(1)
            }
        }
    }
}
#endif
