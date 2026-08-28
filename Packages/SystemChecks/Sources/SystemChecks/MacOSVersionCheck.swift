import Foundation

/// Reports whether the running macOS version meets `minimumMajorVersion`
/// (default 13, Ventura -- the version Continuity Camera requires,
/// matching `scripts/check_prereqs.sh`'s original check). The OS version
/// provider is injectable so this can be tested against arbitrary
/// versions without depending on the machine running the test.
public protocol OperatingSystemVersionProviding: Sendable {
    func currentVersion() -> OperatingSystemVersion
}

public struct SystemOperatingSystemVersionProvider: OperatingSystemVersionProviding {
    public init() {}
    public func currentVersion() -> OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }
}

public struct MacOSVersionCheck: SystemCheck {
    public let id = "macos-version"
    public let title = "macOS Version"

    private let minimumMajorVersion: Int
    private let provider: OperatingSystemVersionProviding

    public init(minimumMajorVersion: Int = 13, provider: OperatingSystemVersionProviding = SystemOperatingSystemVersionProvider()) {
        self.minimumMajorVersion = minimumMajorVersion
        self.provider = provider
    }

    public func run() async -> SystemCheckResult {
        let version = provider.currentVersion()
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if version.majorVersion >= minimumMajorVersion {
            return SystemCheckResult(id: id, title: title, status: .passed, detail: "macOS \(versionString)")
        }
        return SystemCheckResult(
            id: id,
            title: title,
            status: .failed,
            detail: "macOS \(versionString) is older than the required \(minimumMajorVersion).0 (Ventura or newer).",
            remediation: "Update macOS in System Settings > General > Software Update."
        )
    }
}
