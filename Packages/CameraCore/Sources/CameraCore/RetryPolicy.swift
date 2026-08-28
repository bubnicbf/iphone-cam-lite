/// Bounded timing policy for one selection attempt: how long to wait for
/// the target application's process to appear, how long to let its UI
/// settle before driving it, and how long/often to poll for a selection to
/// be confirmed. Every value here has a hard upper bound -- this type
/// cannot express "wait forever" or "retry unboundedly", by construction.
///
/// Defaults reproduce the original scripts' documented timing exactly
/// (`LAUNCHER_ATTEMPTS`/`LAUNCHER_POLL_INTERVAL`/`LAUNCHER_SETTLE_DELAY`
/// from `start_zoom.sh`/`start_teams.sh`, and `confirmationTimeoutSeconds`/
/// `confirmationPollInterval` from the `.scpt` selectors) so migrating to
/// this type changes no observable timing behavior.
public struct RetryPolicy: Sendable, Equatable {
    /// Hard ceiling on `launchPollAttempts` and `confirmationMaxPolls`, so a
    /// misconfigured settings value can never turn a bounded retry loop
    /// into an effectively unbounded one.
    public static let maxAllowedAttempts = 600

    /// Hard ceiling (seconds) on any single poll interval or settle delay.
    public static let maxAllowedInterval: Double = 30

    /// How many times to poll for the target process to appear before
    /// giving up. Matches `LAUNCHER_ATTEMPTS` (Zoom: 20, Teams: 30 in the
    /// original scripts; unified here as a single configurable value).
    public var launchPollAttempts: Int
    /// Seconds between each launch-poll attempt. Matches
    /// `LAUNCHER_POLL_INTERVAL` (0.5s).
    public var launchPollInterval: Double
    /// Seconds to wait after the process appears before driving its UI, so
    /// its window has time to finish drawing. Matches
    /// `LAUNCHER_SETTLE_DELAY` (2s for Zoom, 3s for Teams).
    public var launchSettleDelay: Double
    /// How many times to re-read a control's selection state while waiting
    /// for a click to take effect.
    public var confirmationMaxPolls: Int
    /// Seconds between each confirmation poll. Matches
    /// `confirmationPollInterval` (0.25s) in the original `.scpt` files.
    public var confirmationPollInterval: Double

    public init(
        launchPollAttempts: Int = 20,
        launchPollInterval: Double = 0.5,
        launchSettleDelay: Double = 2.0,
        confirmationMaxPolls: Int = 12,
        confirmationPollInterval: Double = 0.25
    ) {
        self.launchPollAttempts = RetryPolicy.clampAttempts(launchPollAttempts)
        self.launchPollInterval = RetryPolicy.clampInterval(launchPollInterval)
        self.launchSettleDelay = RetryPolicy.clampInterval(launchSettleDelay)
        self.confirmationMaxPolls = RetryPolicy.clampAttempts(confirmationMaxPolls)
        self.confirmationPollInterval = RetryPolicy.clampInterval(confirmationPollInterval)
    }

    public static let `default` = RetryPolicy()

    /// A policy with zero delays and minimal attempt counts, for fast,
    /// deterministic unit tests that still exercise real retry-boundary
    /// logic instead of only mocking it away.
    public static let immediate = RetryPolicy(
        launchPollAttempts: 1,
        launchPollInterval: 0,
        launchSettleDelay: 0,
        confirmationMaxPolls: 1,
        confirmationPollInterval: 0
    )

    /// Total time (seconds) `confirmationMaxPolls`/`confirmationPollInterval`
    /// can consume before a confirmation is abandoned as timed out.
    public var confirmationTimeout: Double {
        Double(confirmationMaxPolls) * confirmationPollInterval
    }

    private static func clampAttempts(_ value: Int) -> Int {
        min(max(value, 1), maxAllowedAttempts)
    }

    private static func clampInterval(_ value: Double) -> Double {
        min(max(value, 0), maxAllowedInterval)
    }
}
