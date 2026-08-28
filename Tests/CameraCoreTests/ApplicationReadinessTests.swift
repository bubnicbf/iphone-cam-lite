import XCTest
@testable import CameraCore

final class ApplicationReadinessTests: XCTestCase {
    func testReturnsAsSoonAsProcessAppears() async throws {
        let checker = FakeProcessAvailabilityChecking(sequence: [false, false, true])
        let sleeper = FakeSleeper()
        try await ApplicationReadiness.awaitRunning(
            application: .zoom,
            policy: RetryPolicy(launchPollAttempts: 10, launchPollInterval: 0.1, launchSettleDelay: 1.0),
            sleeper: sleeper,
            checker: checker
        )
        XCTAssertEqual(checker.callCount, 3)
        // Two poll-interval sleeps before it appeared, plus one settle delay.
        XCTAssertEqual(sleeper.requestedDurations, [0.1, 0.1, 1.0])
    }

    func testThrowsStartupTimeoutWhenProcessNeverAppears() async throws {
        let checker = FakeProcessAvailabilityChecking(sequence: [])
        do {
            try await ApplicationReadiness.awaitRunning(
                application: .microsoftTeams,
                policy: RetryPolicy(launchPollAttempts: 3, launchPollInterval: 0, launchSettleDelay: 0),
                sleeper: FakeSleeper(),
                checker: checker
            )
            XCTFail("expected a timeout")
        } catch SelectionError.applicationStartupTimeout(let application, let attempts) {
            XCTAssertEqual(application, .microsoftTeams)
            XCTAssertEqual(attempts, 3)
            XCTAssertEqual(checker.callCount, 3)
        }
    }

    func testHonorsCancellation() async throws {
        let checker = FakeProcessAvailabilityChecking(sequence: [])
        let task = Task {
            try await ApplicationReadiness.awaitRunning(
                application: .zoom,
                policy: RetryPolicy(launchPollAttempts: 1000, launchPollInterval: 0),
                sleeper: FakeSleeper(),
                checker: checker
            )
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch is SelectionError {
            XCTFail("cancellation should not be reported as a startup timeout")
        }
    }
}
