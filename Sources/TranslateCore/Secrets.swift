import Foundation

public protocol SecretResolving {
    func secret(for reference: String) throws -> String?
}

public struct DictionarySecretResolver: SecretResolving {
    private let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public func secret(for reference: String) throws -> String? {
        values[reference]
    }
}
