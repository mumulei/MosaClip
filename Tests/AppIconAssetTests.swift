import AppKit
import Testing

@Suite("App icon compatibility")
struct AppIconAssetTests {
    @Test("Every macOS icon size includes its own rounded mask and transparent margin")
    func roundedIconRepresentations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconset = folder.appendingPathComponent("App.iconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "iconset", root.appendingPathComponent("Sources/Resources/AppIcon.icns").path,
                             "-o", iconset.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let files = try FileManager.default.contentsOfDirectory(at: iconset, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        #expect(files.count == 10)
        for file in files {
            let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: file)))
            #expect(bitmap.hasAlpha, "\(file.lastPathComponent) must have alpha")
            let size = bitmap.pixelsWide
            for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                #expect(color.alphaComponent < 0.05, "\(file.lastPathComponent): transparent corner")
            }
            // Sample just inside the tile bounds. A square tile would be opaque
            // here; the rounded tile may retain a faint drop shadow. Avoid a
            // one-pixel asymmetry in the 16px representation's antialiasing.
            let inset = Int(Double(size) * 0.11)
            for x in [inset, size - 1 - inset] {
                let color = try #require(bitmap.colorAt(x: x, y: inset))
                #expect(color.alphaComponent < 0.25, "\(file.lastPathComponent): baked rounded mask")
            }
            let center = try #require(bitmap.colorAt(x: size / 2, y: size / 2))
            #expect(center.alphaComponent > 0.99, "\(file.lastPathComponent): opaque body")
        }
    }
}
