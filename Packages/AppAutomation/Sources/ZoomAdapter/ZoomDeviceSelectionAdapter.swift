import Foundation
import CameraCore
import AppAutomationCore
import Logging

/// Adapts Zoom's launch-and-select behavior to `CameraCore`'s
/// `DeviceSelectionAdapter` protocol. Every external effect (launching the
/// app, checking whether its process is running, running the packaged
/// AppleScript selector) is injected, so this type can be exercised in
/// `AdapterFixtureTests` with fakes and never launches real Zoom.
///
/// Zoom's exact main executable name ("zoom.us") is the identifier its own
/// installer registers with Launch Services, distinct from helper
/// processes such as "CptHost" -- matched here with `ProcessProbe`'s exact
/// (never substring) semantics, exactly as the original `start_zoom.sh`
/// documented.
public struct ZoomDeviceSelectionAdapter: DeviceSelectionAdapter {
    /// Zoom's Launch Services bundle identifier.
    public static let bundleIdentifier = "us.zoom.xos"
    /// Zoom's exact main process/executable name (never matched as a
    /// substring of a command line).
    public static let exactProcessName = "zoom.us"

    public let application: MeetingApplication = .zoom

    /// The bundled AppleScript selector's URL, resolved via `Bundle.module`
    /// so it is found reliably regardless of the caller's current working
    /// directory. Exposed publicly so tests can independently inspect the
    /// packaged resource (e.g. to assert it never references credential
    /// UI) without needing `Bundle.module` access themselves, since that
    /// accessor is internal to this module.
    public static var defaultScriptURL: URL? {
        Bundle.module.url(forResource: "select_zoom_camera", withExtension: "scpt")
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
        scriptURLProvider: @escaping () -> URL? = { ZoomDeviceSelectionAdapter.defaultScriptURL },
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
            throw SelectionError.resourceMissing(path: "select_zoom_camera.scpt")
        }

        do {
            try await launcher.launch(bundleIdentifier: Self.bundleIdentifier)
        } catch let failure as ApplicationLaunchFailure {
            switch failure {
            case .applicationNotInstalled:
                throw SelectionError.applicationLaunchFailed(application: .zoom, reason: "Zoom is not installed.")
            case let .launchFailed(reason):
                throw SelectionError.applicationLaunchFailed(application: .zoom, reason: reason)
            }
        }

        let checker = ProcessProbeAvailabilityChecker(probe: processProbe, exactProcessName: Self.exactProcessName)
        try await ApplicationReadiness.awaitRunning(
            application: .zoom,
            policy: settings.retryPolicy,
            sleeper: sleeper,
            checker: checker
        )

        let labels = settings.zoomLabels
        let arguments = [
            settings.cameraName.value,
            settings.microphoneName.value,
            labels.meetingMenu,
            labels.cameraMenu,
            labels.microphoneMenu,
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
            logger.warning("Zoom selection failed: \(message)", category: .adapters)
            throw ZoomAutomationErrorClassifier.classify(message.isEmpty ? outcome.standardOutput : message)
        }

        return DeviceSelectionSuccess(camera: settings.cameraName, microphone: settings.microphoneName)
    }
}
