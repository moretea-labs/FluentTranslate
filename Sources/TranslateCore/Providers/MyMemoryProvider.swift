import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class MyMemoryProvider: TranslationProvider {
    public let configuration: ProviderConfiguration
    private let httpClient: HTTPClientProtocol

    public init(configuration: ProviderConfiguration, httpClient: HTTPClientProtocol) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard configuration.enabled else { throw TranslationError.providerDisabled(configuration.displayName) }
        guard var components = URLComponents(string: configuration.baseURL) else {
            throw TranslationError.invalidURL(configuration.baseURL)
        }
        let source = request.sourceLanguage == "auto" ? detectSourceLanguage(in: request.text) : request.sourceLanguage
        var items = [
            URLQueryItem(name: "q", value: request.text),
            URLQueryItem(name: "langpair", value: "\(source)|\(request.targetLanguage)"),
            URLQueryItem(name: "mt", value: "1")
        ]
        if let email = configuration.options["contactEmail"], !email.isEmpty {
            items.append(URLQueryItem(name: "de", value: email))
        }
        components.queryItems = items
        guard let url = components.url else { throw TranslationError.invalidURL(configuration.baseURL) }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = configuration.timeoutSeconds
        configuration.customHeaders.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        let startedAt = Date()
        let (data, response) = try await httpClient.data(for: urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw TranslationError.remoteError(
                statusCode: response.statusCode,
                message: HTTPUtilities.decodeErrorMessage(from: data)
            )
        }

        struct Payload: Decodable {
            struct ResponseData: Decodable {
                let translatedText: String
            }
            let responseData: ResponseData
            let responseStatus: Int?
            let responseDetails: String?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if let status = payload.responseStatus, status >= 400 {
            throw TranslationError.remoteError(statusCode: status, message: payload.responseDetails ?? "MyMemory 返回错误")
        }

        return TranslationResult(
            sourceText: request.text,
            translatedText: payload.responseData.translatedText,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            providerID: configuration.id,
            providerName: configuration.displayName,
            providerKind: configuration.kind,
            credentialSource: configuration.credentialSource,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    private func detectSourceLanguage(in text: String) -> String {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF: return "ja"
            case 0xAC00...0xD7AF: return "ko"
            case 0x4E00...0x9FFF: return "zh"
            case 0x0400...0x04FF: return "ru"
            default: continue
            }
        }
        return "en"
    }
}
