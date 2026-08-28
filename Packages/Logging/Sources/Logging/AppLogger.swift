#if canImport(os)
import os
#endif
#if canImport(Foundation)
import Foundation
#endif

/// The logging levels this package supports. Deliberately small and
/// application-oriented rather than mirroring every `os.log` level.
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single recorded log event. Exposed publicly so `TestCaptureLogger`
/// (used by unit tests) can make assertions about what was logged without
/// depending on `os.log`'s opaque, unobservable storage.
public struct LogEvent: Sendable, Equatable {
    public let level: LogLevel
    public let category: LogCategory
    public let message: String

    public init(level: LogLevel, category: LogCategory, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// The logging seam every other module depends on. Kept tiny and
/// protocol-based so:
///   - production code logs through Apple's supported `os.Logger` facility,
///   - unit tests can inject `TestCaptureLogger` and assert on emitted
///     events without parsing Console.app output or touching a real
///     logging subsystem.
public protocol AppLogging: Sendable {
    func log(_ level: LogLevel, category: LogCategory, _ message: String)
}

public extension AppLogging {
    func debug(_ message: String, category: LogCategory) { log(.debug, category: category, message) }
    func info(_ message: String, category: LogCategory) { log(.info, category: category, message) }
    func warning(_ message: String, category: LogCategory) { log(.warning, category: category, message) }
    func error(_ message: String, category: LogCategory) { log(.error, category: category, message) }
}

/// Production logger backed by Apple's unified logging system (`os.Logger`).
/// One `os.Logger` instance is cached per category so each category's log
/// lines are independently filterable in Console.app / `log stream`.
public final class OSLogAppLogger: AppLogging {
    public static let shared = OSLogAppLogger()

    #if canImport(os)
    private let loggers: [LogCategory: Logger]
    #endif

    public init() {
        #if canImport(os)
        var built: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            built[category] = Logger(subsystem: LogCategory.subsystem, category: category.rawValue)
        }
        self.loggers = built
        #endif
    }

    public func log(_ level: LogLevel, category: LogCategory, _ message: String) {
        #if canImport(os)
        guard let logger = loggers[category] else { return }
        switch level {
        case .debug:
            // Device names, window titles, and other user/environment
            // specific text must never appear in the default log stream --
            // %{private}@ marks it accordingly. Debug-level messages are
            // themselves compiled out of release archive logs by the OS
            // unless the process opts in to debug logging.
            logger.debug("\(message, privacy: .private)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        #endif
    }
}

/// In-memory logger for tests: records every event so a test can assert
/// "a warning was logged for this category" without depending on the
/// unified logging system, which cannot be observed synchronously in a
/// unit test.
public final class TestCaptureLogger: AppLogging, @unchecked Sendable {
    private let lock = NSRecursiveLockBox()
    private var _events: [LogEvent] = []

    public init() {}

    public func log(_ level: LogLevel, category: LogCategory, _ message: String) {
        lock.withLock {
            _events.append(LogEvent(level: level, category: category, message: message))
        }
    }

    public var events: [LogEvent] {
        lock.withLock { _events }
    }

    public func events(in category: LogCategory) -> [LogEvent] {
        lock.withLock { _events.filter { $0.category == category } }
    }
}

/// Minimal cross-platform lock so `TestCaptureLogger` does not need to pull
/// in Foundation's `NSLock` directly at the call site.
final class NSRecursiveLockBox: @unchecked Sendable {
    #if canImport(Foundation)
    private let lock = NSRecursiveLock()
    #endif

    func withLock<T>(_ body: () -> T) -> T {
        #if canImport(Foundation)
        lock.lock()
        defer { lock.unlock() }
        return body()
        #else
        return body()
        #endif
    }
}
