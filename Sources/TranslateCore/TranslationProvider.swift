import Foundation

public protocol TranslationProvider {
    var configuration: ProviderConfiguration { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public protocol ExpressionProvider {
    var configuration: ProviderConfiguration { get }
    func optimize(_ request: ExpressionRequest, baseProviderName: String) async throws -> ExpressionResult
}
