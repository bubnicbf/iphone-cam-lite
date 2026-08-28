import SwiftUI

/// Persistent settings for device names, per-application UI label
/// overrides, and bounded retry/timeout values. Backed by
/// `AppSettingsStore`; changes are written via an explicit Save action so
/// a half-edited form never partially persists.
public struct SettingsView: View {
    @ObservedObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    public init(settings: AppSettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Devices") {
                LabeledContent("Camera name") {
                    TextField("iPhone Camera", text: $settings.cameraNameOverride)
                }
                LabeledContent("Microphone name") {
                    TextField("iPhone Microphone", text: $settings.microphoneNameOverride)
                }
                Text("Leave blank to use the defaults (iPhone Camera / iPhone Microphone).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Zoom UI Labels") {
                TextField("Meeting menu (Meeting)", text: $settings.zoomMeetingMenuOverride)
                TextField("Camera submenu (Select Camera)", text: $settings.zoomCameraMenuOverride)
                TextField("Microphone submenu (Select Microphone)", text: $settings.zoomMicrophoneMenuOverride)
                TextField("Camera control (Select a camera)", text: $settings.zoomCameraControlOverride)
                TextField("Microphone control (Select a microphone)", text: $settings.zoomMicrophoneControlOverride)
            }

            Section("Teams UI Labels") {
                TextField("Settings menu (Settings)", text: $settings.teamsSettingsMenuOverride)
                TextField("Devices label (Devices)", text: $settings.teamsDevicesOverride)
                TextField("Camera control (Camera)", text: $settings.teamsCameraControlOverride)
                TextField("Microphone control (Microphone)", text: $settings.teamsMicrophoneControlOverride)
            }

            Section("Timing") {
                Stepper("Launch poll attempts: \(settings.launchPollAttempts)", value: $settings.launchPollAttempts, in: 1...120)
                Stepper("Confirmation polls: \(settings.confirmationMaxPolls)", value: $settings.confirmationMaxPolls, in: 1...60)
                Text("Values are bounded automatically to sane limits regardless of what is entered here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save") {
                    settings.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 480)
        .navigationTitle("Settings")
    }
}
