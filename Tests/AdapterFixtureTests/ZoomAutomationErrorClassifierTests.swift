import XCTest
import CameraCore
@testable import ZoomAdapter

/// Every fixture string below is recorded verbatim from the message shapes
/// `select_zoom_camera.scpt` actually produces (see that file's
/// `on run argv` handler and its helper functions), so this classifier is
/// tested against real failure text, not text invented for convenience.
final class ZoomAutomationErrorClassifierTests: XCTestCase {
    func testProcessNotRunning() {
        let error = ZoomAutomationErrorClassifier.classify(
            "Zoom is not running (process \"zoom.us\" not found)."
        )
        XCTAssertEqual(error, .processNeverAppeared(application: .zoom))
    }

    func testItemNotFound() {
        let error = ZoomAutomationErrorClassifier.classify(
            "menu route (Meeting > Select Camera > iPhone Camera): item not found"
        )
        guard case let .controlNotFound(label) = error else {
            return XCTFail("expected .controlNotFound, got \(error)")
        }
        XCTAssertEqual(label, "iPhone Camera")
    }

    func testNoControlFoundMatchingLabel() {
        let error = ZoomAutomationErrorClassifier.classify(
            "no control found matching \"Select a camera\""
        )
        XCTAssertEqual(error, .controlNotFound(label: "Select a camera"))
    }

    func testAmbiguousMatch() {
        let error = ZoomAutomationErrorClassifier.classify(
            "ambiguous match: 3 controls matched \"Select a camera\""
        )
        XCTAssertEqual(error, .ambiguousMatch(label: "Select a camera", matchCount: 3))
    }

    func testClickFailed() {
        let error = ZoomAutomationErrorClassifier.classify(
            "clicking the matched control for \"iPhone Camera\" failed: some AppleEvent error (error -1719)"
        )
        guard case .actionFailed = error else {
            return XCTFail("expected .actionFailed, got \(error)")
        }
    }

    func testValueRemainedUnchanged() {
        let error = ZoomAutomationErrorClassifier.classify(
            "clicked \"iPhone Camera\" on the matched control but the selection remained unchanged within 3.0s (still \"Built-in Camera\")"
        )
        XCTAssertEqual(error, .valueUnchanged(device: "iPhone Camera", observedValue: "Built-in Camera"))
    }

    func testWrongDeviceBecameSelected() {
        let error = ZoomAutomationErrorClassifier.classify(
            "clicked \"iPhone Camera\" on the matched control but a different device became selected within 3.0s (observed \"External Camera\", expected \"iPhone Camera\")"
        )
        XCTAssertEqual(error, .wrongDeviceSelected(expected: "iPhone Camera", observed: "External Camera"))
    }

    func testSelectionStateUnreadable() {
        let error = ZoomAutomationErrorClassifier.classify(
            "clicked \"iPhone Camera\" on the matched control but its resulting value could not be read to confirm the change"
        )
        guard case .selectionStateUnreadable = error else {
            return XCTFail("expected .selectionStateUnreadable, got \(error)")
        }
    }

    func testMenuRouteConfirmationTimeout() {
        let error = ZoomAutomationErrorClassifier.classify(
            "menu route (Meeting > Select Camera > iPhone Camera): clicked but its mark/selected state never confirmed the change within 3.0s (last observed mark: \"\")"
        )
        XCTAssertEqual(error, .confirmationTimeout(device: "iPhone Camera", seconds: 3.0))
    }

    func testNamesWithSpacesApostrophesParenthesesAndUnicodeSurviveClassification() {
        let deviceName = "Bénédicte's iPhone Camera (2)"
        let error = ZoomAutomationErrorClassifier.classify(
            "no control found matching \"\(deviceName)\""
        )
        XCTAssertEqual(error, .controlNotFound(label: deviceName))
    }

    func testTopLevelSingleDeviceFailureIsReportedAsPartialSelection() {
        let error = ZoomAutomationErrorClassifier.classify(
            "Zoom device selection failed: camera \"iPhone Camera\" was not confirmed selected (no control found matching \"Select a camera\")"
        )
        guard case let .partialSelection(cameraFailure, microphoneFailure) = error else {
            return XCTFail("expected .partialSelection, got \(error)")
        }
        XCTAssertNil(microphoneFailure)
        XCTAssertEqual(cameraFailure, .controlNotFound(label: "Select a camera"))
    }

    func testTopLevelMicrophoneOnlyFailureIsReportedAsPartialSelection() {
        let error = ZoomAutomationErrorClassifier.classify(
            "Zoom device selection failed: microphone \"iPhone Microphone\" was not confirmed selected (no control found matching \"Select a microphone\")"
        )
        guard case let .partialSelection(cameraFailure, microphoneFailure) = error else {
            return XCTFail("expected .partialSelection, got \(error)")
        }
        XCTAssertNil(cameraFailure)
        XCTAssertEqual(microphoneFailure, .controlNotFound(label: "Select a microphone"))
    }

    func testTopLevelBothDevicesFailingAreBothReported() {
        let error = ZoomAutomationErrorClassifier.classify(
            "Zoom device selection failed: camera \"iPhone Camera\" was not confirmed selected (no control found matching \"Select a camera\"); microphone \"iPhone Microphone\" was not confirmed selected (no control found matching \"Select a microphone\")"
        )
        guard case let .partialSelection(cameraFailure, microphoneFailure) = error else {
            return XCTFail("expected .partialSelection, got \(error)")
        }
        XCTAssertEqual(cameraFailure, .controlNotFound(label: "Select a camera"))
        XCTAssertEqual(microphoneFailure, .controlNotFound(label: "Select a microphone"))
    }
}
