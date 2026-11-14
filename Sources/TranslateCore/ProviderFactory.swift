import Foundation

public final class ProviderFactory {
    private let httpClient: HTTPClientProtocol
    private let secrets: SecretResolving

    public init(httpClient: HTTPClientProtocol, secrets: SecretResolving) {
        self.httpClient = httpClient
        self.secrets = secrets
    }

    public func translationProvider(for configuration: ProviderConfiguration) -> TranslationProvider? {
        switch configuration.kind {
        case .local:
            return nil
        case .appleSystem:
            return AppleSystemTranslationProvider(configuration: configuration)
        case .myMemory:
            return MyMemoryProvider(configuration: configuration, httpClient: httpClient)
        case .deepL:
            return DeepLProvider(configuration: configuration, httpClient: httpClient, secrets: secrets)
        case .libreTranslate:
            return LibreTranslateProvider(configuration: configuration, httpClient: httpClient, secrets: secrets)
        case .openAICompatible:
            return OpenAICompatibleProvider(configuration: configuration, httpClient: httpClient, secrets: secrets)
        }
    }

    public func expressionProvider(for configuration: ProviderConfiguration) -> ExpressionProvider? {
        guard configuration.kind == .openAICompatible else { return nil }
        return OpenAICompatibleProvider(configuration: configuration, httpClient: httpClient, secrets: secrets)
    }
}
