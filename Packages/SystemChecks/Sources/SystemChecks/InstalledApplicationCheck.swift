#if os(macOS)
import AppKit
#endif

/// Reports whether an application with a given bundle identifier is
/// installed, via a read-only Launch Services lookup -- never launches or
/// otherwise touches the application.
public protocol ApplicationLocating: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
}

#if os(macOS)
public struct WorkspaceApplicationLocator: ApplicationLocating {
    public init() {}
    public func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
#endif

/// Generic "is this meeting application installed" check, parameterized so
/// the same implementation covers both Zoom and Microsoft Teams rather
/// than two near-duplicate types.
public struct InstalledApplicationCheck: SystemCheck {
    public let id: String
    public let title: String

    private let bundleIdentifier: String
    private let locator: ApplicationLocating

    public init(id: String, title: String, bundleIdentifier: String, locator: ApplicationLocating) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.locator = locator
    }

    public func run() async -> SystemCheckResult {
        if locator.isInstalled(bundleIdentifier: bundleIdentifier) {
            return SystemCheckResult(id: id, title: title, status: .passed, detail: "\(title) is installed.")
        }
        return SystemCheckResult(
            id: id,
            title: title,
            status: .warning,
            detail: "\(title) was not found (bundle identifier \(bundleIdentifier)).",
            remediation: "Install \(title) from the vendor or the App Store."
        )
    }
}
