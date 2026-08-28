import XCTest
import Foundation
import CameraCore
@testable import IPhoneCamLite

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testMenuOffersOneActionPerSupportedMeetingApplication() {
        // The menu bar is required to offer a device-selection action for
        // every supported meeting application; this is the source of
        // truth `MenuBarContentView` iterates over to build that menu.
        XCTAssertEqual(Set(MeetingApplication.allCases), [.zoom, .microsoftTeams])
    }

    private func makeViewModel(adapter: FakeDeviceSelectionAdapter) -> MenuBarViewModel {
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]))
        let settings = AppSettingsStore(store: InMemorySettingsStore())
        return MenuBarViewModel(coordinator: coordinator, settings: settings)
    }

    func testSelectingDevicesTransitionsFromRunningToSucceeded() async throws {
        let adapter = FakeDeviceSelectionAdapter(
            application: .zoom,
            result: .success(DeviceSelectionSuccess(camera: "iPhone Camera", microphone: "iPhone Microphone"))
        )
        let viewModel = makeViewModel(adapter: adapter)

        XCTAssertEqual(viewModel.status, .idle)
        viewModel.selectDevices(for: .zoom)
        XCTAssertEqual(viewModel.status, .running(.zoom))

        try await waitUntil { viewModel.status != .running(.zoom) }
        XCTAssertEqual(viewModel.status, .succeeded(.zoom))
    }

    func testFailedSelectionSurfacesAnActionableMessage() async throws {
        let adapter = FakeDeviceSelectionAdapter(
            application: .zoom,
            result: .failure(.controlNotFound(label: "Select a camera"))
        )
        let viewModel = makeViewModel(adapter: adapter)

        viewModel.selectDevices(for: .zoom)
        try await waitUntil { viewModel.status != .running(.zoom) }

        guard case let .failed(application, message) = viewModel.status else {
            return XCTFail("expected .failed, got \(viewModel.status)")
        }
        XCTAssertEqual(application, .zoom)
        XCTAssertTrue(message.contains("Select a camera"))
    }

    func testKeepAwakeToggleFlipsState() {
        let adapter = FakeDeviceSelectionAdapter(application: .zoom, result: .success(DeviceSelectionSuccess(camera: "a", microphone: "b")))
        let viewModel = makeViewModel(adapter: adapter)

        XCTAssertFalse(viewModel.isKeepAwakeEnabled)
        viewModel.toggleKeepAwake()
        XCTAssertTrue(viewModel.isKeepAwakeEnabled)
        viewModel.toggleKeepAwake()
        XCTAssertFalse(viewModel.isKeepAwakeEnabled)
    }

    /// Polls `condition` on the main actor until it becomes true or a
    /// bounded timeout elapses -- avoids an arbitrary fixed sleep while
    /// still never hanging a test indefinitely.
    private func waitUntil(_ condition: @MainActor () -> Bool, timeoutSeconds: Double = 2) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition was not met within \(timeoutSeconds)s")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
