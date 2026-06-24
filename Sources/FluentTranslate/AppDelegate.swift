import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private let hotKeyManager = HotKeyManager()
    private var panelController: FloatingPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SelectionCaptureService.requestAccessibilityPermission()

        let settingsWindowController = SettingsWindowController(settings: appState.settings)
        self.settingsWindowController = settingsWindowController

        let panelController = FloatingPanelController(
            appState: appState,
            openSettings: { [weak settingsWindowController] in
                settingsWindowController?.show()
            }
        )
        self.panelController = panelController
        hotKeyManager.registerOptionA { [weak panelController] in
            panelController?.toggle()
        }
        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "FluentTranslate")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开翻译窗口（⌥A）", action: #selector(openTranslator), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openTranslator() {
        panelController?.showAndCapture()
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
