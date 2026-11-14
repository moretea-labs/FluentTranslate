#!/usr/bin/env swift
import AppKit
import Foundation

// Source of truth for the native 1024px macOS app artwork.
// Usage: swift scripts/render_icon.swift Sources/TranslateDesk/Assets/translatedesk-logo.png

let output = CommandLine.arguments.dropFirst().first
    ?? "Sources/TranslateDesk/Assets/translatedesk-logo.png"
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Cannot create icon bitmap")
}
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Cannot draw icon")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

func roundRect(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// The icon remains legible at 16pt: one silhouette, two glyphs,
// and no hairline strokes or decorative borders.
let tile = NSBezierPath(
    roundedRect: NSRect(x: 34, y: 34, width: 956, height: 956),
    xRadius: 228,
    yRadius: 228
)
let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.98, alpha: 1),
    ending: NSColor(srgbRed: 0.28, green: 0.27, blue: 0.79, alpha: 1)
)!
gradient.draw(in: tile, angle: -43)

// The translucent exchange sheets nod to the desktop's material sidebar.
roundRect(
    NSRect(x: 158, y: 325, width: 532, height: 542),
    120,
    NSColor.white.withAlphaComponent(0.23)
)
roundRect(
    NSRect(x: 451, y: 184, width: 416, height: 423),
    116,
    NSColor(srgbRed: 0.26, green: 0.30, blue: 0.87, alpha: 0.76)
)

func drawCentered(_ text: String, rect: NSRect, fontSize: CGFloat, weight: NSFont.Weight) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let origin = NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 + fontSize * 0.025
    )
    (text as NSString).draw(at: origin, withAttributes: attributes)
}

drawCentered("A", rect: NSRect(x: 165, y: 354, width: 513, height: 500),
             fontSize: 364, weight: .semibold)
drawCentered("文", rect: NSRect(x: 459, y: 200, width: 395, height: 385),
             fontSize: 270, weight: .semibold)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode PNG")
}
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Rendered \(output): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), \(data.count) bytes")
