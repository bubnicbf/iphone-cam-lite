/// A camera or microphone name as it appears in a meeting application's own
/// device menu.
///
/// `DeviceName` centralizes the exact-match rule this repository has always
/// relied on: two names are equal only after trimming leading/trailing
/// whitespace, never via substring/contains matching, and never
/// case-insensitively. This preserves the historical behavior of the
/// AppleScript selectors (`namesMatch` in the original `.scpt` files) as a
/// single, independently testable Swift type instead of duplicated string
/// logic scattered across adapters.
public struct DeviceName: Sendable, Hashable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// The trimmed value. Only leading/trailing whitespace and newlines are
    /// removed; internal spacing, case, punctuation, apostrophes,
    /// parentheses, and non-ASCII/Unicode characters are preserved exactly.
    public let value: String

    public init(_ raw: String) {
        self.value = DeviceName.trim(raw)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { value }

    public var isEmpty: Bool { value.isEmpty }

    /// Exact match after trimming -- the single source of truth every
    /// adapter and the coordinator use to decide whether a confirmed
    /// selection matches what was requested.
    public func matches(_ other: DeviceName) -> Bool {
        value == other.value
    }

    public func matches(_ other: String) -> Bool {
        matches(DeviceName(other))
    }

    private static func trim(_ raw: String) -> String {
        var start = raw.startIndex
        var end = raw.endIndex
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        while start < end, whitespace.contains(raw[start]) {
            start = raw.index(after: start)
        }
        while end > start {
            let before = raw.index(before: end)
            if whitespace.contains(raw[before]) {
                end = before
            } else {
                break
            }
        }
        return String(raw[start..<end])
    }
}
