import XCTest
import SystemChecks
@testable import IPhoneCamLite

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testAccessibilityStatusReflectsThePositivelyConfirmedState() async {
        let checker = FakeAccessibilityTrustChecking(trusted: false)
        let settings = AppSettingsStore(store: InMemorySettingsStore())
        let viewModel = OnboardingViewModel(runner: SystemChecksRunner(checks: []), settings: settings, accessibilityChecker: checker)

        await viewModel.refreshAccessibilityStatus()
        XCTAssertFalse(viewModel.accessibilityTrusted, "must never claim granted until positively confirmed")

        checker.trusted = true
        await viewModel.refreshAccessibilityStatus()
        XCTAssertTrue(viewModel.accessibilityTrusted)
    }

    func testFinishingOnboardingPersistsAndCanBeRevisited() {
        let settings = AppSettingsStore(store: InMemorySettingsStore())
        let viewModel = OnboardingViewModel(
            runner: SystemChecksRunner(checks: []),
            settings: settings,
            accessibilityChecker: FakeAccessibilityTrustChecking(trusted: true)
        )

        XCTAssertFalse(viewModel.hasCompletedOnboarding)
        viewModel.finishOnboarding()
        XCTAssertTrue(viewModel.hasCompletedOnboarding)

        // Onboarding state can be revisited later (e.g. from the menu bar)
        // rather than being a one-time, unrepeatable flag.
        viewModel.revisitOnboarding()
        XCTAssertFalse(viewModel.hasCompletedOnboarding)
    }
}
