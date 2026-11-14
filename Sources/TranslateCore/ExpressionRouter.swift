import Foundation

public final class ExpressionRouter {
    private let configuration: AppConfiguration
    private let factory: ProviderFactory

    public init(configuration: AppConfiguration, factory: ProviderFactory) {
        self.configuration = configuration
        self.factory = factory
    }

    public func optimize(
        _ request: ExpressionRequest,
        baseTranslationProviderName: String,
        providerID explicitProviderID: String? = nil,
        routeUseCase: ExpressionRouteUseCase? = nil
    ) async throws -> ExpressionResult {
        let candidates = providerCandidates(
            for: request,
            explicitProviderID: explicitProviderID,
            routeUseCase: routeUseCase
        )
        guard !candidates.isEmpty else { throw TranslationError.noProviderAvailable }

        var lastError: Error?
        for providerID in candidates {
            do {
                guard let providerConfiguration = configuration.providers.first(where: { $0.id == providerID }) else {
                    throw TranslationError.providerNotFound(providerID)
                }
                guard providerConfiguration.enabled else {
                    throw TranslationError.providerDisabled(providerConfiguration.displayName)
                }
                guard providerConfiguration.capabilities.contains(request.scene.requiredCapability) else {
                    throw TranslationError.unsupportedCapability(providerConfiguration.displayName)
                }
                guard let provider = factory.expressionProvider(for: providerConfiguration) else {
                    throw TranslationError.unsupportedCapability(providerConfiguration.displayName)
                }
                return try await provider.optimize(request, baseProviderName: baseTranslationProviderName)
            } catch {
                lastError = error
                if explicitProviderID != nil { break }
            }
        }

        throw lastError ?? TranslationError.noProviderAvailable
    }

    private func providerCandidates(
        for request: ExpressionRequest,
        explicitProviderID: String?,
        routeUseCase: ExpressionRouteUseCase?
    ) -> [String] {
        if let explicitProviderID { return [explicitProviderID] }

        let route: AIServiceRoute
        if let routeUseCase {
            route = configuration.expressionRouting.route(for: routeUseCase)
        } else {
            route = configuration.expressionRouting.route(for: request.scene)
        }
        if route.mode == .manual { return [] }

        var seen = Set<String>()
        var ids: [String] = []
        for providerID in route.orderedProviderIDs where seen.insert(providerID).inserted {
            ids.append(providerID)
        }

        if route.mode == .defaultWithFallback {
            for provider in configuration.providers
            where provider.enabled
                && provider.capabilities.contains(request.scene.requiredCapability)
                && factory.expressionProvider(for: provider) != nil
                && seen.insert(provider.id).inserted {
                ids.append(provider.id)
            }
        }

        return ids
    }
}
