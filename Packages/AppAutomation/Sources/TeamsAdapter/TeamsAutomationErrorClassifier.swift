import Foundation
import CameraCore

/// Classifies the raw error text raised by `select_teams_camera.scpt`'s
/// `on run argv` handler into a typed `SelectionError`. Mirrors
/// `ZoomAutomationErrorClassifier`'s approach and fixture-testing strategy;
/// see that type's documentation for the general design rationale,
/// including how the combined "camera ...; microphone ..." top-level
/// failure message is detected and split before per-reason classification.
///
/// Teams' Settings and Devices panel are collapsed into the single
/// `settingsUIUnavailable` case: whether Settings itself failed to open, or
/// Settings opened but the Devices entry point could not be located
/// (notably including the state Teams is in when it is signed out or still
/// loading -- the automation never attempts to sign in, it simply cannot
/// find the Devices control and reports that honestly).
public enum TeamsAutomationErrorClassifier {
    public static func classify(_ message: String) -> SelectionError {
        let text = stripWrapperPrefix(message)
        if let combined = classifyCombinedFailure(text) {
            return combined
        }
        return classifyReason(text)
    }

    static func stripWrapperPrefix(_ text: String) -> String {
        let prefix = "Teams device selection failed: "
        return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }

    static func classifyCombinedFailure(_ text: String) -> SelectionError? {
        guard text.contains("was not confirmed selected") else { return nil }

        let cameraMarker = "camera \""
        let micMarker = "microphone \""
        let hasCamera = text.contains(cameraMarker)
        let hasMic = text.contains(micMarker)
        guard hasCamera || hasMic else { return nil }

        if hasCamera, hasMic, let splitRange = text.range(of: "; microphone \"") {
            let cameraSegment = String(text[text.startIndex..<splitRange.lowerBound])
            let micSegment = "microphone " + text[splitRange.upperBound...]
            return .partialSelection(
                cameraFailure: reasonFailure(in: cameraSegment),
                microphoneFailure: reasonFailure(in: micSegment)
            )
        }
        if hasCamera, !hasMic {
            return .partialSelection(cameraFailure: reasonFailure(in: text), microphoneFailure: nil)
        }
        if hasMic, !hasCamera {
            return .partialSelection(cameraFailure: nil, microphoneFailure: reasonFailure(in: text))
        }
        return nil
    }

    private static func reasonFailure(in segment: String) -> SelectionError {
        classifyReason(extractParenthesizedReason(segment) ?? segment)
    }

    static func classifyReason(_ message: String) -> SelectionError {
        let text = message

        if text.contains("is not running") {
            return .processNeverAppeared(application: .microsoftTeams)
        }
        if text.contains("settings could not be opened") {
            return .settingsUIUnavailable(application: .microsoftTeams, reason: extractParenthesizedReason(text) ?? text)
        }
        if text.contains("Devices panel could not be located") {
            return .settingsUIUnavailable(application: .microsoftTeams, reason: extractParenthesizedReason(text) ?? text)
        }
        if text.contains("ambiguous match") {
            return .ambiguousMatch(label: extractQuoted(text) ?? text, matchCount: extractCount(text) ?? 0)
        }
        if text.contains("item") && text.contains("not found in the matched control's menu") {
            return .controlNotFound(label: extractQuoted(text) ?? text)
        }
        if text.contains("no control found matching") {
            return .controlNotFound(label: extractQuoted(text) ?? text)
        }
        if text.contains("click failed") || (text.contains("clicking") && text.contains("failed")) {
            return .actionFailed(reason: text)
        }
        if text.contains("remained unchanged") {
            return .valueUnchanged(device: extractQuoted(text) ?? "", observedValue: extractParenthesizedStill(text) ?? "")
        }
        if text.contains("different device became selected") {
            return .wrongDeviceSelected(expected: extractQuoted(text) ?? "", observed: extractObserved(text) ?? "")
        }
        if text.contains("could not be read to confirm the change") || text.contains("unreadable") {
            return .selectionStateUnreadable(reason: text)
        }
        if text.contains("was not confirmed selected") {
            if let inner = extractParenthesizedReason(text) {
                return classify(inner)
            }
            return .unclassified(message: text)
        }

        return .unclassified(message: text)
    }

    static func extractQuoted(_ text: String) -> String? {
        guard let first = text.firstIndex(of: "\""),
              let second = text[text.index(after: first)...].firstIndex(of: "\"") else {
            return nil
        }
        return String(text[text.index(after: first)..<second])
    }

    static func extractCount(_ text: String) -> Int? {
        guard let range = text.range(of: "ambiguous match: ") else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    static func extractParenthesizedStill(_ text: String) -> String? {
        guard let stillRange = text.range(of: "(still \"") else { return nil }
        let rest = text[stillRange.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func extractObserved(_ text: String) -> String? {
        guard let range = text.range(of: "observed \"") else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func extractParenthesizedReason(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "("),
              let close = text.lastIndex(of: ")"), open < close else { return nil }
        return String(text[text.index(after: open)..<close])
    }
}
