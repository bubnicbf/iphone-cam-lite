import SystemChecks

/// Deterministic Accessibility-trust state for `OnboardingViewModel` tests.
final class FakeAccessibilityTrustChecking: AccessibilityTrustChecking, @unchecked Sendable {
    var trusted: Bool
    init(trusted: Bool) { self.trusted = trusted }
    func isTrusted() -> Bool { trusted }
}
