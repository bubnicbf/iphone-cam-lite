import XCTest
import Foundation
import CameraCore
import AppAutomationCore
@testable import TeamsAdapter

final class TeamsDeviceSelectionAdapterTests: XCTestCase {
    private func makeAdapter(
        launcher: FakeApplicationLauncher = FakeApplicationLauncher(),
        processProbe: FakeProcessProbe,
        runner: FakeAccessibilityAutomationRunner = FakeAccessibilityAutomationRunner(),
        scriptURL: URL? = URL(fileURLWithPath: "/tmp/select_teams_camera.scpt")
    ) -> TeamsDeviceSelectionAdapter {
        TeamsDeviceSelectionAdapter(
            launcher: launcher,
            processProbe: processProbe,
            automationRunner: runner,
            sleeper: FakeSleeper(),
            scriptURLProvider: { scriptURL }
        )
    }

    func testSuccessfulSelectionReturnsBothConfirmedDevices() async throws {
        let probe = FakeProcessProbe(alwaysRunning: ["MSTeams"])
        let runner = FakeAccessibilityAutomationRunner()
        let adapter = makeAdapter(processProbe: probe, runner: runner)

        let result = try await adapter.selectDevices(using: .default)

        XCTAssertEqual(result.camera, "iPhone Camera")
        XCTAssertEqual(result.microphone, "iPhone Microphone")
    }

    func testExactProcessMatchingNeverMatchesTheLegacyTeamsExecutableName() async throws {
        // The legacy Teams client's process is literally named "Teams" --
        // a substring of "MSTeams". Exact matching must never treat that
        // as the new client being ready.
        let probe = FakeProcessProbe(sequence: [["Teams"], ["MSTeams"]])
        let adapter = makeAdapter(processProbe: probe, runner: FakeAccessibilityAutomationRunner())

        _ = try await adapter.selectDevices(using: .default)

        XCTAssertEqual(probe.queriedNames, ["MSTeams", "MSTeams"])
    }

    func testSignedOutOrNotReadyTeamsNeverAttemptsAuthenticationAndReportsHonestly() async throws {
        let probe = FakeProcessProbe(alwaysRunning: ["MSTeams"])
        let runner = FakeAccessibilityAutomationRunner()
        runner.outcome = AutomationOutcome(
            succeeded: false,
            standardOutput: "",
            standardError: "Teams Devices panel could not be located (no window exposed a control matching \"Devices\")."
        )
        let adapter = makeAdapter(processProbe: probe, runner: runner)

        do {
            _ = try await adapter.selectDevices(using: .default)
            XCTFail("expected a classified failure")
        } catch SelectionError.settingsUIUnavailable(let application, _) {
            XCTAssertEqual(application, .microsoftTeams)
        }

        // The packaged AppleScript resource itself never references
        // credential/account UI -- the automation cannot attempt to sign
        // in even if it wanted to.
        let scriptContents = try String(contentsOf: XCTUnwrap(TeamsDeviceSelectionAdapter.defaultScriptURL), encoding: .utf8)
        for forbidden in ["password", "Sign in", "sign in", "Pick an account"] {
            XCTAssertFalse(scriptContents.contains(forbidden), "selector script must never reference \"\(forbidden)\"")
        }
    }

    func testMissingSelectorResourceIsReportedBeforeLaunchingTheApplication() async throws {
        let launcher = FakeApplicationLauncher()
        let probe = FakeProcessProbe(alwaysRunning: ["MSTeams"])
        let adapter = makeAdapter(launcher: launcher, processProbe: probe, scriptURL: nil)

        do {
            _ = try await adapter.selectDevices(using: .default)
            XCTFail("expected .resourceMissing")
        } catch SelectionError.resourceMissing {
            XCTAssertTrue(launcher.launchedBundleIdentifiers.isEmpty)
        }
    }

    func testStartupTimeoutWhenProcessNeverAppears() async throws {
        let probe = FakeProcessProbe(alwaysRunning: [])
        var settings = DeviceSettingsSnapshot.default
        settings.retryPolicy = RetryPolicy(launchPollAttempts: 2, launchPollInterval: 0, launchSettleDelay: 0)
        let adapter = makeAdapter(processProbe: probe, runner: FakeAccessibilityAutomationRunner())

        do {
            _ = try await adapter.selectDevices(using: settings)
            XCTFail("expected a startup timeout")
        } catch SelectionError.applicationStartupTimeout(let application, let attempts) {
            XCTAssertEqual(application, .microsoftTeams)
            XCTAssertEqual(attempts, 2)
        }
    }
}
