import Foundation

public final class TranslationRouter {
    private let configuration: AppConfiguration
    private let factory: ProviderFactory
    private let localDictionary: LocalDictionary
    private let cache: TranslationCache

    public init(
        configuration: AppConfiguration,
        factory: ProviderFactory,
        localDictionary: LocalDictionary = LocalDictionary(),
        cache: TranslationCache = TranslationCache()
    ) {
        self.configuration = configuration
        self.factory = factory
        self.localDictionary = localDictionary
        self.cache = cache
    }

    public func translateDefault(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let preset = configuration.presets.first(where: { $0.id == configuration.defaultPresetID }) else {
            throw TranslationError.noProviderAvailable
        }
        return try await translate(request, preset: preset)
    }

    public func translateAccurate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let providerID = configuration.accurateProviderID else {
            throw TranslationError.noProviderAvailable
        }
        return try await translate(request, using: providerID)
    }

    public func translate(_ request: TranslationRequest, using providerID: String) async throws -> TranslationResult {
        try validateInput(request)
        guard let configuration = configuration.providers.first(where: { $0.id == providerID }) else {
            throw TranslationError.providerNotFound(providerID)
        }
        if configuration.kind == .local {
            guard let result = localDictionary.lookup(request) else {
                throw TranslationError.invalidResponse("本地词典未命中")
            }
            return result
        }
        return try await requestProvider(configuration, request: request, requestedProviderID: providerID)
    }

    public func translate(_ request: TranslationRequest, preset: TranslationPreset) async throws -> TranslationResult {
        try validateInput(request)
        if preset.localFirst, let local = localDictionary.lookup(request) {
            return local
        }

        var failures: [String] = []
        var firstProviderID: String?
        for providerID in preset.providerOrder {
            guard let providerConfiguration = configuration.providers.first(where: { $0.id == providerID }),
                  providerConfiguration.enabled,
                  providerConfiguration.capabilities.contains(.translation)
                    || providerConfiguration.capabilities.contains(.contextualTranslation) else {
                continue
            }
            if firstProviderID == nil { firstProviderID = providerID }
            do {
                var result = try await requestProvider(
                    providerConfiguration,
                    request: request,
                    requestedProviderID: firstProviderID
                )
                if providerID != firstProviderID {
                    result.fallbackOccurred = true
                    result.fallbackReason = failures.joined(separator: "；")
                }
                return result
            } catch {
                failures.append("\(providerConfiguration.displayName)：\(error.localizedDescription)")
                if !preset.fallbackEnabled { throw error }
            }
        }
        throw TranslationError.remoteError(statusCode: 0, message: failures.isEmpty ? "没有启用的翻译服务" : failures.joined(separator: "；"))
    }

    private func requestProvider(
        _ providerConfiguration: ProviderConfiguration,
        request: TranslationRequest,
        requestedProviderID: String?
    ) async throws -> TranslationResult {
        let key = TranslationCache.key(request: request, providerID: providerConfiguration.id)
        if configuration.cacheEnabled, var cached = await cache.result(for: key) {
            cached.requestedProviderID = requestedProviderID
            cached.requestedProviderName = requestedProviderName(for: requestedProviderID)
            return cached
        }
        guard let provider = factory.translationProvider(for: providerConfiguration) else {
            throw TranslationError.unsupportedCapability(providerConfiguration.displayName)
        }
        var result = try await provider.translate(request)
        result.requestedProviderID = requestedProviderID
        result.requestedProviderName = requestedProviderName(for: requestedProviderID)
        if configuration.cacheEnabled {
            await cache.store(result, for: key)
        }
        return result
    }

    private func requestedProviderName(for providerID: String?) -> String? {
        guard let providerID else { return nil }
        return configuration.providers.first(where: { $0.id == providerID })?.displayName
    }

    private func validateInput(_ request: TranslationRequest) throws {
        if request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError.emptyInput
        }
    }
}
