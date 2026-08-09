import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class ResultWindow {
    static let shared = ResultWindow()

    private var window: NSWindow?

    func show(_ text: String) {
        window?.close()
        let hosting = NSHostingController(rootView: ResultView(text: text) { [weak self] in
            self?.window?.close()
        })
        let w = NSWindow(contentViewController: hosting)
        w.title = "Kapture — Extracted Text"
        w.level = .floating
        w.styleMask = [.titled, .closable, .resizable]
        w.setContentSize(NSSize(width: 520, height: 380))
        w.isReleasedWhenClosed = false

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let x = min(max(mouse.x - screen.frame.minX - 260, screen.frame.minX + 8), screen.frame.maxX - 528)
            let y = min(max(mouse.y - screen.frame.minY + 60, screen.frame.minY + 8), screen.frame.maxY - 388)
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            show("Could not load the selected image.")
            return
        }
        OCRService.shared.recognize(cgImage) { text in
            DispatchQueue.main.async {
                self.show(text.isEmpty ? "No text found in the image." : text)
            }
        }
    }
}

struct ResultView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: .constant(text))
                .font(.system(.body))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.4))
                )
            HStack {
                Button("Copy to Clipboard") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
                Spacer()
                Button("Close") { onClose() }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 340)
    }
}
