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
    @Bindable private var upload: UploadModel
    @State private var dropTargeted = false
    @State private var dragStart: CGSize?
    @State private var showingImporter = false

    init(model: AppModel) {
        self.model = model
        _upload = Bindable(model.upload)
    }

    var body: some View {
        GeometryReader { geo in
            // Side columns grow with the window; the preview takes the rest.
            let side = min(360, max(270, geo.size.width * 0.27))
            HStack(spacing: 0) {
                sourcePane.frame(width: side)
                Divider()
                previewPane.frame(maxWidth: .infinity)
                Divider()
                settingsPane.frame(width: side)
            }
        }
        .frame(maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Source")
            dropZone
            if let error = upload.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.l99Note).foregroundStyle(.red)
            }
            if let source = upload.source {
                HStack(spacing: 12) {
                    Image(systemName: source.isAnimated ? "play.rectangle.fill" : "photo.fill")
                        .font(.system(size: 16)).foregroundStyle(Studio.accent)
                        .frame(width: 40, height: 40)
                        .background(Studio.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text("\(source.pixelWidth) × \(source.pixelHeight)" + (source.isAnimated ? " · \(source.frames.count) frames" : ""))
                            .font(.l99Note).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard(padding: 12)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Replaces what's in the \(upload.slot.displayName.lowercased()) slot. Everything you send stays in your Library.",
                      systemImage: "arrow.triangle.2.circlepath")
                if model.skins.homeSkinInstalled {
                    Label("Background is off: the Home skin on the keyboard draws Home itself.", systemImage: "paintpalette")
                        .foregroundStyle(Color(light: 0xB4521B, dark: 0xF5B48A))
                }
            }
            .font(.l99Note)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 14) {
            ZStack {
                Circle().fill(Studio.accent.opacity(dropTargeted ? 0.25 : 0.12)).frame(width: 84, height: 84)
                Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Studio.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(dropTargeted ? 1.08 : 1)
            VStack(spacing: 4) {
                Text(dropTargeted ? "Drop to load" : "Drop an image or GIF").font(.system(size: 17, weight: .semibold))
                Text("PNG, JPEG, HEIC or GIF").font(.l99Note).foregroundStyle(.secondary)
            }
            Button("Choose file…") { showingImporter = true }
                .buttonStyle(.studioPrimary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 420)
        .background(dropTargeted ? Studio.accentSoft : Studio.card.opacity(0.7), in: shape)
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .foregroundStyle(dropTargeted ? Studio.accent : Color.secondary.opacity(0.45)))
        .animation(Studio.snap, value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            upload.load(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: Middle

    private var previewPane: some View {
        GeometryReader { geo in
            // As big as the space allows (whole steps when that's possible, so pixels stay crisp).
            let fit = min((geo.size.width - 96) / 320, (geo.size.height - 110) / 480)
            let scale = max(0.6, fit >= 2 ? floor(fit * 2) / 2 : fit)
            VStack(spacing: 16) {
                ZStack {
                    Rectangle().fill(.black)
                    if let preview = upload.preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .interpolation(.none)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: upload.source == nil ? "sparkles.rectangle.stack" : "hourglass")
                                .font(.system(size: 30, weight: .light))
                            Text(upload.source == nil ? "Your picture appears here,\nexactly as the screen will show it." : "Preparing preview…")
                                .font(.system(size: 15))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .padding()
                    }
                }
                .frame(width: 320 * scale, height: 480 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                .padding(12 * scale)
                .background(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 26 * scale, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26 * scale, style: .continuous).strokeBorder(.white.opacity(0.10)))
                .shadow(color: .black.opacity(0.30), radius: 30, y: 16)
                .gesture(DragGesture()
                    .onChanged { value in
                        let start = dragStart ?? upload.framing.offset
                        dragStart = start
                        // The preview is scaled up; the offset is in screen pixels.
                        upload.framing.offset = CGSize(width: start.width + value.translation.width / scale,
                                                       height: start.height + value.translation.height / scale)
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityLabel("Preview of the 320 by 480 screen. Drag to move the picture.")
                HStack(spacing: 8) {
                    StatusPill(text: String(format: "%g×", (scale * 10).rounded() / 10), tint: .secondary, dot: false)
                    Text("320 × 480 · colours as the screen shows them · drag to move")
                }
                .font(.l99Note)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Studio.canvas.opacity(0.55))
    }

    // MARK: Right

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Framing")
                PillPicker(selection: $upload.framing.mode,
                           options: Framing.Mode.allCases.map { PillOption(value: $0, label: $0.rawValue, icon: $0.rawValue == "Fill" ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") },
                           large: true, fill: true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Zoom").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(String(format: "%.0f%%", upload.framing.zoom * 100)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $upload.framing.zoom, in: 0.5...3)
                }
                Button { upload.framing = Framing(mode: upload.framing.mode) } label: {
                    Label("Reset position and zoom", systemImage: "arrow.counterclockwise")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Colour")
                if upload.isGIF {
                    VStack(spacing: 8) {
                        ForEach(ImagePipeline.GIFColors.allCases, id: \.self) { colors in
                            OptionTile(selected: upload.gifColors == colors, action: { upload.gifColors = colors }) {
                                HStack(alignment: .top, spacing: 10) {
                                    TileCheck(on: upload.gifColors == colors)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(colors.rawValue).font(.system(size: 14, weight: .semibold))
                                        Text(colors == .shared ? "Exact colours where possible, else a best-fit palette per frame."
                                                               : "The fixed 252-colour palette. Use it if the other looks wrong.")
                                            .font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    OptionTile(selected: upload.smoothGradients, action: { upload.smoothGradients.toggle() }) {
                        HStack(alignment: .top, spacing: 10) {
                            TileCheck(on: upload.smoothGradients)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smooth gradients").font(.system(size: 14, weight: .semibold))
                                Text("The screen shows 65,536 colours. Dithering avoids banding in skies and gradients.")
                                    .font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if upload.isGIF { gifPanel }

            Spacer(minLength: 0)
            uploadControls
        }
        .padding(24)
    }

    private var gifPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Animation")
            if let source = upload.source {
                if let animation = upload.animation {
                    Text("\(animation.frameCount) frames · \(String(format: "%.1f", animation.seconds)) s")
                        .font(.system(size: 15, weight: .semibold))
                    Text(ByteCountFormatter.string(fromByteCount: Int64(animation.blob.count), countStyle: .file)
                         + " of " + ByteCountFormatter.string(fromByteCount: Int64(ScreenProtocol.gifMaxBytes), countStyle: .file))
                        .font(.l99Note).foregroundStyle(.secondary)
                    ProgressView(value: min(1, Double(animation.blob.count) / Double(ScreenProtocol.gifMaxBytes))).tint(Studio.accent)
                    ForEach(animation.fixes, id: \.self) { fix in
                        Label(fix, systemImage: "wand.and.stars").font(.l99Note)
                    }
                } else if let progress = upload.preparing {
                    ProgressView("Preparing frames…", value: progress).tint(Studio.accent)
                } else {
                    Text("\(source.frames.count) frames · \(String(format: "%.1f", source.duration)) s")
                        .font(.system(size: 15, weight: .semibold))
                    if source.frames.count > GIFContainer.maxFrames {
                        Label("More than \(GIFContainer.maxFrames) frames; some will be left out evenly.",
                              systemImage: "exclamationmark.triangle").font(.l99Note)
                    }
                    Button("Prepare and check size") { Task { await upload.prepareAnimation() } }
                }
                if let error = upload.prepareError {
                    Text(error).font(.l99Note).foregroundStyle(.red)
                }
            } else {
                Text("Frames, timing and size checks appear here.").font(.l99Note).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(padding: 14)
    }

    private var uploadControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransferStatus(transfer: model.transfer)
            if let error = upload.saveError {
                Text(error).font(.l99Note).foregroundStyle(.red)
            }
            if !model.devices.screen {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cable.connector.horizontal").font(.system(size: 15))
                    Text("Plug in the USB cable to upload. The 2.4 GHz dongle can't carry pictures.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color(light: 0x8A3A12, dark: 0xF5B48A))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                Task { await sendToScreen() }
            } label: {
                Label(model.transfer.isBusy ? "Uploading…" : "Upload to \(upload.slot.displayName.lowercased())", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.studioPrimary)
            .controlSize(.large)
            .disabled(!canUpload)
        }
    }

    private var canUpload: Bool {
        guard upload.source != nil, model.devices.screen, !model.transfer.isBusy, upload.preparing == nil else { return false }
        if upload.slot == .background && model.skins.homeSkinInstalled { return false }
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
