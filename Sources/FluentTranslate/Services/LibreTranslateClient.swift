import Foundation

final class LibreTranslateClient {
    private struct RequestBody: Encodable {
        let q: String
        let source: String
        let target: String
        let format: String
        let api_key: String?
    }

    private struct ResponseBody: Decodable {
        let translatedText: String
        let detectedLanguage: DetectedLanguage?

        struct DetectedLanguage: Decodable {
            let language: String?
        }
    }

    struct Result {
        let translatedText: String
        let detectedLanguage: String
    }

    func translate(text: String, settings: SettingsStore) async throws -> Result {
        guard let endpoint = URL(string: settings.libreEndpoint) else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                q: text,
                source: settings.sourceLanguage,
                target: settings.targetLanguage,
                format: "text",
                api_key: settings.libreAPIKey.isEmpty ? nil : settings.libreAPIKey
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranslationError.apiError("LibreTranslate 请求失败：\(body)")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return Result(
            translatedText: decoded.translatedText,
            detectedLanguage: decoded.detectedLanguage?.language ?? settings.sourceLanguage
        )
    }
}
