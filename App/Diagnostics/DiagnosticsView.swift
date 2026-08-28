import SwiftUI
import SystemChecks

/// Presents `SystemChecksRunner` results with actionable remediation.
/// Opening this view runs only read-only checks; it never mutates system
/// state on its own. The single mutating action (resetting camera
/// services) requires an explicit tap.
public struct DiagnosticsView: View {
    @ObservedObject private var viewModel: DiagnosticsViewModel

    public init(viewModel: DiagnosticsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics").font(.title2).bold()
                Spacer()
                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isRunning)
            }

            List(viewModel.results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        statusIcon(for: result.status)
                        Text(result.title).bold()
                    }
                    Text(result.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let remediation = result.remediation {
                        Text(remediation).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 240)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("If Continuity Camera misbehaves, restarting the camera agents can help.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(viewModel.isResetting ? "Resetting…" : "Reset Camera Services") {
                        Task { await viewModel.resetCameraServices() }
                    }
                    .disabled(viewModel.isResetting)
                    if let confirmation = viewModel.lastResetConfirmation {
                        Text(confirmation).font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .task {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func statusIcon(for status: CheckStatus) -> some View {
        switch status {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unsupported:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}
