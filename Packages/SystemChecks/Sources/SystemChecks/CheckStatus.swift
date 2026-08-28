/// The outcome of one prerequisite check. Deliberately distinguishes
/// "unsupported" and "unknown" from "failed": a check that cannot even be
/// evaluated on this system, or whose underlying read failed/returned an
/// unrecognized value, must never be reported the same way as a check that
/// definitively found a problem -- and, critically, must never be silently
/// treated as passing either.
public enum CheckStatus: String, Sendable, Equatable {
    case passed
    case warning
    case failed
    /// The check does not apply on this system/configuration (for example,
    /// a Bluetooth check on a Mac with no Bluetooth hardware).
    case unsupported
    /// The underlying state could not be read at all, or returned a value
    /// this check does not recognize. Never used as a stand-in for
    /// "passed" -- an unreadable Bluetooth/Wi-Fi/permission/application
    /// state is not proof the prerequisite is satisfied.
    case unknown
}
