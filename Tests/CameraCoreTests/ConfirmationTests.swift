import XCTest
@testable import CameraCore

final class ConfirmationTests: XCTestCase {
    func testIsAlreadySelectedTrueWhenValuesMatch() {
        XCTAssertTrue(Confirmation.isAlreadySelected(requested: "iPhone Camera", currentValue: "iPhone Camera"))
    }

    func testIsAlreadySelectedFalseWhenNilOrDifferent() {
        XCTAssertFalse(Confirmation.isAlreadySelected(requested: "iPhone Camera", currentValue: nil))
        XCTAssertFalse(Confirmation.isAlreadySelected(requested: "iPhone Camera", currentValue: "Other Camera"))
    }

    func testPollUntilValueMatches_confirmsAsSoonAsValueMatches() async throws {
        let sleeper = FakeSleeper()
        var reads = ["Other Camera", "Other Camera", "iPhone Camera"]
        let result = try await Confirmation.pollUntilValueMatches(
            requested: "iPhone Camera",
            baseline: "Other Camera",
            policy: RetryPolicy(confirmationMaxPolls: 5, confirmationPollInterval: 0.1),
            sleeper: sleeper,
            readValue: { reads.isEmpty ? nil : reads.removeFirst() }
        )
        XCTAssertEqual(result, .confirmed)
        // Two polls before the match, so exactly two sleeps were requested.
        XCTAssertEqual(sleeper.requestedDurations.count, 2)
    }

    func testPollUntilValueMatches_reportsUnchangedWhenValueNeverMoves() async throws {
        let sleeper = FakeSleeper()
        let result = try await Confirmation.pollUntilValueMatches(
            requested: "iPhone Camera",
            baseline: "Built-in Camera",
            policy: RetryPolicy(confirmationMaxPolls: 3, confirmationPollInterval: 0),
            sleeper: sleeper,
            readValue: { "Built-in Camera" }
        )
        XCTAssertEqual(result, .unchanged(observed: "Built-in Camera"))
    }

    func testPollUntilValueMatches_reportsWrongValueWhenItChangesToSomethingElse() async throws {
        let result = try await Confirmation.pollUntilValueMatches(
            requested: "iPhone Camera",
            baseline: "Built-in Camera",
            policy: RetryPolicy(confirmationMaxPolls: 3, confirmationPollInterval: 0),
            sleeper: FakeSleeper(),
            readValue: { "External USB Camera" }
        )
        XCTAssertEqual(result, .wrongValue(observed: "External USB Camera"))
    }

    func testPollUntilValueMatches_reportsUnreadableWhenNeverReadable() async throws {
        let result = try await Confirmation.pollUntilValueMatches(
            requested: "iPhone Camera",
            baseline: nil,
            policy: RetryPolicy(confirmationMaxPolls: 3, confirmationPollInterval: 0),
            sleeper: FakeSleeper(),
            readValue: { nil }
        )
        XCTAssertEqual(result, .unreadable)
    }

    func testPollUntilValueMatches_honorsCancellation() async throws {
        let task = Task {
            try await Confirmation.pollUntilValueMatches(
                requested: "iPhone Camera",
                baseline: nil,
                policy: RetryPolicy(confirmationMaxPolls: 100, confirmationPollInterval: 0),
                sleeper: FakeSleeper(),
                readValue: { "Other" }
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation to propagate")
        } catch is CancellationError {
            // expected
        }
    }

    func testPollUntilFlagIsTrue_confirmsWhenFlagBecomesTrue() async throws {
        var reads: [(Bool, String)] = [(false, ""), (false, ""), (true, "\u{2713}")]
        let result = try await Confirmation.pollUntilFlagIsTrue(
            policy: RetryPolicy(confirmationMaxPolls: 5, confirmationPollInterval: 0),
            sleeper: FakeSleeper(),
            readFlag: { reads.isEmpty ? nil : reads.removeFirst() }
        )
        XCTAssertEqual(result, .confirmed)
    }

    func testPollUntilFlagIsTrue_timesOutWhenNeverTrue() async throws {
        let result = try await Confirmation.pollUntilFlagIsTrue(
            policy: RetryPolicy(confirmationMaxPolls: 3, confirmationPollInterval: 0),
            sleeper: FakeSleeper(),
            readFlag: { (false, "") }
        )
        XCTAssertEqual(result, .timedOut(lastObserved: ""))
    }

    func testPollUntilFlagIsTrue_reportsUnreadableWhenNeverReadable() async throws {
        let result = try await Confirmation.pollUntilFlagIsTrue(
            policy: RetryPolicy(confirmationMaxPolls: 3, confirmationPollInterval: 0),
            sleeper: FakeSleeper(),
            readFlag: { nil }
        )
        XCTAssertEqual(result, .unreadable)
    }
}
