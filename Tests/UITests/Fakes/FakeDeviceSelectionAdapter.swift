import CameraCore

/// A minimal scripted `DeviceSelectionAdapter` for exercising
/// `MenuBarViewModel` without any real automation. Kept intentionally
/// separate from `CameraCoreTests`' fake of the same name -- UI-level
/// tests exercise the coordinator/view-model wiring, not CameraCore's own
/// internals, so they should not need to depend on CameraCore's test
/// target.
final class FakeDeviceSelectionAdapter: DeviceSelectionAdapter, @unchecked Sendable {
    let application: MeetingApplication
    private let result: Result<DeviceSelectionSuccess, SelectionError>
    private let delayNanoseconds: UInt64

    init(application: MeetingApplication, result: Result<DeviceSelectionSuccess, SelectionError>, delayNanoseconds: UInt64 = 0) {
        self.application = application
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func selectDevices(using settings: DeviceSettingsSnapshot) async throws -> DeviceSelectionSuccess {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}
