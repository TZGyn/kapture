import AppKit
import CoreGraphics
import ScreenCaptureKit

final class CaptureController: NSObject {
    static let shared = CaptureController()

    private var overlays: [NSWindow] = []
    private(set) var isSelecting = false
    private var previousApp: NSRunningApplication?
    private var overlayIDs: [Int] = []

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
        overlayIDs = overlays.map { $0.windowNumber }
    }

    private func finishSelection(_ rect: NSRect) {
        let ids = overlayIDs
        hideOverlays()
        guard rect.width >= 2, rect.height >= 2 else {
            cancelSelection()
            return
        }
        DispatchQueue.main.async { [self] in
            capture(rect, excludingWindowIDs: ids)
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

    private func capture(_ rect: NSRect, excludingWindowIDs ids: [Int]) {
        ScreenCapture.shared.capture(rect, excludingWindowIDs: ids) { [weak self] image in
            DispatchQueue.main.async {
                self?.isSelecting = false
                self?.restorePreviousApp()
                Task { @MainActor in
                    guard let image else {
                        ResultWindow.shared.show(image: ResultWindow.failureImage("Capture failed. Check Screen Recording permission."))
                        return
                    }
                    ResultWindow.shared.show(image: image)
                }
            }
        }
    }
}

final class ScreenCapture {
    static let shared = ScreenCapture()

    private init() {}

    @available(macOS 14.0, *)
    private func crop(_ image: CGImage, to rect: NSRect, display: SCDisplay) -> CGImage? {
        let scaleX = CGFloat(display.width) / display.frame.width
        let scaleY = CGFloat(display.height) / display.frame.height
        let cgRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
        let pxRect = CGRect(
            x: (cgRect.minX - display.frame.minX) * scaleX,
            y: (cgRect.minY - display.frame.minY) * scaleY,
            width: cgRect.width * scaleX,
            height: cgRect.height * scaleY
        )
        guard let cropCtx = CGContext(
            data: nil, width: Int(pxRect.width), height: Int(pxRect.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cropCtx.interpolationQuality = .high
        cropCtx.draw(image, in: CGRect(x: -pxRect.minX, y: -pxRect.minY, width: CGFloat(image.width), height: CGFloat(image.height)))
        return cropCtx.makeImage()
    }

    @available(macOS 14.0, *)
    private func displayContaining(_ rect: NSRect, in content: SCShareableContent) -> SCDisplay? {
        let mid = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mid) }) ?? NSScreen.screens.first else {
            return nil
        }
        let cgID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return content.displays.first(where: { $0.displayID == cgID }) ?? content.displays.first
    }

    func capture(_ rect: NSRect, excludingWindowIDs excludedIDs: [Int], completion: @escaping (CGImage?) -> Void) {
        if #available(macOS 14.0, *) {
            Task {
                guard let content = try? await SCShareableContent.current,
                      let display = displayContaining(rect, in: content) else {
                    completion(nil)
                    return
                }
                let excludedSet = Set(excludedIDs.map { CGWindowID($0) })
                let excluded = content.windows.filter { excludedSet.contains($0.windowID) }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)
                let config = SCStreamConfiguration()
                config.width = Int(display.width)
                config.height = Int(display.height)
                config.showsCursor = true

                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                    completion(nil)
                    return
                }
                completion(self.crop(image, to: rect, display: display))
            }
        } else {
            guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
                completion(nil)
                return
            }
            let cgRect = CGRect(
                x: rect.minX,
                y: primary.frame.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            completion(CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .boundsIgnoreFraming]))
        }
    }
}
