import CryptoKit
import Foundation

final class ResponseCacheStore {
    static let shared = ResponseCacheStore()

    private struct Record: Codable {
        let output: TranslationOutput
        let expiresAt: Date
    }

    private var records: [String: Record] = [:]
    private let lock = NSLock()

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluentTranslate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("responses.json")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.fluent.decode([String: Record].self, from: data) {
            records = decoded.filter { $0.value.expiresAt > Date() }
        }
    }

    func key(_ parts: String...) -> String {
        let value = parts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func value(for key: String) -> TranslationOutput? {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[key], record.expiresAt > Date() else {
            records.removeValue(forKey: key)
            return nil
        }
        return record.output
    }

    func save(_ output: TranslationOutput, for key: String, days: Int = 30) {
        lock.lock()
        records[key] = Record(output: output, expiresAt: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
        let snapshot = records
        lock.unlock()
        if let data = try? JSONEncoder.fluent.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        lock.lock(); records.removeAll(); lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
