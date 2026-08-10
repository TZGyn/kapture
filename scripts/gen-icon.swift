import AppKit

let size = NSSize(width: 1024, height: 1024)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.60, alpha: 1),
])!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: -45)

let canvas = NSRect(origin: .zero, size: size)

NSColor.white.withAlphaComponent(0.92).setStroke()
let border = NSBezierPath(roundedRect: canvas.insetBy(dx: 64, dy: 64), xRadius: 64, yRadius: 64)
border.lineWidth = 28
border.stroke()

let glyphColor = NSColor.white
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 520, weight: .semibold),
    .foregroundColor: glyphColor,
]
let glyph = "Aa"
let glyphSize = glyph.size(withAttributes: attrs)
glyph.draw(
    at: NSPoint(
        x: (1024 - glyphSize.width) / 2,
        y: (1024 - glyphSize.height) / 2 - 40
    ),
    withAttributes: attrs
)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
if CommandLine.arguments.count < 2 { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    exit(1)
}
