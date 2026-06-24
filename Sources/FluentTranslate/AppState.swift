import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var inputText = ""
    @Published var output: TranslationOutput?
    @Published var isLoading = false
    @Published var isAILoading = false
    @Published var errorMessage: String?
    @Published var history: [HistoryItem] = HistoryStore.shared.load()
    @Published var showHistory = false

    let settings = SettingsStore.shared

    private let coordinator = TranslationCoordinator()
    private var currentTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private let selectionService = SelectionCaptureService()
    private(set) var sourceApplication: NSRunningApplication?

    func acceptCapture(_ result: SelectionCaptureService.CaptureResult) {
        sourceApplication = result.sourceApplication
        if let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            inputText = text
            output = nil
            errorMessage = nil
            if settings.autoCapture { translate() }
        }
    }

    func translate() {
        let source = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { errorMessage = TranslationError.emptyInput.localizedDescription; return }

        currentTask?.cancel(); aiTask?.cancel()
        isLoading = true; isAILoading = false; errorMessage = nil
        let local = coordinator.localResult(text: source, settings: settings)
        output = local

        if coordinator.shouldSkipRemoteTranslation(text: source, localEntry: local?.offlineEntry) {
            isLoading = false
            if let local { history = HistoryStore.shared.append(input: source, output: local) }
            return
        }

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let base = try await coordinator.translateBase(text: source, localEntry: local?.offlineEntry, settings: settings)
                guard !Task.isCancelled else { return }
                output = base
                history = HistoryStore.shared.append(input: source, output: base)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = local == nil ? error.localizedDescription : "本地查询已完成；基础翻译失败：\(error.localizedDescription)"
                if let local { history = HistoryStore.shared.append(input: source, output: local) }
            }
            isLoading = false
        }
    }

    func runAIQuery() { runAI(.query) }
    func runAIExpression() { runAI(.expression) }

    private func runAI(_ mode: AITaskMode) {
        let source = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        aiTask?.cancel(); isAILoading = true; errorMessage = nil
        let current = output
        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let enhanced = try await coordinator.runAI(text: source, current: current, mode: mode, settings: settings)
                guard !Task.isCancelled else { return }
                output = enhanced
                history = HistoryStore.shared.append(input: source, output: enhanced)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "AI 补充失败：\(error.localizedDescription)"
            }
            isAILoading = false
        }
    }

    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func replaceSelection(with text: String, completion: (() -> Void)? = nil) { selectionService.replaceSelection(with: text, in: sourceApplication, completion: completion) }
    func useHistory(_ item: HistoryItem) { inputText = item.input; output = item.output; showHistory = false }
    func clearHistory() { HistoryStore.shared.clear(); history = [] }
}
