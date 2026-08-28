import XCTest
@testable import CameraCore

final class DeviceSettingsSnapshotTests: XCTestCase {
    func testDefaultsMatchOriginalScriptDefaults() {
        let snapshot = DeviceSettingsSnapshot.default
        XCTAssertEqual(snapshot.cameraName, DeviceName("iPhone Camera"))
        XCTAssertEqual(snapshot.microphoneName, DeviceName("iPhone Microphone"))
        XCTAssertEqual(snapshot.zoomLabels.meetingMenu, "Meeting")
        XCTAssertEqual(snapshot.zoomLabels.cameraMenu, "Select Camera")
        XCTAssertEqual(snapshot.zoomLabels.microphoneMenu, "Select Microphone")
        XCTAssertEqual(snapshot.zoomLabels.cameraControl, "Select a camera")
        XCTAssertEqual(snapshot.zoomLabels.microphoneControl, "Select a microphone")
        XCTAssertEqual(snapshot.teamsLabels.settingsMenu, "Settings")
        XCTAssertEqual(snapshot.teamsLabels.devices, "Devices")
        XCTAssertEqual(snapshot.teamsLabels.cameraControl, "Camera")
        XCTAssertEqual(snapshot.teamsLabels.microphoneControl, "Microphone")
    }

    func testOverriddenValuesAreUsedVerbatim() {
        var snapshot = DeviceSettingsSnapshot()
        snapshot.cameraNameOverride = "Benjamin's iPhone Camera"
        snapshot.microphoneNameOverride = "Studio USB Mic"
        XCTAssertEqual(snapshot.cameraName.value, "Benjamin's iPhone Camera")
        XCTAssertEqual(snapshot.microphoneName.value, "Studio USB Mic")
    }

    func testEmptyStringOverrideFallsBackToDefault_notUnsetOnly() {
        // Mirrors the original shell scripts' "${VAR:-default}" semantics:
        // an explicitly empty override must fall back exactly like an
        // absent one, not be treated as "use an empty device name".
        var snapshot = DeviceSettingsSnapshot()
        snapshot.cameraNameOverride = ""
        snapshot.microphoneNameOverride = ""
        XCTAssertEqual(snapshot.cameraName.value, DeviceSettingsSnapshot.defaultCameraName)
        XCTAssertEqual(snapshot.microphoneName.value, DeviceSettingsSnapshot.defaultMicrophoneName)
    }

    func testZoomLabelOverridesFallBackIndependently() {
        var labels = ZoomUILabels()
        labels.cameraMenuOverride = "Sélectionner la caméra"
        XCTAssertEqual(labels.cameraMenu, "Sélectionner la caméra")
        // Every other label is untouched and still uses its own default.
        XCTAssertEqual(labels.meetingMenu, ZoomUILabels.defaultMeetingMenu)
        XCTAssertEqual(labels.microphoneMenu, ZoomUILabels.defaultMicrophoneMenu)
    }

    func testTeamsLabelOverridesFallBackIndependently() {
        var labels = TeamsUILabels()
        labels.devicesOverride = "Geräte"
        XCTAssertEqual(labels.devices, "Geräte")
        XCTAssertEqual(labels.settingsMenu, TeamsUILabels.defaultSettingsMenu)
    }
}
