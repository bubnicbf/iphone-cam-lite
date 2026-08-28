/// Resolves a possibly-unset-or-empty override to `fallback`, mirroring the
/// original scripts' `"${VAR:-default}"` shell semantics: both "unset" and
/// "set but empty" use the documented default. Centralized here so every
/// settings type in this file applies the rule identically.
func resolvedOrDefault(_ override: String, default fallback: String) -> String {
    override.isEmpty ? fallback : override
}

/// Configurable menu/control labels `ZoomAdapter` looks for. Mirrors the
/// `ZOOM_*` environment variables the original `start_zoom.sh` read, and
/// the corresponding `on run argv` parameters `select_zoom_camera.scpt`
/// accepted. An empty override string falls back to Zoom's current English
/// label, exactly as before.
public struct ZoomUILabels: Sendable, Equatable {
    public static let defaultMeetingMenu = "Meeting"
    public static let defaultCameraMenu = "Select Camera"
    public static let defaultMicrophoneMenu = "Select Microphone"
    public static let defaultCameraControl = "Select a camera"
    public static let defaultMicrophoneControl = "Select a microphone"

    public var meetingMenuOverride: String
    public var cameraMenuOverride: String
    public var microphoneMenuOverride: String
    public var cameraControlOverride: String
    public var microphoneControlOverride: String

    public init(
        meetingMenuOverride: String = "",
        cameraMenuOverride: String = "",
        microphoneMenuOverride: String = "",
        cameraControlOverride: String = "",
        microphoneControlOverride: String = ""
    ) {
        self.meetingMenuOverride = meetingMenuOverride
        self.cameraMenuOverride = cameraMenuOverride
        self.microphoneMenuOverride = microphoneMenuOverride
        self.cameraControlOverride = cameraControlOverride
        self.microphoneControlOverride = microphoneControlOverride
    }

    public static let `default` = ZoomUILabels()

    public var meetingMenu: String { resolvedOrDefault(meetingMenuOverride, default: Self.defaultMeetingMenu) }
    public var cameraMenu: String { resolvedOrDefault(cameraMenuOverride, default: Self.defaultCameraMenu) }
    public var microphoneMenu: String { resolvedOrDefault(microphoneMenuOverride, default: Self.defaultMicrophoneMenu) }
    public var cameraControl: String { resolvedOrDefault(cameraControlOverride, default: Self.defaultCameraControl) }
    public var microphoneControl: String { resolvedOrDefault(microphoneControlOverride, default: Self.defaultMicrophoneControl) }
}

/// Configurable menu/control labels `TeamsAdapter` looks for. Mirrors the
/// `TEAMS_*` environment variables the original `start_teams.sh` read.
public struct TeamsUILabels: Sendable, Equatable {
    public static let defaultSettingsMenu = "Settings"
    public static let defaultDevices = "Devices"
    public static let defaultCameraControl = "Camera"
    public static let defaultMicrophoneControl = "Microphone"

    public var settingsMenuOverride: String
    public var devicesOverride: String
    public var cameraControlOverride: String
    public var microphoneControlOverride: String

    public init(
        settingsMenuOverride: String = "",
        devicesOverride: String = "",
        cameraControlOverride: String = "",
        microphoneControlOverride: String = ""
    ) {
        self.settingsMenuOverride = settingsMenuOverride
        self.devicesOverride = devicesOverride
        self.cameraControlOverride = cameraControlOverride
        self.microphoneControlOverride = microphoneControlOverride
    }

    public static let `default` = TeamsUILabels()

    public var settingsMenu: String { resolvedOrDefault(settingsMenuOverride, default: Self.defaultSettingsMenu) }
    public var devices: String { resolvedOrDefault(devicesOverride, default: Self.defaultDevices) }
    public var cameraControl: String { resolvedOrDefault(cameraControlOverride, default: Self.defaultCameraControl) }
    public var microphoneControl: String { resolvedOrDefault(microphoneControlOverride, default: Self.defaultMicrophoneControl) }
}

/// The full set of user-configurable inputs a single selection operation
/// needs: which devices to select, and which UI labels to look for in each
/// supported application. Constructed fresh from `AppSettings` (in the App
/// target) for each selection request, so `CameraSelectionCoordinator`
/// never reads persistence directly.
public struct DeviceSettingsSnapshot: Sendable, Equatable {
    public static let defaultCameraName = "iPhone Camera"
    public static let defaultMicrophoneName = "iPhone Microphone"

    /// Raw, possibly-empty camera name override. Empty falls back to
    /// `defaultCameraName`, matching `CAMERA_NAME`'s original shell default.
    public var cameraNameOverride: String
    /// Raw, possibly-empty microphone name override. Empty falls back to
    /// `defaultMicrophoneName`, matching `MICROPHONE_NAME`'s original
    /// shell default.
    public var microphoneNameOverride: String
    public var zoomLabels: ZoomUILabels
    public var teamsLabels: TeamsUILabels
    public var retryPolicy: RetryPolicy

    public init(
        cameraNameOverride: String = "",
        microphoneNameOverride: String = "",
        zoomLabels: ZoomUILabels = .default,
        teamsLabels: TeamsUILabels = .default,
        retryPolicy: RetryPolicy = .default
    ) {
        self.cameraNameOverride = cameraNameOverride
        self.microphoneNameOverride = microphoneNameOverride
        self.zoomLabels = zoomLabels
        self.teamsLabels = teamsLabels
        self.retryPolicy = retryPolicy
    }

    public static let `default` = DeviceSettingsSnapshot()

    public var cameraName: DeviceName {
        DeviceName(resolvedOrDefault(cameraNameOverride, default: Self.defaultCameraName))
    }

    public var microphoneName: DeviceName {
        DeviceName(resolvedOrDefault(microphoneNameOverride, default: Self.defaultMicrophoneName))
    }
}
