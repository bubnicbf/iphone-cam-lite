/// Pure, adapter-agnostic polling logic shared by every
/// `DeviceSelectionAdapter` implementation (and directly unit-tested here)
/// so the "click, then re-read until it matches or a bounded window
/// elapses" pattern used by both the Zoom and Teams selectors is written,
/// and tested, exactly once instead of duplicated per adapter.
///
/// Two shapes of confirmable state exist in the underlying UIs:
///   - a control whose read-back *value* should equal the requested device
///     name (both apps' camera/microphone pop-ups), and
///   - a menu item whose *selected/marked flag* should become true (Zoom's
///     Meeting-menu route).
/// Each gets its own polling function below because "the value drifted to
/// something else" only makes sense for the first shape.
public enum ValueConfirmationResult: Sendable, Equatable {
    case confirmed
    /// The read-back value never moved from its pre-action baseline.
    case unchanged(observed: String)
    /// The read-back value changed, but not to the requested device.
    case wrongValue(observed: String)
    /// The value could not be read at all during polling.
    case unreadable
}

public enum FlagConfirmationResult: Sendable, Equatable {
    case confirmed
    /// Readable throughout, but never became true within the poll budget.
    case timedOut(lastObserved: String?)
    /// Could not be read at all during polling.
    case unreadable
}

public enum Confirmation {
    /// True if `currentValue` already equals `requested` -- callers use
    /// this to skip issuing a click entirely when the desired device is
    /// already selected, matching the original AppleScript selectors'
    /// "already selected" fast path.
    public static func isAlreadySelected(requested: DeviceName, currentValue: String?) -> Bool {
        guard let currentValue else { return false }
        return requested.matches(currentValue)
    }

    /// Polls `readValue` up to `policy.confirmationMaxPolls` times, waiting
    /// `policy.confirmationPollInterval` between reads, until it returns a
    /// value matching `requested`. Distinguishes "never changed from its
    /// pre-click baseline" from "changed to something else" so callers can
    /// surface `SelectionError.valueUnchanged` vs `.wrongDeviceSelected`
    /// rather than one generic failure. Cancellation-aware via `sleeper`.
    public static func pollUntilValueMatches(
        requested: DeviceName,
        baseline: String?,
        policy: RetryPolicy,
        sleeper: Sleeping,
        readValue: () async throws -> String?
    ) async throws -> ValueConfirmationResult {
        var lastObserved: String?
        var everReadable = false

        let pollCount = max(policy.confirmationMaxPolls, 1)
        for attempt in 0..<pollCount {
            try Task.checkCancellation()
            if let value = try await readValue() {
                everReadable = true
                lastObserved = value
                if requested.matches(value) {
                    return .confirmed
                }
            }
            if attempt < pollCount - 1 {
                try await sleeper.sleep(seconds: policy.confirmationPollInterval)
            }
        }

        guard everReadable, let lastObserved else { return .unreadable }
        if let baseline, baseline == lastObserved {
            return .unchanged(observed: lastObserved)
        }
        return .wrongValue(observed: lastObserved)
    }

    /// Polls `readFlag` up to `policy.confirmationMaxPolls` times until it
    /// reports `true`, for controls (such as a Zoom menu item's mark
    /// character) that expose "is this selected" as a boolean rather than
    /// a comparable value. `readFlag` returns `(isSelected, rawObservedText)`
    /// so a timeout can still report the last observed raw state for
    /// diagnostics.
    public static func pollUntilFlagIsTrue(
        policy: RetryPolicy,
        sleeper: Sleeping,
        readFlag: () async throws -> (isSelected: Bool, raw: String)?
    ) async throws -> FlagConfirmationResult {
        var lastObserved: String?
        var everReadable = false

        let pollCount = max(policy.confirmationMaxPolls, 1)
        for attempt in 0..<pollCount {
            try Task.checkCancellation()
            if let result = try await readFlag() {
                everReadable = true
                lastObserved = result.raw
                if result.isSelected {
                    return .confirmed
                }
            }
            if attempt < pollCount - 1 {
                try await sleeper.sleep(seconds: policy.confirmationPollInterval)
            }
        }

        guard everReadable else { return .unreadable }
        return .timedOut(lastObserved: lastObserved)
    }
}
