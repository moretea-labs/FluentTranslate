import Foundation

final class DeepLTranslateClient {
    func translate(text: String, settings: SettingsStore) async throws -> LibreTranslateClient.Result {
        guard let url = URL(string: settings.deepLEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw TranslationError.invalidEndpoint
        }
        guard !settings.deepLAPIKey.isEmpty else { throw TranslationError.apiError("请先配置 DeepL API Key。") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(settings.deepLAPIKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["text": [text], "target_lang": settings.targetLanguage.uppercased()]
        if settings.sourceLanguage != "auto" { body["source_lang"] = settings.sourceLanguage.uppercased() }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranslationError.apiError(String(data: data, encoding: .utf8) ?? "DeepL 请求失败")
        }
        struct Response: Decodable { struct Item: Decodable { let detected_source_language: String?; let text: String }; let translations: [Item] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let first = decoded.translations.first else { throw TranslationError.invalidResponse }
        return LibreTranslateClient.Result(translatedText: first.text, detectedLanguage: first.detected_source_language ?? settings.sourceLanguage)
    }
}
