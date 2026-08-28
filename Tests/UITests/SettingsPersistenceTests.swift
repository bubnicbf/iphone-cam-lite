import XCTest
import CameraCore
@testable import IPhoneCamLite

@MainActor
final class SettingsPersistenceTests: XCTestCase {
    func testSavedSettingsRoundTripThroughTheInjectedStore() {
        let backingStore = InMemorySettingsStore()

        let first = AppSettingsStore(store: backingStore)
        first.cameraNameOverride = "Studio Camera"
        first.zoomCameraControlOverride = "Sélectionner une caméra"
        first.launchPollAttempts = 999_999 // out-of-range; RetryPolicy clamps it downstream
        first.save()

        // A fresh store instance backed by the same persistence reads back
        // exactly what was saved -- settings are never scattered across
        // ad hoc UserDefaults access.
        let second = AppSettingsStore(store: backingStore)
        XCTAssertEqual(second.cameraNameOverride, "Studio Camera")
        XCTAssertEqual(second.zoomCameraControlOverride, "Sélectionner une caméra")
        XCTAssertEqual(second.launchPollAttempts, 999_999)

        // The clamp itself lives in CameraCore.RetryPolicy, applied when a
        // snapshot is built for an actual selection -- never silently
        // capped in the settings store itself.
        XCTAssertEqual(second.snapshot.retryPolicy.launchPollAttempts, RetryPolicy.maxAllowedAttempts)
    }

    func testUnsavedChangesDoNotPersist() {
        let backingStore = InMemorySettingsStore()
        let first = AppSettingsStore(store: backingStore)
        first.cameraNameOverride = "Not Saved"
        // No call to save().

        let second = AppSettingsStore(store: backingStore)
        XCTAssertEqual(second.cameraNameOverride, "")
    }

    func testOnboardingCompletionPersistsImmediatelyWithoutAnExplicitSave() {
        let backingStore = InMemorySettingsStore()
        let first = AppSettingsStore(store: backingStore)
        XCTAssertFalse(first.hasCompletedOnboarding)

        first.setOnboardingCompleted(true)

        let second = AppSettingsStore(store: backingStore)
        XCTAssertTrue(second.hasCompletedOnboarding)
    }
}
