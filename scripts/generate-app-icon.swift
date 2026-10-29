#!/usr/bin/env swift
import AppKit

// macOS 14 displays ICNS artwork as provided, without applying a system mask.
// Keep a square master, but bake the rounded tile and transparent margin into
// every representation. Run from the repository root; no external tools needed.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Sources/Resources/Brand/app-icon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Missing icon master") }
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("MosaClip.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    cg.saveGState()
    // CGContext shadows use device-space dimensions; scale them explicitly
    // so the 16/32px representations do not acquire a square shadow haze.
    cg.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 14 * scale,
                 color: NSColor.black.withAlphaComponent(0.22).cgColor)
    NSColor.white.setFill()
    shape.fill()
    cg.restoreGState()
    shape.addClip()
    source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let suffix = multiplier == 2 ? "@2x" : ""
        let png = render(pixels: points * multiplier)
        try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 256 && multiplier == 2 {
            try png.write(to: root.appendingPathComponent("docs/assets/mosaclip-app-icon.png"))
        }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o",
    root.appendingPathComponent("Sources/Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated rounded, transparent macOS icon (10 representations).")
