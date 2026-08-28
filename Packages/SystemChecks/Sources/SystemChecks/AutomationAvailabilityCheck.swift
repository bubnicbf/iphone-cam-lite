import Foundation

/// Confirms the automation facility the transitional AppleScript bridge
/// depends on (`/usr/bin/osascript`) is present and executable. A purely
/// read-only file-system check -- never invokes osascript itself.
public struct AutomationAvailabilityCheck: SystemCheck {
    public let id = "automation-availability"
    public let title = "Automation Support"

    private let osascriptPath: String
    private let fileManager: FileManager

    public init(osascriptPath: String = "/usr/bin/osascript", fileManager: FileManager = .default) {
        self.osascriptPath = osascriptPath
        self.fileManager = fileManager
    }

    public func run() async -> SystemCheckResult {
        guard fileManager.isExecutableFile(atPath: osascriptPath) else {
            return SystemCheckResult(
                id: id,
                title: title,
                status: .failed,
                detail: "\(osascriptPath) was not found or is not executable.",
                remediation: "Reinstall the Xcode Command Line Tools (xcode-select --install)."
            )
        }
        return SystemCheckResult(id: id, title: title, status: .passed, detail: "Automation support is available.")
    }
}
