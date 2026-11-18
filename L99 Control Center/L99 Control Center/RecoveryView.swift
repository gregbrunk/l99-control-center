import AppKit
import L99Core
import SwiftUI

struct RecoveryView: View {
    let model: AppModel
    @State private var restorePhoto = true
    @State private var restoreAnimation = false
    @State private var restoreBackground = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let interrupted = model.transfer.interrupted {
                interruptedCard(interrupted)
            }
            factoryCard
            windowsCard
            TransferStatus(transfer: model.transfer)
        }
        .padding(18)
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Interrupted upload

    private func interruptedCard(_ interrupted: ScreenTransferController.Interrupted) -> some View {
        Card(systemImage: "exclamationmark.triangle", tint: .orange, title: "Last upload didn't finish") {
            Text("“\(interrupted.name)” stopped at \(interrupted.fraction, format: .percent.precision(.fractionLength(0))). \(interrupted.reason) The keyboard itself is fine; only the \(interrupted.slot.displayName.lowercased()) is incomplete.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Make sure the USB cable is plugged in.")
                Text("2. If the screen is frozen, unplug the cable, wait 5 seconds and plug it back in.")
                Text("3. Send the same picture again. It always restarts from the beginning.")
            }
            .font(.callout)
            HStack {
                Button("Send again") {
                    if let item = model.library.item(interrupted.itemID) { model.transfer.send(item) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.devices.screen || model.transfer.isBusy || model.library.item(interrupted.itemID) == nil)
                Button("Not now") { model.transfer.forgetInterrupted() }
                if !model.devices.screen {
                    Text("Plug in the cable first.").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Factory content

    private var factoryItems: [ScreenProtocol.Slot: [LibraryItem]] {
        Dictionary(grouping: model.library.items.filter(\.isFactory), by: \.slot)
    }

    private var factoryCard: some View {
        Card(systemImage: "arrow.counterclockwise", tint: .primary, title: "Put back the factory pictures") {
            if model.library.hasFactoryContent {
                Text("Sends the original pictures that came with the keyboard, over the cable. The animation takes about a minute.")
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Photo frame: the mascot", isOn: $restorePhoto)
                Toggle("Animation: the factory GIF (26 MB)", isOn: $restoreAnimation)
                Toggle("Background: factory wallpaper 1", isOn: $restoreBackground)
                Text("The keyboard's own default background is built in and isn't stored in the background slot, so a factory wallpaper is the closest match.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Restore selected") { restore() }
                    .disabled(!model.devices.screen || model.transfer.isBusy || !(restorePhoto || restoreAnimation || restoreBackground))
            } else {
                Text("First, add the factory pictures from AULA's reset package to your Library. Choose UartTFT-II_Flash.bin; every picture in it is checked against the verified copy.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(importing ? "Checking…" : "Choose UartTFT-II_Flash.bin…") { chooseFactoryFile() }
                        .disabled(importing)
                    if importing { ProgressView().controlSize(.small) }
                }
                if let importError {
                    Text(importError).font(.callout).foregroundStyle(.red)
                }
            }
        }
    }

    private func restore() {
        var queue = [LibraryItem]()
        if restorePhoto, let item = factoryItems[.photo]?.first { queue.append(item) }
        if restoreBackground, let item = factoryItems[.background]?.first(where: { $0.name.hasSuffix("1") }) { queue.append(item) }
        if restoreAnimation, let item = factoryItems[.gif]?.first { queue.append(item) }
        model.transfer.send(queue)
    }

    private func chooseFactoryFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose UartTFT-II_Flash.bin"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/L99 Control Center/research/factory")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        importError = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FactoryContent.extract(from: url) } }.value
            importing = false
            switch result {
            case .success(let pieces):
                do {
                    for piece in pieces.reversed() {
                        try model.library.add(slot: piece.slot, name: piece.name, payload: piece.payload,
                                              preview: ImagePipeline.cgImage(fromRGB565: piece.preview),
                                              isFactory: true, frameCount: piece.frameCount)
                    }
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    // MARK: Windows fallback

    private var windowsCard: some View {
        Card(systemImage: "desktopcomputer", tint: .primary, title: "If the screen won't start at all") {
            Text("This app only writes the three picture slots, so this shouldn't happen. If it ever does, the full fix needs a Windows PC and AULA's reset package (research/L99 reset firmware 2026.5.25). Typing keeps working in the meantime.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To enter upgrade mode, press Fn + X, then 0, then 6, or hold Fn + Space for about 5 seconds with the USB cable connected. Then run AULA's tool on Windows.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Card<Content: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint == .primary ? Color.primary : tint)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint == .orange ? Color.orange.opacity(0.6) : Color(nsColor: .separatorColor)))
    }
}
