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

    enum CaptureMode {
        case screenshot
        case text
    }

    init(image: CGImage) {
        self.image = image
    }

    var displayText: String {
        if isOCRRunning {
            return "Recognizing text…"
        }
        return extractedText ?? "Text appears here — click “Get Text”."
    }

    func runOCR() {
        guard !isOCRRunning else { return }
        isOCRRunning = true
        statusMessage = nil
        OCRService.shared.recognize(image) { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.isOCRRunning = false
                self.mode = .text
                if text.isEmpty {
                    self.extractedText = "No text found in the screenshot."
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
        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $model.mode) {
                    Text("Screenshot").tag(CaptureModel.CaptureMode.screenshot)
                    Text("Text").tag(CaptureModel.CaptureMode.text)
                    if model.isOCRRunning {
                        Text("…").tag(CaptureModel.CaptureMode.text)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Button("Copy Image") { model.copyImage() }
                Button("Save PNG…") { model.savePNG() }
                Button("Get Text") { model.runOCR() }
                    .disabled(model.isOCRRunning || model.extractedText != nil)
                Button("Close") { onClose() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if model.mode == .screenshot {
                GeometryReader { geo in
                    let imageWidth = CGFloat(model.image.width)
                    Image(nsImage: NSImage(cgImage: model.image, size: .zero))
                        .resizable()
                        // Downscale with smoothing (AA); upscale keeps pixels crisp.
                        .interpolation(imageWidth >= geo.size.width ? .high : .none)
                        .aspectRatio(contentMode: .fit)
                }
                .border(Color.secondary.opacity(0.4))
                .padding(.horizontal, 12)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        Text(model.displayText)
                            .font(.system(.body))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.4))
                    )

                    HStack(spacing: 8) {
                        if let msg = model.statusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button("Copy Text") { model.copyText() }
                    }
                    .padding(8)
                }
            }

            if model.statusMessage != nil && model.mode == .screenshot {
                Text(model.statusMessage!)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 10)
        .frame(minWidth: 480, minHeight: 380)
    }
}
