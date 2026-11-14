import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class DeepLProvider: TranslationProvider {
    public let configuration: ProviderConfiguration
    private let httpClient: HTTPClientProtocol
    private let secrets: SecretResolving

    public init(configuration: ProviderConfiguration, httpClient: HTTPClientProtocol, secrets: SecretResolving) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.secrets = secrets
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard configuration.enabled else { throw TranslationError.providerDisabled(configuration.displayName) }
        guard let url = URL(string: configuration.baseURL) else {
            throw TranslationError.invalidURL(configuration.baseURL)
        }
        let apiKey = try requiredSecret()

        var body: [String: Any] = [
            "text": [request.text],
            "target_lang": normalizeLanguage(request.targetLanguage, uppercased: true),
            "preserve_formatting": true
        ]
        if request.sourceLanguage != "auto" {
            body["source_lang"] = normalizeLanguage(request.sourceLanguage, uppercased: true)
        }
        if let context = request.context, !context.isEmpty {
            body["context"] = context
        }
        if let modelType = configuration.options["modelType"], !modelType.isEmpty {
            body["model_type"] = modelType
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutSeconds
        urlRequest.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configuration.customHeaders.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response) = try await httpClient.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw TranslationError.remoteError(
                statusCode: response.statusCode,
                message: HTTPUtilities.decodeErrorMessage(from: data)
            )
        }

        struct Payload: Decodable {
            struct Translation: Decodable {
                let detectedSourceLanguage: String?
                let text: String
                let modelTypeUsed: String?

                enum CodingKeys: String, CodingKey {
                    case detectedSourceLanguage = "detected_source_language"
                    case text
                    case modelTypeUsed = "model_type_used"
                }
            }
            let translations: [Translation]
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let translated = payload.translations.first else {
            throw TranslationError.invalidResponse("DeepL 未返回翻译结果")
        }

        return TranslationResult(
            sourceText: request.text,
            translatedText: translated.text,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: configuration.id,
            providerName: configuration.displayName,
            providerKind: configuration.kind,
            credentialSource: configuration.credentialSource,
            modelName: translated.modelTypeUsed,
            detectedSourceLanguage: translated.detectedSourceLanguage,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    private func requiredSecret() throws -> String {
        guard let reference = configuration.secretReference,
              let value = try secrets.secret(for: reference),
              !value.isEmpty else {
            throw TranslationError.missingCredential(configuration.displayName)
        }
        return value
    }

    private func normalizeLanguage(_ value: String, uppercased: Bool) -> String {
        let base = value.replacingOccurrences(of: "_", with: "-")
        return uppercased ? base.uppercased() : base.lowercased()
    }
}
