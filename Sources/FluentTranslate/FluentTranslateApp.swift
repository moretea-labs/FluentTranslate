import SwiftUI

@main
@MainActor
struct FluentTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState.settings)
                .frame(width: 620, height: 560)
        }
    }
}
