import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class ResultWindow {
    static let shared = ResultWindow()

    private var windows: [NSWindow] = []
    private var nextOrigin = NSPoint(x: 60, y: 60)
    private var openCount = 0

    @MainActor
    func show(image: CGImage) {
        let model = CaptureModel(image: image)
        let w = NSWindow()
        w.contentViewController = NSHostingController(rootView: ResultView(model: model) {
            w.close()
        })
        w.title = "Kapture — Screenshot" + (openCount > 0 ? " \(openCount + 1)" : "")
        w.level = .floating
        w.styleMask = [.titled, .closable, .resizable]
        w.setContentSize(NSSize(width: 694, height: 520))
        w.isReleasedWhenClosed = false
        w.setFrameOrigin(nextOrigin)
        w.makeKeyAndOrderFront(nil)

        windows.append(w)
        openCount += 1
        nextOrigin = NSPoint(x: nextOrigin.x + 28, y: nextOrigin.y - 28)

        windowCleanup(for: w)
    }

    private func windowCleanup(for window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windows.removeAll { $0 === window }
                self.openCount = max(0, self.openCount - 1)
            }
        }
    }

    @MainActor
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            self.show(image: Self.failureImage("Could not load the selected image."))
            return
        }
        show(image: cgImage)
    }

    static func failureImage(_ message: String) -> CGImage {
        let size = NSSize(width: 800, height: 200)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return NSImage(size: size).cgImage(forProposedRect: nil, context: nil, hints: nil)! }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.systemRed,
        ]
        message.draw(at: NSPoint(x: 40, y: 80), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}

@MainActor
final class CaptureModel: ObservableObject {
    let image: CGImage

    @Published var mode: CaptureMode = .screenshot
    @Published var extractedText: String?
    @Published var isOCRRunning = false
    @Published var statusMessage: String?
    /// Drag selection rect in IMAGE point space (nil = none)
    @Published var selection: CGRect?

    enum CaptureMode {
        case screenshot
        case text
    }

    init(image: CGImage) {
        self.image = image
    }

    var hasSelection: Bool { selection != nil && selection!.width >= 2 && selection!.height >= 2 }

    var displayText: String {
        if isOCRRunning {
            return "Recognizing text…"
        }
        return extractedText ?? "Select text in the screenshot, then click “Get Text”."
    }

    func cropImage(to rectInImage: CGRect) -> CGImage? {
        return image.cropping(to: rectInImage)
    }

    func runOCR(over selectionOnly: CGRect? = nil) {
        guard !isOCRRunning else { return }
        isOCRRunning = true
        statusMessage = nil

        let targetImage: CGImage
        if let sel = selectionOnly {
            guard let cropped = image.cropping(to: sel) else {
                self.isOCRRunning = false
                self.statusMessage = "Selection too small."
                return
            }
            targetImage = cropped
        } else {
            targetImage = image
        }

        OCRService.shared.recognize(targetImage) { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.isOCRRunning = false
                self.mode = .text
                if text.isEmpty {
                    self.extractedText = "No text found in the selection."
                } else {
                    self.extractedText = text
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    self.statusMessage = "Copied to clipboard."
                }
            }
        }
    }

    func runOCRSelection() {
        guard let sel = selection, hasSelection else { return }
        runOCR(over: sel)
    }

    func copyText() {
        guard let text = extractedText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "Copied to clipboard."
    }

    func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
        statusMessage = "Image copied to clipboard."
    }

    func savePNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Kapture-\(Self.timestamp()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            statusMessage = "Could not create PNG file."
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            statusMessage = "Saved PNG."
        } else {
            statusMessage = "Could not save PNG."
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

struct ResultView: View {
    @ObservedObject var model: CaptureModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Picker("", selection: $model.mode) {
                    Text("Screenshot").tag(CaptureModel.CaptureMode.screenshot)
                    Text("Text").tag(CaptureModel.CaptureMode.text)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                if model.hasSelection {
                    Button {
                        model.runOCRSelection()
                    } label: {
                        Label("OCR Selection", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isOCRRunning)
                    .help("Recognize text inside the selected region")
                }

                Button {
                    model.runOCR()
                } label: {
                    Label("Get All Text", systemImage: "text.viewfinder")
                }
                .buttonStyle(.bordered)
                .disabled(model.isOCRRunning)
                .help("Recognize all text in the screenshot")

                Divider().frame(height: 18)

                Button {
                    model.copyImage()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy image to clipboard")

                Button {
                    model.savePNG()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("Save screenshot as PNG");

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Content
            if model.mode == .screenshot {
                ScreenshotPane(model: model)
                    .padding(12)
            } else {
                ZStack {
                    ScrollView {
                        Text(model.displayText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Status bar
            HStack(spacing: 8) {
                if model.isOCRRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusMessage ?? (model.mode == .screenshot
                    ? (model.hasSelection ? "Region selected — click OCR Selection." : "Drag to select a region, or Get All Text.")
                    : "Selectable text"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if model.mode == .text, model.extractedText != nil {
                    Button {
                        model.copyText()
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

struct ScreenshotPane: View {
    @ObservedObject var model: CaptureModel

    private var imageSize: CGSize {
        CGSize(width: model.image.width, height: model.image.height)
    }

    private func geometry(for geo: GeometryProxy) -> (scale: CGFloat, drawSize: CGSize, origin: CGPoint) {
        let size = imageSize
        let scale = min(geo.size.width / size.width, geo.size.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(
            x: (geo.size.width - drawSize.width) / 2,
            y: (geo.size.height - drawSize.height) / 2
        )
        return (scale, drawSize, origin)
    }

    private func toImagePoint(_ viewPoint: CGPoint, scale: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - origin.x) / scale,
            y: (viewPoint.y - origin.y) / scale
        )
    }

    private func clampSelection(_ rect: CGRect) -> CGRect {
        rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    var body: some View {
        GeometryReader { geo in
            let (scale, drawSize, origin) = geometry(for: geo)

            ZStack {
                Image(nsImage: NSImage(cgImage: model.image, size: .zero))
                    .resizable()
                    .interpolation(imageSize.width >= geo.size.width ? .high : .none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: drawSize.width, height: drawSize.height)
                    .position(x: origin.x + drawSize.width / 2, y: origin.y + drawSize.height / 2)

                if let sel = model.selection {
                    let viewRect = CGRect(
                        x: origin.x + sel.minX * scale,
                        y: origin.y + sel.minY * scale,
                        width: sel.width * scale,
                        height: sel.height * scale
                    )
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                        .border(Color.accentColor, width: 1.5)
                        .frame(width: viewRect.width, height: viewRect.height)
                        .position(x: viewRect.midX, y: viewRect.midY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = toImagePoint(value.startLocation, scale: scale, origin: origin)
                        let current = toImagePoint(value.location, scale: scale, origin: origin)
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        model.selection = clampSelection(rect)
                    }
                    .onEnded { _ in
                        if let s = model.selection, (s.width < 2 || s.height < 2) {
                            model.selection = nil
                        }
                    }
            )
        }
    }
}
