import L99Core
import SwiftUI
import UniformTypeIdentifiers

/// State of the upload window: the chosen file, framing, and the prepared bytes.
@Observable
final class UploadModel {
    var slot: ScreenProtocol.Slot = .photo
    private(set) var source: SourceImage?
    private(set) var loadError: String?

    var framing = Framing() { didSet { if framing != oldValue { invalidate() } } }
    var smoothGradients = true { didSet { if smoothGradients != oldValue { invalidate() } } }
    var gifColors: ImagePipeline.GIFColors = .shared { didSet { if gifColors != oldValue { invalidate() } } }

    /// What the screen will show (first frame for animations).
    private(set) var preview: CGImage?
    private(set) var still: ImagePipeline.Still?
    private(set) var animation: ImagePipeline.Animation?
    private(set) var preparing: Double?           // GIF encoding progress
    private(set) var prepareError: String?
    var saveError: String?

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    var isGIF: Bool { slot == .gif }

    func load(_ url: URL) {
        do {
            let image = try SourceImage.load(url)
            source = image
            loadError = nil
            framing = Framing()
            if image.isAnimated { slot = .gif } else if slot == .gif { slot = .photo }
            invalidate()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func slotChanged() { invalidate() }

    /// Re-renders the preview, debounced so dragging stays smooth.
    func invalidate() {
        still = nil
        animation = nil
        prepareError = nil
        preparing = nil
        generation += 1
        let current = generation
        renderTask?.cancel()
        guard let source else { preview = nil; return }
        let framing = framing, smooth = smoothGradients, slot = slot, colors = gifColors
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> (CGImage?, ImagePipeline.Still?) in
                if slot == .gif {
                    // Preview the first frame with the chosen colour method; the full encode happens on Upload.
                    let rgba = ImagePipeline.render(source.frames[0], framing: framing)
                    let pixels: [UInt16]
                    switch colors {
                    case .shared: pixels = PaletteQuantizer.convertAnimation([rgba], width: 320, height: 480)[0]
                    case .ramp: pixels = ColorConversion.convert(rgba: rgba, width: 320, height: 480, method: .ramp)
                    }
                    return (ImagePipeline.cgImage(fromRGB565: pixels), nil)
                }
                guard let still = try? ImagePipeline.makeStill(source.frames[0], framing: framing, smoothGradients: smooth) else {
                    return (nil, nil)
                }
                return (ImagePipeline.cgImage(fromRGB565: still.pixels), still)
            }.value
            guard current == generation else { return }
            preview = result.0
            still = result.1
        }
    }

    /// Encodes the animation (can take a few seconds).
    func prepareAnimation() async -> ImagePipeline.Animation? {
        if let animation { return animation }
        guard let source else { return nil }
        let framing = framing, colors = gifColors, current = generation
        preparing = 0
        let report: @MainActor (Double) -> Void = { [weak self] value in
            if self?.generation == current { self?.preparing = value }
        }
        let progress: @Sendable (Double) -> Void = { value in Task { @MainActor in report(value) } }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try ImagePipeline.makeAnimation(source, framing: framing, colors: colors, progress: progress) }
        }.value
        guard current == generation else { return nil }
        preparing = nil
        switch result {
        case .success(let value):
            animation = value
            return value
        case .failure(let error):
            prepareError = error.localizedDescription
            return nil
        }
    }
}

struct UploadView: View {
    let model: AppModel
    @State private var upload = UploadModel()
    @State private var dropTargeted = false
    @State private var dragStart: CGSize?
    @State private var showingImporter = false

    var body: some View {
        HStack(spacing: 0) {
            sourcePane
                .frame(width: 250)
            Divider()
            previewPane
                .frame(minWidth: 420)
            Divider()
            settingsPane
                .frame(width: 280)
        }
        .frame(height: 660)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Destination", selection: $upload.slot) {
                    ForEach(ScreenProtocol.Slot.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onChange(of: upload.slot) { upload.slotChanged() }
            }
            ToolbarItem(placement: .automatic) {
                Label(model.devices.screen ? "Cable connected" : "Cable not connected",
                      systemImage: model.devices.screen ? "cable.connector" : "cable.connector.slash")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(model.devices.screen ? .green : .orange)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: SourceImage.supportedTypes) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                upload.load(url)
                if access { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    // MARK: Left

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SOURCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                Text("Drop an image or GIF").font(.callout)
                Text("PNG, JPEG, HEIC or GIF").font(.caption).foregroundStyle(.secondary)
                Button("Choose file…") { showingImporter = true }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                upload.load(url)
                return true
            } isTargeted: { dropTargeted = $0 }

            if let error = upload.loadError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if let source = upload.source {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.url.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(2)
                    Text("\(source.pixelWidth) × \(source.pixelHeight)" + (source.isAnimated ? " · \(source.frames.count) frames" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Replaces what's in the \(upload.slot.displayName.lowercased()) slot. Everything you send stays in your Library.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    // MARK: Middle

    private var previewPane: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.black)
                if let preview = upload.preview {
                    Image(decorative: preview, scale: 1)
                        .interpolation(.none)
                } else {
                    Text(upload.source == nil ? "Your picture appears here at its real size." : "Preparing preview…")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(width: 320, height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(14)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22))
            .gesture(DragGesture()
                .onChanged { value in
                    let start = dragStart ?? upload.framing.offset
                    dragStart = start
                    upload.framing.offset = CGSize(width: start.width + value.translation.width,
                                                   height: start.height + value.translation.height)
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityLabel("Preview at actual size, 320 by 480. Drag to move the picture.")
            Text("Actual size · 320 × 480 · colours as the screen shows them. Drag to move.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: Right

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FRAMING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Framing", selection: $upload.framing.mode) {
                    ForEach(Framing.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                LabeledContent("Zoom") {
                    Slider(value: $upload.framing.zoom, in: 0.5...3)
                }
                Button("Reset") { upload.framing = Framing(mode: upload.framing.mode) }
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("COLOUR").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if upload.isGIF {
                    Picker("Colours", selection: $upload.gifColors) {
                        ForEach(ImagePipeline.GIFColors.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    Text(upload.gifColors == .shared
                         ? "Exact colours where possible, otherwise a best-fit palette for each frame."
                         : "The fixed 252-colour palette from earlier tests. Use it if Best colours ever looks wrong.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle("Smooth gradients (dithering)", isOn: $upload.smoothGradients)
                    Text("The screen shows 65,536 colours. Dithering avoids banding in skies and gradients.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if upload.isGIF { gifPanel }

            Spacer()
            uploadControls
        }
        .padding(20)
    }

    private var gifPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ANIMATION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let source = upload.source {
                if let animation = upload.animation {
                    Text("\(animation.frameCount) frames · \(String(format: "%.1f", animation.seconds)) s · "
                         + ByteCountFormatter.string(fromByteCount: Int64(animation.blob.count), countStyle: .file)
                         + " of " + ByteCountFormatter.string(fromByteCount: Int64(ScreenProtocol.gifMaxBytes), countStyle: .file))
                        .font(.callout)
                    ForEach(animation.fixes, id: \.self) { fix in
                        Label(fix, systemImage: "wand.and.stars").font(.caption)
                    }
                } else if let progress = upload.preparing {
                    ProgressView("Preparing frames…", value: progress)
                } else {
                    Text("\(source.frames.count) frames · \(String(format: "%.1f", source.duration)) s")
                        .font(.callout)
                    if source.frames.count > GIFContainer.maxFrames {
                        Label("More than \(GIFContainer.maxFrames) frames; some will be left out evenly.",
                              systemImage: "exclamationmark.triangle").font(.caption)
                    }
                    Button("Prepare and check size") { Task { await upload.prepareAnimation() } }
                        .controlSize(.small)
                }
                if let error = upload.prepareError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("Frames, timing and size checks appear here.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var uploadControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TransferStatus(transfer: model.transfer)
            if let error = upload.saveError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !model.devices.screen {
                Text("Plug in the USB cable to upload. The 2.4 GHz dongle can't carry pictures.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button {
                Task { await sendToScreen() }
            } label: {
                Text(model.transfer.isBusy ? "Uploading…" : "Upload").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canUpload)
        }
    }

    private var canUpload: Bool {
        guard upload.source != nil, model.devices.screen, !model.transfer.isBusy, upload.preparing == nil else { return false }
        return upload.isGIF || upload.still != nil
    }

    private func sendToScreen() async {
        guard let source = upload.source else { return }
        upload.saveError = nil
        let name = source.url.deletingPathExtension().lastPathComponent
        do {
            let item: LibraryItem
            if upload.isGIF {
                guard let animation = await upload.prepareAnimation() else { return }
                let preview = animation.previewFrames.first.flatMap { ImagePipeline.cgImage(fromRGB565: $0) }
                item = try model.library.add(slot: .gif, name: name, payload: animation.blob, preview: preview,
                                             source: source.url, frameCount: animation.frameCount)
            } else {
                guard let still = upload.still else { return }
                item = try model.library.add(slot: upload.slot, name: name, payload: still.container,
                                             preview: ImagePipeline.cgImage(fromRGB565: still.pixels), source: source.url)
            }
            model.transfer.send(item)
        } catch {
            upload.saveError = "Couldn't save to the Library: \(error.localizedDescription)"
        }
    }
}
