import AppAutomationCore

/// Records every launch request and returns a scripted result, so adapter
/// tests never call `NSWorkspace`/launch a real application.
final class FakeApplicationLauncher: ApplicationLauncher, @unchecked Sendable {
    private(set) var launchedBundleIdentifiers: [String] = []
    var failure: ApplicationLaunchFailure?

    func launch(bundleIdentifier: String) async throws {
        launchedBundleIdentifiers.append(bundleIdentifier)
        if let failure {
            throw failure
        }
    }
}
