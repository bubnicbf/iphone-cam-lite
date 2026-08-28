import Foundation

/// The raw result of running one Accessibility/AppleScript automation
/// invocation: whether the process exited zero, and its captured
/// stdout/stderr. Adapters classify this into typed `CameraCore.SelectionError`
/// values (see each adapter's error classifier) -- this type itself is
/// just a faithful, untransformed record of what happened.
public struct AutomationOutcome: Sendable, Equatable {
    public let succeeded: Bool
    public let standardOutput: String
    public let standardError: String

    public init(succeeded: Bool, standardOutput: String, standardError: String) {
        self.succeeded = succeeded
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Runs a packaged AppleScript resource against the system's Accessibility
/// / Apple Events automation facilities. This is the one seam in the
/// codebase that still bridges to the transitional AppleScript selectors
/// (see docs/ARCHITECTURE.md for why); everything above this protocol is
/// pure Swift and fully unit-testable via `FakeAccessibilityAutomationRunner`.
public protocol AccessibilityAutomationRunner: Sendable {
    /// Runs the script at `scriptURL`, passing `arguments` through as
    /// discrete argv entries -- never concatenated into a command string,
    /// so user-configurable device names and UI labels containing spaces,
    /// apostrophes, parentheses, or Unicode reach the script byte-for-byte
    /// intact, exactly like the original
    /// `osascript "$SELECTOR_PATH" "$CAMERA_NAME" ...` invocation.
    func run(scriptURL: URL, arguments: [String]) async throws -> AutomationOutcome
}

public enum AutomationRunnerFailure: Error, Sendable, Equatable {
    case scriptNotReadable(path: String)
    case processLaunchFailed(reason: String)
}

#if os(macOS)
/// Production runner backed by `/usr/bin/osascript`. Deliberately shells
/// out (rather than using `NSAppleScript` in-process) so this app's
/// Apple-Events permission story matches exactly what the original
/// scripts already required and users may have already granted --
/// macOS attributes the automation permission prompt to the responsible
/// launching process, the same way it did when these scripts ran from a
/// terminal.
public struct OsascriptAutomationRunner: AccessibilityAutomationRunner {
    private let osascriptExecutableURL: URL

    public init(osascriptExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript")) {
        self.osascriptExecutableURL = osascriptExecutableURL
    }

    public func run(scriptURL: URL, arguments: [String]) async throws -> AutomationOutcome {
        guard FileManager.default.isReadableFile(atPath: scriptURL.path) else {
            throw AutomationRunnerFailure.scriptNotReadable(path: scriptURL.path)
        }

        let process = Process()
        process.executableURL = osascriptExecutableURL
        process.arguments = [scriptURL.path] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AutomationRunnerFailure.processLaunchFailed(reason: String(describing: error))
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return AutomationOutcome(
            succeeded: process.terminationStatus == 0,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
#endif
