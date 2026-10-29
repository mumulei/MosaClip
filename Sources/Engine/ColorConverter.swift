import AppKit

enum ColorFormat: String, CaseIterable {
    case hex = "HEX"
    case rgb = "RGB"
    case rgba = "RGBA"
    case hsl = "HSL"
    case hsla = "HSLA"
}

struct ParsedColor: Equatable {
    let r: CGFloat  // 0-255
    let g: CGFloat  // 0-255
    let b: CGFloat  // 0-255
    let a: CGFloat  // 0-1
    let originalFormat: ColorFormat

    var nsColor: NSColor {
        NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    func formatted(_ format: ColorFormat) -> String {
        let red = Self.byte(r)
        let green = Self.byte(g)
        let blue = Self.byte(b)
        let alpha = min(max(a, 0), 1)

        switch format {
        case .hex:
            if alpha < 1 {
                return String(
                    format: "#%02X%02X%02X%02X",
                    red,
                    green,
                    blue,
                    Self.byte(alpha * 255)
                )
            }
            return String(format: "#%02X%02X%02X", red, green, blue)
        case .rgb:
            return "rgb(\(red), \(green), \(blue))"
        case .rgba:
            return "rgba(\(red), \(green), \(blue), \(Self.decimal(alpha)))"
        case .hsl:
            let (h, s, l) = rgbToHSL(r: r / 255, g: g / 255, b: b / 255)
            return "hsl(\(Self.decimal(h)), \(Self.decimal(s))%, \(Self.decimal(l))%)"
        case .hsla:
            let (h, s, l) = rgbToHSL(r: r / 255, g: g / 255, b: b / 255)
            return "hsla(\(Self.decimal(h)), \(Self.decimal(s))%, \(Self.decimal(l))%, \(Self.decimal(alpha)))"
        }
    }

    /// The alternate format exposed by the command palette's second copy action.
    var alternateFormat: ColorFormat {
        originalFormat == .hex ? .rgb : .hex
    }

    private static func byte(_ value: CGFloat) -> Int {
        Int(round(min(max(value, 0), 255)))
    }

    private static func decimal(_ value: CGFloat) -> String {
        let text = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(value)
        )
        return text
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

enum ColorConverter {
    /// Color detection runs synchronously in the clipboard classification path, so
    /// keep the accepted input deliberately small and single-line.
    static let maximumSourceLength = 160

    static func parse(_ text: String) -> ParsedColor? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              source.utf8.count <= maximumSourceLength,
              !source.contains(where: \Character.isNewline)
        else {
            return nil
        }

        if source.hasPrefix("#") {
            return parseHex(source)
        }

        guard let function = functionalComponents(source) else { return nil }
        switch function.name {
        case "rgb", "rgba":
            return parseRGB(name: function.name, body: function.body)
        case "hsl", "hsla":
            return parseHSL(name: function.name, body: function.body)
        default:
            return nil
        }
    }

    static func from(nsColor: NSColor) -> ParsedColor {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return ParsedColor(
            r: round(color.redComponent * 255),
            g: round(color.greenComponent * 255),
            b: round(color.blueComponent * 255),
            a: min(max(color.alphaComponent, 0), 1),
            originalFormat: .hex
        )
    }

    // MARK: - Parsers

    private static func parseHex(_ source: String) -> ParsedColor? {
        let hex = String(source.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count),
              hex.allSatisfy(\.isHexDigit),
              let value = UInt64(hex, radix: 16)
        else {
            return nil
        }

        switch hex.count {
        case 3:
            return ParsedColor(
                r: CGFloat((value >> 8) & 0xF) * 17,
                g: CGFloat((value >> 4) & 0xF) * 17,
                b: CGFloat(value & 0xF) * 17,
                a: 1,
                originalFormat: .hex
            )
        case 4:
            return ParsedColor(
                r: CGFloat((value >> 12) & 0xF) * 17,
                g: CGFloat((value >> 8) & 0xF) * 17,
                b: CGFloat((value >> 4) & 0xF) * 17,
                a: CGFloat(value & 0xF) / 15,
                originalFormat: .hex
            )
        case 6:
            return ParsedColor(
                r: CGFloat((value >> 16) & 0xFF),
                g: CGFloat((value >> 8) & 0xFF),
                b: CGFloat(value & 0xFF),
                a: 1,
                originalFormat: .hex
            )
        case 8:
            return ParsedColor(
                r: CGFloat((value >> 24) & 0xFF),
                g: CGFloat((value >> 16) & 0xFF),
                b: CGFloat((value >> 8) & 0xFF),
                a: CGFloat(value & 0xFF) / 255,
                originalFormat: .hex
            )
        default:
            return nil
        }
    }

    private static func parseRGB(name: String, body: String) -> ParsedColor? {
        guard let components = colorFunctionComponents(body) else { return nil }

        let channels: [String]
        let alphaToken: String?
        if components.usesCommas {
            let expectedCount = name == "rgba" ? 4 : 3
            guard components.values.count == expectedCount else { return nil }
            channels = Array(components.values.prefix(3))
            alphaToken = expectedCount == 4 ? components.values[3] : nil
        } else {
            guard components.values.count == 3 else { return nil }
            guard name != "rgba" || components.alpha != nil else { return nil }
            channels = components.values
            alphaToken = components.alpha
        }

        guard let red = rgbChannel(channels[0]),
              let green = rgbChannel(channels[1]),
              let blue = rgbChannel(channels[2]),
              let alpha = alphaToken.map(alphaValue) ?? 1
        else {
            return nil
        }

        let hasAlpha = alphaToken != nil
        return ParsedColor(
            r: red,
            g: green,
            b: blue,
            a: alpha,
            originalFormat: hasAlpha ? .rgba : .rgb
        )
    }

    private static func parseHSL(name: String, body: String) -> ParsedColor? {
        guard let components = colorFunctionComponents(body) else { return nil }

        let channels: [String]
        let alphaToken: String?
        if components.usesCommas {
            let expectedCount = name == "hsla" ? 4 : 3
            guard components.values.count == expectedCount else { return nil }
            channels = Array(components.values.prefix(3))
            alphaToken = expectedCount == 4 ? components.values[3] : nil
        } else {
            guard components.values.count == 3 else { return nil }
            guard name != "hsla" || components.alpha != nil else { return nil }
            channels = components.values
            alphaToken = components.alpha
        }

        guard let hue = hueDegrees(channels[0]),
              let saturation = percentage(channels[1]),
              let lightness = percentage(channels[2]),
              let alpha = alphaToken.map(alphaValue) ?? 1
        else {
            return nil
        }

        let (red, green, blue) = hslToRGB(h: hue, s: saturation, l: lightness)
        let hasAlpha = alphaToken != nil
        return ParsedColor(
            r: red * 255,
            g: green * 255,
            b: blue * 255,
            a: alpha,
            originalFormat: hasAlpha ? .hsla : .hsl
        )
    }

    private static func functionalComponents(_ source: String) -> (name: String, body: String)? {
        guard let opening = source.firstIndex(of: "("),
              source.last == ")",
              !source[source.index(after: opening)..<source.index(before: source.endIndex)].contains(where: { $0 == "(" || $0 == ")" })
        else {
            return nil
        }

        let name = source[..<opening]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let body = source[source.index(after: opening)..<source.index(before: source.endIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !body.isEmpty else { return nil }
        return (name, body)
    }

    private struct FunctionComponents {
        let values: [String]
        let alpha: String?
        let usesCommas: Bool
    }

    private static func colorFunctionComponents(_ body: String) -> FunctionComponents? {
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            let values = body
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.allSatisfy({ !$0.isEmpty }) else { return nil }
            return FunctionComponents(values: values, alpha: nil, usesCommas: true)
        }

        let slashParts = body.split(separator: "/", omittingEmptySubsequences: false)
        guard slashParts.count <= 2 else { return nil }
        let values = slashParts[0]
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        let alpha: String?
        if slashParts.count == 2 {
            let alphaParts = slashParts[1]
                .split(whereSeparator: \Character.isWhitespace)
                .map(String.init)
            guard alphaParts.count == 1 else { return nil }
            alpha = alphaParts[0]
        } else {
            alpha = nil
        }
        return FunctionComponents(values: values, alpha: alpha, usesCommas: false)
    }

    private static func rgbChannel(_ token: String) -> CGFloat? {
        if token.hasSuffix("%") {
            guard let value = finiteDouble(String(token.dropLast())), (0...100).contains(value) else {
                return nil
            }
            return CGFloat(value * 2.55)
        }
        guard let value = finiteDouble(token), (0...255).contains(value) else { return nil }
        return CGFloat(value)
    }

    private static func alphaValue(_ token: String) -> CGFloat? {
        if token.hasSuffix("%") {
            guard let value = finiteDouble(String(token.dropLast())), (0...100).contains(value) else {
                return nil
            }
            return CGFloat(value / 100)
        }
        guard let value = finiteDouble(token), (0...1).contains(value) else { return nil }
        return CGFloat(value)
    }

    private static func percentage(_ token: String) -> Double? {
        guard token.hasSuffix("%"),
              let value = finiteDouble(String(token.dropLast())),
              (0...100).contains(value)
        else {
            return nil
        }
        return value
    }

    private static func hueDegrees(_ token: String) -> Double? {
        let lowercased = token.lowercased()
        let value: Double

        if lowercased.hasSuffix("turn") {
            guard let parsed = finiteDouble(String(lowercased.dropLast(4))) else { return nil }
            value = parsed * 360
        } else if lowercased.hasSuffix("grad") {
            guard let parsed = finiteDouble(String(lowercased.dropLast(4))) else { return nil }
            value = parsed * 0.9
        } else if lowercased.hasSuffix("rad") {
            guard let parsed = finiteDouble(String(lowercased.dropLast(3))) else { return nil }
            value = parsed * 180 / .pi
        } else if lowercased.hasSuffix("deg") {
            guard let parsed = finiteDouble(String(lowercased.dropLast(3))) else { return nil }
            value = parsed
        } else {
            guard let parsed = finiteDouble(lowercased) else { return nil }
            value = parsed
        }

        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func finiteDouble(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Color Space Conversion

private func rgbToHSL(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, l: CGFloat) {
    let maxComponent = max(r, g, b)
    let minComponent = min(r, g, b)
    let lightness = (maxComponent + minComponent) / 2

    guard maxComponent != minComponent else { return (0, 0, lightness * 100) }

    let delta = maxComponent - minComponent
    let saturation = lightness > 0.5
        ? delta / (2 - maxComponent - minComponent)
        : delta / (maxComponent + minComponent)
    let hue: CGFloat
    switch maxComponent {
    case r:
        hue = ((g - b) / delta + (g < b ? 6 : 0)) * 60
    case g:
        hue = ((b - r) / delta + 2) * 60
    default:
        hue = ((r - g) / delta + 4) * 60
    }
    return (hue, saturation * 100, lightness * 100)
}

private func hslToRGB(h: Double, s: Double, l: Double) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let saturation = s / 100
    let lightness = l / 100
    guard saturation > 0 else {
        return (CGFloat(lightness), CGFloat(lightness), CGFloat(lightness))
    }

    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let secondary = chroma * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let match = lightness - chroma / 2

    let channels: (Double, Double, Double)
    switch h {
    case 0..<60:
        channels = (chroma, secondary, 0)
    case 60..<120:
        channels = (secondary, chroma, 0)
    case 120..<180:
        channels = (0, chroma, secondary)
    case 180..<240:
        channels = (0, secondary, chroma)
    case 240..<300:
        channels = (secondary, 0, chroma)
    default:
        channels = (chroma, 0, secondary)
    }
    return (
        CGFloat(channels.0 + match),
        CGFloat(channels.1 + match),
        CGFloat(channels.2 + match)
    )
}
