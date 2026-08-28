import XCTest
@testable import CameraCore

final class RetryPolicyTests: XCTestCase {
    func testDefaultsMatchOriginalScriptTiming() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.launchPollAttempts, 20)
        XCTAssertEqual(policy.launchPollInterval, 0.5)
        XCTAssertEqual(policy.launchSettleDelay, 2.0)
        XCTAssertEqual(policy.confirmationMaxPolls, 12)
        XCTAssertEqual(policy.confirmationPollInterval, 0.25)
    }

    func testAttemptsAreClampedToAtLeastOne() {
        let policy = RetryPolicy(launchPollAttempts: 0, confirmationMaxPolls: -5)
        XCTAssertEqual(policy.launchPollAttempts, 1)
        XCTAssertEqual(policy.confirmationMaxPolls, 1)
    }

    func testAttemptsAreClampedToTheUpperBound() {
        let policy = RetryPolicy(launchPollAttempts: 999_999, confirmationMaxPolls: 999_999)
        XCTAssertEqual(policy.launchPollAttempts, RetryPolicy.maxAllowedAttempts)
        XCTAssertEqual(policy.confirmationMaxPolls, RetryPolicy.maxAllowedAttempts)
    }

    func testIntervalsAreClampedToNonNegativeAndUpperBound() {
        let policy = RetryPolicy(launchPollInterval: -1, launchSettleDelay: 10_000, confirmationPollInterval: -3)
        XCTAssertEqual(policy.launchPollInterval, 0)
        XCTAssertEqual(policy.launchSettleDelay, RetryPolicy.maxAllowedInterval)
        XCTAssertEqual(policy.confirmationPollInterval, 0)
    }

    func testConfirmationTimeoutIsDerivedFromPollsAndInterval() {
        let policy = RetryPolicy(confirmationMaxPolls: 4, confirmationPollInterval: 0.5)
        XCTAssertEqual(policy.confirmationTimeout, 2.0, accuracy: 0.0001)
    }

    func testImmediatePolicyHasNoDelaysAndMinimalAttempts() {
        let policy = RetryPolicy.immediate
        XCTAssertEqual(policy.launchPollAttempts, 1)
        XCTAssertEqual(policy.launchPollInterval, 0)
        XCTAssertEqual(policy.confirmationMaxPolls, 1)
        XCTAssertEqual(policy.confirmationPollInterval, 0)
    }
}
