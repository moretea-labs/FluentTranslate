import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let panel: NSPanel
    private let appState: AppState
    private let selectionService = SelectionCaptureService()

    init(appState: AppState, openSettings: @escaping () -> Void) {
        self.appState = appState
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "FluentTranslate"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 620, height: 480)
        panel.contentView = NSHostingView(
            rootView: TranslatorView(
                closePanel: { [weak panel] in panel?.orderOut(nil) },
                openSettings: openSettings
            )
                .environmentObject(appState)
                .environmentObject(appState.settings)
        )
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showAndCapture()
        }
    }

    func showAndCapture() {
        selectionService.captureSelectedText { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.appState.acceptCapture(result)
                self.show()
            }
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}
