/// Minimal capability an adapter's launcher needs to expose for
/// `ApplicationReadiness` to poll: "is the target process running right
/// now". Deliberately not "what is the exact process name" or anything
/// else process-execution related -- those concrete details (exact
/// executable-name matching via `pgrep -x`-equivalent lookups) live in
/// `AppAutomationCore`'s `ProcessProbe`, one layer below CameraCore, and
/// adapters bridge between the two.
public protocol ProcessAvailabilityChecking: Sendable {
    func isRunning() async -> Bool
}

/// Bounded polling for "has the target application's process appeared
/// yet", reproducing `start_zoom.sh`/`start_teams.sh`'s launcher wait loop
/// as shared, adapter-agnostic, cancellation-aware logic. Written once
/// here instead of duplicated per adapter, and independently testable with
/// a fake checker and a fake sleeper.
public enum ApplicationReadiness {
    /// Polls `checker` up to `policy.launchPollAttempts` times, waiting
    /// `policy.launchPollInterval` between attempts. On success, also
    /// waits `policy.launchSettleDelay` so the just-launched UI has time to
    /// finish drawing before automation drives it -- matching the original
    /// scripts' post-launch settle `sleep`. Throws
    /// `SelectionError.applicationStartupTimeout` if the process never
    /// appears within the attempt budget.
    public static func awaitRunning(
        application: MeetingApplication,
        policy: RetryPolicy,
        sleeper: Sleeping,
        checker: ProcessAvailabilityChecking
    ) async throws {
        let attempts = max(policy.launchPollAttempts, 1)
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            if await checker.isRunning() {
                if policy.launchSettleDelay > 0 {
                    try await sleeper.sleep(seconds: policy.launchSettleDelay)
                }
                return
            }
            if attempt < attempts - 1 {
                try await sleeper.sleep(seconds: policy.launchPollInterval)
            }
        }
        throw SelectionError.applicationStartupTimeout(application: application, attempts: attempts)
    }
}
