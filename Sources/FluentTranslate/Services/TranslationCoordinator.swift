import Foundation

final class TranslationCoordinator {
    private let ai = AITranslationClient()
    private let libre = LibreTranslateClient()
    private let deepL = DeepLTranslateClient()
    private let myMemory = MyMemoryTranslateClient()
    private let dictionary = LocalDictionaryService.shared
    private let cache = ResponseCacheStore.shared

    func localResult(text: String, settings: SettingsStore) -> TranslationOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, settings.offlineDictionaryEnabled,
              let entry = dictionary.lookup(trimmed) else { return nil }
        return .localInitial(sourceText: trimmed, entry: entry)
    }

    func shouldSkipRemoteTranslation(text: String, localEntry: DictionaryEntry?) -> Bool {
        guard let localEntry, let chinese = localEntry.chineseDefinition, !chinese.isEmpty else { return false }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = normalized.split(whereSeparator: { $0.isWhitespace }).count
        return normalized.count <= 48 && wordCount <= 5 && !normalized.contains("\n")
    }

    func translateBase(text: String, localEntry: DictionaryEntry?, settings: SettingsStore) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        if shouldSkipRemoteTranslation(text: trimmed, localEntry: localEntry), let localEntry {
            return .localInitial(sourceText: trimmed, entry: localEntry)
        }

        let cacheKey = cache.key("base-v1", trimmed.lowercased(), settings.sourceLanguage, settings.targetLanguage, settings.translationProvider.rawValue)
        if let cached = cache.value(for: cacheKey) { return cached }

        let result: TranslationOutput
        switch settings.translationProvider {
        case .openAICompatible:
            result = try await ai.translate(text: trimmed, baseTranslation: nil, offlineEntry: localEntry, settings: settings, mode: .queryAndExpression)
        case .libreTranslate:
            let base = try await libre.translate(text: trimmed, settings: settings)
            result = .baseOnly(sourceLanguage: base.detectedLanguage, translation: base.translatedText, offlineEntry: localEntry)
        case .deepL:
            let base = try await deepL.translate(text: trimmed, settings: settings)
            result = .baseOnly(sourceLanguage: base.detectedLanguage, translation: base.translatedText, offlineEntry: localEntry)
        case .myMemory:
            let base = try await myMemory.translate(text: trimmed, settings: settings)
            result = .baseOnly(sourceLanguage: base.detectedLanguage, translation: base.translatedText, offlineEntry: localEntry)
        }
        cache.save(result, for: cacheKey, days: 90)
        return result
    }

    func runAI(text: String, current: TranslationOutput?, mode: AITaskMode, settings: SettingsStore) async throws -> TranslationOutput {
        let cacheKey = cache.key("ai-v1", text.lowercased(), mode.rawValue, settings.expressionStyle.rawValue, settings.englishVariant.rawValue, settings.aiEndpoint, settings.aiModel)
        if let cached = cache.value(for: cacheKey) { return merge(base: current, ai: cached, mode: mode) }
        let aiResult = try await ai.translate(
            text: text,
            baseTranslation: current?.accurateTranslation,
            offlineEntry: current?.offlineEntry,
            settings: settings,
            mode: mode
        )
        cache.save(aiResult, for: cacheKey, days: 30)
        return merge(base: current, ai: aiResult, mode: mode)
    }

    private func merge(base: TranslationOutput?, ai: TranslationOutput, mode: AITaskMode) -> TranslationOutput {
        guard var result = base else { return ai }
        if result.accurateTranslation.isEmpty { result.accurateTranslation = ai.accurateTranslation }
        result.detectedLanguage = ai.detectedLanguage.isEmpty ? result.detectedLanguage : ai.detectedLanguage
        if mode == .query || mode == .queryAndExpression {
            result.queryExplanation = ai.queryExplanation
            result.terms = ai.terms
        }
        if mode == .expression || mode == .queryAndExpression {
            result.recommendedExpression = ai.recommendedExpression
            result.politeAlternative = ai.politeAlternative
            result.conciseAlternative = ai.conciseAlternative
            result.formalAlternative = ai.formalAlternative
            result.explanation = ai.explanation
        }
        result.offlineEntry = base?.offlineEntry ?? ai.offlineEntry
        return result
    }
}
