import Foundation
import CameraCore

/// Reports whether a process with an *exact* executable name is currently
/// running. Every conformance must match exactly, never by substring or
/// full command-line containment, so a helper process or an unrelated
/// process whose arguments merely mention the target name can never
/// produce a false positive -- preserving the original scripts' documented
/// `pgrep -x` (never `pgrep -f`) behavior.
public protocol ProcessProbe: Sendable {
    func isRunning(exactProcessName: String) async -> Bool
}

#if os(macOS)
/// Production probe backed by `/usr/bin/pgrep -x`. The process name is
/// always passed as a single, discrete `Process.arguments` entry -- never
/// interpolated into a shell command string -- so it is safe even for
/// names containing spaces or shell metacharacters (not that exact
/// executable names typically do, but the argument-passing discipline is
/// applied uniformly across this codebase; see `AccessibilityAutomationRunner`
/// for the same rule applied to user-configurable device names and
/// labels).
public struct PgrepProcessProbe: ProcessProbe {
    public init() {}

    public func isRunning(exactProcessName: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", exactProcessName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
#endif


/// Bridges this module's `ProcessProbe` (which checks an arbitrary,
/// explicitly-named process) to `CameraCore.ProcessAvailabilityChecking`
/// (which only asks "is the process I care about running"), so
/// `CameraCore.ApplicationReadiness`'s shared polling logic never needs to
/// know about exact process names. Shared by both `ZoomAdapter` and
/// `TeamsAdapter` so the bridge is written once.
public struct ProcessProbeAvailabilityChecker: ProcessAvailabilityChecking {
    private let probe: ProcessProbe
    private let exactProcessName: String

    public init(probe: ProcessProbe, exactProcessName: String) {
        self.probe = probe
        self.exactProcessName = exactProcessName
    }

    public func isRunning() async -> Bool {
        await probe.isRunning(exactProcessName: exactProcessName)
    }
}
