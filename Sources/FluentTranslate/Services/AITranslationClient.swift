import Foundation

final class AITranslationClient {
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: MessageContent?
            }

            let message: Message?
            let text: String?
        }

        struct APIError: Decodable {
            let message: String
        }

        let choices: [Choice]?
        let error: APIError?
    }

    private enum MessageContent: Decodable {
        struct Part: Decodable {
            let type: String?
            let text: String?
        }

        case text(String)
        case parts([Part])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            if let parts = try? container.decode([Part].self) {
                self = .parts(parts)
                return
            }
            throw DecodingError.typeMismatch(
                MessageContent.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported message.content format")
            )
        }

        var textValue: String {
            switch self {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.compactMap(\.text).joined(separator: "\n")
            }
        }
    }

    func translate(
        text: String,
        baseTranslation: String?,
        offlineEntry: DictionaryEntry?,
        settings: SettingsStore,
        mode: AITaskMode = .queryAndExpression
    ) async throws -> TranslationOutput {
        guard !settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingModel
        }

        let endpoint: URL
        switch settings.aiAPIFormat {
        case .openAIChatCompletions:
            guard let resolved = Self.resolveChatCompletionsEndpoint(settings.aiEndpoint) else {
                throw TranslationError.invalidEndpoint
            }
            endpoint = resolved
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(settings.aiAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let queryInstructions: String
        if mode == .query || mode == .queryAndExpression {
            queryInstructions = """
            Query mode is enabled. Provide only contextual grammar/usage information not already available from the local dictionary. Extract at most 3 useful terms.
            """
        } else {
            queryInstructions = "Query mode is disabled. Return an empty queryExplanation and an empty terms array."
        }

        let expressionInstructions: String
        if mode == .expression || mode == .queryAndExpression {
            expressionInstructions = """
            Expression mode is enabled.
            - recommendedExpression must be \(settings.expressionStyle.promptDescription).
            - When the target language is English, use \(settings.englishVariant.promptDescription).
            - Also provide politeAlternative, conciseAlternative and formalAlternative when meaningfully different.
            - explanation must explain material wording and tone changes in Chinese.
            """
        } else {
            expressionInstructions = """
            Expression mode is disabled. Do not optimize or rewrite the translation.
            Return empty strings for recommendedExpression, politeAlternative, conciseAlternative, formalAlternative and explanation.
            """
        }

        let systemPrompt = """
        You are the translation and language-query engine inside a macOS app.
        Every request has three result modules: Translation, Query and optional Expression.
        Return valid JSON only. Do not use Markdown fences or commentary outside JSON.

        Translation requirements:
        1. Preserve names, product names, API names, code, dates, numbers, negation, conditions and uncertainty.
        2. accurateTranslation must be faithful, complete and must not add facts.

        Query requirements:
        3. \(queryInstructions)
        When enabled, queryExplanation must contain useful lookup information in Chinese.
           - For one word or a short phrase: explain contextual meaning, part of speech, common usage and distinctions when relevant.
           - For a sentence: explain key grammar, sentence structure and reusable expressions.
           - For Chinese source text translated to English: explain the most useful English equivalents and why they fit.
        4. Extract at most 3 useful English words or phrases into terms. Give concise English and Chinese definitions, pronunciation only when reliably known, examples and a usage note.
        5. Treat the local dictionary entry as reference material. Do not discard a useful dictionary definition.

        \(expressionInstructions)

        General requirements:
        6. Empty fields must be empty strings or empty arrays, never null.
        7. Do not merge the three modules: accurateTranslation is Translation, queryExplanation/terms are Query, and expression fields are Expression.

        Output schema:
        {
          "detectedLanguage": "string",
          "accurateTranslation": "string",
          "queryExplanation": "string",
          "recommendedExpression": "string",
          "politeAlternative": "string",
          "conciseAlternative": "string",
          "formalAlternative": "string",
          "explanation": "string",
          "terms": [
            {
              "text": "string",
              "partOfSpeech": "string",
              "phonetic": "string",
              "englishDefinition": "string",
              "chineseDefinition": "string",
              "examples": ["string"],
              "usageNote": "string"
            }
          ]
        }
        """

        let baseSection = baseTranslation.map {
            "Reference machine translation (verify it; do not blindly copy):\n\($0)"
        } ?? ""

        let dictionarySection: String
        if let offlineEntry {
            let englishHint = String((offlineEntry.englishDefinition ?? "").prefix(240))
            let chineseHint = String((offlineEntry.chineseDefinition ?? "").prefix(160))
            dictionarySection = """
            Local dictionary hint (do not repeat it in the response):
            headword: \(offlineEntry.word)
            part of speech: \(offlineEntry.partOfSpeech ?? "")
            selected English sense: \(englishHint)
            selected Chinese sense: \(chineseHint)
            """
        } else {
            dictionarySection = ""
        }

        let userPrompt = """
        Source language preference: \(settings.sourceLanguage)
        Target language: \(settings.targetLanguage)
        Source text:
        \(text)

        \(baseSection)
        \(dictionarySection)
        """

        let payload = ChatRequest(
            model: settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data)
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = decoded?.error?.message ?? raw ?? "HTTP \(http.statusCode)"
            throw TranslationError.apiError("OpenAI 兼容 API 请求失败（HTTP \(http.statusCode)）：\(detail)")
        }

        let envelope: ChatResponse
        do {
            envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.apiError("第三方服务响应不符合 OpenAI Chat Completions 格式：\(raw.prefix(500))")
        }

        if let message = envelope.error?.message {
            throw TranslationError.apiError("第三方服务返回错误：\(message)")
        }

        guard let firstChoice = envelope.choices?.first else {
            throw TranslationError.invalidResponse
        }
        let content = firstChoice.message?.content?.textValue ?? firstChoice.text ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.invalidResponse
        }

        let cleaned = Self.extractJSONObject(from: content)
        do {
            var result = try JSONDecoder().decode(TranslationOutput.self, from: Data(cleaned.utf8))
            result.offlineEntry = offlineEntry
            return result
        } catch {
            throw TranslationError.decodingFailed("\(error.localizedDescription)\n原始结果：\(content.prefix(500))")
        }
    }

    private static func resolveChatCompletionsEndpoint(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed),
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased()),
              components.host != nil else {
            return nil
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = path.lowercased()
        if path.isEmpty {
            components.path = "/v1/chat/completions"
        } else if lowercasedPath == "v1" || lowercasedPath.hasSuffix("/v1") {
            components.path = "/\(path)/chat/completions"
        } else if lowercasedPath.hasSuffix("chat/completions") {
            components.path = "/\(path)"
        } else {
            // A non-root custom path is treated as a complete endpoint.
            components.path = "/\(path)"
        }
        return components.url
    }

    private static func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            let withoutOpening = lines.dropFirst()
            let withoutFence = withoutOpening.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
                ? withoutOpening.dropLast()
                : withoutOpening[...]
            return withoutFence.joined(separator: "\n")
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            return trimmed
        }
        return String(trimmed[start...end])
    }
}
