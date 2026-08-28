import Foundation

/// Restarts the camera/media agents macOS sometimes needs kicked after a
/// Continuity Camera hiccup -- the native replacement for
/// `scripts/reset_camera_services.sh`. Unlike `SystemCheck`s (which must
/// never mutate anything), this is a deliberately explicit, user-initiated
/// remediation action: it only runs when the person clicks "Reset Camera
/// Services" in Diagnostics, never automatically and never just from
/// opening the view.
public protocol CameraServiceResetting: Sendable {
    func reset() async
}

#if os(macOS)
public struct SystemCameraServiceResetter: CameraServiceResetting {
    public init() {}

    public func reset() async {
        run("/bin/launchctl", ["kickstart", "-k", "system/com.apple.cmio.AVCAssistant"])
        run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/com.apple.cmio.AppleCameraAssistant"])
        run("/usr/bin/pkill", ["-f", "VCam"])
    }

    /// Best-effort: mirrors the original script's `|| true` -- a missing
    /// service or process is not an error worth surfacing here.
    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
#endif

/// Deterministic fake for tests/previews: records whether it was invoked
/// without touching any real system service.
public final class FakeCameraServiceResetter: CameraServiceResetting, @unchecked Sendable {
    public private(set) var resetCallCount = 0
    public init() {}
    public func reset() async {
        resetCallCount += 1
    }
}
