import Foundation
#if canImport(Translation)
import Translation
#endif

/// Built-in on-device translation; does not use API keys or HTTP.
public final class AppleSystemTranslationProvider: TranslationProvider {
    public let configuration: ProviderConfiguration

    public init(configuration: ProviderConfiguration) {
        self.configuration = configuration
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard configuration.enabled else {
            throw TranslationError.providerDisabled(configuration.displayName)
        }
        #if os(macOS) && canImport(Translation)
        if #available(macOS 26.0, *) {
            let source = Locale.Language(identifier: request.sourceLanguage)
            let target = Locale.Language(identifier: request.targetLanguage)
            let status = await LanguageAvailability().status(from: source, to: target)
            guard status == .installed else {
                throw TranslationError.invalidResponse(
                    status == .supported
                        ? "请在系统设置 → 通用 → 语言与地区 → 翻译语言中下载相应语言包"
                        : "Apple 系统翻译暂不支持这组语言"
                )
            }
            let startedAt = Date()
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await session.translate(request.text)
            return TranslationResult(
                sourceText: request.text,
                translatedText: response.targetText,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                providerID: configuration.id,
                providerName: configuration.displayName,
                providerKind: configuration.kind,
                credentialSource: .local,
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
        }
        #endif
        throw TranslationError.unsupportedCapability("Apple 原生翻译需要 macOS 26 或更新版本")
    }
}
