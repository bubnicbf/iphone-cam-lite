import Foundation
#if os(macOS)
import AppKit
#endif

/// Launches a meeting application in the background (never stealing focus),
/// matching the original scripts' `open -ga <name>` behavior. Injectable so
/// adapters can be exercised in tests without ever spawning a real
/// application.
public protocol ApplicationLauncher: Sendable {
    func launch(bundleIdentifier: String) async throws
}

/// Everything that can go wrong launching an application, distinct from
/// "the process never subsequently appeared" (see `ApplicationReadiness`
/// in CameraCore, which polls for that separately).
public enum ApplicationLaunchFailure: Error, Sendable, Equatable {
    case applicationNotInstalled(bundleIdentifier: String)
    case launchFailed(reason: String)
}

#if os(macOS)
/// Production launcher backed by `NSWorkspace`. Uses a background,
/// non-activating launch configuration -- the SwiftUI/AppKit equivalent of
/// the original `open -ga` invocation -- so launching Zoom or Teams never
/// steals focus from the menu bar app.
public struct WorkspaceApplicationLauncher: ApplicationLauncher {
    public init() {}

    public func launch(bundleIdentifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ApplicationLaunchFailure.applicationNotInstalled(bundleIdentifier: bundleIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw ApplicationLaunchFailure.launchFailed(reason: String(describing: error))
        }
    }
}
#endif
