/// The meeting applications this app knows how to drive. Adding a new
/// application means adding a new case here, a new `DeviceSelectionAdapter`
/// conformance in its own adapter module, and registering it with
/// `AdapterRegistry` -- `CameraSelectionCoordinator` itself never branches
/// on which application is in play.
public enum MeetingApplication: String, CaseIterable, Sendable, Identifiable, Hashable {
    case zoom
    case microsoftTeams

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .microsoftTeams: return "Microsoft Teams"
        }
    }
}
