import AppKit
import CoreGraphics

final class CaptureController: NSObject {
    static let shared = CaptureController()

    private var overlays: [NSWindow] = []
    private(set) var isSelecting = false
    private var previousApp: NSRunningApplication?

    func begin() {
        guard !isSelecting else { return }
        guard PermissionManager.isGranted else {
            PermissionManager.request()
            return
        }
        isSelecting = true
        previousApp = NSWorkspace.shared.frontmostApplication
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        overlays = NSScreen.screens.map { screen in
            OverlayWindow(
                screen: screen,
                onComplete: { [weak self] rect in self?.finishSelection(rect) },
                onCancel: { [weak self] in self?.cancelSelection() }
            )
        }
        overlays.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    private func finishSelection(_ rect: NSRect) {
        hideOverlays()
        guard rect.width >= 2, rect.height >= 2 else {
            cancelSelection()
            return
        }
        DispatchQueue.main.async { [self] in
            capture(rect)
        }
    }

    private func cancelSelection() {
        hideOverlays()
        isSelecting = false
        restorePreviousApp()
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func restorePreviousApp() {
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        previousApp = nil
    }

    private func capture(_ rect: NSRect) {
        guard let image = ScreenCapture.capture(rect) else {
            isSelecting = false
            restorePreviousApp()
            ResultWindow.shared.show("Capture failed. Check Screen Recording permission.")
            return
        }
        OCRService.shared.recognize(image) { [weak self] text in
            DispatchQueue.main.async {
                self?.isSelecting = false
                self?.restorePreviousApp()
                if text.isEmpty {
                    ResultWindow.shared.show("No text found in the selected area.")
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    ResultWindow.shared.show(text)
                }
            }
        }
    }
}

enum ScreenCapture {
    static func capture(_ rect: NSRect) -> CGImage? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first else { return nil }
        let cgRect = CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }
}
