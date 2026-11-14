import Foundation


public enum WorkspaceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case smart
    case translation
    case dictionary
    case expression

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smart: return "智能识别"
        case .translation: return "翻译句子"
        case .dictionary: return "查询单词/词组"
        case .expression: return "优化表达"
        }
    }
}

public enum InputKind: String, Codable, Sendable {
    case word
    case phrase
    case sentence
    case unknown
}

public struct InputAnalysis: Hashable, Sendable {
    public var detectedLanguage: String
    public var targetLanguage: String
    public var kind: InputKind
    public var shouldLookupDictionary: Bool
    public var shouldTranslate: Bool

    public init(
        detectedLanguage: String,
        targetLanguage: String,
        kind: InputKind,
        shouldLookupDictionary: Bool,
        shouldTranslate: Bool
    ) {
        self.detectedLanguage = detectedLanguage
        self.targetLanguage = targetLanguage
        self.kind = kind
        self.shouldLookupDictionary = shouldLookupDictionary
        self.shouldTranslate = shouldTranslate
    }

    public var actionDescription: String {
        switch (shouldLookupDictionary, shouldTranslate) {
        case (true, true): return "查词并翻译"
        case (true, false): return "查询词典"
        case (false, true): return "翻译"
        default: return "优化表达"
        }
    }
}

public enum InputAnalyzer {
    public static func analyze(_ text: String, mode: WorkspaceMode = .translation) -> InputAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = detectLanguage(trimmed)
        let kind = detectKind(trimmed, language: language)
        let target = language == "zh" ? "en" : "zh"
        // A lexical query may be a single word or a multi-word expression.
        // The dictionary performs an exact lookup, so a phrase with no entry
        // simply yields a translation rather than fabricated dictionary content.
        let isDictionaryTerm = (language == "en" || language == "zh")
            && (kind == .word || kind == .phrase)

        switch mode {
        case .smart:
            return InputAnalysis(
                detectedLanguage: language,
                targetLanguage: target,
                kind: kind,
                shouldLookupDictionary: !trimmed.isEmpty && isDictionaryTerm,
                shouldTranslate: !trimmed.isEmpty
            )
        case .translation:
            return InputAnalysis(
                detectedLanguage: language,
                targetLanguage: target,
                kind: kind,
                shouldLookupDictionary: false,
                shouldTranslate: !trimmed.isEmpty
            )
        case .dictionary:
            return InputAnalysis(
                detectedLanguage: language,
                targetLanguage: target,
                kind: kind,
                shouldLookupDictionary: !trimmed.isEmpty,
                shouldTranslate: false
            )
        case .expression:
            return InputAnalysis(
                detectedLanguage: language,
                targetLanguage: target,
                kind: kind,
                shouldLookupDictionary: false,
                shouldTranslate: false
            )
        }
    }

    /// Language selection remains separate from detection, so a previous query
    /// cannot silently turn automatic direction into a manual override.
    public static func resolveLanguages(
        _ text: String,
        sourceLanguage: String = "auto",
        targetLanguage: String = "auto"
    ) -> (source: String, target: String) {
        let source = sourceLanguage == "auto" ? detectLanguage(text) : sourceLanguage
        let target = targetLanguage == "auto" ? (source == "zh" ? "en" : "zh") : targetLanguage
        return (source, target)
    }

    public static func detectLanguage(_ text: String) -> String {
        var hanCount = 0
        var latinCount = 0
        var japaneseCount = 0
        var koreanCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF:
                japaneseCount += 1
            case 0xAC00...0xD7AF:
                koreanCount += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF:
                hanCount += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            default:
                continue
            }
        }

        if japaneseCount > 0 { return "ja" }
        if koreanCount > 0 { return "ko" }
        // Chinese work messages often contain long API names, environment codes,
        // and English identifiers. Any Han character is therefore a stronger
        // signal than the raw Latin character count.
        if hanCount > 0 { return "zh" }
        if latinCount > 0 { return "en" }
        return "auto"
    }

    public static func detectKind(_ text: String, language: String? = nil) -> InputKind {
        guard !text.isEmpty else { return .unknown }
        let resolvedLanguage = language ?? detectLanguage(text)
        let terminalPunctuation = CharacterSet(charactersIn: ".!?。！？")

        if text.unicodeScalars.contains(where: terminalPunctuation.contains) || text.contains("\n") {
            return .sentence
        }

        if resolvedLanguage == "en" {
            let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-'’"))
            let isSingleWord = !text.contains(where: { $0.isWhitespace })
                && text.unicodeScalars.allSatisfy { allowed.contains($0) }
            if isSingleWord { return .word }

            let words = text.split(whereSeparator: { $0.isWhitespace })
            return words.count >= 8 ? .sentence : .phrase
        }

        if resolvedLanguage == "zh" {
            let meaningfulCount = text.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
            }.count
            if meaningfulCount <= 4 { return .word }
            return meaningfulCount >= 18 ? .sentence : .phrase
        }

        return text.contains(where: { $0.isWhitespace }) ? .phrase : .word
    }
}

public struct DictionaryLookupResult: Identifiable, Hashable, Sendable {
    public var id: String { "\(dictionaryID):\(entry.term.lowercased())" }
    public var dictionaryID: String
    public var dictionaryName: String
    public var entry: LocalDictionaryEntry
    public var latencyMilliseconds: Int

    public init(
        dictionaryID: String,
        dictionaryName: String,
        entry: LocalDictionaryEntry,
        latencyMilliseconds: Int = 0
    ) {
        self.dictionaryID = dictionaryID
        self.dictionaryName = dictionaryName
        self.entry = entry
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case local
    case appleSystem
    case myMemory
    case deepL
    case libreTranslate
    case openAICompatible
}

public enum ProviderCapability: String, Codable, CaseIterable, Sendable {
    case dictionary
    case translation
    case contextualTranslation
    case dailyExpression
    case teamsExpression
    case emailExpression
    case explanation
}

public enum CredentialSource: String, Codable, CaseIterable, Sendable {
    case local
    case builtIn
    case userConfigured

    public var displayName: String {
        switch self {
        case .local: return "本地"
        case .builtIn: return "应用内置"
        case .userConfigured: return "用户配置"
        }
    }
}

public struct ProviderConfiguration: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: ProviderKind
    public var baseURL: String
    public var enabled: Bool
    public var credentialSource: CredentialSource
    public var secretReference: String?
    public var model: String?
    public var capabilities: Set<ProviderCapability>
    public var timeoutSeconds: Double
    public var customHeaders: [String: String]
    public var options: [String: String]

    public init(
        id: String,
        displayName: String,
        kind: ProviderKind,
        baseURL: String,
        enabled: Bool,
        credentialSource: CredentialSource,
        secretReference: String? = nil,
        model: String? = nil,
        capabilities: Set<ProviderCapability>,
        timeoutSeconds: Double = 15,
        customHeaders: [String: String] = [:],
        options: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.enabled = enabled
        self.credentialSource = credentialSource
        self.secretReference = secretReference
        self.model = model
        self.capabilities = capabilities
        self.timeoutSeconds = timeoutSeconds
        self.customHeaders = customHeaders
        self.options = options
    }
}

public enum DeepLAccountType: String, Codable, CaseIterable, Sendable {
    case free
    case pro

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
}

public extension ProviderConfiguration {
    static let deepLFreeTranslateURL = "https://api-free.deepl.com/v2/translate"
    static let deepLProTranslateURL = "https://api.deepl.com/v2/translate"

    static func deepLTranslateURL(for accountType: DeepLAccountType) -> String {
        switch accountType {
        case .free: return deepLFreeTranslateURL
        case .pro: return deepLProTranslateURL
        }
    }

    var deepLAccountType: DeepLAccountType {
        if let configured = options["accountType"], let value = DeepLAccountType(rawValue: configured) {
            return value
        }
        return baseURL.contains("api-free.deepl.com") ? .free : .pro
    }

    mutating func setDeepLAccountType(_ accountType: DeepLAccountType) {
        options["accountType"] = accountType.rawValue
        baseURL = Self.deepLTranslateURL(for: accountType)
    }

    var requiresSecretForTranslation: Bool {
        switch kind {
        case .deepL, .openAICompatible:
            return true
        case .local, .appleSystem, .myMemory, .libreTranslate:
            return false
        }
    }

    var requiresModelName: Bool {
        kind == .openAICompatible
    }

    var supportsConnectionCheck: Bool {
        kind != .local && kind != .appleSystem
    }

    func runtimeConfigurationIssues(secretAvailable: Bool) -> [String] {
        var issues: [String] = []

        if kind != .local && kind != .appleSystem && URL(string: baseURL) == nil {
            issues.append("服务地址无效")
        }

        if requiresSecretForTranslation && !secretAvailable {
            issues.append("缺少 API Key")
        }

        if requiresModelName && (model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) {
            issues.append("缺少模型名称")
        }

        return issues
    }
}

public struct TranslationPreset: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var localFirst: Bool
    public var fallbackEnabled: Bool
    public var providerOrder: [String]

    public init(
        id: String,
        displayName: String,
        localFirst: Bool,
        fallbackEnabled: Bool,
        providerOrder: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.localFirst = localFirst
        self.fallbackEnabled = fallbackEnabled
        self.providerOrder = providerOrder
    }
}

public enum ExpressionScene: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case teams
    case email

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: return "地道表达"
        case .teams: return "Teams 快速消息"
        case .email: return "工作邮件"
        }
    }

    public var requiredCapability: ProviderCapability {
        switch self {
        case .daily: return .dailyExpression
        case .teams: return .teamsExpression
        case .email: return .emailExpression
        }
    }
}

public enum ExpressionTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case concise
    case polite
    case formal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "自然"
        case .concise: return "更简短"
        case .polite: return "更委婉"
        case .formal: return "更正式"
        }
    }
}

public enum EmailScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case body
    case fullEmail

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .body: return "只优化正文"
        case .fullEmail: return "生成完整邮件"
        }
    }
}

public enum AIRoutingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixedDefault
    case defaultWithFallback
    case manual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fixedDefault: return "只用默认服务"
        case .defaultWithFallback: return "默认失败后自动切换"
        case .manual: return "每次手动选择"
        }
    }
}

public enum ExpressionRouteUseCase: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case teams
    case email
    case scenario
    case optimizeTranslation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: return "地道表达"
        case .teams: return "Teams 快速消息"
        case .email: return "邮件表达"
        case .scenario: return "按场景生成"
        case .optimizeTranslation: return "优化当前翻译"
        }
    }
}

public struct AIServiceRoute: Codable, Hashable, Sendable {
    public var mode: AIRoutingMode
    public var defaultProviderID: String?
    public var fallbackProviderIDs: [String]

    public init(
        mode: AIRoutingMode = .defaultWithFallback,
        defaultProviderID: String?,
        fallbackProviderIDs: [String] = []
    ) {
        self.mode = mode
        self.defaultProviderID = defaultProviderID
        self.fallbackProviderIDs = fallbackProviderIDs
    }

    public var orderedProviderIDs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        if let defaultProviderID, seen.insert(defaultProviderID).inserted {
            ordered.append(defaultProviderID)
        }
        for providerID in fallbackProviderIDs where seen.insert(providerID).inserted {
            ordered.append(providerID)
        }
        return ordered
    }
}

public struct ExpressionRouting: Codable, Hashable, Sendable {
    public var daily: AIServiceRoute
    public var teams: AIServiceRoute
    public var email: AIServiceRoute
    public var scenario: AIServiceRoute
    public var optimizeTranslation: AIServiceRoute

    public var dailyProviderID: String? {
        get { daily.defaultProviderID }
        set { daily.defaultProviderID = newValue }
    }

    public var teamsProviderID: String? {
        get { teams.defaultProviderID }
        set { teams.defaultProviderID = newValue }
    }

    public var emailProviderID: String? {
        get { email.defaultProviderID }
        set { email.defaultProviderID = newValue }
    }

    public init(dailyProviderID: String?, teamsProviderID: String?, emailProviderID: String?) {
        self.daily = AIServiceRoute(defaultProviderID: dailyProviderID)
        self.teams = AIServiceRoute(defaultProviderID: teamsProviderID)
        self.email = AIServiceRoute(defaultProviderID: emailProviderID)
        self.scenario = AIServiceRoute(defaultProviderID: dailyProviderID)
        self.optimizeTranslation = AIServiceRoute(defaultProviderID: dailyProviderID)
    }

    public init(
        daily: AIServiceRoute,
        teams: AIServiceRoute,
        email: AIServiceRoute,
        scenario: AIServiceRoute,
        optimizeTranslation: AIServiceRoute
    ) {
        self.daily = daily
        self.teams = teams
        self.email = email
        self.scenario = scenario
        self.optimizeTranslation = optimizeTranslation
    }

    public func providerID(for scene: ExpressionScene) -> String? {
        route(for: scene).defaultProviderID
    }

    public func route(for scene: ExpressionScene) -> AIServiceRoute {
        switch scene {
        case .daily: return daily
        case .teams: return teams
        case .email: return email
        }
    }

    public func route(for useCase: ExpressionRouteUseCase) -> AIServiceRoute {
        switch useCase {
        case .daily: return daily
        case .teams: return teams
        case .email: return email
        case .scenario: return scenario
        case .optimizeTranslation: return optimizeTranslation
        }
    }

    private enum CodingKeys: String, CodingKey {
        case dailyProviderID
        case teamsProviderID
        case emailProviderID
        case daily
        case teams
        case email
        case scenario
        case optimizeTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyDaily = try container.decodeIfPresent(String.self, forKey: .dailyProviderID)
        let legacyTeams = try container.decodeIfPresent(String.self, forKey: .teamsProviderID)
        let legacyEmail = try container.decodeIfPresent(String.self, forKey: .emailProviderID)

        daily = try container.decodeIfPresent(AIServiceRoute.self, forKey: .daily)
            ?? AIServiceRoute(defaultProviderID: legacyDaily)
        teams = try container.decodeIfPresent(AIServiceRoute.self, forKey: .teams)
            ?? AIServiceRoute(defaultProviderID: legacyTeams)
        email = try container.decodeIfPresent(AIServiceRoute.self, forKey: .email)
            ?? AIServiceRoute(defaultProviderID: legacyEmail)
        scenario = try container.decodeIfPresent(AIServiceRoute.self, forKey: .scenario)
            ?? AIServiceRoute(defaultProviderID: legacyDaily)
        optimizeTranslation = try container.decodeIfPresent(AIServiceRoute.self, forKey: .optimizeTranslation)
            ?? AIServiceRoute(defaultProviderID: legacyDaily)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(daily, forKey: .daily)
        try container.encode(teams, forKey: .teams)
        try container.encode(email, forKey: .email)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(optimizeTranslation, forKey: .optimizeTranslation)
    }
}

public struct AppConfiguration: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var defaultPresetID: String
    public var accurateProviderID: String?
    public var cacheEnabled: Bool
    public var presets: [TranslationPreset]
    public var expressionRouting: ExpressionRouting
    public var providers: [ProviderConfiguration]

    public init(
        schemaVersion: Int = 1,
        defaultPresetID: String,
        accurateProviderID: String?,
        cacheEnabled: Bool = true,
        presets: [TranslationPreset],
        expressionRouting: ExpressionRouting,
        providers: [ProviderConfiguration]
    ) {
        self.schemaVersion = schemaVersion
        self.defaultPresetID = defaultPresetID
        self.accurateProviderID = accurateProviderID
        self.cacheEnabled = cacheEnabled
        self.presets = presets
        self.expressionRouting = expressionRouting
        self.providers = providers
    }
}

public struct TranslationRequest: Hashable, Sendable {
    public var text: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var context: String?

    public init(text: String, sourceLanguage: String, targetLanguage: String, context: String? = nil) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.context = context
    }
}

public struct TranslationResult: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceText: String
    public var translatedText: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var requestedProviderID: String?
    public var requestedProviderName: String?
    public var providerID: String
    public var providerName: String
    public var providerKind: ProviderKind
    public var credentialSource: CredentialSource
    public var modelName: String?
    public var detectedSourceLanguage: String?
    public var fallbackOccurred: Bool
    public var fallbackReason: String?
    public var fromCache: Bool
    public var latencyMilliseconds: Int?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        requestedProviderID: String? = nil,
        requestedProviderName: String? = nil,
        providerID: String,
        providerName: String,
        providerKind: ProviderKind,
        credentialSource: CredentialSource,
        modelName: String? = nil,
        detectedSourceLanguage: String? = nil,
        fallbackOccurred: Bool = false,
        fallbackReason: String? = nil,
        fromCache: Bool = false,
        latencyMilliseconds: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.requestedProviderID = requestedProviderID
        self.requestedProviderName = requestedProviderName
        self.providerID = providerID
        self.providerName = providerName
        self.providerKind = providerKind
        self.credentialSource = credentialSource
        self.modelName = modelName
        self.detectedSourceLanguage = detectedSourceLanguage
        self.fallbackOccurred = fallbackOccurred
        self.fallbackReason = fallbackReason
        self.fromCache = fromCache
        self.latencyMilliseconds = latencyMilliseconds
        self.createdAt = createdAt
    }
}

public struct ExpressionRequest: Hashable, Sendable {
    public var sourceText: String
    public var currentTranslation: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var scene: ExpressionScene
    public var tone: ExpressionTone
    public var emailScope: EmailScope?
    public var context: String?

    public init(
        sourceText: String,
        currentTranslation: String,
        sourceLanguage: String,
        targetLanguage: String,
        scene: ExpressionScene,
        tone: ExpressionTone = .normal,
        emailScope: EmailScope? = nil,
        context: String? = nil
    ) {
        self.sourceText = sourceText
        self.currentTranslation = currentTranslation
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.scene = scene
        self.tone = tone
        self.emailScope = emailScope
        self.context = context
    }
}

public struct ExpressionResult: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var primaryText: String
    public var alternatives: [String]
    public var scene: ExpressionScene
    public var tone: ExpressionTone
    public var providerID: String
    public var providerName: String
    public var credentialSource: CredentialSource
    public var modelName: String?
    public var baseTranslationProviderName: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        primaryText: String,
        alternatives: [String] = [],
        scene: ExpressionScene,
        tone: ExpressionTone,
        providerID: String,
        providerName: String,
        credentialSource: CredentialSource,
        modelName: String?,
        baseTranslationProviderName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.primaryText = primaryText
        self.alternatives = alternatives
        self.scene = scene
        self.tone = tone
        self.providerID = providerID
        self.providerName = providerName
        self.credentialSource = credentialSource
        self.modelName = modelName
        self.baseTranslationProviderName = baseTranslationProviderName
        self.createdAt = createdAt
    }
}

public struct LocalDictionaryEntry: Codable, Hashable, Sendable {
    public var term: String
    public var language: String
    public var translations: [String: String]
    public var englishDefinitions: [String]
    public var examples: [String]
    /// Preformatted local dictionary text for large imported dictionaries.
    /// Structured built-in entries leave this nil and use the fields above.
    public var bodyText: String?

    public init(
        term: String,
        language: String,
        translations: [String: String],
        englishDefinitions: [String],
        examples: [String],
        bodyText: String? = nil
    ) {
        self.term = term
        self.language = language
        self.translations = translations
        self.englishDefinitions = englishDefinitions
        self.examples = examples
        self.bodyText = bodyText
    }
}

public enum TranslationError: LocalizedError, Equatable {
    case invalidURL(String)
    case providerDisabled(String)
    case providerNotFound(String)
    case unsupportedCapability(String)
    case missingCredential(String)
    case invalidResponse(String)
    case remoteError(statusCode: Int, message: String)
    case noProviderAvailable
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "服务地址无效：\(value)"
        case .providerDisabled(let name): return "服务 \(name) 未启用"
        case .providerNotFound(let id): return "找不到服务：\(id)"
        case .unsupportedCapability(let name): return "服务 \(name) 不支持当前操作"
        case .missingCredential(let name): return "服务 \(name) 尚未配置 API Key"
        case .invalidResponse(let message): return "服务响应无法解析：\(message)"
        case .remoteError(let code, let message): return "服务请求失败（\(code)）：\(message)"
        case .noProviderAvailable: return "没有可用服务，请先在设置中启用并配置服务商"
        case .emptyInput: return "请输入需要翻译的内容"
        }
    }
}
