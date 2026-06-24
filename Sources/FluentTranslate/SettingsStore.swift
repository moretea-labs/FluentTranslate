import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let aiEndpoint = "settings.aiEndpoint"
        static let aiModel = "settings.aiModel"
        static let aiAPIFormat = "settings.aiAPIFormat"
        static let backend = "settings.backend"
        static let translationProvider = "settings.translationProvider"
        static let aiQueryEnabled = "settings.aiQueryEnabled"
        static let deepLEndpoint = "settings.deepLEndpoint"
        static let myMemoryEmail = "settings.myMemoryEmail"
        static let libreEndpoint = "settings.libreEndpoint"
        static let libreAPIKey = "settings.libreAPIKey"
        static let sourceLanguage = "settings.sourceLanguage"
        static let targetLanguage = "settings.targetLanguage"
        static let expressionStyle = "settings.expressionStyle"
        static let expressionEnabled = "settings.expressionEnabled"
        static let offlineDictionaryEnabled = "settings.offlineDictionaryEnabled"
        static let englishVariant = "settings.englishVariant"
        static let autoCapture = "settings.autoCapture"
        static let closeAfterReplace = "settings.closeAfterReplace"
        static let usagePreset = "settings.usagePreset"
        static let manualAIOnly = "settings.manualAIOnly"
    }

    @Published var aiEndpoint: String { didSet { defaults.set(aiEndpoint, forKey: Keys.aiEndpoint) } }
    @Published var aiModel: String { didSet { defaults.set(aiModel, forKey: Keys.aiModel) } }
    @Published var aiAPIFormat: AIAPIFormat { didSet { defaults.set(aiAPIFormat.rawValue, forKey: Keys.aiAPIFormat) } }
    @Published var backend: TranslationBackend { didSet { defaults.set(backend.rawValue, forKey: Keys.backend) } }
    @Published var translationProvider: TranslationProvider { didSet { defaults.set(translationProvider.rawValue, forKey: Keys.translationProvider) } }
    @Published var aiQueryEnabled: Bool { didSet { defaults.set(aiQueryEnabled, forKey: Keys.aiQueryEnabled) } }
    @Published var deepLEndpoint: String { didSet { defaults.set(deepLEndpoint, forKey: Keys.deepLEndpoint) } }
    @Published var myMemoryEmail: String { didSet { defaults.set(myMemoryEmail, forKey: Keys.myMemoryEmail) } }
    @Published var libreEndpoint: String { didSet { defaults.set(libreEndpoint, forKey: Keys.libreEndpoint) } }
    @Published var libreAPIKey: String { didSet { defaults.set(libreAPIKey, forKey: Keys.libreAPIKey) } }
    @Published var sourceLanguage: String { didSet { defaults.set(sourceLanguage, forKey: Keys.sourceLanguage) } }
    @Published var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) } }
    @Published var expressionStyle: ExpressionStyle { didSet { defaults.set(expressionStyle.rawValue, forKey: Keys.expressionStyle) } }
    @Published var expressionEnabled: Bool { didSet { defaults.set(expressionEnabled, forKey: Keys.expressionEnabled) } }
    @Published var offlineDictionaryEnabled: Bool { didSet { defaults.set(offlineDictionaryEnabled, forKey: Keys.offlineDictionaryEnabled) } }
    @Published var englishVariant: EnglishVariant { didSet { defaults.set(englishVariant.rawValue, forKey: Keys.englishVariant) } }
    @Published var autoCapture: Bool { didSet { defaults.set(autoCapture, forKey: Keys.autoCapture) } }
    @Published var closeAfterReplace: Bool { didSet { defaults.set(closeAfterReplace, forKey: Keys.closeAfterReplace) } }
    @Published var usagePreset: UsagePreset { didSet { defaults.set(usagePreset.rawValue, forKey: Keys.usagePreset) } }
    @Published var manualAIOnly: Bool { didSet { defaults.set(manualAIOnly, forKey: Keys.manualAIOnly) } }

    var aiAPIKey: String {
        get { KeychainStore.read(service: "FluentTranslate", account: "AI_API_KEY") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(service: "FluentTranslate", account: "AI_API_KEY")
            } else {
                KeychainStore.save(newValue, service: "FluentTranslate", account: "AI_API_KEY")
            }
            objectWillChange.send()
        }
    }


    var deepLAPIKey: String {
        get { KeychainStore.read(service: "FluentTranslate", account: "DEEPL_API_KEY") ?? "" }
        set {
            if newValue.isEmpty { KeychainStore.delete(service: "FluentTranslate", account: "DEEPL_API_KEY") }
            else { KeychainStore.save(newValue, service: "FluentTranslate", account: "DEEPL_API_KEY") }
            objectWillChange.send()
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        aiEndpoint = defaults.string(forKey: Keys.aiEndpoint) ?? "https://api.openai.com/v1/chat/completions"
        aiModel = defaults.string(forKey: Keys.aiModel) ?? ""
        aiAPIFormat = AIAPIFormat(rawValue: defaults.string(forKey: Keys.aiAPIFormat) ?? "") ?? .openAIChatCompletions

        // Migrate v4's old raw value without breaking existing users.
        let backendRaw = defaults.string(forKey: Keys.backend) ?? ""
        switch backendRaw {
        case "仅兼容 AI API":
            backend = .openAICompatible
        case "LibreTranslate + AI":
            backend = .libreThenAI
        default:
            backend = TranslationBackend(rawValue: backendRaw) ?? .openAICompatible
        }

        translationProvider = TranslationProvider(rawValue: defaults.string(forKey: Keys.translationProvider) ?? "") ?? .myMemory
        aiQueryEnabled = defaults.object(forKey: Keys.aiQueryEnabled) as? Bool ?? true
        deepLEndpoint = defaults.string(forKey: Keys.deepLEndpoint) ?? "https://api-free.deepl.com/v2/translate"
        myMemoryEmail = defaults.string(forKey: Keys.myMemoryEmail) ?? ""

        libreEndpoint = defaults.string(forKey: Keys.libreEndpoint) ?? "http://127.0.0.1:5000/translate"
        libreAPIKey = defaults.string(forKey: Keys.libreAPIKey) ?? ""
        sourceLanguage = defaults.string(forKey: Keys.sourceLanguage) ?? "auto"
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        expressionStyle = ExpressionStyle(rawValue: defaults.string(forKey: Keys.expressionStyle) ?? "") ?? .workplace
        expressionEnabled = defaults.object(forKey: Keys.expressionEnabled) as? Bool ?? true
        offlineDictionaryEnabled = defaults.object(forKey: Keys.offlineDictionaryEnabled) as? Bool ?? true
        englishVariant = EnglishVariant(rawValue: defaults.string(forKey: Keys.englishVariant) ?? "") ?? .american
        autoCapture = defaults.object(forKey: Keys.autoCapture) as? Bool ?? true
        closeAfterReplace = defaults.object(forKey: Keys.closeAfterReplace) as? Bool ?? true
        usagePreset = UsagePreset(rawValue: defaults.string(forKey: Keys.usagePreset) ?? "") ?? .localFirst
        manualAIOnly = defaults.object(forKey: Keys.manualAIOnly) as? Bool ?? true
    }

    func applyPreset(_ preset: UsagePreset) {
        usagePreset = preset
        switch preset {
        case .localFirst:
            translationProvider = .myMemory; manualAIOnly = true; offlineDictionaryEnabled = true
        case .freeFast:
            translationProvider = .myMemory; manualAIOnly = true; offlineDictionaryEnabled = true
        case .quality:
            translationProvider = .deepL; manualAIOnly = true; offlineDictionaryEnabled = true
        case .privateLocal:
            translationProvider = .libreTranslate; libreEndpoint = "http://127.0.0.1:5000/translate"; manualAIOnly = true; offlineDictionaryEnabled = true
        case .custom:
            break
        }
    }
}
