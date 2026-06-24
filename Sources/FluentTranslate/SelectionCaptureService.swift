import AppKit
import ApplicationServices

final class SelectionCaptureService {
    struct CaptureResult {
        let text: String?
        let sourceApplication: NSRunningApplication?
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func captureSelectedText(completion: @escaping (CaptureResult) -> Void) {
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        guard sourceApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            completion(CaptureResult(text: nil, sourceApplication: nil))
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        pasteboard.clearContents()

        sendCommandKey(virtualKey: 8, to: sourceApplication?.processIdentifier) // C

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let selectedText = pasteboard.string(forType: .string)
            self.restorePasteboard(pasteboard, from: snapshot)
            completion(CaptureResult(text: selectedText, sourceApplication: sourceApplication))
        }
    }

    func replaceSelection(with text: String, in sourceApplication: NSRunningApplication?, completion: (() -> Void)? = nil) {
        guard let sourceApplication else {
            completion?()
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sourceApplication.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.sendCommandKey(virtualKey: 9, to: sourceApplication.processIdentifier) // V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.restorePasteboard(pasteboard, from: snapshot)
                completion?()
            }
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map { sourceItem in
            let copiedItem = NSPasteboardItem()
            for type in sourceItem.types {
                if let data = sourceItem.data(forType: type) {
                    copiedItem.setData(data, forType: type)
                }
            }
            return copiedItem
        } ?? []
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, from items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func sendCommandKey(virtualKey: CGKeyCode, to processID: pid_t?) {
        guard AXIsProcessTrusted(), let processID else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.postToPid(processID)
        keyUp?.postToPid(processID)
    }
}
