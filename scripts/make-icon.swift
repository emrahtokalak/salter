// Renders the Şalter app icon (a circuit-breaker switch in the ON position) into an .iconset folder:
//   swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func drawIcon(size: CGFloat) {
    let inset = size * 0.1
    let canvas = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let w = canvas.width

    // Background: dark navy squircle.
    let background = NSBezierPath(roundedRect: canvas, xRadius: w * 0.225, yRadius: w * 0.225)
    NSGradient(starting: color(0x2C3E5C), ending: color(0x111827))?.draw(in: background, angle: -90)

    // Breaker body: light panel with a soft drop shadow.
    let body = NSRect(x: canvas.midX - w * 0.22, y: canvas.midY - w * 0.34, width: w * 0.44, height: w * 0.68)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: w * 0.07, yRadius: w * 0.07)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = w * 0.04
    shadow.shadowOffset = NSSize(width: 0, height: -w * 0.015)
    shadow.set()
    color(0xF3F5F8).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xDDE3EA))?.draw(in: bodyPath, angle: -90)

    // Slot the lever travels in.
    let slot = NSRect(x: canvas.midX - w * 0.075, y: body.minY + w * 0.22, width: w * 0.15, height: w * 0.36)
    color(0x283241).setFill()
    NSBezierPath(roundedRect: slot, xRadius: w * 0.075, yRadius: w * 0.075).fill()

    // Lever, thrown up (ON), in signal orange.
    let lever = NSRect(x: canvas.midX - w * 0.125, y: slot.maxY - w * 0.17, width: w * 0.25, height: w * 0.19)
    let leverPath = NSBezierPath(roundedRect: lever, xRadius: w * 0.05, yRadius: w * 0.05)
    NSGraphicsContext.saveGraphicsState()
    let leverShadow = NSShadow()
    leverShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    leverShadow.shadowBlurRadius = w * 0.02
    leverShadow.shadowOffset = NSSize(width: 0, height: -w * 0.01)
    leverShadow.set()
    color(0xFF8A00).setFill()
    leverPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFB040), ending: color(0xF26B00))?.draw(in: leverPath, angle: -90)
    // Grip lines on the lever.
    color(0xFFFFFF).withAlphaComponent(0.55).setFill()
    for i in 0..<3 {
        let y = lever.minY + lever.height * (0.3 + 0.2 * CGFloat(i))
        NSBezierPath(roundedRect: NSRect(x: lever.minX + lever.width * 0.22, y: y, width: lever.width * 0.56, height: w * 0.012),
                     xRadius: w * 0.006, yRadius: w * 0.006).fill()
    }

    // Small bolt under the slot.
    let config = NSImage.SymbolConfiguration(pointSize: w * 0.11, weight: .black)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color(0xF26B00)]))
    if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = bolt.size
        bolt.draw(in: NSRect(x: canvas.midX - s.width / 2, y: body.minY + w * 0.055, width: s.width, height: s.height))
    }
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in sizes {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try png.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
