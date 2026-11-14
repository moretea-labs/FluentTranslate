import Foundation

public extension AppConfiguration {
    static var `default`: AppConfiguration {
        let providers: [ProviderConfiguration] = [
            ProviderConfiguration(
                id: "local-dictionary",
                displayName: "本地词典",
                kind: .local,
                baseURL: "",
                enabled: true,
                credentialSource: .local,
                capabilities: [.dictionary, .translation, .explanation],
                timeoutSeconds: 1
            ),
            ProviderConfiguration(
                id: "apple-system",
                displayName: "Apple 系统翻译",
                kind: .appleSystem,
                baseURL: "",
                enabled: true,
                credentialSource: .local,
                capabilities: [.translation],
                timeoutSeconds: 15
            ),
            ProviderConfiguration(
                id: "mymemory-public",
                displayName: "MyMemory",
                kind: .myMemory,
                baseURL: "https://api.mymemory.translated.net/get",
                enabled: true,
                credentialSource: .builtIn,
                capabilities: [.translation],
                timeoutSeconds: 8,
                options: ["contactEmail": ""]
            ),
            ProviderConfiguration(
                id: "deepl-user",
                displayName: "DeepL",
                kind: .deepL,
                baseURL: "https://api-free.deepl.com/v2/translate",
                enabled: false,
                credentialSource: .userConfigured,
                secretReference: "provider.deepl-user.apiKey",
                capabilities: [.translation, .contextualTranslation],
                timeoutSeconds: 15,
                options: [
                    "accountType": DeepLAccountType.free.rawValue,
                    "modelType": "prefer_quality_optimized"
                ]
            ),
            ProviderConfiguration(
                id: "libretranslate-user",
                displayName: "LibreTranslate",
                kind: .libreTranslate,
                baseURL: "https://libretranslate.com/translate",
                enabled: false,
                credentialSource: .userConfigured,
                secretReference: "provider.libretranslate-user.apiKey",
                capabilities: [.translation],
                timeoutSeconds: 15
            ),
            ProviderConfiguration(
                id: "openai-compatible-user",
                displayName: "OpenAI 兼容服务",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1/chat/completions",
                enabled: false,
                credentialSource: .userConfigured,
                secretReference: "provider.openai-compatible-user.apiKey",
                model: "",
                capabilities: [.contextualTranslation, .dailyExpression, .teamsExpression, .emailExpression, .explanation],
                timeoutSeconds: 30
            )
        ]

        return AppConfiguration(
            defaultPresetID: "local-first",
            accurateProviderID: "deepl-user",
            cacheEnabled: true,
            presets: [
                TranslationPreset(
                    id: "local-first",
                    displayName: "本地优先",
                    localFirst: true,
                    fallbackEnabled: true,
                    providerOrder: ["apple-system", "mymemory-public"]
                ),
                TranslationPreset(
                    id: "free-fast",
                    displayName: "免费极速",
                    localFirst: false,
                    fallbackEnabled: true,
                    providerOrder: ["mymemory-public", "libretranslate-user"]
                ),
                TranslationPreset(
                    id: "recommended-quality",
                    displayName: "推荐质量",
                    localFirst: true,
                    fallbackEnabled: true,
                    providerOrder: ["deepl-user", "mymemory-public"]
                )
            ],
            expressionRouting: ExpressionRouting(
                dailyProviderID: "openai-compatible-user",
                teamsProviderID: "openai-compatible-user",
                emailProviderID: "openai-compatible-user"
            ),
            providers: providers
        )
    }

    /// Migrate the prior stock preset without changing custom provider choices.
    mutating func addNativeTranslationIfNeeded() -> Bool {
        guard !providers.contains(where: { $0.id == "apple-system" }),
              let native = Self.default.providers.first(where: { $0.id == "apple-system" }) else {
            return false
        }
        providers.append(native)
        if let index = presets.firstIndex(where: {
            $0.id == "local-first" && $0.providerOrder == ["mymemory-public"]
        }) {
            presets[index].providerOrder.insert("apple-system", at: 0)
        }
        return true
    }
}
