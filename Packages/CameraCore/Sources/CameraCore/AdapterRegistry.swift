/// Maps each supported `MeetingApplication` to the adapter that drives it.
/// `CameraSelectionCoordinator` looks up adapters through this type rather
/// than switching on `MeetingApplication` itself, so adding a new
/// supported application never requires editing the coordinator.
public struct AdapterRegistry: Sendable {
    private let adaptersByApplication: [MeetingApplication: any DeviceSelectionAdapter]

    public init(adapters: [any DeviceSelectionAdapter]) {
        var map: [MeetingApplication: any DeviceSelectionAdapter] = [:]
        for adapter in adapters {
            map[adapter.application] = adapter
        }
        self.adaptersByApplication = map
    }

    public func adapter(for application: MeetingApplication) throws -> any DeviceSelectionAdapter {
        guard let adapter = adaptersByApplication[application] else {
            throw SelectionError.automationUnavailable(
                reason: "No adapter is registered for \(application.displayName)."
            )
        }
        return adapter
    }

    public var registeredApplications: Set<MeetingApplication> {
        Set(adaptersByApplication.keys)
    }
}
