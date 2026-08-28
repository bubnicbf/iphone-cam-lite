import XCTest
import Foundation
import CameraCore
import AppAutomationCore
@testable import ZoomAdapter

final class ZoomDeviceSelectionAdapterTests: XCTestCase {
    private func makeAdapter(
        launcher: FakeApplicationLauncher = FakeApplicationLauncher(),
        processProbe: FakeProcessProbe,
        runner: FakeAccessibilityAutomationRunner = FakeAccessibilityAutomationRunner(),
        scriptURL: URL? = URL(fileURLWithPath: "/tmp/select_zoom_camera.scpt")
    ) -> ZoomDeviceSelectionAdapter {
        ZoomDeviceSelectionAdapter(
            launcher: launcher,
            processProbe: processProbe,
            automationRunner: runner,
            sleeper: FakeSleeper(),
            scriptURLProvider: { scriptURL }
        )
    }

    func testSuccessfulSelectionReturnsBothConfirmedDevices() async throws {
        let probe = FakeProcessProbe(alwaysRunning: ["zoom.us"])
        let runner = FakeAccessibilityAutomationRunner()
        runner.outcome = AutomationOutcome(succeeded: true, standardOutput: "", standardError: "")
        let adapter = makeAdapter(processProbe: probe, runner: runner)

        let result = try await adapter.selectDevices(using: .default)

        XCTAssertEqual(result.camera, DeviceName(DeviceSettingsSnapshot.defaultCameraName))
        XCTAssertEqual(result.microphone, "iPhone Microphone")
        XCTAssertEqual(runner.invokedArguments.first?.first, "iPhone Camera")
    }

    func testDeviceNamesAndLabelsReachTheScriptAsDiscreteArgumentsIntact() async throws {
        let probe = FakeProcessProbe(alwaysRunning: ["zoom.us"])
        let runner = FakeAccessibilityAutomationRunner()
        let adapter = makeAdapter(processProbe: probe, runner: runner)

        var settings = DeviceSettingsSnapshot.default
        settings.cameraNameOverride = "Bénédicte's iPhone Camera (2)"
        _ = try await adapter.selectDevices(using: settings)

        let arguments = try XCTUnwrap(runner.invokedArguments.first)
        // Passed through as one discrete argv entry -- spaces, apostrophes,
        // parentheses, and Unicode all intact, never shell-escaped/altered.
        XCTAssertEqual(arguments[0], "Bénédicte's iPhone Camera (2)")
    }

    func testExactProcessMatchingIgnoresHelperOrSubstringProcesses() async throws {
        // "ZoomOpener" and other helper processes must never satisfy the
        // readiness check for the real "zoom.us" process.
        let probe = FakeProcessProbe(sequence: [["ZoomOpener", "CptHost"], ["zoom.us"]])
        let adapter = makeAdapter(processProbe: probe, runner: FakeAccessibilityAutomationRunner())

        _ = try await adapter.selectDevices(using: .default)

        XCTAssertEqual(probe.queriedNames, ["zoom.us", "zoom.us"])
    }

    func testStartupTimeoutWhenProcessNeverAppears() async throws {
        let probe = FakeProcessProbe(alwaysRunning: [])
        var settings = DeviceSettingsSnapshot.default
        settings.retryPolicy = RetryPolicy(launchPollAttempts: 3, launchPollInterval: 0, launchSettleDelay: 0)
        let adapter = makeAdapter(processProbe: probe, runner: FakeAccessibilityAutomationRunner())

        do {
            _ = try await adapter.selectDevices(using: settings)
            XCTFail("expected a startup timeout")
        } catch SelectionError.applicationStartupTimeout(let application, let attempts) {
            XCTAssertEqual(application, .zoom)
            XCTAssertEqual(attempts, 3)
        }
    }

    func testMissingSelectorResourceIsReportedBeforeLaunchingTheApplication() async throws {
        let launcher = FakeApplicationLauncher()
        let probe = FakeProcessProbe(alwaysRunning: ["zoom.us"])
        let adapter = makeAdapter(launcher: launcher, processProbe: probe, scriptURL: nil)

        do {
            _ = try await adapter.selectDevices(using: .default)
            XCTFail("expected .resourceMissing")
        } catch SelectionError.resourceMissing {
            XCTAssertTrue(launcher.launchedBundleIdentifiers.isEmpty, "should not launch Zoom if the selector resource is missing")
        }
    }

    func testAutomationFailureIsClassifiedIntoATypedSelectionError() async throws {
        let probe = FakeProcessProbe(alwaysRunning: ["zoom.us"])
        let runner = FakeAccessibilityAutomationRunner()
        runner.outcome = AutomationOutcome(
            succeeded: false,
            standardOutput: "",
            standardError: "no control found matching \"Select a camera\""
        )
        let adapter = makeAdapter(processProbe: probe, runner: runner)

        do {
            _ = try await adapter.selectDevices(using: .default)
            XCTFail("expected a classified failure")
        } catch SelectionError.controlNotFound(let label) {
            XCTAssertEqual(label, "Select a camera")
        }
    }

    func testApplicationLaunchFailureSurfacesBeforePollingForReadiness() async throws {
        let launcher = FakeApplicationLauncher()
        launcher.failure = .applicationNotInstalled(bundleIdentifier: ZoomDeviceSelectionAdapter.bundleIdentifier)
        let probe = FakeProcessProbe(alwaysRunning: ["zoom.us"])
        let adapter = makeAdapter(launcher: launcher, processProbe: probe)

        do {
            _ = try await adapter.selectDevices(using: .default)
            XCTFail("expected .applicationLaunchFailed")
        } catch SelectionError.applicationLaunchFailed(let application, _) {
            XCTAssertEqual(application, .zoom)
            XCTAssertEqual(probe.queriedNames.count, 0, "should not poll for readiness if launch itself failed")
        }
    }
}
