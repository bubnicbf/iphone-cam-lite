/// Cooperative, cancellation-aware sleeping, injected everywhere
/// `CameraSelectionCoordinator` and its adapters would otherwise call
/// `Task.sleep`/`usleep` directly. Abstracting this out means:
///   - unit tests can substitute an instantaneous fake and exercise every
///     retry/timeout boundary without a multi-second test run,
///   - every wait in this codebase is expressed as "sleep for at most N
///     seconds, but return early if cancelled" rather than an
///     uncancellable blocking sleep.
public protocol Sleeping: Sendable {
    /// Suspends for approximately `seconds`. Must throw `CancellationError`
    /// (or propagate an equivalent cancellation) promptly if the calling
    /// `Task` is cancelled while suspended, rather than completing the
    /// full duration regardless.
    func sleep(seconds: Double) async throws
}

/// Production implementation backed by `Task.sleep`, which is itself
/// cancellation-aware.
public struct SystemSleeper: Sleeping {
    public init() {}

    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Deterministic fake for tests: never actually suspends, but still checks
/// `Task.isCancelled` and records how many times/how long it was asked to
/// sleep, so a test can assert both "cancellation was honored" and "the
/// coordinator asked for exactly N polls" without a real clock.
public final class FakeSleeper: Sleeping, @unchecked Sendable {
    public private(set) var requestedDurations: [Double] = []

    public init() {}

    public func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        requestedDurations.append(seconds)
    }
}
