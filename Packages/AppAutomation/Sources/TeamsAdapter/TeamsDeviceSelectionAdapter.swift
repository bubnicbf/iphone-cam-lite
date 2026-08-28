import Foundation
import CameraCore
import AppAutomationCore
import Logging

/// Adapts the current ("new") Microsoft Teams client's launch-and-select
/// behavior to `CameraCore`'s `DeviceSelectionAdapter` protocol.
///
/// This adapter intentionally only supports the new Teams client
/// ("MSTeams" / `com.microsoft.teams2`). The legacy/classic Teams client
/// has a different executable name and a different Settings UI; it is
/// deliberately NOT matched here, so this adapter can never silently drive
/// UI the legacy client doesn't have (see docs/ARCHITECTURE.md).
///
/// Teams must already be signed in and fully loaded before this adapter
/// runs -- it never enters credentials, clicks a sign-in or
/// account-picker button, or completes any part of authentication. If
/// Teams is signed out or still loading, the packaged selector simply
/// cannot find the Devices entry point and this surfaces as
/// `SelectionError.settingsUIUnavailable`, never as an attempt to sign in.
public struct TeamsDeviceSelectionAdapter: DeviceSelectionAdapter {
    /// The new Teams client's Launch Services bundle identifier.
    public static let bundleIdentifier = "com.microsoft.teams2"
    /// The new Teams client's exact main process/executable name (never
    /// matched as a substring of a command line, and never the legacy
    /// client's "Teams" executable name).
    public static let exactProcessName = "MSTeams"

    public let application: MeetingApplication = .microsoftTeams

    /// The bundled AppleScript selector's URL, resolved via `Bundle.module`
    /// so it is found reliably regardless of the caller's current working
    /// directory. Exposed publicly so tests can independently inspect the
    /// packaged resource (e.g. to assert it never references credential
    /// UI) without needing `Bundle.module` access themselves, since that
    /// accessor is internal to this module.
    public static var defaultScriptURL: URL? {
        Bundle.module.url(forResource: "select_teams_camera", withExtension: "scpt")
    }

    private let launcher: ApplicationLauncher
    private let processProbe: ProcessProbe
    private let automationRunner: AccessibilityAutomationRunner
    private let sleeper: Sleeping
    private let scriptURLProvider: () -> URL?
    private let logger: any AppLogging

    public init(
        launcher: ApplicationLauncher,
        processProbe: ProcessProbe,
        automationRunner: AccessibilityAutomationRunner,
        sleeper: Sleeping = SystemSleeper(),
        scriptURLProvider: @escaping () -> URL? = { TeamsDeviceSelectionAdapter.defaultScriptURL },
        logger: any AppLogging = OSLogAppLogger.shared
    ) {
        self.launcher = launcher
        self.processProbe = processProbe
        self.automationRunner = automationRunner
        self.sleeper = sleeper
        self.scriptURLProvider = scriptURLProvider
        self.logger = logger
    }

    public func selectDevices(using settings: DeviceSettingsSnapshot) async throws -> DeviceSelectionSuccess {
        guard let scriptURL = scriptURLProvider() else {
            throw SelectionError.resourceMissing(path: "select_teams_camera.scpt")
        }

        do {
            try await launcher.launch(bundleIdentifier: Self.bundleIdentifier)
        } catch let failure as ApplicationLaunchFailure {
            switch failure {
            case .applicationNotInstalled:
                throw SelectionError.applicationLaunchFailed(application: .microsoftTeams, reason: "Microsoft Teams is not installed.")
            case let .launchFailed(reason):
                throw SelectionError.applicationLaunchFailed(application: .microsoftTeams, reason: reason)
            }
        }

        let checker = ProcessProbeAvailabilityChecker(probe: processProbe, exactProcessName: Self.exactProcessName)
        try await ApplicationReadiness.awaitRunning(
            application: .microsoftTeams,
            policy: settings.retryPolicy,
            sleeper: sleeper,
            checker: checker
        )

        let labels = settings.teamsLabels
        let arguments = [
            settings.cameraName.value,
            settings.microphoneName.value,
            labels.settingsMenu,
            labels.devices,
            labels.cameraControl,
            labels.microphoneControl
        ]

        let outcome: AutomationOutcome
        do {
            outcome = try await automationRunner.run(scriptURL: scriptURL, arguments: arguments)
        } catch let failure as AutomationRunnerFailure {
            switch failure {
            case let .scriptNotReadable(path):
                throw SelectionError.resourceMissing(path: path)
            case let .processLaunchFailed(reason):
                throw SelectionError.automationUnavailable(reason: reason)
            }
        }

        guard outcome.succeeded else {
            let message = outcome.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.warning("Teams selection failed: \(message)", category: .adapters)
            throw TeamsAutomationErrorClassifier.classify(message.isEmpty ? outcome.standardOutput : message)
        }

        return DeviceSelectionSuccess(camera: settings.cameraName, microphone: settings.microphoneName)
    }
}
