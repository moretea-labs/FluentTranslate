import Foundation

enum ExpressionStyle: String, CaseIterable, Codable, Identifiable {
    case workplace = "外企沟通"
    case polite = "更礼貌"
    case concise = "简洁直接"
    case daily = "日常自然"
    case formal = "正式邮件"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .workplace:
            return "natural, concise communication suitable for an international workplace"
        case .polite:
            return "polite, considerate and tactful communication"
        case .concise:
            return "clear, direct and concise communication without sounding rude"
        case .daily:
            return "natural everyday spoken communication"
        case .formal:
            return "professional and formal business email communication"
        }
    }
}

enum EnglishVariant: String, CaseIterable, Codable, Identifiable {
    case american = "美式英语"
    case british = "英式英语"

    var id: String { rawValue }

    var promptDescription: String {
        switch self {
        case .american: return "American English"
        case .british: return "British English"
        }
    }
}

enum TranslationBackend: String, CaseIterable, Codable, Identifiable {
    case openAICompatible = "OpenAI 兼容 API"
    case libreThenAI = "LibreTranslate + OpenAI 兼容 API"
    case libreOnly = "仅 LibreTranslate"

    var id: String { rawValue }
}


enum TranslationProvider: String, CaseIterable, Codable, Identifiable {
    case openAICompatible = "OpenAI 兼容 API"
    case deepL = "DeepL API Free/Pro"
    case libreTranslate = "LibreTranslate"
    case myMemory = "MyMemory 免费接口"
    var id: String { rawValue }
}

enum UsagePreset: String, CaseIterable, Codable, Identifiable {
    case localFirst = "本地优先"
    case freeFast = "免费极速"
    case quality = "推荐质量"
    case privateLocal = "完全本地"
    case custom = "自定义"
    var id: String { rawValue }
}

enum AITaskMode: String, Codable {
    case query
    case expression
    case queryAndExpression
}

enum AIAPIFormat: String, CaseIterable, Codable, Identifiable {
    case openAIChatCompletions = "OpenAI Chat Completions"

    var id: String { rawValue }
}

struct TranslationTerm: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var partOfSpeech: String?
    var phonetic: String?
    var englishDefinition: String
    var chineseDefinition: String
    var examples: [String]
    var usageNote: String?

    enum CodingKeys: String, CodingKey {
        case text, partOfSpeech, phonetic, englishDefinition, chineseDefinition, examples, usageNote
    }
}

struct TranslationOutput: Codable, Identifiable, Hashable {
    var id = UUID()
    var detectedLanguage: String
    var accurateTranslation: String
    var queryExplanation: String?
    var recommendedExpression: String
    var politeAlternative: String
    var conciseAlternative: String
    var formalAlternative: String
    var explanation: String
    var terms: [TranslationTerm]
    var offlineEntry: DictionaryEntry?

    enum CodingKeys: String, CodingKey {
        case detectedLanguage, accurateTranslation, queryExplanation, recommendedExpression, politeAlternative
        case conciseAlternative, formalAlternative, explanation, terms, offlineEntry
    }

    static func localInitial(sourceText: String, entry: DictionaryEntry) -> TranslationOutput {
        TranslationOutput(
            detectedLanguage: "en",
            accurateTranslation: entry.chineseDefinition ?? "",
            queryExplanation: nil,
            recommendedExpression: "",
            politeAlternative: "",
            conciseAlternative: "",
            formalAlternative: "",
            explanation: "",
            terms: [],
            offlineEntry: entry
        )
    }

    static func baseOnly(sourceLanguage: String, translation: String, offlineEntry: DictionaryEntry?) -> TranslationOutput {
        TranslationOutput(
            detectedLanguage: sourceLanguage,
            accurateTranslation: translation,
            queryExplanation: offlineEntry.map { entry in
                [entry.englishDefinition, entry.chineseDefinition]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            } ?? "当前为仅 LibreTranslate 模式，未找到对应的离线词典条目。启用 OpenAI 兼容 API 后可查询句型、语法和上下文用法。",
            recommendedExpression: "",
            politeAlternative: "",
            conciseAlternative: "",
            formalAlternative: "",
            explanation: "当前未使用 AI 表达优化服务。",
            terms: [],
            offlineEntry: offlineEntry
        )
    }

    static func offlineOnly(sourceText: String, entry: DictionaryEntry, apiError: String) -> TranslationOutput {
        TranslationOutput(
            detectedLanguage: "en",
            accurateTranslation: "",
            queryExplanation: "已完成本地离线查询。翻译与表达模块需要配置可用的 OpenAI 兼容 API。\n\nAPI 状态：\(apiError)",
            recommendedExpression: "",
            politeAlternative: "",
            conciseAlternative: "",
            formalAlternative: "",
            explanation: "",
            terms: [],
            offlineEntry: entry
        )
    }
}

struct DictionaryEntry: Codable, Hashable {
    var word: String
    var phonetic: String?
    var englishDefinition: String?
    var chineseDefinition: String?
    var partOfSpeech: String?
    var exchange: String?
    var sourceName: String?
}

struct DictionaryStatus: Hashable {
    var bundledAvailable: Bool
    var bundledName: String?
    var bundledEntryCount: Int?
    var ecdictAvailable: Bool

    var summary: String {
        var parts: [String] = []
        if bundledAvailable {
            if let bundledName, let bundledEntryCount {
                parts.append("\(bundledName) · \(bundledEntryCount.formatted()) 词条")
            } else {
                parts.append("内置词典已可用")
            }
        }
        if ecdictAvailable {
            parts.append("ECDICT 已安装")
        }
        return parts.isEmpty ? "暂无可用离线词典" : parts.joined(separator: "；")
    }
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: Date
    var input: String
    var output: TranslationOutput
}

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case missingModel
    case emptyInput
    case invalidResponse
    case apiError(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "API 地址无效。可填写完整 /v1/chat/completions 地址，或只填写服务根地址。"
        case .missingModel:
            return "请先在设置中填写第三方服务支持的模型名称。"
        case .emptyInput:
            return "请输入或选中需要处理的文字。"
        case .invalidResponse:
            return "API 返回了无法识别的 OpenAI Chat Completions 响应。"
        case .apiError(let message):
            return message
        case .decodingFailed(let message):
            return "结果解析失败：\(message)"
        }
    }
}
