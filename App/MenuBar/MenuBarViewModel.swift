import Foundation
import CameraCore
#if os(macOS)
import AppKit
#endif

/// The full lifecycle of one device-selection attempt, as the menu bar UI
/// needs to present it: idle, in progress, a confirmed success, or a
/// typed, actionable failure.
public enum SelectionStatus: Equatable {
    case idle
    case running(MeetingApplication)
    case succeeded(MeetingApplication)
    case failed(MeetingApplication, String)
}

/// Drives the menu bar's status line and actions: triggering device
/// selection for Zoom/Teams, a "prevent sleep during calls" toggle
/// (native replacement for `scripts/keepawake.sh`, using
/// `ProcessInfo` activity assertions rather than shelling out to
/// `caffeinate`), and app-level navigation (Settings/Diagnostics/Quit).
/// All published state is confined to the main actor.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public private(set) var status: SelectionStatus = .idle
    @Published public private(set) var isKeepAwakeEnabled = false

    private let coordinator: CameraSelectionCoordinator
    private let settings: AppSettingsStore
    private var activityToken: NSObjectProtocol?
    private var runningTask: Task<Void, Never>?

    public init(coordinator: CameraSelectionCoordinator, settings: AppSettingsStore) {
        self.coordinator = coordinator
        self.settings = settings
    }

    public var isBusy: Bool {
        if case .running = status { return true }
        return false
    }

    /// Starts a selection attempt for `application`. Cancels any
    /// in-flight attempt first, so only one selection ever runs at a time.
    public func selectDevices(for application: MeetingApplication) {
        runningTask?.cancel()
        status = .running(application)
        let snapshot = settings.snapshot
        runningTask = Task { [coordinator] in
            do {
                let result = try await coordinator.select(application: application, settings: snapshot)
                await self.applySuccess(result)
            } catch let error as SelectionError {
                await self.applyFailure(application, error.description)
            } catch {
                await self.applyFailure(application, String(describing: error))
            }
        }
    }

    public func cancelCurrentSelection() {
        runningTask?.cancel()
    }

    @MainActor
    private func applySuccess(_ result: SelectionSuccess) {
        status = .succeeded(result.application)
    }

    @MainActor
    private func applyFailure(_ application: MeetingApplication, _ message: String) {
        status = .failed(application, message)
    }

    /// Toggles an `IOPMAssertion`-backed activity that prevents idle system
    /// sleep, the native equivalent of `caffeinate -dimsu`.
    public func toggleKeepAwake() {
        #if os(macOS)
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
            isKeepAwakeEnabled = false
        } else {
            let token = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "A video call is in progress"
            )
            activityToken = token
            isKeepAwakeEnabled = true
        }
        #endif
    }

    public func quit() {
        #if os(macOS)
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        NSApplication.shared.terminate(nil)
        #endif
    }
}
