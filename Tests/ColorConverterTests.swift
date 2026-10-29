import Testing
@testable import PasteMemo

@Suite("Color conversion")
struct ColorConverterTests {
    @Test("HEX accepts short, alpha, and full forms")
    func hexForms() throws {
        let short = try #require(ColorConverter.parse("#aBc"))
        #expect(short.r == 170)
        #expect(short.g == 187)
        #expect(short.b == 204)
        #expect(short.a == 1)

        let shortAlpha = try #require(ColorConverter.parse("#0F08"))
        #expect(shortAlpha.r == 0)
        #expect(shortAlpha.g == 255)
        #expect(shortAlpha.b == 0)
        #expect(abs(shortAlpha.a - (8.0 / 15.0)) < 0.0001)

        let fullAlpha = try #require(ColorConverter.parse("#33669980"))
        #expect(fullAlpha.r == 51)
        #expect(fullAlpha.g == 102)
        #expect(fullAlpha.b == 153)
        #expect(abs(fullAlpha.a - (128.0 / 255.0)) < 0.0001)
    }

    @Test("RGB accepts legacy and modern CSS syntax")
    func rgbForms() throws {
        let legacy = try #require(ColorConverter.parse("RGB(255, 12, 127)"))
        #expect(legacy.originalFormat == .rgb)
        #expect(legacy.r == 255)
        #expect(legacy.g == 12)
        #expect(legacy.b == 127)
        #expect(legacy.a == 1)

        let legacyAlpha = try #require(ColorConverter.parse("rgba(10, 20, 30, 0.25)"))
        #expect(legacyAlpha.originalFormat == .rgba)
        #expect(legacyAlpha.a == 0.25)

        let modern = try #require(ColorConverter.parse("rgb(100% 0% 50% / 25%)"))
        #expect(modern.originalFormat == .rgba)
        #expect(abs(modern.r - 255) < 0.0001)
        #expect(modern.g == 0)
        #expect(abs(modern.b - 127.5) < 0.0001)
        #expect(modern.a == 0.25)
    }

    @Test("HSL accepts alpha and angle units")
    func hslForms() throws {
        let red = try #require(ColorConverter.parse("hsl(0, 100%, 50%)"))
        #expect(abs(red.r - 255) < 0.0001)
        #expect(abs(red.g) < 0.0001)
        #expect(abs(red.b) < 0.0001)
        #expect(red.originalFormat == .hsl)

        let cyan = try #require(ColorConverter.parse("HSLA(0.5turn 100% 50% / 40%)"))
        #expect(abs(cyan.r) < 0.0001)
        #expect(abs(cyan.g - 255) < 0.0001)
        #expect(abs(cyan.b - 255) < 0.0001)
        #expect(cyan.a == 0.4)
        #expect(cyan.originalFormat == .hsla)

        let wrapped = try #require(ColorConverter.parse("hsl(-120deg 100% 50%)"))
        #expect(abs(wrapped.r) < 0.0001)
        #expect(abs(wrapped.g) < 0.0001)
        #expect(abs(wrapped.b - 255) < 0.0001)
    }

    @Test("Formatting exposes every copy format and preserves alpha")
    func formatting() throws {
        let color = try #require(ColorConverter.parse("#33669980"))
        #expect(color.formatted(.hex) == "#33669980")
        #expect(color.formatted(.rgb) == "rgb(51, 102, 153)")
        #expect(color.formatted(.rgba) == "rgba(51, 102, 153, 0.5)")
        #expect(color.formatted(.hsl) == "hsl(210, 50%, 40%)")
        #expect(color.formatted(.hsla) == "hsla(210, 50%, 40%, 0.5)")
    }

    @Test("Invalid and out-of-range values are rejected", arguments: [
        "#GGG",
        "#12",
        "#12345",
        "rgb(256, 0, 0)",
        "rgb(-1, 0, 0)",
        "rgb(1, 2, 3",
        "rgb(1, 2, 3) trailing",
        "rgb(1, 2, 3, 0.5)",
        "rgba(1, 2, 3)",
        "rgba(1, 2, 3, 1.1)",
        "rgb(1 2 3 / 101%)",
        "hsl(0, 101%, 50%)",
        "hsl(0, 50, 50)",
        "hsla(0, 50%, 50%)",
        "hsl(0 50% 50% / -0.1)",
        "rgb(1, 2, 3)\n#fff",
    ])
    func rejectsInvalid(source: String) {
        #expect(ColorConverter.parse(source) == nil)
    }

    @Test("Parsing stays bounded for clipboard classification")
    func boundedInput() {
        let oversized = "rgb(" + String(repeating: "1 ", count: 100) + ")"
        #expect(oversized.utf8.count > ColorConverter.maximumSourceLength)
        #expect(ColorConverter.parse(oversized) == nil)
    }

    @Test("Clipboard detection uses the same strict parser", arguments: [
        "#1234",
        "#12345678",
        "rgb(255 0 0 / 50%)",
        "rgba(1, 2, 3, 0.5)",
        "hsl(120deg 100% 50%)",
        "hsla(240, 100%, 50%, 0.25)",
    ])
    @MainActor func validDetection(source: String) {
        #expect(ColorConverter.parse(source) != nil)
        #expect(ClipboardManager.shared.detectContentType(source).type == .color)
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            source,
            contentType: .text,
            language: nil
        ))
    }

    @Test("Malformed color-like text stays out of Color", arguments: [
        "#GGG",
        "rgb(999, 0, 0)",
        "rgba(0, 0, 0, 2)",
        "hsl(0, 200%, 50%)",
    ])
    @MainActor func invalidDetection(source: String) {
        #expect(ColorConverter.parse(source) == nil)
        #expect(ClipboardManager.shared.detectContentType(source).type != .color)
    }
}
