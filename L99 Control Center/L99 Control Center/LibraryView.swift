import L99Core
import SwiftUI

struct LibraryView: View {
    let model: AppModel
    private var filter: ScreenProtocol.Slot? { model.libraryFilter }
    private var search: String { model.librarySearch }
    @State private var pendingDelete: LibraryItem?

    private var items: [LibraryItem] {
        model.library.items.filter { item in
            (filter == nil || item.slot == filter) &&
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.skins.homeSkinInstalled {
                Notice(systemImage: "rectangle.on.rectangle.slash", tint: .orange,
                       text: "Backgrounds are off while a Home skin is on the keyboard: the skin draws Home itself. Keep Screen › Background on Default on the keyboard.",
                       large: true) {
                    Button("Open Skins") { withAnimation(Studio.motion) { model.tab = .skins } }
                }
            }
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "photo.on.rectangle",
                                       description: Text("Pictures you upload appear here. Factory content can be added from Recovery."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 18)], spacing: 18) {
                        ForEach(items) { item in
                            LibraryCard(model: model, item: item, onDelete: { pendingDelete = item })
                        }
                    }
                }
            }
            if !model.devices.screen {
                Label("Sending needs the USB cable.", systemImage: "cable.connector.horizontal")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
            }
            TransferStatus(transfer: model.transfer)
        }
        .confirmationDialog("Move “\(pendingDelete?.name ?? "")” to the Trash?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingDelete { model.library.delete(item) }
                pendingDelete = nil
            }
        } message: {
            Text("This removes it from the Library on this Mac. What's on the keyboard's screen doesn't change.")
        }
    }
}

private struct LibraryCard: View {
    let model: AppModel
    let item: LibraryItem
    let onDelete: () -> Void

    private var isOnScreen: Bool { model.library.onScreen[item.slot] == item.id }
    /// A Home skin owns the background slot, so backgrounds can't be sent.
    private var blocked: Bool { item.slot == .background && model.skins.homeSkinInstalled }
    private var canTalk: Bool { model.devices.screen && !model.transfer.isBusy && !blocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = model.library.thumbnails[item.id] {
                        Image(nsImage: image).resizable()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Tag(text: item.slot.displayName, background: .white.opacity(0.92), foreground: .black)
                    Spacer()
                    if blocked {
                        Tag(text: "Off", background: .black.opacity(0.7), foreground: .white)
                    }
                }
                .padding(8)
            }
            .saturation(blocked ? 0 : 1)
            .opacity(blocked ? 0.5 : 1)
            Text(item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text(subtitle).font(.l99Note).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Button("Send") { model.transfer.send(item) }
                    .disabled(!canTalk)
                    .help(blocked ? "Backgrounds don't show while a Home skin is installed." : "")
                Spacer(minLength: 4)
                if isOnScreen && !blocked { StatusPill(text: "On screen") }
            }
                .controlSize(.small)
        }
        .studioCard(padding: 10)
        .hoverLift()
        .contextMenu {
            Button("Show in Finder") { model.library.revealInFinder(item) }
            Divider()
            Button("Move to Trash…", role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        var parts = [String]()
        if item.isFactory { parts.append("Factory") }
        if let frames = item.frameCount { parts.append("\(frames) frames") }
        parts.append((item.lastSent ?? item.created).formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

private struct Tag: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
}
