#if os(macOS)
import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppLifecycleController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()

    private var mainWindow: NSWindow?
    private var quickWindow: NSWindow?
    private var quickWindowPinned = false
    private var globalHotKey: GlobalHotKeyManager?
    private var isCapturingSelection = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)
        if let icon = AppBrand.logoImage() {
            NSApp.applicationIconImage = icon
        }

        installEditMenu()
        registerGlobalHotKey()
        showMainWindow(focusInput: false)

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow(focusInput: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === quickWindow, !quickWindowPinned else { return }
        window.orderOut(nil)
    }

    @objc func showMainWindowFromMenu(_ sender: Any? = nil) {
        showMainWindow(focusInput: true)
    }

    func showMainWindow(focusInput: Bool = true) {
        // The workspace keeps its own frame. The compact lookup never resizes it.
        quickWindow?.orderOut(nil)
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if focusInput { focusEditor() }
    }

    @objc func hideMainWindow(_ sender: Any? = nil) {
        mainWindow?.orderOut(nil)
    }

    private func hideQuickWindow() {
        quickWindow?.orderOut(nil)
    }

    func showQuickWindow(positionNearPointer: Bool = false) {
        // Construct the quick window directly at compact size, never as a
        // visible 1280pt workspace that gets animated down to a smaller frame.
        let window = quickWindow ?? makeQuickWindow()
        quickWindow = window

        let size = window.frame.size
        let origin = compactOrigin(
            for: size, relativeTo: mainWindow ?? window, nearPointer: positionNearPointer
        )
        window.setFrameOrigin(origin)
        mainWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusEditor()
    }

    private func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.model.focusInput()
        }
    }

    private func compactOrigin(for size: NSSize, relativeTo window: NSWindow,
                               nearPointer: Bool) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let anchor = nearPointer ? pointer : NSPoint(x: window.frame.midX, y: window.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
                ?? window.screen ?? NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let visible = screen.visibleFrame
        let desiredX = nearPointer ? pointer.x + 20 : anchor.x - size.width / 2
        let desiredY = nearPointer ? pointer.y - size.height - 22 : anchor.y - size.height / 2
        return NSPoint(
            x: min(max(desiredX, visible.minX + 12), visible.maxX - size.width - 12),
            y: min(max(desiredY, visible.minY + 12), visible.maxY - size.height - 12)
        )
    }

    @objc private func minimizeToStatusBar(_ sender: Any? = nil) {
        showQuickWindow()
    }

    private func makeMainWindow() -> NSWindow {
        let rootView = RootView(
            compact: false,
            onCompact: { [weak self] in self?.showQuickWindow() },
            onExpand: { [weak self] in self?.showMainWindow(focusInput: true) },
            onClose: { [weak self] in self?.hideMainWindow() },
            onPin: { [weak self] pinned in self?.quickWindowPinned = pinned }
        ).environmentObject(model)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppBrand.displayName
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 820, height: 560)
        // Apply the new workspace's intended width before enabling frame autosave.
        // Setting the autosave name first can persist the hosting view's 820pt minimum.
        window.setContentSize(NSSize(width: 1280, height: 800))
        let frameName = "TranslateDesk.MainWindow.VisualV2"
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
        window.setFrameAutosaveName(frameName)

        if let minimizeButton = window.standardWindowButton(.miniaturizeButton) {
            minimizeButton.target = self
            minimizeButton.action = #selector(minimizeToStatusBar(_:))
            minimizeButton.toolTip = "缩小为快捷翻译窗口"
        }
        return window
    }

    private func makeQuickWindow() -> NSWindow {
        let view = RootView(
            compact: true,
            onCompact: {},
            onExpand: { [weak self] in self?.showMainWindow(focusInput: true) },
            onClose: { [weak self] in self?.hideQuickWindow() },
            onPin: { [weak self] pinned in self?.quickWindowPinned = pinned }
        ).environmentObject(model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppBrand.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 440, height: 310)
        window.maxSize = NSSize(width: 700, height: 620)
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        return window
    }

    private func installEditMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        if NSApp.mainMenu == nil { NSApp.mainMenu = mainMenu }
        guard !mainMenu.items.contains(where: { $0.title == "编辑" || $0.title == "Edit" }) else { return }

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "编辑")
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        let focus = menu.addItem(withTitle: "聚焦输入框", action: #selector(showMainWindowFromMenu(_:)), keyEquivalent: "l")
        focus.target = self
        editItem.submenu = menu
        mainMenu.addItem(editItem)
    }

    private func translateSelectionFromHotKey() {
        // Option+A inside TranslateDesk must never turn the full workspace
        // into the compact window or replace text that the user is editing.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        if sourceApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Do not interrupt editing or replace the current workspace.
            return
        }
        guard !isCapturingSelection else { return }
        isCapturingSelection = true
        Task { [weak self] in
            let result = await SelectedTextCapture.capture(from: sourceApp)
            guard let self else { return }
            self.isCapturingSelection = false
            switch result {
            case .text(let text):
                self.model.workspaceMode = .smart
                self.model.sourceText = text
                self.presentHotKeyWindow()
                await self.model.performPrimaryAction()
            case .noSelection:
                // With no selection, leave the existing workspace intact.
                // The quick-panel editor selects its text for immediate replacement.
                self.model.workspaceMode = .smart
                self.presentHotKeyWindow()
            case .accessibilityRequired:
                self.presentHotKeyWindow()
                self.model.errorMessage = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 TranslateDesk，才能读取其他应用的选中文本。"
            }
        }
    }

    private func presentHotKeyWindow() {
        showQuickWindow(positionNearPointer: true)
    }

    private func registerGlobalHotKey() {
        do {
            globalHotKey = try GlobalHotKeyManager(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(optionKey)
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.translateSelectionFromHotKey()
                }
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
#endif