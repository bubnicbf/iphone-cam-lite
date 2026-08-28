import Foundation
import CameraCore

/// Classifies the raw error text raised by `select_zoom_camera.scpt`'s
/// `on run argv` handler into a typed `SelectionError`. Pure string logic
/// with no accessibility/process dependency, so every distinct failure
/// message the transitional AppleScript bridge can produce is independently
/// testable (`AdapterFixtureTests`) using recorded fixture text rather than
/// a live Zoom instance.
///
/// The top-level "on run argv" failure is a single combined message
/// (`"Zoom device selection failed: <failureText>"`) where `failureText`
/// names whichever of camera/microphone did NOT get confirmed -- if only
/// one is named, the other was confirmed, i.e. a partial selection.
/// `classify` detects that combined shape first and recurses into each
/// device's own reason text; otherwise it falls through to
/// `classifyReason`, which handles every single-message failure shape
/// directly (including the bare "Zoom is not running" precondition error,
/// which is never wrapped).
public enum ZoomAutomationErrorClassifier {
    public static func classify(_ message: String) -> SelectionError {
        let text = stripWrapperPrefix(message)
        if let combined = classifyCombinedFailure(text, application: .zoom) {
            return combined
        }
        return classifyReason(text)
    }

    static func stripWrapperPrefix(_ text: String) -> String {
        let prefix = "Zoom device selection failed: "
        return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }

    /// Detects the combined "camera ... was not confirmed selected (...);
    /// microphone ... was not confirmed selected (...)" shape (either half
    /// optional) and recurses into whichever half(s) are present. Returns
    /// nil for any text that is not in this combined shape, so callers can
    /// fall back to treating the whole message as a single reason.
    static func classifyCombinedFailure(_ text: String, application: MeetingApplication) -> SelectionError? {
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
            return .processNeverAppeared(application: .zoom)
        }
        if text.contains("ambiguous match") {
            return .ambiguousMatch(label: extractQuoted(text) ?? text, matchCount: extractCount(text) ?? 0)
        }
        if text.contains("item not found") {
            // Shape: "menu route (A > B > itemName): item not found" --
            // the item name is never quoted here (see
            // `extractMenuRouteItemName`'s documentation).
            return .controlNotFound(label: extractMenuRouteItemName(text) ?? extractQuoted(text) ?? text)
        }
        if text.contains("not found in the matched control's menu") {
            // Shape: "device item \"X\" not found in the matched control's menu".
            return .controlNotFound(label: extractQuoted(text) ?? text)
        }
        if text.contains("no control found matching") {
            return .controlNotFound(label: extractQuoted(text) ?? text)
        }
        if text.contains("click failed") || text.contains("clicking") && text.contains("failed") {
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
        if text.contains("never confirmed the change within") {
            let device = extractMenuRouteItemName(text) ?? extractQuoted(text) ?? text
            return .confirmationTimeout(device: device, seconds: extractSeconds(text) ?? 0)
        }
        if text.contains("was not confirmed selected") {
            // The top-level "on run argv" failure summary -- one or both of
            // camera/microphone were not confirmed. The underlying reason
            // is embedded in parentheses; classify that inner reason
            // recursively so the outermost wrapper never masks a more
            // specific case above.
            if let inner = extractParenthesizedReason(text) {
                return classify(inner)
            }
            return .unclassified(message: text)
        }

        return .unclassified(message: text)
    }

    // MARK: - Fixture text parsing helpers

    /// Extracts the final "> itemName" segment from a
    /// "menu route (A > B > itemName):" prefix -- the device/item being
    /// confirmed is never itself quoted in this message shape (only the
    /// trailing "last observed mark" value is), so it cannot be recovered
    /// with `extractQuoted`.
    static func extractMenuRouteItemName(_ text: String) -> String? {
        guard let openRange = text.range(of: "menu route ("),
              let closeRange = text.range(of: "):", range: openRange.upperBound..<text.endIndex) else {
            return nil
        }
        let inner = text[openRange.upperBound..<closeRange.lowerBound]
        let parts = String(inner).components(separatedBy: " > ")
        return parts.last?.trimmingCharacters(in: .whitespaces)
    }

    static func extractQuoted(_ text: String) -> String? {
        guard let first = text.firstIndex(of: "\""),
              let second = text[text.index(after: first)...].firstIndex(of: "\"") else {
            return nil
        }
        return String(text[text.index(after: first)..<second])
    }

    static func extractCount(_ text: String) -> Int? {
        // "ambiguous match: 3 controls matched ..."
        guard let range = text.range(of: "ambiguous match: ") else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    static func extractSeconds(_ text: String) -> Double? {
        // "... within 3.0s (last observed mark: ...)"
        guard let range = text.range(of: "within ") else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix(while: { $0.isNumber || $0 == "." })
        return Double(digits)
    }

    static func extractParenthesizedStill(_ text: String) -> String? {
        // `(still "X")`
        guard let stillRange = text.range(of: "(still \"") else { return nil }
        let rest = text[stillRange.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    static func extractObserved(_ text: String) -> String? {
        // `(observed "X", expected "Y")`
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
