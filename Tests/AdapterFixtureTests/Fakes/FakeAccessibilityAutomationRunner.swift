import Foundation
import AppAutomationCore

/// Returns a scripted `AutomationOutcome` (or throws a scripted failure)
/// instead of ever invoking `/usr/bin/osascript`, and records exactly what
/// it was asked to run -- including the raw argument array, so a test can
/// assert that device names/labels reached it unmodified (spaces,
/// apostrophes, parentheses, and Unicode all intact).
final class FakeAccessibilityAutomationRunner: AccessibilityAutomationRunner, @unchecked Sendable {
    private(set) var invokedScriptURLs: [URL] = []
    private(set) var invokedArguments: [[String]] = []

    var outcome: AutomationOutcome = AutomationOutcome(succeeded: true, standardOutput: "", standardError: "")
    var thrownFailure: AutomationRunnerFailure?

    func run(scriptURL: URL, arguments: [String]) async throws -> AutomationOutcome {
        invokedScriptURLs.append(scriptURL)
        invokedArguments.append(arguments)
        if let thrownFailure {
            throw thrownFailure
        }
        return outcome
    }
}
