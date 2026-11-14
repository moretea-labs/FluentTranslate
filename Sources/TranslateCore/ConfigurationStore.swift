import Foundation

public protocol ConfigurationStoring {
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

public final class FileConfigurationStore: ConfigurationStoring {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let configuration = AppConfiguration.default
            try save(configuration)
            return configuration
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
    }
}
