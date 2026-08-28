import XCTest
@testable import CameraCore

final class AdapterRegistryTests: XCTestCase {
    func testRoutesToTheAdapterRegisteredForEachApplication() throws {
        let zoomAdapter = FakeDeviceSelectionAdapter(application: .zoom, script: .succeed(camera: "iPhone Camera", microphone: "iPhone Microphone"))
        let teamsAdapter = FakeDeviceSelectionAdapter(application: .microsoftTeams, script: .succeed(camera: "iPhone Camera", microphone: "iPhone Microphone"))
        let registry = AdapterRegistry(adapters: [zoomAdapter, teamsAdapter])

        let resolvedZoom = try registry.adapter(for: .zoom)
        let resolvedTeams = try registry.adapter(for: .microsoftTeams)

        XCTAssertEqual(resolvedZoom.application, .zoom)
        XCTAssertEqual(resolvedTeams.application, .microsoftTeams)
    }

    func testThrowsAutomationUnavailableForAnUnregisteredApplication() {
        let registry = AdapterRegistry(adapters: [])
        XCTAssertThrowsError(try registry.adapter(for: .zoom)) { error in
            guard case SelectionError.automationUnavailable = error else {
                XCTFail("expected .automationUnavailable, got \(error)")
                return
            }
        }
    }

    func testRegisteredApplicationsReflectsWhatWasProvided() {
        let registry = AdapterRegistry(adapters: [
            FakeDeviceSelectionAdapter(application: .zoom, script: .succeed(camera: "a", microphone: "b"))
        ])
        XCTAssertEqual(registry.registeredApplications, [.zoom])
    }
}
