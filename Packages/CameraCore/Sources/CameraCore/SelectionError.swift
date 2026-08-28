/// Every distinct way a device-selection attempt can fail, preserved from
/// the original Bash/AppleScript implementation's error messages so no
/// failure mode becomes less specific after migration. `CameraCore` never
/// reports success unless both devices are positively confirmed; every
/// other outcome surfaces as one of these cases (see
/// `CameraSelectionCoordinator`).
public enum SelectionError: Error, Sendable, Equatable {
    /// `open`/launch itself failed (the original scripts: "the 'open'
    /// command reported an error").
    case applicationLaunchFailed(application: MeetingApplication, reason: String)
    /// The target process never appeared within the configured attempt
    /// budget (`RetryPolicy.launchPollAttempts`).
    case applicationStartupTimeout(application: MeetingApplication, attempts: Int)
    /// The automation stage found the target process not running when it
    /// expected it to already be running (the `.scpt` files' own
    /// precondition check, distinct from the launcher's wait loop above).
    case processNeverAppeared(application: MeetingApplication)
    /// Settings/devices UI could not be opened (Teams: neither the
    /// Settings menu item nor the Command-, shortcut worked).
    case settingsUIUnavailable(application: MeetingApplication, reason: String)
    /// A required menu item or control was not found at all.
    case controlNotFound(label: String)
    /// More than one control matched a label -- never guessed at.
    case ambiguousMatch(label: String, matchCount: Int)
    /// A click/activation action itself failed.
    case actionFailed(reason: String)
    /// The click was issued but the read-back value never changed.
    case valueUnchanged(device: String, observedValue: String)
    /// The click was issued but a different device ended up selected.
    case wrongDeviceSelected(expected: String, observed: String)
    /// The relevant accessibility state could not be read at all.
    case selectionStateUnreadable(reason: String)
    /// Confirmation polling (`RetryPolicy.confirmationMaxPolls` /
    /// `confirmationPollInterval`) was exhausted without confirming.
    case confirmationTimeout(device: String, seconds: Double)
    /// A packaged automation resource (e.g. the bundled AppleScript
    /// selector) could not be located.
    case resourceMissing(path: String)
    /// The selection `Task` was cancelled before it completed.
    case cancelled
    /// The automation facility itself (osascript / Apple Events) is
    /// unavailable, so no strategy could even be attempted.
    case automationUnavailable(reason: String)
    /// One device was confirmed and the other was not. Carries the
    /// specific failure for whichever device did not succeed.
    case partialSelection(cameraFailure: SelectionError?, microphoneFailure: SelectionError?)
    /// An error surfaced by the transitional AppleScript bridge that did
    /// not match any of the classifier's known patterns. Preserves the raw
    /// message for diagnostics rather than discarding it.
    case unclassified(message: String)
}

extension SelectionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .applicationLaunchFailed(application, reason):
            return "Failed to launch \(application.displayName): \(reason)"
        case let .applicationStartupTimeout(application, attempts):
            return "\(application.displayName) did not start within \(attempts) attempts; its process never appeared."
        case let .processNeverAppeared(application):
            return "\(application.displayName) is not running."
        case let .settingsUIUnavailable(application, reason):
            return "\(application.displayName) settings could not be opened: \(reason)"
        case let .controlNotFound(label):
            return "No control found matching \"\(label)\"."
        case let .ambiguousMatch(label, count):
            return "Ambiguous match: \(count) controls matched \"\(label)\"."
        case let .actionFailed(reason):
            return "Action failed: \(reason)"
        case let .valueUnchanged(device, observedValue):
            return "Selecting \"\(device)\" had no effect; observed value remained \"\(observedValue)\"."
        case let .wrongDeviceSelected(expected, observed):
            return "Expected \"\(expected)\" to become selected, but observed \"\(observed)\"."
        case let .selectionStateUnreadable(reason):
            return "Selection state could not be read: \(reason)"
        case let .confirmationTimeout(device, seconds):
            return "Selecting \"\(device)\" was not confirmed within \(seconds)s."
        case let .resourceMissing(path):
            return "Required automation resource not found: \(path)"
        case .cancelled:
            return "Selection was cancelled."
        case let .automationUnavailable(reason):
            return "Automation is unavailable: \(reason)"
        case let .partialSelection(cameraFailure, microphoneFailure):
            var parts: [String] = []
            if let cameraFailure { parts.append("camera: \(cameraFailure.description)") }
            if let microphoneFailure { parts.append("microphone: \(microphoneFailure.description)") }
            return "Partial selection: \(parts.joined(separator: "; "))"
        case let .unclassified(message):
            return message
        }
    }
}
