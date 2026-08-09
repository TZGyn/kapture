import AppKit

final class OverlayWindow: NSPanel {
    init(screen: NSScreen, onComplete: @escaping (NSRect) -> Void, onCancel: @escaping () -> Void) {
        let content = OverlayView(onComplete: onComplete, onCancel: onCancel)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = content
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    private let onComplete: (NSRect) -> Void
    private let onCancel: () -> Void

    private var startPoint: NSPoint?
    private(set) var selection: NSRect?

    init(onComplete: @escaping (NSRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p
        selection = NSRect(origin: p, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let sel = selection else { return }
        if sel.width >= 2, sel.height >= 2 {
            onComplete(window!.convertToScreen(sel))
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: bounds).fill()

        guard let sel = selection, sel.width > 0, sel.height > 0 else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.black.setFill()
        NSBezierPath(rect: sel).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        border.stroke()

        let label = "\(Int(sel.width)) × \(Int(sel.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelRect = NSRect(
            x: sel.maxX - labelSize.width - 8,
            y: sel.minY - labelSize.height - 10,
            width: labelSize.width + 8,
            height: labelSize.height + 6
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        label.draw(
            at: NSPoint(x: labelRect.minX + 4, y: labelRect.minY + 3),
            withAttributes: attrs
        )
    }
}
