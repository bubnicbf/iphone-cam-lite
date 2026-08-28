#if os(macOS)
import ApplicationServices
#endif

/// Reports whether this process is trusted for Accessibility control,
/// without ever prompting the user (the onboarding flow is responsible for
/// deciding when to prompt) -- Diagnostics must never mutate permission
/// state just by being viewed.
public protocol AccessibilityTrustChecking: Sendable {
    /// Returns trust state without showing a system prompt.
    func isTrusted() -> Bool
}

#if os(macOS)
public struct SystemAccessibilityTrustChecker: AccessibilityTrustChecking {
    public init() {}
    public func isTrusted() -> Bool {
        // Passing an empty options dictionary (rather than the
        // kAXTrustedCheckOptionPrompt key) performs a read-only check: it
        // never shows the "would like to control this computer" prompt.
        AXIsProcessTrustedWithOptions(nil)
    }
}
#endif

public struct AccessibilityTrustCheck: SystemCheck {
    public let id = "accessibility-trust"
    public let title = "Accessibility Permission"

    private let checker: AccessibilityTrustChecking

    public init(checker: AccessibilityTrustChecking) {
        self.checker = checker
    }

    public func run() async -> SystemCheckResult {
        if checker.isTrusted() {
            return SystemCheckResult(id: id, title: title, status: .passed, detail: "This app is trusted for Accessibility control.")
        }
        return SystemCheckResult(
            id: id,
            title: title,
            status: .failed,
            detail: "This app has not been granted Accessibility permission.",
            remediation: "Open System Settings > Privacy & Security > Accessibility and enable this app."
        )
    }
}
