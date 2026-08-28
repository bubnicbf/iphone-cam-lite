import SwiftUI
#if os(macOS)
import AppKit
#endif

/// App entry point. Runs as a menu bar accessory -- never a Dock icon or
/// an unnecessary main window -- by setting the activation policy to
/// `.accessory` directly (belt-and-suspenders alongside `LSUIElement` in
/// the packaged `Info.plist`; see `Resources/Info.plist` and
/// `scripts/package_app.sh`), so the app behaves correctly as a menu bar
/// app even when run via `swift run` without a bundled `Info.plist`.
@main
struct IPhoneCamLiteApp: App {
    @State private var environment: AppEnvironment

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.accessory)
        #endif
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        MenuBarExtra("IPhoneCamLite", systemImage: "video.fill") {
            MenuBarSceneContent(environment: environment)
        }
        .menuBarExtraStyle(.window)

        Window("Onboarding", id: "onboarding") {
            OnboardingView(viewModel: environment.onboardingViewModel) {
                NSApplication.shared.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView(settings: environment.settings)
        }
        .windowResizability(.contentSize)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(viewModel: environment.diagnosticsViewModel)
        }
        .windowResizability(.contentSize)
    }
}

/// Thin wrapper so the `openWindow` environment action (only available
/// inside a `View`'s body) can be captured and handed to
/// `MenuBarContentView` as plain closures.
private struct MenuBarSceneContent: View {
    let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContentView(
            viewModel: environment.menuBarViewModel,
            onOpenSettings: { openWindow(id: "settings") },
            onOpenDiagnostics: { openWindow(id: "diagnostics") },
            onOpenOnboarding: { openWindow(id: "onboarding") }
        )
        .task {
            // First run only: show onboarding automatically. Revisiting it
            // later is always available from the menu above.
            if !environment.settings.hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }
}
