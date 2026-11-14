#if os(macOS)
import AppKit
import SwiftUI

@main
struct TranslateDeskApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleController.self)
    private var lifecycleController

    var body: some Scene {
        MenuBarExtra {
            StatusBarMenuView(controller: lifecycleController)
        } label: {
            Image(systemName: "character.bubble")
                .accessibilityLabel("TranslateDesk")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(lifecycleController.model)
                .frame(width: 760, height: 620)
        }
    }
}

private struct StatusBarMenuView: View {
    let controller: AppLifecycleController

    var body: some View {
        Button {
            controller.showQuickWindow(positionNearPointer: true)
        } label: {
            Label("快速翻译", systemImage: "character.bubble")
        }

        Button {
            controller.showMainWindow(focusInput: true)
        } label: {
            Label("切换到完整工作区", systemImage: "macwindow")
        }

        Button {
            controller.hideMainWindow()
        } label: {
            Label("隐藏窗口", systemImage: "eye.slash")
        }

        Divider()

        Text("选中文本后按 ⌥A：快速查词或翻译")

        SettingsLink {
            Label("服务设置…", systemImage: "gearshape")
        }

        Divider()

        Button("退出 TranslateDesk") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
#else
import Foundation

@main
struct TranslateDeskUnsupportedPlatform {
    static func main() {
        print("TranslateDesk GUI requires macOS 14 or later.")
    }
}
#endif
