/// Wraps a value that may be personally identifying (a device name, a
/// window title, a free-text automation label) so call sites make a
/// conscious choice about redaction instead of interpolating raw strings
/// into log messages.
///
/// `AppLogger` implementations are expected to log `redactedDescription`
/// by default and only ever surface `raw` when a build is explicitly
/// configured for verbose/debug logging.
public struct PrivacyValue: Sendable, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    /// A fixed-width placeholder that reveals nothing about the underlying
    /// value's content, only that a value was present.
    public var redactedDescription: String { "<private>" }

    public var description: String { redactedDescription }
}
