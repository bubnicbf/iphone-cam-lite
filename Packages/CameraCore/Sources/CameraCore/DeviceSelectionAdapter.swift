/// The confirmed result of a fully successful selection: both the camera
/// and microphone names that were positively read back and matched.
public struct DeviceSelectionSuccess: Sendable, Equatable {
    public let camera: DeviceName
    public let microphone: DeviceName

    public init(camera: DeviceName, microphone: DeviceName) {
        self.camera = camera
        self.microphone = microphone
    }
}

/// The seam every meeting-application-specific automation implementation
/// conforms to (`ZoomAdapter`'s `ZoomDeviceSelectionAdapter`,
/// `TeamsAdapter`'s `TeamsDeviceSelectionAdapter`). `CameraCore` depends
/// only on this protocol -- never on a concrete accessibility/AppleScript
/// detail, SwiftUI, or global process execution -- so it can be exercised
/// in tests with a fake and remains free of any one application's quirks.
///
/// A conforming type must not report success unless both devices were
/// positively confirmed selected; a partial result is surfaced by throwing
/// `SelectionError.partialSelection`, never by returning a partially
/// populated success value.
public protocol DeviceSelectionAdapter: Sendable {
    var application: MeetingApplication { get }

    func selectDevices(using settings: DeviceSettingsSnapshot) async throws -> DeviceSelectionSuccess
}
