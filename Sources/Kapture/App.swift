import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement

@main
struct KaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kapture", systemImage: "text.viewfinder") {
            MenuView()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--test-ocr") {
            runOCRSelfTest()
            return
        }
        HotkeyManager.shared.onTrigger = { CaptureController.shared.begin() }
        HotkeyManager.shared.register()
    }
}

struct MenuView: View {
    @State private var granted = PermissionManager.isGranted

    var body: some View {
        Button("Capture & OCR") { CaptureController.shared.begin() }
            .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Extract from Image File…") { ResultWindow.shared.showOpenPanel() }

        Divider()

        if granted {
            Text("Screen Recording: Granted")
        } else {
            Button("Grant Screen Recording Permission…") {
                PermissionManager.request()
                granted = PermissionManager.isGranted
            }
        }

        Divider()

        Button(LoginItem.isEnabled ? "Disable Launch at Login" : "Launch at Login") {
            if !LoginItem.toggle() {
                let alert = NSAlert()
                alert.messageText = "Could not update Launch at Login"
                alert.informativeText = "Launch at Login requires a signed app bundle in /Applications. It is not available when running via `swift run`."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        Divider()

        Button("Quit Kapture") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

enum PermissionManager {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func request() {
        CGRequestScreenCaptureAccess()
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() -> Bool {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            return true
        } catch {
            return false
        }
    }
}

func runOCRSelfTest() {
    let text = "Kapture OCR test 1234, hello world"
    let size = NSSize(width: 1600, height: 220)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 56),
        .foregroundColor: NSColor.black,
    ]
    text.draw(at: NSPoint(x: 60, y: 75), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = rep.cgImage else { exit(1) }
    OCRService.shared.recognize(cgImage) { recognized in
        print("expected: \(text)")
        print("got:      \(recognized)")
        let ok = recognized == text
        print(ok ? "PASS" : "FAIL")
        exit(ok ? 0 : 1)
    }
    RunLoop.main.run()
}
