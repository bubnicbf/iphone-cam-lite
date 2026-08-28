#if os(macOS)
import AppKit
#endif
import SwiftUI

/// First-run onboarding: explains why Accessibility/Apple Events
/// permission is required, shows live status, and links to the exact
/// System Settings pane. Revisitable later from the menu bar.
public struct OnboardingView: View {
    @ObservedObject private var viewModel: OnboardingViewModel
    var onFinished: () -> Void

    public init(viewModel: OnboardingViewModel, onFinished: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to IPhoneCamLite").font(.title).bold()

            Text("""
            This app selects your iPhone's Continuity Camera and microphone \
            inside Zoom and Microsoft Teams for you. To click their menus and \
            buttons on your behalf, macOS requires this app to be trusted for \
            Accessibility and Apple Events automation. It never reads your \
            messages, files, or accounts, and it never signs in to anything \
            for you.
            """)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: viewModel.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(viewModel.accessibilityTrusted ? .green : .orange)
                Text(viewModel.accessibilityTrusted
                     ? "Accessibility permission is granted."
                     : "Accessibility permission has not been granted yet.")
                if viewModel.isChecking {
                    ProgressView().controlSize(.small)
                }
            }

            HStack {
                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }
                Button("Check Again") {
                    Task { await viewModel.refreshAccessibilityStatus() }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") {
                    viewModel.finishOnboarding()
                    onFinished()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.accessibilityTrusted)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 360)
        .task {
            await viewModel.refreshAccessibilityStatus()
        }
    }

    private func openAccessibilitySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

