import Foundation
import OSLog

public enum MarkdownPerformanceInstrumentation {
    public struct Interval: Sendable {
        #if DEBUG
        fileprivate let name: StaticString
        fileprivate let id: OSSignpostID

        fileprivate init(name: StaticString, id: OSSignpostID) {
            self.name = name
            self.id = id
        }
        #else
        fileprivate init() {}
        #endif
    }

    #if DEBUG
    private static let signpostLog = OSLog(
        subsystem: "com.rzkr.MarkdownQuickLook",
        category: .pointsOfInterest
    )

    private static let logger = Logger(
        subsystem: "com.rzkr.MarkdownQuickLook",
        category: "performance"
    )
    #endif

    @discardableResult
    public static func begin(_ name: StaticString) -> Interval {
        #if DEBUG
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return Interval(name: name, id: id)
        #else
        return Interval()
        #endif
    }

    public static func end(_ interval: Interval) {
        #if DEBUG
        os_signpost(.end, log: signpostLog, name: interval.name, signpostID: interval.id)
        #endif
    }

    public static func event(_ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: signpostLog, name: name)
        #endif
    }

    public static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let resolvedMessage = message()
        logger.debug("\(resolvedMessage, privacy: .public)")
        #endif
    }
}
