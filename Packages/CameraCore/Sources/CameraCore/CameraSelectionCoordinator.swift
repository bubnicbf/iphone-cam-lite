import Logging

/// The confirmed result of a coordinator-driven selection: which
/// application, and which exact camera/microphone names were positively
/// read back and matched.
public struct SelectionSuccess: Sendable, Equatable {
    public let application: MeetingApplication
    public let camera: DeviceName
    public let microphone: DeviceName
}

/// Top-level orchestration entry point for the App target: given a target
/// application and a settings snapshot, routes to the correct adapter
/// (`AdapterRegistry`), runs the selection, and maps every possible
/// outcome onto a typed `SelectionSuccess` or a thrown `SelectionError` --
/// never a partial or ambiguous result. Contains no SwiftUI, AppKit, or
/// application-specific accessibility logic of its own.
public final class CameraSelectionCoordinator: Sendable {
    private let registry: AdapterRegistry
    private let logger: any AppLogging

    public init(registry: AdapterRegistry, logger: any AppLogging = OSLogAppLogger.shared) {
        self.registry = registry
        self.logger = logger
    }

    /// Selects the configured camera and microphone in `application`.
    /// Succeeds only when the adapter positively confirms both devices;
    /// every other outcome -- adapter failure, an unregistered
    /// application, or cancellation -- surfaces as a typed `SelectionError`
    /// rather than a partial `SelectionSuccess`.
    public func select(
        application: MeetingApplication,
        settings: DeviceSettingsSnapshot
    ) async throws -> SelectionSuccess {
        try Task.checkCancellation()
        logger.info("Starting device selection for \(application.displayName).", category: .app)

        let adapter: any DeviceSelectionAdapter
        do {
            adapter = try registry.adapter(for: application)
        } catch let error as SelectionError {
            logger.error("No adapter available for \(application.displayName).", category: .app)
            throw error
        }

        do {
            let result = try await adapter.selectDevices(using: settings)
            logger.info("Confirmed both devices for \(application.displayName).", category: .app)
            return SelectionSuccess(application: application, camera: result.camera, microphone: result.microphone)
        } catch is CancellationError {
            logger.warning("Selection for \(application.displayName) was cancelled.", category: .app)
            throw SelectionError.cancelled
        } catch let error as SelectionError {
            logger.warning("Selection for \(application.displayName) failed: \(error.description)", category: .app)
            throw error
        } catch {
            let wrapped = SelectionError.unclassified(message: String(describing: error))
            logger.error("Selection for \(application.displayName) failed with an unmapped error: \(error).", category: .app)
            throw wrapped
        }
    }
}
