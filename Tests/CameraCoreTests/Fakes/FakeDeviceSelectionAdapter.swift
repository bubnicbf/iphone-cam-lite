import CameraCore

/// Deterministic stand-in for a real adapter: returns a scripted result
/// (success, a specific `SelectionError`, or a plain `Error` to exercise
/// unmapped-error wrapping) and records how it was called, without ever
/// touching accessibility APIs or launching an application.
final class FakeDeviceSelectionAdapter: DeviceSelectionAdapter, @unchecked Sendable {
    enum Script {
        case succeed(camera: DeviceName, microphone: DeviceName)
        case throwSelectionError(SelectionError)
        case throwPlainError
        case throwCancellation
        case hang
    }

    let application: MeetingApplication
    private let script: Script

    private(set) var callCount = 0
    private(set) var lastSettings: DeviceSettingsSnapshot?

    init(application: MeetingApplication, script: Script) {
        self.application = application
        self.script = script
    }

    struct PlainError: Error {}

    func selectDevices(using settings: DeviceSettingsSnapshot) async throws -> DeviceSelectionSuccess {
        callCount += 1
        lastSettings = settings
        switch script {
        case let .succeed(camera, microphone):
            return DeviceSelectionSuccess(camera: camera, microphone: microphone)
        case let .throwSelectionError(error):
            throw error
        case .throwPlainError:
            throw PlainError()
        case .throwCancellation:
            throw CancellationError()
        case .hang:
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }
}
