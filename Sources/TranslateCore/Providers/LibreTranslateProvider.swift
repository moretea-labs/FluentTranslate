import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class LibreTranslateProvider: TranslationProvider {
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

        var body: [String: Any] = [
            "q": request.text,
            "source": request.sourceLanguage,
            "target": request.targetLanguage,
            "format": "text",
            "alternatives": 0
        ]
        if let reference = configuration.secretReference,
           let apiKey = try secrets.secret(for: reference),
           !apiKey.isEmpty {
            body["api_key"] = apiKey
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutSeconds
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
            struct DetectedLanguage: Decodable { let language: String? }
            let translatedText: String
            let detectedLanguage: DetectedLanguage?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return TranslationResult(
            sourceText: request.text,
            translatedText: payload.translatedText,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: configuration.id,
            providerName: configuration.displayName,
            providerKind: configuration.kind,
            credentialSource: configuration.credentialSource,
            detectedSourceLanguage: payload.detectedLanguage?.language,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }
}
