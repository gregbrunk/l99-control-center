import L99Core
import SwiftUI

struct LibraryView: View {
    let model: AppModel
    @State private var filter: ScreenProtocol.Slot?
    @State private var search = ""
    @State private var pendingDelete: LibraryItem?

    private var items: [LibraryItem] {
        model.library.items.filter { item in
            (filter == nil || item.slot == filter) &&
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything you've sent to the screen is kept here, so you can send it again. A blue tag means it's on the screen now.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "photo.on.rectangle",
                                       description: Text("Pictures you upload appear here. Factory content can be added from Recovery."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 12)], spacing: 12) {
                        ForEach(items) { item in
                            LibraryCard(model: model, item: item, onDelete: { pendingDelete = item })
                        }
                    }
                }
            }
            if !model.devices.screen {
                Label("Sending needs the USB cable.", systemImage: "cable.connector")
                    .font(.callout).foregroundStyle(.orange)
            }
            TransferStatus(transfer: model.transfer)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $filter) {
                    Text("All").tag(ScreenProtocol.Slot?.none)
                    ForEach(ScreenProtocol.Slot.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .frame(width: 340)
            }
        }
        .searchable(text: $search, placement: .toolbar)
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
    private var canTalk: Bool { model.devices.screen && !model.transfer.isBusy }

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
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Tag(text: item.slot.displayName, background: .white.opacity(0.92), foreground: .black)
                    Spacer()
                    if isOnScreen { Tag(text: "On screen", background: .accentColor, foreground: .white) }
                }
                .padding(6)
            }
            Text(item.name).font(.callout.weight(.semibold)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("Send") { model.transfer.send(item) }
                .disabled(!canTalk)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
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
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(foreground)
    }
}
