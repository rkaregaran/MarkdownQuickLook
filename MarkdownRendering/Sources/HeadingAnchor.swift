import Foundation

public struct HeadingAnchor: Equatable, Sendable {
    public let level: Int
    public let text: String
    public let range: NSRange

    public init(level: Int, text: String, range: NSRange) {
        self.level = level
        self.text = text
        self.range = range
    }
}
