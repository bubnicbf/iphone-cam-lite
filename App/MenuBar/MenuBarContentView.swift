import SwiftUI
import CameraCore

/// The menu bar's dropdown content: current status, one action per
/// supported meeting application, a keep-awake toggle, and navigation to
/// Settings/Diagnostics/Quit. This is the `App/MenuBar` UI the task
/// requires: readiness presentation, device-selection actions, Settings
/// and Diagnostics access, and a clear Quit action, all with progress and
/// actionable success/failure feedback.
public struct MenuBarContentView: View {
    @ObservedObject private var viewModel: MenuBarViewModel
    var onOpenSettings: () -> Void
    var onOpenDiagnostics: () -> Void
    var onOpenOnboarding: () -> Void

    public init(
        viewModel: MenuBarViewModel,
        onOpenSettings: @escaping () -> Void,
        onOpenDiagnostics: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onOpenOnboarding = onOpenOnboarding
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusView

            Divider()

            ForEach(MeetingApplication.allCases) { application in
                Button {
                    viewModel.selectDevices(for: application)
                } label: {
                    Label("Select devices in \(application.displayName)", systemImage: "video.fill")
                }
                .disabled(viewModel.isBusy)
            }

            if viewModel.isBusy {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelCurrentSelection()
                }
            }

            Toggle("Prevent sleep during calls", isOn: Binding(
                get: { viewModel.isKeepAwakeEnabled },
                set: { _ in viewModel.toggleKeepAwake() }
            ))

            Divider()

            Button("Onboarding…") { onOpenOnboarding() }
            Button("Settings…") { onOpenSettings() }
            Button("Diagnostics…") { onOpenDiagnostics() }

            Divider()

            Button("Quit IPhoneCamLite") { viewModel.quit() }
        }
        .padding(8)
        .frame(minWidth: 260)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .idle:
            Label("Ready", systemImage: "circle")
        case let .running(application):
            HStack {
                ProgressView().controlSize(.small)
                Text("Selecting devices in \(application.displayName)…")
            }
        case let .succeeded(application):
            Label("Devices confirmed in \(application.displayName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(application, message):
            VStack(alignment: .leading, spacing: 2) {
                Label("Failed in \(application.displayName)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}
