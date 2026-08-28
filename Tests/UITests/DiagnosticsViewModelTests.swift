import XCTest
import SystemChecks
@testable import IPhoneCamLite

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {
    func testRefreshDisplaysAMockedFailureWithItsRemediation() async {
        let failingCheck = FakeSystemCheck(
            id: "accessibility-trust",
            title: "Accessibility Permission",
            status: .failed,
            detail: "This app has not been granted Accessibility permission.",
            remediation: "Open System Settings > Privacy & Security > Accessibility and enable this app."
        )
        let passingCheck = FakeSystemCheck(id: "macos-version", title: "macOS Version", status: .passed, detail: "macOS 14.0")
        let runner = SystemChecksRunner(checks: [failingCheck, passingCheck])
        let viewModel = DiagnosticsViewModel(runner: runner, resetter: FakeCameraServiceResetter())

        await viewModel.refresh()

        XCTAssertEqual(viewModel.results.count, 2)
        let failing = try? XCTUnwrap(viewModel.results.first { $0.id == "accessibility-trust" })
        XCTAssertEqual(failing?.status, .failed)
        XCTAssertEqual(failing?.remediation, "Open System Settings > Privacy & Security > Accessibility and enable this app.")
        XCTAssertEqual(viewModel.failingResults.map(\.id), ["accessibility-trust"])
    }

    func testRefreshingNeverInvokesTheMutatingResetAction() async {
        let resetter = FakeCameraServiceResetter()
        let runner = SystemChecksRunner(checks: [
            FakeSystemCheck(id: "wifi", title: "Wi-Fi", status: .passed, detail: "connected")
        ])
        let viewModel = DiagnosticsViewModel(runner: runner, resetter: resetter)

        await viewModel.refresh()

        XCTAssertEqual(resetter.resetCallCount, 0, "opening/refreshing Diagnostics must never mutate system state")
    }

    func testResetCameraServicesIsOnlyInvokedExplicitly() async {
        let resetter = FakeCameraServiceResetter()
        let viewModel = DiagnosticsViewModel(runner: SystemChecksRunner(checks: []), resetter: resetter)

        await viewModel.resetCameraServices()

        XCTAssertEqual(resetter.resetCallCount, 1)
        XCTAssertNotNil(viewModel.lastResetConfirmation)
    }
}
