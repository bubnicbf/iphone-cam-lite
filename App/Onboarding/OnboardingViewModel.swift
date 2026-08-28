import Foundation
import SystemChecks

/// Drives first-run onboarding: explains why Accessibility/Apple Events
/// permission is needed, shows live prerequisite status via
/// `SystemChecksRunner`, and lets the user mark onboarding complete (or
/// revisit it later from the menu bar). Never claims a permission was
/// granted except by positively re-running the check -- there is no
/// "mark as granted" shortcut.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public private(set) var accessibilityTrusted = false
    @Published public private(set) var isChecking = false

    private let runner: SystemChecksRunner
    private let settings: AppSettingsStore
    private let accessibilityChecker: AccessibilityTrustChecking

    public init(runner: SystemChecksRunner, settings: AppSettingsStore, accessibilityChecker: AccessibilityTrustChecking) {
        self.runner = runner
        self.settings = settings
        self.accessibilityChecker = accessibilityChecker
    }

    public var hasCompletedOnboarding: Bool { settings.hasCompletedOnboarding }

    /// Re-reads the live Accessibility trust state. Read-only -- never
    /// prompts, and never sets `accessibilityTrusted = true` except when
    /// the check itself reports trusted.
    public func refreshAccessibilityStatus() async {
        isChecking = true
        defer { isChecking = false }
        accessibilityTrusted = accessibilityChecker.isTrusted()
    }

    public func finishOnboarding() {
        settings.setOnboardingCompleted(true)
    }

    public func revisitOnboarding() {
        settings.setOnboardingCompleted(false)
    }
}
