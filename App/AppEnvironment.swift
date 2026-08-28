import Foundation
import CameraCore
import AppAutomationCore
import ZoomAdapter
import TeamsAdapter
import SystemChecks

/// The single composition root for the app: constructs every concrete
/// dependency exactly once and wires it into the view models the UI
/// observes. No other file in `App/` constructs a `CameraSelectionCoordinator`,
/// an adapter, or a `SettingsStoring` implementation -- this is the one
/// place production wiring happens, which is what keeps persistence and
/// automation injectable rather than scattered.
@MainActor
public final class AppEnvironment {
    public let settings: AppSettingsStore
    public let menuBarViewModel: MenuBarViewModel
    public let diagnosticsViewModel: DiagnosticsViewModel
    public let onboardingViewModel: OnboardingViewModel

    public init(
        settingsStore: SettingsStoring,
        coordinator: CameraSelectionCoordinator,
        checksRunner: SystemChecksRunner,
        accessibilityChecker: AccessibilityTrustChecking,
        cameraServiceResetter: CameraServiceResetting
    ) {
        let settings = AppSettingsStore(store: settingsStore)
        self.settings = settings
        self.menuBarViewModel = MenuBarViewModel(coordinator: coordinator, settings: settings)
        self.diagnosticsViewModel = DiagnosticsViewModel(runner: checksRunner, resetter: cameraServiceResetter)
        self.onboardingViewModel = OnboardingViewModel(runner: checksRunner, settings: settings, accessibilityChecker: accessibilityChecker)
    }
}

#if os(macOS)
public extension AppEnvironment {
    /// Production wiring, backed by real macOS automation and persistence.
    static func live() -> AppEnvironment {
        let registry = AdapterRegistry(adapters: [
            ZoomDeviceSelectionAdapter(
                launcher: WorkspaceApplicationLauncher(),
                processProbe: PgrepProcessProbe(),
                automationRunner: OsascriptAutomationRunner()
            ),
            TeamsDeviceSelectionAdapter(
                launcher: WorkspaceApplicationLauncher(),
                processProbe: PgrepProcessProbe(),
                automationRunner: OsascriptAutomationRunner()
            )
        ])
        let coordinator = CameraSelectionCoordinator(registry: registry)
        return AppEnvironment(
            settingsStore: UserDefaultsSettingsStore(),
            coordinator: coordinator,
            checksRunner: .standard(),
            accessibilityChecker: SystemAccessibilityTrustChecker(),
            cameraServiceResetter: SystemCameraServiceResetter()
        )
    }
}
#endif
