import XCTest
import CameraCore
@testable import TeamsAdapter

/// Fixture strings are recorded verbatim from `select_teams_camera.scpt`'s
/// message shapes.
final class TeamsAutomationErrorClassifierTests: XCTestCase {
    func testProcessNotRunning() {
        let error = TeamsAutomationErrorClassifier.classify(
            "Teams is not running (process \"Microsoft Teams\" not found)."
        )
        XCTAssertEqual(error, .processNeverAppeared(application: .microsoftTeams))
    }

    func testSettingsCouldNotBeOpened() {
        let error = TeamsAutomationErrorClassifier.classify(
            "Teams settings could not be opened (Settings menu (Settings) failed: some error (error -1719); Command-, shortcut failed: some error (error -1719))."
        )
        guard case .settingsUIUnavailable(let application, _) = error else {
            return XCTFail("expected .settingsUIUnavailable, got \(error)")
        }
        XCTAssertEqual(application, .microsoftTeams)
    }

    /// Teams signed-out (or still loading) is never detected as a distinct
    /// state -- the automation simply cannot find the Devices entry point,
    /// and reports that honestly rather than attempting to sign in. This
    /// is the exact message shape produced when Teams is showing a
    /// sign-in/loading screen with no Devices control present.
    func testTeamsSignedOutOrNotReadyNeverAttemptsAuthentication() {
        let error = TeamsAutomationErrorClassifier.classify(
            "Teams Devices panel could not be located (no window exposed a control matching \"Devices\")."
        )
        guard case .settingsUIUnavailable(let application, let reason) = error else {
            return XCTFail("expected .settingsUIUnavailable, got \(error)")
        }
        XCTAssertEqual(application, .microsoftTeams)
        XCTAssertTrue(reason.contains("Devices"))
    }

    func testDeviceItemNotFoundInMatchedControlsMenu() {
        let error = TeamsAutomationErrorClassifier.classify(
            "device item \"iPhone Camera\" not found in the matched control's menu"
        )
        XCTAssertEqual(error, .controlNotFound(label: "iPhone Camera"))
    }

    func testNoControlFoundMatchingLabel() {
        let error = TeamsAutomationErrorClassifier.classify(
            "no control found matching \"Camera\""
        )
        XCTAssertEqual(error, .controlNotFound(label: "Camera"))
    }

    func testAmbiguousMatch() {
        let error = TeamsAutomationErrorClassifier.classify(
            "ambiguous match: 2 controls matched \"Camera\""
        )
        XCTAssertEqual(error, .ambiguousMatch(label: "Camera", matchCount: 2))
    }

    func testClickFailed() {
        let error = TeamsAutomationErrorClassifier.classify(
            "clicking the matched control for \"iPhone Camera\" failed: some error (error -1719)"
        )
        guard case .actionFailed = error else {
            return XCTFail("expected .actionFailed, got \(error)")
        }
    }

    func testValueRemainedUnchanged() {
        let error = TeamsAutomationErrorClassifier.classify(
            "clicked \"iPhone Microphone\" on the matched control but the selection remained unchanged within 3.0s (still \"MacBook Pro Microphone\")"
        )
        XCTAssertEqual(error, .valueUnchanged(device: "iPhone Microphone", observedValue: "MacBook Pro Microphone"))
    }

    func testWrongDeviceBecameSelected() {
        let error = TeamsAutomationErrorClassifier.classify(
            "clicked \"iPhone Camera\" on the matched control but a different device became selected within 3.0s (observed \"FaceTime HD Camera\", expected \"iPhone Camera\")"
        )
        XCTAssertEqual(error, .wrongDeviceSelected(expected: "iPhone Camera", observed: "FaceTime HD Camera"))
    }

    func testSelectionStateUnreadable() {
        let error = TeamsAutomationErrorClassifier.classify(
            "clicked \"iPhone Camera\" on the matched control but its resulting value could not be read to confirm the change"
        )
        guard case .selectionStateUnreadable = error else {
            return XCTFail("expected .selectionStateUnreadable, got \(error)")
        }
    }

    func testNamesWithSpacesApostrophesParenthesesAndUnicodeSurviveClassification() {
        let deviceName = "François's iPhone Microphone (Studio)"
        let error = TeamsAutomationErrorClassifier.classify(
            "no control found matching \"\(deviceName)\""
        )
        XCTAssertEqual(error, .controlNotFound(label: deviceName))
    }

    func testTopLevelSingleDeviceFailureIsReportedAsPartialSelection() {
        let error = TeamsAutomationErrorClassifier.classify(
            "Teams device selection failed: camera \"iPhone Camera\" was not confirmed selected (no control found matching \"Camera\")"
        )
        guard case let .partialSelection(cameraFailure, microphoneFailure) = error else {
            return XCTFail("expected .partialSelection, got \(error)")
        }
        XCTAssertNil(microphoneFailure)
        XCTAssertEqual(cameraFailure, .controlNotFound(label: "Camera"))
    }
}
