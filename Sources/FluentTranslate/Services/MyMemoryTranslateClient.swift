import Foundation

final class MyMemoryTranslateClient {
    func translate(text: String, settings: SettingsStore) async throws -> LibreTranslateClient.Result {
        let source = settings.sourceLanguage == "auto" ? Self.guessSource(text) : settings.sourceLanguage
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        var items = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "langpair", value: "\(source)|\(settings.targetLanguage)")]
        if !settings.myMemoryEmail.isEmpty { items.append(URLQueryItem(name: "de", value: settings.myMemoryEmail)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw TranslationError.apiError("MyMemory 请求失败") }
        struct Response: Decodable { struct DataItem: Decodable { let translatedText: String }; let responseData: DataItem; let responseStatus: Int? }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return LibreTranslateClient.Result(translatedText: decoded.responseData.translatedText, detectedLanguage: source)
    }

    private static func guessSource(_ text: String) -> String {
        text.range(of: "[\\p{Han}]", options: .regularExpression) == nil ? "en" : "zh-CN"
    }
}
