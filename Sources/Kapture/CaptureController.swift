import AppKit
import CoreGraphics
import ScreenCaptureKit

final class CaptureController: NSObject {
    static let shared = CaptureController()

    private var overlays: [NSWindow] = []
    private(set) var isSelecting = false
    private var previousApp: NSRunningApplication?
    private var overlayIDs: [Int] = []

    /// Diagnostic snapshot for "Copy Diagnostics" menu item.
    func diagnostics() -> String {
        var lines: [String] = []
        lines.append("Kapture diagnostics")
        for (i, s) in NSScreen.screens.enumerated() {
            let scale = s.backingScaleFactor
            let cgID = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            lines.append("screen[\(i)]: frame=\(s.frame) scale=\(scale) backingSize=\(s.frame.width*scale)x\(s.frame.height*scale) cgID=\(cgID)")
        }
        if #available(macOS 14.0, *) {
            Task {
                if let content = try? await SCShareableContent.current {
                    for (i, d) in content.displays.enumerated() {
                        lines.append("SCDisplay[\(i)]: frame=\(d.frame) width=\(d.width)x\(d.height) id=\(d.displayID)")
                    }
                } else {
                    lines.append("SCShareableContent: unavailable (no Screen Recording permission?)")
                }
                let text = lines.joined(separator: "\n")
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        } else {
            let text = lines.joined(separator: "\n")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        return lines.joined(separator: "\n")
    }

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
    private func crop(_ image: CGImage, to cgRect: CGRect, display: SCDisplay) -> CGImage? {
        // cgRect is already in SCDisplay space (Y flipped relative to AppKit).
        // Derive the pixel scale from the image we actually got, relative to
        // the display's point frame.
        let scaleX = CGFloat(image.width) / display.frame.width
        let scaleY = CGFloat(image.height) / display.frame.height
        guard scaleX > 0, scaleY > 0 else { return nil }
        let pxRect = CGRect(
            x: (cgRect.minX - display.frame.minX) * scaleX,
            y: (cgRect.minY - display.frame.minY) * scaleY,
            width: cgRect.width * scaleX,
            height: cgRect.height * scaleY
        )
        // Guard against negative offsets when the selection reaches beyond the
        // display's frame (e.g. secondary monitor coordinate quirks).
        let safeRect = pxRect.intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard safeRect.width >= 1, safeRect.height >= 1 else { return nil }
        guard let cropCtx = CGContext(
            data: nil, width: Int(safeRect.width), height: Int(safeRect.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cropCtx.interpolationQuality = .high
        cropCtx.draw(image, in: CGRect(x: -safeRect.minX, y: -safeRect.minY, width: CGFloat(image.width), height: CGFloat(image.height)))
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
                // SCDisplay.width/height are in POINTS; SCStreamConfiguration
                // width/height are output PIXELS. Multiply by the backing scale
                // of the screen containing the selection so retina displays are
                // captured at full resolution and 1x displays stay 1x.
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }) else {
                    completion(nil)
                    return
                }
                let backingScale = screen.backingScaleFactor
                config.width = Int(CGFloat(display.width) * backingScale)
                config.height = Int(CGFloat(display.height) * backingScale)
                config.showsCursor = true

                // ScreenCaptureKit's Y axis is flipped relative to AppKit
                // NSScreen frames. Convert the selection into SCDisplay space
                // using the matching NSScreen's top edge, then crop there.
                let scRect = CGRect(
                    x: rect.minX,
                    y: screen.frame.maxY - rect.maxY + display.frame.minY,
                    width: rect.width,
                    height: rect.height
                )

                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                    completion(nil)
                    return
                }
                completion(self.crop(image, to: scRect, display: display))
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
