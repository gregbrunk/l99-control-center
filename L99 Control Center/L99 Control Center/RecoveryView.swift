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
        VStack(alignment: .leading, spacing: 20) {
            if let interrupted = model.transfer.interrupted {
                interruptedCard(interrupted)
            }
            factoryCard
            windowsCard
            TransferStatus(transfer: model.transfer)
        }
    }

    // MARK: Interrupted upload

    private func interruptedCard(_ interrupted: ScreenTransferController.Interrupted) -> some View {
        Card(systemImage: "exclamationmark.triangle", tint: .orange, title: "Last upload didn't finish",
             subtitle: "“\(interrupted.name)” stopped at \(interrupted.fraction.formatted(.percent.precision(.fractionLength(0)))). \(interrupted.reason)") {
            Text("The keyboard itself is fine; only the \(interrupted.slot.displayName.lowercased()) is incomplete.")
                .fixedSize(horizontal: false, vertical: true)
            StepList(steps: ["Make sure the USB cable is plugged in.",
                             "If the screen is frozen, unplug the cable, wait 5 seconds and plug it back in.",
                             "Send the same picture again. It always restarts from the beginning."])
            HStack(spacing: 10) {
                Button("Send again") {
                    if let item = model.library.item(interrupted.itemID) { model.transfer.send(item) }
                }
                .buttonStyle(.studioPrimary)
                .disabled(!model.devices.screen || model.transfer.isBusy || model.library.item(interrupted.itemID) == nil)
                Button("Not now") { model.transfer.forgetInterrupted() }
                if !model.devices.screen {
                    Text("Plug in the cable first.").font(.l99Note).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Factory content

    private var factoryItems: [ScreenProtocol.Slot: [LibraryItem]] {
        Dictionary(grouping: model.library.items.filter(\.isFactory), by: \.slot)
    }

    private var factoryCard: some View {
        Card(systemImage: "arrow.counterclockwise", tint: Studio.accent, title: "Put back the factory pictures",
             subtitle: model.library.hasFactoryContent
                ? "Pick what to send back over the cable. The animation takes about a minute."
                : "First, add the factory pictures from AULA's reset package to your Library.") {
            if model.library.hasFactoryContent {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    factoryTile(.photo, title: "Photo frame", detail: "The mascot", isOn: $restorePhoto)
                    factoryTile(.gif, title: "Animation", detail: "The factory GIF · 26 MB", isOn: $restoreAnimation)
                    factoryTile(.background, title: "Background", detail: model.skins.homeSkinInstalled ? "Off under a Home skin" : "Factory wallpaper 1",
                                isOn: $restoreBackground, blocked: model.skins.homeSkinInstalled)
                }
                Text("The keyboard's own default background is built in and isn't stored in the background slot, so a factory wallpaper is the closest match.")
                    .font(.l99Note).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { restore() } label: { Label("Restore \(selectedCount) selected", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.studioPrimary)
                        .controlSize(.large)
                        .disabled(!model.devices.screen || model.transfer.isBusy || selectedCount == 0)
                    if !model.devices.screen {
                        Label("Needs the USB cable", systemImage: "cable.connector.horizontal").font(.l99Note).foregroundStyle(.orange)
                    }
                }
            } else {
                Text("Choose UartTFT-II_Flash.bin; every picture in it is checked against the verified copy.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(importing ? "Checking…" : "Choose UartTFT-II_Flash.bin…") { chooseFactoryFile() }
                        .buttonStyle(.studioPrimary)
                        .disabled(importing)
                    if importing { ProgressView().controlSize(.small) }
                }
                if let importError {
                    Text(importError).font(.l99Note).foregroundStyle(.red)
                }
            }
        }
    }

    private var selectedCount: Int {
        [restorePhoto, restoreAnimation, restoreBackground && !model.skins.homeSkinInstalled].filter { $0 }.count
    }

    private func factoryTile(_ slot: ScreenProtocol.Slot, title: String, detail: String, isOn: Binding<Bool>, blocked: Bool = false) -> some View {
        let item = slot == .background ? factoryItems[slot]?.first(where: { $0.name.hasSuffix("1") }) : factoryItems[slot]?.first
        let on = isOn.wrappedValue && !blocked
        return OptionTile(selected: on, action: { isOn.wrappedValue.toggle() }) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let item, let image = model.library.thumbnails[item.id] {
                        Image(nsImage: image).resizable().interpolation(.medium)
                    } else {
                        Rectangle().fill(Studio.secondaryFill)
                    }
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .saturation(blocked ? 0 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    TileCheck(on: on)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 90)
        }
        .disabled(blocked)
    }

    private func restore() {
        var queue = [LibraryItem]()
        if restorePhoto, let item = factoryItems[.photo]?.first { queue.append(item) }
        if restoreBackground, !model.skins.homeSkinInstalled, let item = factoryItems[.background]?.first(where: { $0.name.hasSuffix("1") }) { queue.append(item) }
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
        Card(systemImage: "desktopcomputer", tint: .secondary, title: "If the screen won't start at all",
             subtitle: "This app only writes the three picture slots, so this shouldn't happen. Typing keeps working in the meantime.") {
            StepList(steps: ["Find a Windows PC and AULA's reset package (research/L99 reset firmware 2026.5.25).",
                             "Connect the USB cable, then press Fn + X, then 0, then 6, or hold Fn + Space for about 5 seconds, to enter upgrade mode.",
                             "Run AULA's tool on Windows."])
        }
    }
}

/// A numbered list of steps with accent number badges.
struct StepList: View {
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Studio.accent)
                        .frame(width: 24, height: 24)
                        .background(Studio.accentSoft, in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(steps[i]).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A titled card with an icon badge; an orange tint marks it as needing attention.
struct Card<Content: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        SectionCard(icon: systemImage, title: title, subtitle: subtitle, tint: tint == .primary ? .secondary : tint) {
            VStack(alignment: .leading, spacing: 14) { content() }
        }
        .overlay(RoundedRectangle(cornerRadius: Studio.cardRadius, style: .continuous)
            .strokeBorder(tint == .orange ? Color.orange.opacity(0.5) : .clear))
    }
}
