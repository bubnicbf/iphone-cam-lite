import Foundation
import CameraCore

/// Persisted keys used by `AppSettingsStore`. Centralized so a key is
/// never duplicated or typo'd across call sites.
private enum SettingsKey {
    static let cameraName = "cameraNameOverride"
    static let microphoneName = "microphoneNameOverride"
    static let zoomMeetingMenu = "zoomMeetingMenuOverride"
    static let zoomCameraMenu = "zoomCameraMenuOverride"
    static let zoomMicrophoneMenu = "zoomMicrophoneMenuOverride"
    static let zoomCameraControl = "zoomCameraControlOverride"
    static let zoomMicrophoneControl = "zoomMicrophoneControlOverride"
    static let teamsSettingsMenu = "teamsSettingsMenuOverride"
    static let teamsDevices = "teamsDevicesOverride"
    static let teamsCameraControl = "teamsCameraControlOverride"
    static let teamsMicrophoneControl = "teamsMicrophoneControlOverride"
    static let launchPollAttempts = "launchPollAttempts"
    static let launchPollInterval = "launchPollInterval"
    static let launchSettleDelay = "launchSettleDelay"
    static let confirmationMaxPolls = "confirmationMaxPolls"
    static let confirmationPollInterval = "confirmationPollInterval"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}

/// The single, typed, `@MainActor`-observable settings surface the whole
/// app reads and writes through. Every property here round-trips through
/// the injected `SettingsStoring` seam -- nothing else in the app touches
/// persistence directly. Empty-string overrides are stored as-is; the
/// documented default-fallback rule itself lives once, in
/// `CameraCore.DeviceSettingsSnapshot`/`ZoomUILabels`/`TeamsUILabels`, not
/// duplicated here.
@MainActor
public final class AppSettingsStore: ObservableObject {
    private let store: SettingsStoring

    @Published public var cameraNameOverride: String
    @Published public var microphoneNameOverride: String

    @Published public var zoomMeetingMenuOverride: String
    @Published public var zoomCameraMenuOverride: String
    @Published public var zoomMicrophoneMenuOverride: String
    @Published public var zoomCameraControlOverride: String
    @Published public var zoomMicrophoneControlOverride: String

    @Published public var teamsSettingsMenuOverride: String
    @Published public var teamsDevicesOverride: String
    @Published public var teamsCameraControlOverride: String
    @Published public var teamsMicrophoneControlOverride: String

    @Published public var launchPollAttempts: Int
    @Published public var launchPollInterval: Double
    @Published public var launchSettleDelay: Double
    @Published public var confirmationMaxPolls: Int
    @Published public var confirmationPollInterval: Double

    @Published public var hasCompletedOnboarding: Bool

    public init(store: SettingsStoring) {
        self.store = store
        cameraNameOverride = store.string(forKey: SettingsKey.cameraName) ?? ""
        microphoneNameOverride = store.string(forKey: SettingsKey.microphoneName) ?? ""
        zoomMeetingMenuOverride = store.string(forKey: SettingsKey.zoomMeetingMenu) ?? ""
        zoomCameraMenuOverride = store.string(forKey: SettingsKey.zoomCameraMenu) ?? ""
        zoomMicrophoneMenuOverride = store.string(forKey: SettingsKey.zoomMicrophoneMenu) ?? ""
        zoomCameraControlOverride = store.string(forKey: SettingsKey.zoomCameraControl) ?? ""
        zoomMicrophoneControlOverride = store.string(forKey: SettingsKey.zoomMicrophoneControl) ?? ""
        teamsSettingsMenuOverride = store.string(forKey: SettingsKey.teamsSettingsMenu) ?? ""
        teamsDevicesOverride = store.string(forKey: SettingsKey.teamsDevices) ?? ""
        teamsCameraControlOverride = store.string(forKey: SettingsKey.teamsCameraControl) ?? ""
        teamsMicrophoneControlOverride = store.string(forKey: SettingsKey.teamsMicrophoneControl) ?? ""
        launchPollAttempts = store.integer(forKey: SettingsKey.launchPollAttempts) ?? RetryPolicy.default.launchPollAttempts
        launchPollInterval = store.double(forKey: SettingsKey.launchPollInterval) ?? RetryPolicy.default.launchPollInterval
        launchSettleDelay = store.double(forKey: SettingsKey.launchSettleDelay) ?? RetryPolicy.default.launchSettleDelay
        confirmationMaxPolls = store.integer(forKey: SettingsKey.confirmationMaxPolls) ?? RetryPolicy.default.confirmationMaxPolls
        confirmationPollInterval = store.double(forKey: SettingsKey.confirmationPollInterval) ?? RetryPolicy.default.confirmationPollInterval
        hasCompletedOnboarding = store.bool(forKey: SettingsKey.hasCompletedOnboarding)
    }

    /// Persists every current value. Call after editing settings in the UI;
    /// individual `@Published` mutations are not written through
    /// automatically, so a Settings screen can offer an explicit
    /// Save/Cancel without partial writes leaking through mid-edit.
    public func save() {
        store.setString(cameraNameOverride, forKey: SettingsKey.cameraName)
        store.setString(microphoneNameOverride, forKey: SettingsKey.microphoneName)
        store.setString(zoomMeetingMenuOverride, forKey: SettingsKey.zoomMeetingMenu)
        store.setString(zoomCameraMenuOverride, forKey: SettingsKey.zoomCameraMenu)
        store.setString(zoomMicrophoneMenuOverride, forKey: SettingsKey.zoomMicrophoneMenu)
        store.setString(zoomCameraControlOverride, forKey: SettingsKey.zoomCameraControl)
        store.setString(zoomMicrophoneControlOverride, forKey: SettingsKey.zoomMicrophoneControl)
        store.setString(teamsSettingsMenuOverride, forKey: SettingsKey.teamsSettingsMenu)
        store.setString(teamsDevicesOverride, forKey: SettingsKey.teamsDevices)
        store.setString(teamsCameraControlOverride, forKey: SettingsKey.teamsCameraControl)
        store.setString(teamsMicrophoneControlOverride, forKey: SettingsKey.teamsMicrophoneControl)
        store.setInteger(launchPollAttempts, forKey: SettingsKey.launchPollAttempts)
        store.setDouble(launchPollInterval, forKey: SettingsKey.launchPollInterval)
        store.setDouble(launchSettleDelay, forKey: SettingsKey.launchSettleDelay)
        store.setInteger(confirmationMaxPolls, forKey: SettingsKey.confirmationMaxPolls)
        store.setDouble(confirmationPollInterval, forKey: SettingsKey.confirmationPollInterval)
    }

    public func setOnboardingCompleted(_ completed: Bool) {
        hasCompletedOnboarding = completed
        store.setBool(completed, forKey: SettingsKey.hasCompletedOnboarding)
    }

    /// Builds an immutable `DeviceSettingsSnapshot` for one selection
    /// operation. `CameraSelectionCoordinator` never reads persistence
    /// itself -- it only ever sees this snapshot.
    public var snapshot: DeviceSettingsSnapshot {
        DeviceSettingsSnapshot(
            cameraNameOverride: cameraNameOverride,
            microphoneNameOverride: microphoneNameOverride,
            zoomLabels: ZoomUILabels(
                meetingMenuOverride: zoomMeetingMenuOverride,
                cameraMenuOverride: zoomCameraMenuOverride,
                microphoneMenuOverride: zoomMicrophoneMenuOverride,
                cameraControlOverride: zoomCameraControlOverride,
                microphoneControlOverride: zoomMicrophoneControlOverride
            ),
            teamsLabels: TeamsUILabels(
                settingsMenuOverride: teamsSettingsMenuOverride,
                devicesOverride: teamsDevicesOverride,
                cameraControlOverride: teamsCameraControlOverride,
                microphoneControlOverride: teamsMicrophoneControlOverride
            ),
            retryPolicy: RetryPolicy(
                launchPollAttempts: launchPollAttempts,
                launchPollInterval: launchPollInterval,
                launchSettleDelay: launchSettleDelay,
                confirmationMaxPolls: confirmationMaxPolls,
                confirmationPollInterval: confirmationPollInterval
            )
        )
    }
}
