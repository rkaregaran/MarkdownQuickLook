import AppKit

public struct MarkdownRenderSettings: Codable, Equatable, Sendable {
    public var textSizeLevel: TextSizeLevel
    public var fontFamily: FontFamily

    public static let `default` = MarkdownRenderSettings(
        textSizeLevel: .medium,
        fontFamily: .system
    )

    public init(textSizeLevel: TextSizeLevel = .medium, fontFamily: FontFamily = .system) {
        self.textSizeLevel = textSizeLevel
        self.fontFamily = fontFamily
    }
}

public enum TextSizeLevel: Int, Codable, CaseIterable, Sendable {
    case extraSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case extraLarge = 4
    case extraExtraLarge = 5
    case extraExtraExtraLarge = 6

    public var scaleFactor: CGFloat {
        switch self {
        case .extraSmall: return 0.80
        case .small: return 0.90
        case .medium: return 1.00
        case .large: return 1.10
        case .extraLarge: return 1.25
        case .extraExtraLarge: return 1.40
        case .extraExtraExtraLarge: return 1.55
        }
    }

    public var displayName: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .extraExtraLarge: return "Extra Extra Large"
        case .extraExtraExtraLarge: return "Extra Extra Extra Large"
        }
    }
}

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case monospaced

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    public func font(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: descriptor, size: size) ?? base
            }
            return base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}
