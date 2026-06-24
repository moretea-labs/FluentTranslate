import Foundation

final class HistoryStore {
    static let shared = HistoryStore()
    private let maxItems = 100

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluentTranslate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    func load() -> [HistoryItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.fluent.decode([HistoryItem].self, from: data)) ?? []
    }

    func append(input: String, output: TranslationOutput) -> [HistoryItem] {
        var items = load()
        items.insert(HistoryItem(id: UUID(), createdAt: Date(), input: input, output: output), at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save(items)
        return items
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save(_ items: [HistoryItem]) {
        guard let data = try? JSONEncoder.fluent.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var fluent: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var fluent: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
