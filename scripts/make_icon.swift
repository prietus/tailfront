#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count >= 2 else {
    print("usage: make_icon.swift <output.png>")
    exit(1)
}
let outputPath = CommandLine.arguments[1]

let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    print("failed to make bitmap rep")
    exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-square background in the app's accent color.
let bg = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: size * 0.2237,
    yRadius: size * 0.2237
)
NSColor(srgbRed: 0.20, green: 0.478, blue: 0.820, alpha: 1.0).setFill()
bg.fill()

// Subtle top highlight band.
let highlight = NSBezierPath(
    roundedRect: NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45),
    xRadius: size * 0.2237,
    yRadius: size * 0.2237
)
NSColor(white: 1.0, alpha: 0.08).setFill()
highlight.fill()

// Centered SF Symbol glyph in white.
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.58, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

if let symbol = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let sz = symbol.size
    let rect = NSRect(
        x: (size - sz.width) / 2,
        y: (size - sz.height) / 2,
        width: sz.width,
        height: sz.height
    )
    symbol.draw(in: rect)
} else {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.7, weight: .heavy),
        .foregroundColor: NSColor.white
    ]
    let s = NSAttributedString(string: "T", attributes: attrs)
    let ss = s.size()
    s.draw(in: NSRect(x: (size - ss.width) / 2, y: (size - ss.height) / 2, width: ss.width, height: ss.height))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("failed to make PNG")
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath) (\(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh)))")
} catch {
    print("write failed: \(error)")
    exit(1)
}
