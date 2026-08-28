import XCTest
@testable import CameraCore
import Logging

final class CameraSelectionCoordinatorTests: XCTestCase {
    func testSucceedsOnlyWhenAdapterConfirmsBothDevices() async throws {
        let adapter = FakeDeviceSelectionAdapter(application: .zoom, script: .succeed(camera: "iPhone Camera", microphone: "iPhone Microphone"))
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]), logger: TestCaptureLogger())

        let result = try await coordinator.select(application: .zoom, settings: .default)

        XCTAssertEqual(result.application, .zoom)
        XCTAssertEqual(result.camera, "iPhone Camera")
        XCTAssertEqual(result.microphone, "iPhone Microphone")
        XCTAssertEqual(adapter.callCount, 1)
    }

    func testPropagatesPartialSelectionFailureWithoutLosingDetail() async throws {
        let underlyingFailure = SelectionError.confirmationTimeout(device: "iPhone Microphone", seconds: 3.0)
        let adapter = FakeDeviceSelectionAdapter(
            application: .zoom,
            script: .throwSelectionError(.partialSelection(cameraFailure: nil, microphoneFailure: underlyingFailure))
        )
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]))

        do {
            _ = try await coordinator.select(application: .zoom, settings: .default)
            XCTFail("expected a partial-selection failure")
        } catch SelectionError.partialSelection(let cameraFailure, let microphoneFailure) {
            XCTAssertNil(cameraFailure)
            XCTAssertEqual(microphoneFailure, underlyingFailure)
        }
    }

    func testUnregisteredApplicationSurfacesAutomationUnavailable() async {
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: []))
        do {
            _ = try await coordinator.select(application: .zoom, settings: .default)
            XCTFail("expected failure")
        } catch SelectionError.automationUnavailable {
            // expected
        } catch {
            XCTFail("expected .automationUnavailable, got \(error)")
        }
    }

    func testCancellationIsMappedToTypedCancelledError() async {
        let adapter = FakeDeviceSelectionAdapter(application: .zoom, script: .throwCancellation)
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]))
        do {
            _ = try await coordinator.select(application: .zoom, settings: .default)
            XCTFail("expected cancellation to be mapped")
        } catch SelectionError.cancelled {
            // expected
        } catch {
            XCTFail("expected .cancelled, got \(error)")
        }
    }

    func testUnmappedErrorsAreWrappedAsUnclassifiedRatherThanLost() async {
        let adapter = FakeDeviceSelectionAdapter(application: .zoom, script: .throwPlainError)
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]))
        do {
            _ = try await coordinator.select(application: .zoom, settings: .default)
            XCTFail("expected an error")
        } catch SelectionError.unclassified {
            // expected
        } catch {
            XCTFail("expected .unclassified, got \(error)")
        }
    }

    func testCooperativelyCancellableWhileAdapterIsRunning() async throws {
        let adapter = FakeDeviceSelectionAdapter(application: .zoom, script: .hang)
        let coordinator = CameraSelectionCoordinator(registry: AdapterRegistry(adapters: [adapter]))
        let task = Task {
            try await coordinator.select(application: .zoom, settings: .default)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch SelectionError.cancelled {
            // expected: CameraSelectionCoordinator maps CancellationError to .cancelled
        }
    }
}
