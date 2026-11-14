import Foundation

public protocol DictionarySource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var entryCount: Int? { get }
    var detail: String { get }
    func lookupEntry(_ term: String) -> DictionaryLookupResult?
    func suggestions(for prefix: String, limit: Int) -> [String]
}

public extension DictionarySource {
    var entryCount: Int? { nil }
    var detail: String { "本地词典" }
    func suggestions(for prefix: String, limit: Int) -> [String] { [] }
}

public final class DictionaryCatalog: @unchecked Sendable {
    public let sources: [any DictionarySource]

    public init(sources: [any DictionarySource]) {
        self.sources = sources
    }

    public var sourceInfos: [DictionarySourceInfo] {
        sources.map {
            DictionarySourceInfo(
                id: $0.id,
                displayName: $0.displayName,
                entryCount: $0.entryCount,
                detail: $0.detail
            )
        }
    }

    public func lookup(_ term: String) -> [DictionaryLookupResult] {
        sources.compactMap { $0.lookupEntry(term) }
    }

    public func suggestions(for prefix: String, limit: Int = 8) -> [String] {
        guard limit > 0 else { return [] }
        var output: [String] = []
        var seen = Set<String>()
        for source in sources {
            for value in source.suggestions(for: prefix, limit: limit) {
                let normalized = value.lowercased()
                if seen.insert(normalized).inserted {
                    output.append(value)
                    if output.count == limit { return output }
                }
            }
        }
        return output
    }
}

public final class LocalDictionary: @unchecked Sendable, DictionarySource {
    private let entries: [String: LocalDictionaryEntry]
    private let reverseEntries: [String: LocalDictionaryEntry]

    public init(entries: [LocalDictionaryEntry] = LocalDictionary.builtInEntries) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { (Self.normalize($0.term), $0) })
        self.reverseEntries = Self.makeReverseEntries(from: entries)
    }

    public let id = "built-in-basic"
    public let displayName = "内置基础词典"
    public let detail = "工作常用词 · 作为离线兜底"
    public var entryCount: Int? { entries.count + reverseEntries.count }

    public func lookup(_ request: TranslationRequest) -> TranslationResult? {
        let normalized = Self.normalize(request.text)
        guard Self.isSingleLookupTerm(normalized), let entry = entry(for: normalized) else { return nil }

        let translated: String?
        if request.targetLanguage.lowercased().hasPrefix("en"), !entry.englishDefinitions.isEmpty {
            translated = entry.englishDefinitions.first
        } else {
            translated = entry.translations[request.targetLanguage.lowercased()]
                ?? entry.translations[String(request.targetLanguage.lowercased().prefix(2))]
        }
        guard let translated else { return nil }

        return TranslationResult(
            sourceText: request.text,
            translatedText: translated,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: "local-dictionary",
            providerName: "内置基础词典",
            providerKind: .local,
            credentialSource: .local,
            detectedSourceLanguage: entry.language,
            fromCache: false,
            latencyMilliseconds: 0
        )
    }

    public func lookupEntry(_ term: String) -> DictionaryLookupResult? {
        let normalized = Self.normalize(term)
        guard Self.isSingleLookupTerm(normalized), let entry = entry(for: normalized) else { return nil }
        return DictionaryLookupResult(
            dictionaryID: id,
            dictionaryName: displayName,
            entry: entry
        )
    }

    public func lookupEntries(_ term: String) -> [DictionaryLookupResult] {
        lookupEntry(term).map { [$0] } ?? []
    }

    public func detail(for term: String) -> LocalDictionaryEntry? {
        entry(for: Self.normalize(term))
    }

    private func entry(for normalizedTerm: String) -> LocalDictionaryEntry? {
        entries[normalizedTerm] ?? reverseEntries[normalizedTerm]
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isSingleLookupTerm(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { $0.isWhitespace })
    }

    private static func makeReverseEntries(from entries: [LocalDictionaryEntry]) -> [String: LocalDictionaryEntry] {
        [:]
    }

    public func suggestions(for prefix: String, limit: Int) -> [String] {
        let normalized = Self.normalize(prefix)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        let matches = entries.keys
            .filter { $0.hasPrefix(normalized) }
            .sorted()
        return Array(matches.prefix(limit))
    }

    public static let builtInEntries: [LocalDictionaryEntry] = [
        LocalDictionaryEntry(
            term: "deploy",
            language: "en",
            translations: ["zh": "部署"],
            englishDefinitions: ["to make software or a service available for use"],
            examples: ["We plan to deploy the fix to SIT today."]
        ),
        LocalDictionaryEntry(
            term: "deployment",
            language: "en",
            translations: ["zh": "部署；发布"],
            englishDefinitions: ["the process of making software available in an environment"],
            examples: ["The deployment completed successfully."]
        ),
        LocalDictionaryEntry(
            term: "clarify",
            language: "en",
            translations: ["zh": "澄清；说明清楚"],
            englishDefinitions: ["to make a statement or situation easier to understand"],
            examples: ["Could you clarify whether batch queries are supported?"]
        ),
        LocalDictionaryEntry(
            term: "batch",
            language: "en",
            translations: ["zh": "批量；一批"],
            englishDefinitions: ["a group of items processed together"],
            examples: ["The API supports batch queries."]
        ),
        LocalDictionaryEntry(
            term: "inconsistent",
            language: "en",
            translations: ["zh": "不一致的；前后矛盾的"],
            englishDefinitions: ["not staying the same or not matching another thing"],
            examples: ["The response is inconsistent with the documentation."]
        ),
        LocalDictionaryEntry(
            term: "follow-up",
            language: "en",
            translations: ["zh": "跟进；后续事项"],
            englishDefinitions: ["an action taken to continue or check earlier work"],
            examples: ["This is a quick follow-up on the API issue."]
        ),
        LocalDictionaryEntry(
            term: "部署",
            language: "zh",
            translations: ["en": "deploy"],
            englishDefinitions: ["deploy"],
            examples: ["We plan to deploy the fix to SIT today."]
        ),
        LocalDictionaryEntry(
            term: "发布",
            language: "zh",
            translations: ["en": "deployment"],
            englishDefinitions: ["deployment"],
            examples: ["The deployment completed successfully."]
        ),
        LocalDictionaryEntry(
            term: "澄清",
            language: "zh",
            translations: ["en": "clarify"],
            englishDefinitions: ["clarify"],
            examples: ["Could you clarify whether batch queries are supported?"]
        ),
        LocalDictionaryEntry(
            term: "批量",
            language: "zh",
            translations: ["en": "batch"],
            englishDefinitions: ["batch"],
            examples: ["The API supports batch queries."]
        ),
        LocalDictionaryEntry(
            term: "不一致",
            language: "zh",
            translations: ["en": "inconsistent"],
            englishDefinitions: ["inconsistent"],
            examples: ["The response is inconsistent with the documentation."]
        ),
        LocalDictionaryEntry(
            term: "跟进",
            language: "zh",
            translations: ["en": "follow-up"],
            englishDefinitions: ["follow-up"],
            examples: ["This is a quick follow-up on the API issue."]
        )
    ]
}
