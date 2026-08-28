import Logging

/// Runs a set of `SystemCheck`s and reports their results. The check list
/// is injected (never hardcoded) so Diagnostics-related view models can be
/// tested with a fixed, fake set of checks instead of depending on real
/// system state.
public struct SystemChecksRunner: Sendable {
    private let checks: [any SystemCheck]
    private let logger: any AppLogging

    public init(checks: [any SystemCheck], logger: any AppLogging = OSLogAppLogger.shared) {
        self.checks = checks
        self.logger = logger
    }

    /// Runs every check concurrently (they are required to be read-only,
    /// so concurrent execution is always safe) and returns results in the
    /// same order the checks were provided, so the Diagnostics UI's
    /// ordering is stable and predictable.
    public func runAll() async -> [SystemCheckResult] {
        logger.info("Running \(checks.count) system checks.", category: .systemChecks)
        return await withTaskGroup(of: (Int, SystemCheckResult).self) { group in
            for (index, check) in checks.enumerated() {
                group.addTask { (index, await check.run()) }
            }
            var results = [SystemCheckResult?](repeating: nil, count: checks.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results.compactMap { $0 }
        }
    }
}

#if os(macOS)
public extension SystemChecksRunner {
    /// The production check set, backed by real macOS APIs.
    static func standard() -> SystemChecksRunner {
        SystemChecksRunner(checks: [
            MacOSVersionCheck(),
            AccessibilityTrustCheck(checker: SystemAccessibilityTrustChecker()),
            InstalledApplicationCheck(
                id: "zoom-installed",
                title: "Zoom",
                bundleIdentifier: "us.zoom.xos",
                locator: WorkspaceApplicationLocator()
            ),
            InstalledApplicationCheck(
                id: "teams-installed",
                title: "Microsoft Teams",
                bundleIdentifier: "com.microsoft.teams2",
                locator: WorkspaceApplicationLocator()
            ),
            WiFiCheck(provider: NetworksetupWiFiStateProvider()),
            BluetoothCheck(provider: DefaultsBluetoothStateProvider()),
            AutomationAvailabilityCheck()
        ])
    }
}
#endif
