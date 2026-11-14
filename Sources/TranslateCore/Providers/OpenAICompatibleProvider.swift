import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class OpenAICompatibleProvider: TranslationProvider, ExpressionProvider {
    public let configuration: ProviderConfiguration
    private let httpClient: HTTPClientProtocol
    private let secrets: SecretResolving

    public init(configuration: ProviderConfiguration, httpClient: HTTPClientProtocol, secrets: SecretResolving) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.secrets = secrets
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try ensureEnabled(capability: .contextualTranslation)
        let startedAt = Date()
        let response = try await complete(
            system: PromptTemplates.translationSystemPrompt(
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage
            ),
            user: PromptTemplates.translationUserPrompt(request),
            temperature: 0.1
        )
        return TranslationResult(
            sourceText: request.text,
            translatedText: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: configuration.id,
            providerName: configuration.displayName,
            providerKind: configuration.kind,
            credentialSource: configuration.credentialSource,
            modelName: response.model,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    public func optimize(_ request: ExpressionRequest, baseProviderName: String) async throws -> ExpressionResult {
        try ensureEnabled(capability: request.scene.requiredCapability)
        let response = try await complete(
            system: PromptTemplates.expressionSystemPrompt(request),
            user: PromptTemplates.expressionUserPrompt(request),
            temperature: 0.35
        )
        let parsed = parseExpression(response.content)
        return ExpressionResult(
            primaryText: parsed.primary,
            alternatives: Array(parsed.alternatives.prefix(2)),
            scene: request.scene,
            tone: request.tone,
            providerID: configuration.id,
            providerName: configuration.displayName,
            credentialSource: configuration.credentialSource,
            modelName: response.model,
            baseTranslationProviderName: baseProviderName
        )
    }

    private func complete(system: String, user: String, temperature: Double) async throws -> (content: String, model: String?) {
        guard let url = URL(string: configuration.baseURL) else {
            throw TranslationError.invalidURL(configuration.baseURL)
        }
        guard let model = configuration.model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.invalidResponse("请先配置模型名称")
        }
        let apiKey = try requiredSecret()

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": temperature
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configuration.customHeaders.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw TranslationError.remoteError(
                statusCode: response.statusCode,
                message: HTTPUtilities.decodeErrorMessage(from: data)
            )
        }

        struct Payload: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let model: String?
            let choices: [Choice]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let content = payload.choices.first?.message.content, !content.isEmpty else {
            throw TranslationError.invalidResponse("AI 服务未返回文本")
        }
        return (content, payload.model ?? model)
    }

    private func ensureEnabled(capability: ProviderCapability) throws {
        guard configuration.enabled else { throw TranslationError.providerDisabled(configuration.displayName) }
        guard configuration.capabilities.contains(capability) else {
            throw TranslationError.unsupportedCapability(configuration.displayName)
        }
    }

    private func requiredSecret() throws -> String {
        guard let reference = configuration.secretReference,
              let value = try secrets.secret(for: reference),
              !value.isEmpty else {
            throw TranslationError.missingCredential(configuration.displayName)
        }
        return value
    }

    private func parseExpression(_ raw: String) -> (primary: String, alternatives: [String]) {
        struct Structured: Decodable {
            let primary: String
            let alternatives: [String]?
        }
        let trimmed = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let value = try? JSONDecoder().decode(Structured.self, from: data) {
            return (value.primary, value.alternatives ?? [])
        }
        return (trimmed, [])
    }
}
