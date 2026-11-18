import Foundation
import L99Core
import L99Link
import Observation

/// Runs one screen job at a time (upload or check) off the main thread and publishes its state.
/// Safety: every byte goes through `ScreenTransfer`, which only uses the bounds-checked slot plans.
@Observable
final class ScreenTransferController {
    enum State: Equatable {
        case idle
        case sending(name: String, slot: ScreenProtocol.Slot, fraction: Double, attempt: Int)
        case done(String)
        case failed(String)
    }

    /// An upload that started but didn't finish. Kept across launches so Recovery can offer a resend.
    struct Interrupted: Codable, Equatable {
        var itemID: UUID
        var slot: ScreenProtocol.Slot
        var name: String
        var fraction: Double
        var reason: String
    }

    private(set) var state: State = .idle
    private(set) var interrupted: Interrupted? {
        didSet {
            let data = try? interrupted.map { try JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: "interruptedUpload")
        }
    }

    var isBusy: Bool {
        switch state {
        case .sending: true
        default: false
        }
    }

    @ObservationIgnored private let cancelFlag = CancelFlag()
    @ObservationIgnored private let library: Library

    init(library: Library) {
        self.library = library
        if let data = UserDefaults.standard.data(forKey: "interruptedUpload") {
            interrupted = try? JSONDecoder().decode(Interrupted.self, from: data)
        }
    }

    /// Items waiting to be sent after the current one (Restore factory content sends several).
    private(set) var queue: [LibraryItem] = []

    func cancel() {
        cancelFlag.set(true)
        queue = []
    }

    /// Sends several items one after another. Stops at the first failure.
    func send(_ items: [LibraryItem]) {
        guard !isBusy, let first = items.first else { return }
        queue = Array(items.dropFirst())
        send(first)
    }

    func dismissResult() {
        if case .done = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    func forgetInterrupted() { interrupted = nil }

    /// Sends a library item to its slot. Retries once from the start of the slot after an error.
    func send(_ item: LibraryItem) {
        guard !isBusy else { return }
        let payload: [UInt8]
        do { payload = try library.payload(of: item) } catch { state = .failed(error.localizedDescription); return }
        cancelFlag.set(false)
        let flag = cancelFlag
        let name = item.name, slot = item.slot
        interrupted = Interrupted(itemID: item.id, slot: slot, name: name, fraction: 0, reason: "The upload was still running.")
        state = .sending(name: name, slot: slot, fraction: 0, attempt: 1)

        // The controller lives as long as the app, so the worker holds it strongly.
        Task.detached(priority: .userInitiated) { [self] in
            let throttle = ProgressThrottle()
            var attempt = 1
            while true {
                do {
                    let port = try ScreenPort()
                    let result = try ScreenTransfer.upload(payload, to: slot, port: port) { progress in
                        if throttle.shouldReport(progress.fraction) {
                            let a = attempt
                            Task { @MainActor in self.state = .sending(name: name, slot: slot, fraction: progress.fraction, attempt: a) }
                        }
                        return !flag.isSet
                    }
                    let lastFraction = throttle.latest
                    await MainActor.run {
                        switch result {
                        case .completed:
                            self.interrupted = nil
                            self.library.markSent(item)
                            self.state = .done("“\(name)” is on the screen. On the keyboard, leave that page and open it again to see it.")
                            if !self.queue.isEmpty {
                                let next = self.queue.removeFirst()
                                self.send(next)
                            }
                        case .cancelled:
                            self.interrupted = Interrupted(itemID: item.id, slot: slot, name: name, fraction: lastFraction,
                                                           reason: "You cancelled the upload.")
                            self.library.setOnScreen(slot, nil)
                            self.state = .failed("Upload cancelled. The \(slot.displayName.lowercased()) is incomplete until you send something to it again.")
                        }
                    }
                    return
                } catch {
                    if attempt < 2 && !flag.isSet {
                        attempt += 1
                        try? await Task.sleep(for: .seconds(1.5))
                        continue
                    }
                    let message = error.localizedDescription
                    let lastFraction = throttle.latest
                    await MainActor.run {
                        self.queue = []
                        self.interrupted = Interrupted(itemID: item.id, slot: slot, name: name, fraction: lastFraction, reason: message)
                        self.library.setOnScreen(slot, nil)
                        self.state = .failed(message)
                    }
                    return
                }
            }
        }
    }
}

/// Thread-safe flag shared with the worker.
nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set(_ v: Bool) { lock.withLock { value = v } }
}

/// Limits progress updates to about one per percent, and remembers the latest fraction seen.
nonisolated final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    private var newest = 0.0
    var latest: Double { lock.withLock { newest } }
    func shouldReport(_ fraction: Double) -> Bool {
        lock.withLock {
            newest = fraction
            if fraction >= 1 || fraction - last >= 0.01 { last = fraction; return true }
            return false
        }
    }
}
