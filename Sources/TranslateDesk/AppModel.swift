#if os(macOS)
import AVFoundation
import AppKit
import Foundation
import SwiftUI
import TranslateCore

enum ProviderConnectionStatus: Equatable {
    case idle
    case checking
    case success(String)
    case failure(String)
}

struct ProviderRuntimeStatus: Equatable {
    var isReady: Bool
    var issues: [String]
    var secretAvailable = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceText = ""
    @Published var lastSubmittedText = ""
    @Published var workspaceMode: WorkspaceMode = .smart
    @Published var sourceLanguage = "auto"
    @Published var targetLanguage = "auto"
    @Published var contextText = ""
    @Published var dictionaryResults: [DictionaryLookupResult] = []
    @Published var dictionaryPresentations: [String: DictionaryPresentation] = [:]
    @Published var dictionarySuggestions: [String] = []
    @Published var results: [TranslationResult] = []
    @Published var expressionResults: [ExpressionResult] = []
    @Published var selectedResultID: UUID?
    @Published var lastAnalysis: InputAnalysis?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var copyFeedback: String?
    @Published var inputFocusRequest = 0
    @Published var resultDisplayPreferences = ResultDisplayPreferences()
    @Published var configuration: AppConfiguration
    @Published var englishAccent: EnglishAccent = .american {
        didSet { UserDefaults.standard.set(englishAccent.rawValue, forKey: Self.accentPreferenceKey) }
    }
    @Published private(set) var wordPronunciation: EnglishPronunciationEntry?
    @Published private(set) var englishMeaningIPAs: [String: String] = [:]
    @Published private(set) var speechStatus: String?

    @Published private(set) var providerRuntimeStatuses: [String: ProviderRuntimeStatus] = [:]
    @Published private(set) var providerConnectionStatuses: [String: ProviderConnectionStatus] = [:]

    let configurationStore: FileConfigurationStore
    let keychain = KeychainSecretStore.shared
    private let cache = TranslationCache(fileURL: StoragePaths.cache)
    private let localDictionary: LocalDictionary
    private let dictionaryCatalog: DictionaryCatalog
    private let resultDisplayPreferenceStore = ResultDisplayPreferenceStore()
    private var requestGeneration = 0
    private var providerStatusRevision = 0
    private var copyFeedbackTask: Task<Void, Never>?
    private let speechSynthesizer = NSSpeechSynthesizer()
    private static let accentPreferenceKey = "TranslateDesk.englishAccent"
    private var pronunciationWord: String?
    private var pronunciationTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var speechFeedbackTask: Task<Void, Never>?

    init() {
        let builtInDictionary = LocalDictionary()
        localDictionary = builtInDictionary
        dictionaryCatalog = DictionaryCatalog(
            sources: BundledDictionaries.makeSources() + [builtInDictionary]
        )
        configurationStore = FileConfigurationStore(fileURL: StoragePaths.configuration)
        configuration = (try? configurationStore.load()) ?? .default
        if configuration.addNativeTranslationIfNeeded() {
            try? configurationStore.save(configuration)
        }
        englishAccent = EnglishAccent(rawValue: UserDefaults.standard.string(forKey: Self.accentPreferenceKey) ?? "") ?? .american
        resultDisplayPreferences = resultDisplayPreferenceStore.load()
        refreshProviderRuntimeStatuses()
    }

    var loadedDictionaries: [DictionarySourceInfo] {
        dictionaryCatalog.sourceInfos
    }

    var defaultPreset: TranslationPreset? {
        configuration.presets.first { $0.id == configuration.defaultPresetID }
    }

    var accurateProvider: ProviderConfiguration? {
        guard let id = configuration.accurateProviderID else { return nil }
        return configuration.providers.first { $0.id == id }
    }

    var enabledTranslationProviders: [ProviderConfiguration] {
        configuration.providers.filter {
            isProviderEnabledAndReady($0) && $0.kind != .local &&
            ($0.capabilities.contains(.translation) || $0.capabilities.contains(.contextualTranslation))
        }
    }

    var selectedResultFilterKey: String {
        resultDisplayPreferences.selectedFilterKey
    }

    func presentation(for result: DictionaryLookupResult) -> DictionaryPresentation {
        dictionaryPresentations[result.id] ?? DictionaryPresentationParser.parse(result)
    }

    func displayedIPA(for presentation: DictionaryPresentation) -> String? {
        if pronunciationWord == presentation.headword.lowercased(),
           let entry = wordPronunciation {
            if let local = entry.localizedIPA(for: englishAccent) {
                return "\(englishAccent.title) \(local)"
            }
            if let generic = entry.ipa(for: englishAccent) {
                return generic
            }
        }
        return presentation.pronunciation
    }

    func ipaForEnglishMeaning(_ meaning: String) -> String? {
        guard let word = EnglishMeaningHeadword.extract(from: meaning) else { return nil }
        return englishMeaningIPAs[word]
    }

    private func refreshEnglishMeaningIPAs() {
        let meanings = dictionaryPresentations.values.flatMap { presentation in
            presentation.senses.flatMap { $0.definitions.map(\.text) }
        }
        let words = Set(meanings.compactMap { EnglishMeaningHeadword.extract(from: $0) })
        var phonetics: [String: String] = [:]
        for word in words {
            guard let source = dictionaryCatalog.lookup(word).first(where: {
                $0.dictionaryID == "cambridge-en-zh"
            }), let ipa = DictionaryPresentationParser.parse(source).pronunciation else { continue }
            phonetics[word] = ipa
        }
        englishMeaningIPAs = phonetics
    }

    private static func isSingleEnglishWord(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z][A-Za-z'-]{0,63}$", options: .regularExpression) != nil
    }

    private func resetPronunciation() {
        pronunciationTask?.cancel()
        pronunciationWord = nil
        wordPronunciation = nil
    }

    private func loadPronunciation(for word: String) {
        resetPronunciation()
        guard Self.isSingleEnglishWord(word) else { return }
        let key = word.lowercased()
        pronunciationWord = key
        pronunciationTask = Task { [weak self] in
            guard let self, let entry = try? await Self.fetchPronunciation(for: key),
                  !Task.isCancelled, self.pronunciationWord == key else { return }
            self.wordPronunciation = entry
        }
    }

    private static func fetchPronunciation(for word: String) async throws -> EnglishPronunciationEntry? {
        guard Self.isSingleEnglishWord(word),
              let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 750_000 else { return nil }
        let entries = try JSONDecoder().decode([EnglishPronunciationEntry].self, from: data)
        return entries.first { $0.word?.lowercased() == word } ?? entries.first
    }

    func selectResultFilter(_ key: String) {
        updateResultDisplayPreferences { $0.selectedFilterKey = key }
    }

    func shouldShowDictionary(_ dictionaryID: String) -> Bool {
        selectedResultFilterKey == ResultFilterKey.all
            || selectedResultFilterKey == ResultFilterKey.dictionary(dictionaryID)
    }

    var shouldShowTranslations: Bool {
        selectedResultFilterKey == ResultFilterKey.all
            || selectedResultFilterKey == ResultFilterKey.translation
    }

    var shouldShowExpressions: Bool {
        selectedResultFilterKey == ResultFilterKey.all
            || selectedResultFilterKey == ResultFilterKey.expression
    }

    func isDictionaryCollapsed(_ dictionaryID: String) -> Bool {
        resultDisplayPreferences.collapsedDictionaryIDs.contains(dictionaryID)
    }

    func toggleDictionaryCollapsed(_ dictionaryID: String) {
        updateResultDisplayPreferences { preferences in
            if preferences.collapsedDictionaryIDs.contains(dictionaryID) {
                preferences.collapsedDictionaryIDs.remove(dictionaryID)
            } else {
                preferences.collapsedDictionaryIDs.insert(dictionaryID)
            }
        }
    }

    func isDictionaryGroupExpanded(
        dictionaryID: String,
        groupID: String,
        defaultValue: Bool
    ) -> Bool {
        resultDisplayPreferences.groupExpansion[groupPreferenceKey(dictionaryID, groupID)] ?? defaultValue
    }

    func setDictionaryGroupExpanded(dictionaryID: String, groupID: String, expanded: Bool) {
        updateResultDisplayPreferences {
            $0.groupExpansion[groupPreferenceKey(dictionaryID, groupID)] = expanded
        }
    }

    func isDictionaryGroupFullyExpanded(dictionaryID: String, groupID: String) -> Bool {
        resultDisplayPreferences.groupDetailExpansion[groupPreferenceKey(dictionaryID, groupID)] ?? false
    }

    func setDictionaryGroupFullyExpanded(dictionaryID: String, groupID: String, expanded: Bool) {
        updateResultDisplayPreferences {
            $0.groupDetailExpansion[groupPreferenceKey(dictionaryID, groupID)] = expanded
        }
    }

    func setAllDictionaryGroups(
        dictionaryID: String,
        groupIDs: [String],
        expanded: Bool
    ) {
        updateResultDisplayPreferences { preferences in
            for groupID in groupIDs {
                preferences.groupExpansion[groupPreferenceKey(dictionaryID, groupID)] = expanded
            }
        }
    }

    func setAllDictionaryGroupDetails(
        dictionaryID: String,
        groupIDs: [String],
        expanded: Bool
    ) {
        updateResultDisplayPreferences { preferences in
            for groupID in groupIDs {
                preferences.groupDetailExpansion[groupPreferenceKey(dictionaryID, groupID)] = expanded
            }
        }
    }

    func resetDictionaryLayout(dictionaryID: String) {
        updateResultDisplayPreferences { preferences in
            let prefix = "\(dictionaryID)::"
            preferences.collapsedDictionaryIDs.remove(dictionaryID)
            preferences.groupExpansion = preferences.groupExpansion.filter { !$0.key.hasPrefix(prefix) }
            preferences.groupDetailExpansion = preferences.groupDetailExpansion.filter { !$0.key.hasPrefix(prefix) }
        }
    }

    var hasPendingInputChanges: Bool {
        let current = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !lastSubmittedText.isEmpty && current != lastSubmittedText
    }

    var selectedResult: TranslationResult? {
        if let id = selectedResultID, let result = results.first(where: { $0.id == id }) {
            return result
        }
        return results.last
    }

    var currentAnalysis: InputAnalysis {
        InputAnalyzer.analyze(sourceText, mode: workspaceMode)
    }

    var primaryActionTitle: String {
        if workspaceMode == .expression { return "生成表达" }
        if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch workspaceMode {
            case .smart: return "查词或翻译"
            case .translation: return "翻译"
            case .dictionary: return "查询词典"
            case .expression: return "生成表达"
            }
        }
        return currentAnalysis.actionDescription
    }

    var detectedRouteSummary: String {
        let analysis = currentAnalysis
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return workspaceMode == .expression ? "输入场景，生成地道表达" : "自动识别中英文"
        }
        let languages = InputAnalyzer.resolveLanguages(
            sourceText, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage
        )
        let source = languageName(languages.source)
        let target = languageName(languages.target)
        switch (analysis.shouldLookupDictionary, analysis.shouldTranslate) {
        case (true, true): return "识别为\(source)词条 · 查词 + \(source) → \(target)"
        case (true, false): return "识别为\(source) · 查询已加载词典"
        case (false, true): return "识别为\(source) · \(source) → \(target)"
        default: return "等待输入"
        }
    }

    var inputPlaceholder: String {
        switch workspaceMode {
        case .smart: return "输入英文单词自动查词；输入句子直接翻译"
        case .translation: return "输入要翻译的句子、单词或短语，按 Return 执行"
        case .dictionary: return "输入要查询的单词或词组，按 Return 查词"
        case .expression: return "描述你要表达的场景，例如：礼貌催同事确认接口文档"
        }
    }

    func performPrimaryAction() async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = TranslationError.emptyInput.localizedDescription
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        let analysis = InputAnalyzer.analyze(text, mode: workspaceMode)
        updateResultDisplayPreferences {
            $0.resetForNewQuery(summarizeDictionaries: workspaceMode == .smart)
        }
        lastSubmittedText = text
        lastAnalysis = analysis
        errorMessage = nil
        dictionaryResults = []
        dictionaryPresentations = [:]
        englishMeaningIPAs = [:]
        resetPronunciation()
        dictionarySuggestions = []
        results = []
        expressionResults = []
        selectedResultID = nil

        if workspaceMode == .expression {
            await generateExpressionForScenario(text)
            return
        }

        if analysis.shouldLookupDictionary {
            dictionaryResults = dictionaryCatalog.lookup(text)
            dictionaryPresentations = await Self.parsePresentations(dictionaryResults)
            if analysis.detectedLanguage == "zh" { refreshEnglishMeaningIPAs() }
            if analysis.detectedLanguage == "en" { loadPronunciation(for: text) }
            if ResultFilterKey.dictionaryID(from: selectedResultFilterKey) != nil {
                normalizeResultFilter()
            }
            if dictionaryResults.isEmpty {
                dictionarySuggestions = dictionaryCatalog.suggestions(for: text, limit: 8)
            }
        }

        guard analysis.shouldTranslate else {
            isLoading = false
            if dictionaryResults.isEmpty && dictionarySuggestions.isEmpty {
                errorMessage = analysis.detectedLanguage == "en"
                    ? "已加载词典中没有找到“\(text)”"
                    : "当前已加载词典不支持这个词条或语言"
            }
            normalizeResultFilter()
            return
        }

        let languages = InputAnalyzer.resolveLanguages(
            text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage
        )
        let resolvedSource = languages.source
        let resolvedTarget = languages.target
        isLoading = true
        defer {
            if generation == requestGeneration { isLoading = false }
        }

        do {
            let result = try await makeRouter().translateDefault(
                TranslationRequest(
                    text: text,
                    sourceLanguage: resolvedSource,
                    targetLanguage: resolvedTarget,
                    context: contextText.nilIfBlank
                )
            )
            guard generation == requestGeneration else { return }
            results = [result]
            selectedResultID = result.id
            normalizeResultFilter()
        } catch {
            guard generation == requestGeneration else { return }
            if dictionaryResults.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "词典结果已显示；翻译服务失败：\(error.localizedDescription)"
            }
            normalizeResultFilter()
        }
    }

    func translateDefault() async {
        await performTranslation(replaceCurrentResults: results.isEmpty) { router, request in
            try await router.translateDefault(request)
        }
    }

    func translateAccurate() async {
        await performTranslation(replaceCurrentResults: results.isEmpty) { router, request in
            try await router.translateAccurate(request)
        }
    }

    func translate(using providerID: String) async {
        await performTranslation(replaceCurrentResults: results.isEmpty) { router, request in
            try await router.translate(request, using: providerID)
        }
    }

    func optimize(scene: ExpressionScene, tone: ExpressionTone = .normal, scope: EmailScope? = nil) async {
        guard let base = selectedResult else {
            errorMessage = "请先完成一次翻译"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let request = ExpressionRequest(
                sourceText: base.sourceText,
                currentTranslation: base.translatedText,
                sourceLanguage: base.sourceLanguage,
                targetLanguage: base.targetLanguage,
                scene: scene,
                tone: tone,
                emailScope: scope,
                context: contextText.nilIfBlank
            )
            let factory = ProviderFactory(httpClient: URLSessionHTTPClient(), secrets: keychain)
            let router = ExpressionRouter(configuration: configuration, factory: factory)
            let result = try await router.optimize(request, baseTranslationProviderName: base.providerName)
            if let index = expressionResults.firstIndex(where: {
                $0.scene == result.scene && $0.tone == result.tone && $0.providerID == result.providerID
            }) {
                expressionResults[index] = result
            } else {
                expressionResults.append(result)
            }
            selectResultFilter(ResultFilterKey.expression)
            normalizeResultFilter()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateExpressionForScenario(_ scenarioText: String) async {
        let trimmed = scenarioText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = TranslationError.emptyInput.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detectedLanguage = InputAnalyzer.detectLanguage(trimmed)
            let request = ExpressionRequest(
                sourceText: "用户输入的表达场景：\(trimmed)",
                currentTranslation: "请根据这个场景生成 3 到 5 条自然、可直接使用的英文表达，并给出适合发送的推荐版本。",
                sourceLanguage: detectedLanguage,
                targetLanguage: targetLanguage,
                scene: .daily,
                tone: .normal,
                emailScope: nil,
                context: contextText.nilIfBlank
            )
            let factory = ProviderFactory(httpClient: URLSessionHTTPClient(), secrets: keychain)
            let router = ExpressionRouter(configuration: configuration, factory: factory)
            let result = try await router.optimize(request, baseTranslationProviderName: "场景表达")
            expressionResults = [result]
            selectResultFilter(ResultFilterKey.expression)
            normalizeResultFilter()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearWorkspace() {
        requestGeneration += 1
        sourceText = ""
        lastSubmittedText = ""
        contextText = ""
        dictionaryResults = []
        dictionaryPresentations = [:]
        englishMeaningIPAs = [:]
        resetPronunciation()
        dictionarySuggestions = []
        results = []
        expressionResults = []
        selectedResultID = nil
        lastAnalysis = nil
        errorMessage = nil
        isLoading = false
        focusInput()
    }

    func swapLanguages() {
        let languages = InputAnalyzer.resolveLanguages(
            sourceText, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage
        )
        sourceLanguage = languages.target
        targetLanguage = languages.source == "auto" ? "zh" : languages.source
        if sourceText.trimmingCharacters(in: .whitespacesAndNewlines) == lastSubmittedText,
           let translation = selectedResult?.translatedText {
            sourceText = translation
        }
    }

    func focusInput() {
        inputFocusRequest += 1
    }

    func runExample(_ text: String) async {
        sourceText = text
        focusInput()
        await performPrimaryAction()
    }

    func useDictionarySuggestion(_ term: String) async {
        sourceText = term
        workspaceMode = .smart
        await performPrimaryAction()
    }

    @discardableResult
    func saveConfiguration() -> Bool {
        do {
            try configurationStore.save(configuration)
            providerConnectionStatuses = [:]
            refreshProviderRuntimeStatuses()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存配置失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveSecret(_ value: String, for provider: ProviderConfiguration) -> Bool {
        guard let reference = provider.secretReference else {
            errorMessage = "此服务不支持保存 API Key"
            return false
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "未输入新的 API Key，已保留原有配置"
            return false
        }
        do {
            try keychain.save(trimmed, for: reference)
            providerConnectionStatuses[provider.id] = .idle
            refreshProviderRuntimeStatuses()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存 API Key 失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearSecret(for provider: ProviderConfiguration) {
        guard let reference = provider.secretReference else { return }
        do {
            try keychain.save("", for: reference)
            providerConnectionStatuses[provider.id] = .idle
            refreshProviderRuntimeStatuses()
            errorMessage = nil
        } catch {
            errorMessage = "清除 API Key 失败：\(error.localizedDescription)"
        }
    }

    func hasSecret(for provider: ProviderConfiguration) -> Bool {
        providerRuntimeStatuses[provider.id]?.secretAvailable ?? false
    }

    func runtimeStatus(for provider: ProviderConfiguration) -> ProviderRuntimeStatus {
        if let status = providerRuntimeStatuses[provider.id] { return status }
        let issues = provider.runtimeConfigurationIssues(secretAvailable: false)
        return ProviderRuntimeStatus(isReady: issues.isEmpty, issues: issues)
    }

    func connectionStatus(for provider: ProviderConfiguration) -> ProviderConnectionStatus {
        providerConnectionStatuses[provider.id] ?? .idle
    }

    func isProviderEnabledAndReady(_ provider: ProviderConfiguration) -> Bool {
        provider.enabled && runtimeStatus(for: provider).isReady
    }

    func hasSecret(for providerID: String) -> Bool {
        guard let provider = configuration.providers.first(where: { $0.id == providerID }) else { return false }
        return hasSecret(for: provider)
    }

    func refreshProviderRuntimeStatuses() {
        let providers = configuration.providers
        providerStatusRevision += 1
        let revision = providerStatusRevision

        // UI receives an immediate nonblocking snapshot. Keychain can display
        // access prompts after ad-hoc app signing, so never query it on MainActor.
        providerRuntimeStatuses = Dictionary(uniqueKeysWithValues: providers.map { provider in
            let issues = provider.runtimeConfigurationIssues(secretAvailable: false)
            return (provider.id, ProviderRuntimeStatus(isReady: issues.isEmpty, issues: issues))
        })

        Task.detached(priority: .utility) { [weak self] in
            let statuses = Dictionary(uniqueKeysWithValues: providers.map { provider in
                let secretAvailable: Bool
                if let reference = provider.secretReference {
                    secretAvailable = KeychainSecretStore.shared.containsSecret(for: reference)
                } else {
                    secretAvailable = false
                }
                let issues = provider.runtimeConfigurationIssues(secretAvailable: secretAvailable)
                return (provider.id, ProviderRuntimeStatus(
                    isReady: issues.isEmpty,
                    issues: issues,
                    secretAvailable: secretAvailable
                ))
            })
            await MainActor.run { [weak self] in
                guard let self, self.providerStatusRevision == revision else { return }
                self.providerRuntimeStatuses = statuses
                self.providerConnectionStatuses = self.providerConnectionStatuses.filter { statuses[$0.key] != nil }
            }
        }
    }

    func testProviderConnection(_ provider: ProviderConfiguration) async {
        saveConfiguration()
        providerConnectionStatuses[provider.id] = .checking
        isLoading = true
        defer { isLoading = false }
        do {
            var configurationForCheck = provider
            configurationForCheck.enabled = true
            let factory = ProviderFactory(httpClient: URLSessionHTTPClient(), secrets: keychain)
            guard let translationProvider = factory.translationProvider(for: configurationForCheck) else {
                providerConnectionStatuses[provider.id] = .failure("当前服务不支持连接测试")
                return
            }
            let request = TranslationRequest(
                text: "Connection test",
                sourceLanguage: "en",
                targetLanguage: "zh",
                context: nil
            )
            let startedAt = Date()
            _ = try await translationProvider.translate(request)
            let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
            providerConnectionStatuses[provider.id] = .success("连接成功 · \(latency) ms")
        } catch {
            providerConnectionStatuses[provider.id] = .failure(error.localizedDescription)
        }
    }

    func addPreset() {
        let suffix = UUID().uuidString.lowercased().prefix(6)
        let id = "custom-\(suffix)"
        configuration.presets.append(
            TranslationPreset(
                id: id,
                displayName: "自定义预设",
                localFirst: true,
                fallbackEnabled: true,
                providerOrder: enabledTranslationProviders.map(\.id)
            )
        )
        configuration.defaultPresetID = id
        saveConfiguration()
    }

    func removePreset(id: String) {
        guard configuration.presets.count > 1 else { return }
        configuration.presets.removeAll { $0.id == id }
        if configuration.defaultPresetID == id {
            configuration.defaultPresetID = configuration.presets.first?.id ?? "local-first"
        }
        saveConfiguration()
    }

    func addOpenAICompatibleProvider() {
        let suffix = UUID().uuidString.lowercased().prefix(8)
        let id = "openai-compatible-\(suffix)"
        configuration.providers.append(
            ProviderConfiguration(
                id: id,
                displayName: "自定义 AI 服务",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1/chat/completions",
                enabled: false,
                credentialSource: .userConfigured,
                secretReference: "provider.\(id).apiKey",
                model: "",
                capabilities: [.contextualTranslation, .dailyExpression, .teamsExpression, .emailExpression, .explanation]
            )
        )
        saveConfiguration()
    }

    func addLibreTranslateProvider() {
        let suffix = UUID().uuidString.lowercased().prefix(8)
        let id = "libretranslate-\(suffix)"
        configuration.providers.append(
            ProviderConfiguration(
                id: id,
                displayName: "自建 LibreTranslate",
                kind: .libreTranslate,
                baseURL: "http://localhost:5000/translate",
                enabled: false,
                credentialSource: .userConfigured,
                secretReference: "provider.\(id).apiKey",
                capabilities: [.translation]
            )
        )
        saveConfiguration()
    }

    func removeProvider(id: String) {
        configuration.providers.removeAll { $0.id == id }
        for index in configuration.presets.indices {
            configuration.presets[index].providerOrder.removeAll { $0 == id }
        }
        if configuration.accurateProviderID == id { configuration.accurateProviderID = nil }
        if configuration.expressionRouting.dailyProviderID == id { configuration.expressionRouting.dailyProviderID = nil }
        if configuration.expressionRouting.teamsProviderID == id { configuration.expressionRouting.teamsProviderID = nil }
        if configuration.expressionRouting.emailProviderID == id { configuration.expressionRouting.emailProviderID = nil }
        saveConfiguration()
    }

    func speak(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        playbackTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking { speechSynthesizer.stopSpeaking() }

        guard Self.isSingleEnglishWord(value) else {
            speakUsingSystem(value)
            return
        }

        let accent = englishAccent
        let key = value.lowercased()
        let cachedFile = StoragePaths.pronunciationCache
            .appendingPathComponent(accent.rawValue, isDirectory: true)
            .appendingPathComponent("\(key).mp3")
        if FileManager.default.fileExists(atPath: cachedFile.path), playAudioFile(at: cachedFile) {
            setSpeechStatus("\(accent.title)词典录音")
            return
        }

        // If the dictionary endpoint is unavailable, speak immediately rather
        // than delaying every click for a new network request. Lookup already
        // fetches the audio metadata asynchronously.
        guard pronunciationWord == key,
              let remoteURL = wordPronunciation?.audioURL(for: accent) else {
            speakUsingSystem(value, preferredAccent: accent)
            return
        }
        setSpeechStatus("正在获取\(accent.title)发音…")
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let played = (try? await playDictionaryAudio(remoteURL, word: key, accent: accent)) ?? false
            guard !Task.isCancelled else { return }
            if played {
                setSpeechStatus("\(accent.title)词典录音")
            } else {
                speakUsingSystem(value, preferredAccent: accent)
            }
        }
    }

    /// Download a word recording only when it is first played, then reuse it offline.
    private func playDictionaryAudio(_ remoteURL: URL, word: String, accent: EnglishAccent) async throws -> Bool {
        let folder = StoragePaths.pronunciationCache
            .appendingPathComponent(accent.rawValue, isDirectory: true)
        let fileURL = folder.appendingPathComponent("\(word).mp3")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 7
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  !data.isEmpty, data.count < 5_000_000 else { return false }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        }
        guard !Task.isCancelled else { return false }
        return playAudioFile(at: fileURL)
    }

    private func playAudioFile(at url: URL) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            if player.play() {
                audioPlayer = player
                return true
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
        return false
    }

    private func setSpeechStatus(_ text: String) {
        speechFeedbackTask?.cancel()
        speechStatus = text
        speechFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.speechStatus = nil
        }
    }

    private func speakUsingSystem(_ text: String, preferredAccent: EnglishAccent? = nil) {
        let language: String
        switch InputAnalyzer.detectLanguage(text) {
        case "zh": language = "zh-CN"
        case "ja": language = "ja-JP"
        case "ko": language = "ko-KR"
        case "fr": language = "fr-FR"
        case "de": language = "de-DE"
        case "es": language = "es-ES"
        default: language = (preferredAccent ?? englishAccent).rawValue
        }
        let locale = language.replacingOccurrences(of: "-", with: "_").lowercased()
        let matching = NSSpeechSynthesizer.availableVoices.filter { voice in
            let value = NSSpeechSynthesizer.attributes(forVoice: voice)[.localeIdentifier] as? String ?? ""
            return value.replacingOccurrences(of: "-", with: "_").lowercased() == locale
        }
        let preferredNames: [String]
        switch locale {
        case "en_us": preferredNames = ["Samantha", "Alex"]
        case "en_gb": preferredNames = ["Daniel"]
        default: preferredNames = []
        }
        // The first macOS en_US voice is "Albert", a novelty voice. Select
        // a natural installed voice explicitly before any generic fallback.
        let voice = preferredNames.compactMap { name in
            matching.first { voice in
                let displayName = NSSpeechSynthesizer.attributes(forVoice: voice)[.name] as? String ?? ""
                return displayName == name || displayName.hasPrefix(name + " (")
            }
        }.first ?? matching.first {
            $0.rawValue.contains(".voice.compact.") || $0.rawValue.contains(".voice.premium.")
        } ?? matching.first {
            $0.rawValue.contains(".eloquence.")
        }
        guard let voice, speechSynthesizer.setVoice(voice) else {
            setSpeechStatus("没有可用的\(language)朗读声线，请在系统设置中安装语音")
            return
        }
        let started = speechSynthesizer.startSpeaking(text)
        setSpeechStatus(started
            ? (language.hasPrefix("en-")
                ? "\((preferredAccent ?? englishAccent).title)系统语音"
                : "系统语音朗读")
            : "系统朗读启动失败，请检查系统声音输出")
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyFeedbackTask?.cancel()
        copyFeedback = "已复制到剪贴板"
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            self?.copyFeedback = nil
        }
    }

    private func performTranslation(
        replaceCurrentResults: Bool,
        _ operation: (TranslationRouter, TranslationRequest) async throws -> TranslationResult
    ) async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = TranslationError.emptyInput.localizedDescription
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        let isNewQuery = text != lastSubmittedText
        let analysis = InputAnalyzer.analyze(text, mode: .translation)
        let languages = InputAnalyzer.resolveLanguages(
            text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage
        )
        let resolvedSource = languages.source
        let resolvedTarget = languages.target

        if isNewQuery {
            lastSubmittedText = text
            lastAnalysis = analysis
            dictionaryResults = []
            dictionaryPresentations = [:]
            dictionarySuggestions = []
            results = []
            expressionResults = []
            selectedResultID = nil
        }

        selectResultFilter(ResultFilterKey.translation)
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestGeneration { isLoading = false }
        }
        do {
            let request = TranslationRequest(
                text: text,
                sourceLanguage: resolvedSource,
                targetLanguage: resolvedTarget,
                context: contextText.nilIfBlank
            )
            let result = try await operation(makeRouter(), request)
            guard generation == requestGeneration else { return }
            if replaceCurrentResults || isNewQuery {
                results = [result]
            } else {
                upsertTranslationResult(result)
            }
            selectedResultID = result.id
            normalizeResultFilter()
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
            normalizeResultFilter()
        }
    }

    private func upsertTranslationResult(_ result: TranslationResult) {
        if let index = results.firstIndex(where: {
            $0.providerID == result.providerID
                && $0.modelName == result.modelName
                && $0.sourceText == result.sourceText
                && $0.targetLanguage == result.targetLanguage
        }) {
            results[index] = result
        } else {
            results.append(result)
        }
    }

    private static func parsePresentations(
        _ results: [DictionaryLookupResult]
    ) async -> [String: DictionaryPresentation] {
        await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: results.map { result in
                (result.id, DictionaryPresentationParser.parse(result))
            })
        }.value
    }

    private func updateResultDisplayPreferences(
        _ update: (inout ResultDisplayPreferences) -> Void
    ) {
        var preferences = resultDisplayPreferences
        update(&preferences)
        resultDisplayPreferences = preferences
        resultDisplayPreferenceStore.save(preferences)
    }

    private func groupPreferenceKey(_ dictionaryID: String, _ groupID: String) -> String {
        "\(dictionaryID)::\(groupID)"
    }

    private func normalizeResultFilter() {
        let key = selectedResultFilterKey
        if let dictionaryID = ResultFilterKey.dictionaryID(from: key) {
            if !dictionaryResults.contains(where: { $0.dictionaryID == dictionaryID }) {
                selectResultFilter(ResultFilterKey.all)
            }
            return
        }
        if key == ResultFilterKey.translation, results.isEmpty {
            selectResultFilter(ResultFilterKey.all)
        } else if key == ResultFilterKey.expression, expressionResults.isEmpty {
            selectResultFilter(ResultFilterKey.all)
        }
    }

    private func makeRouter() -> TranslationRouter {
        let factory = ProviderFactory(httpClient: URLSessionHTTPClient(), secrets: keychain)
        return TranslationRouter(configuration: configuration, factory: factory, localDictionary: localDictionary, cache: cache)
    }

    private func languageName(_ code: String) -> String {
        switch code.lowercased() {
        case "zh": return "中文"
        case "en": return "英文"
        case "ja": return "日文"
        case "ko": return "韩文"
        case "fr": return "法文"
        case "de": return "德文"
        case "es": return "西班牙文"
        case "auto": return "未知语言"
        default: return code.uppercased()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
#endif
