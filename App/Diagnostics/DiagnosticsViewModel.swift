import Foundation
import SystemChecks

/// Drives the Diagnostics view: runs `SystemChecksRunner`'s read-only
/// checks and exposes their results, plus the explicit (non-automatic)
/// "reset camera services" remediation action. All UI-facing state is
/// confined to the main actor.
@MainActor
public final class DiagnosticsViewModel: ObservableObject {
    @Published public private(set) var results: [SystemCheckResult] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var isResetting = false
    @Published public private(set) var lastResetConfirmation: String?

    private let runner: SystemChecksRunner
    private let resetter: CameraServiceResetting

    public init(runner: SystemChecksRunner, resetter: CameraServiceResetting) {
        self.runner = runner
        self.resetter = resetter
    }

    /// Runs every check. Safe to call repeatedly (e.g. on every view
    /// appearance or a manual refresh) since checks are guaranteed
    /// read-only -- this never mutates system state.
    public func refresh() async {
        isRunning = true
        defer { isRunning = false }
        results = await runner.runAll()
    }

    public var failingResults: [SystemCheckResult] {
        results.filter { $0.status == .failed || $0.status == .unknown }
    }

    /// Explicit, user-initiated remediation: restarts camera/media agents.
    /// Never called automatically.
    public func resetCameraServices() async {
        isResetting = true
        defer { isResetting = false }
        await resetter.reset()
        lastResetConfirmation = "Camera services were restarted. Relaunch Zoom or Teams if they were open."
    }
}
