import Foundation

public struct DictionarySourceInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var entryCount: Int?
    public var detail: String

    public init(id: String, displayName: String, entryCount: Int?, detail: String) {
        self.id = id
        self.displayName = displayName
        self.entryCount = entryCount
        self.detail = detail
    }
}

public enum BundledDictionaries {
    public static func makeSources() -> [any DictionarySource] {
        var result: [any DictionarySource] = []

        func appendIfAvailable(
            id: String,
            displayName: String,
            detail: String,
            resourceName: String,
            entryLanguage: String = "en"
        ) {
            if let source = try? IndexedDictionarySource(
                id: id,
                displayName: displayName,
                detail: detail,
                entryLanguage: entryLanguage,
                resourceName: resourceName
            ) {
                result.append(source)
            }
        }

        appendIfAvailable(
            id: "cambridge-en-zh",
            displayName: "Cambridge English-Chinese 双解",
            detail: "英汉双解 · 约 6.4 万可查询词头",
            resourceName: "cambridge-en-zh"
        )
        appendIfAvailable(
            id: "collins-han-en",
            displayName: "Collins 汉英大词典",
            detail: "汉英 · 用户本地词典转换",
            resourceName: "collins-han-en",
            entryLanguage: "zh"
        )
        appendIfAvailable(
            id: "collins-cobuild-en",
            displayName: "Collins COBUILD 高阶英英",
            detail: "英英释义 · 约 3.3 万可查询词头",
            resourceName: "collins-cobuild-en"
        )
        return result
    }
}

public enum IndexedDictionaryError: LocalizedError {
    case resourceMissing(String)
    case invalidFile(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "找不到内置词典资源：\(name)"
        case .invalidFile(let message): return "词典索引损坏：\(message)"
        }
    }
}

/// Exact-key dictionary backed by a memory-mapped TranslateDesk dictionary file.
/// The index is binary-searched in place; the full dictionary is never decoded
/// or loaded into a Swift Dictionary.
public final class IndexedDictionarySource: @unchecked Sendable, DictionarySource {
    public let id: String
    public let displayName: String
    public let detail: String
    public let entryCount: Int?

    private let entryLanguage: String
    private let file: IndexedDictionaryFile

    public convenience init(
        id: String,
        displayName: String,
        detail: String,
        entryLanguage: String = "en",
        resourceName: String
    ) throws {
        guard let url = DictionaryResourceLocator.url(for: resourceName, extension: "tdict") else {
            throw IndexedDictionaryError.resourceMissing(resourceName)
        }
        try self.init(
            id: id,
            displayName: displayName,
            detail: detail,
            entryLanguage: entryLanguage,
            fileURL: url
        )
    }

    public init(
        id: String,
        displayName: String,
        detail: String,
        entryLanguage: String = "en",
        fileURL: URL
    ) throws {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.entryLanguage = entryLanguage
        self.file = try IndexedDictionaryFile(url: fileURL)
        self.entryCount = file.count
    }

    public func lookupEntry(_ term: String) -> DictionaryLookupResult? {
        let started = DispatchTime.now().uptimeNanoseconds
        guard let record = file.lookup(normalize(term)) else { return nil }
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        return DictionaryLookupResult(
            dictionaryID: id,
            dictionaryName: displayName,
            entry: LocalDictionaryEntry(
                term: record.displayTerm,
                language: entryLanguage,
                translations: [:],
                englishDefinitions: [],
                examples: [],
                bodyText: record.body
            ),
            latencyMilliseconds: elapsed
        )
    }

    public func suggestions(for prefix: String, limit: Int) -> [String] {
        file.suggestions(prefix: normalize(prefix), limit: limit)
    }

    private func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‐", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private enum DictionaryResourceLocator {
    static func url(for name: String, extension fileExtension: String) -> URL? {
        let filename = "\(name).\(fileExtension)"
        // A standalone packaged app ships dictionaries in Contents/Resources.
        // Its SwiftPM resource bundle is intentionally not included; accessing
        // Bundle.module there would trap before any fallback could run.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.url(forResource: name, withExtension: fileExtension)
        }
        if let resource = Bundle.module.url(forResource: name, withExtension: fileExtension) {
            return resource
        }

        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(filename))
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let executableDirectory = executable.deletingLastPathComponent()
        candidates.append(executableDirectory.appendingPathComponent(filename))
        candidates.append(
            executableDirectory
                .appendingPathComponent("TranslateDesk_TranslateCore.resources", isDirectory: true)
                .appendingPathComponent(filename)
        )
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("TranslateDesk_TranslateCore.resources", isDirectory: true)
                .appendingPathComponent(filename)
        )

        for bundleName in ["TranslateDesk_TranslateCore.resources", "TranslateDesk_TranslateCore.bundle"] {
            if let resourceURL = Bundle.main.resourceURL {
                candidates.append(
                    resourceURL
                        .appendingPathComponent(bundleName, isDirectory: true)
                        .appendingPathComponent(filename)
                )
            }
            candidates.append(
                executableDirectory
                    .appendingPathComponent(bundleName, isDirectory: true)
                    .appendingPathComponent(filename)
            )
        }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private struct IndexedDictionaryRecord {
    var displayTerm: String
    var body: String
}

private final class IndexedDictionaryFile: @unchecked Sendable {
    private static let magic = Array("TDICT01\0".utf8)
    private static let headerSize = 40
    private static let indexHeaderSize = 16

    private let data: Data
    private let offsetTableOffset: Int
    private let dataOffset: Int
    let count: Int

    init(url: URL) throws {
        let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard mapped.count >= Self.headerSize else {
            throw IndexedDictionaryError.invalidFile("文件头不完整")
        }
        guard Array(mapped[0..<8]) == Self.magic else {
            throw IndexedDictionaryError.invalidFile("Magic 不匹配")
        }
        let version = Int(mapped.readUInt32LE(at: 8))
        guard version == 1 else {
            throw IndexedDictionaryError.invalidFile("不支持版本 \(version)")
        }
        let parsedCount = Int(mapped.readUInt32LE(at: 12))
        let parsedOffsetTable = Int(mapped.readUInt64LE(at: 16))
        let parsedDataOffset = Int(mapped.readUInt64LE(at: 32))
        guard parsedCount >= 0,
              parsedOffsetTable >= Self.headerSize,
              parsedOffsetTable + parsedCount * 8 <= mapped.count,
              parsedDataOffset >= parsedOffsetTable,
              parsedDataOffset <= mapped.count else {
            throw IndexedDictionaryError.invalidFile("索引边界无效")
        }
        data = mapped
        count = parsedCount
        offsetTableOffset = parsedOffsetTable
        dataOffset = parsedDataOffset
    }

    func lookup(_ normalizedKey: String) -> IndexedDictionaryRecord? {
        let sought = Array(normalizedKey.utf8)
        guard !sought.isEmpty else { return nil }
        var low = 0
        var high = count
        while low < high {
            let mid = low + (high - low) / 2
            guard let record = recordMetadata(at: mid) else { return nil }
            let comparison = compare(record.keyRange, to: sought)
            if comparison < 0 {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < count,
              let record = recordMetadata(at: low),
              compare(record.keyRange, to: sought) == 0,
              record.contentStart >= 0,
              record.contentLength >= 0,
              record.contentStart + record.contentLength <= data.count else {
            return nil
        }
        return IndexedDictionaryRecord(
            displayTerm: String(decoding: data[record.displayRange], as: UTF8.self),
            body: String(decoding: data[record.contentStart..<(record.contentStart + record.contentLength)], as: UTF8.self)
        )
    }

    func suggestions(prefix: String, limit: Int) -> [String] {
        let sought = Array(prefix.utf8)
        guard !sought.isEmpty, limit > 0 else { return [] }
        var low = 0
        var high = count
        while low < high {
            let mid = low + (high - low) / 2
            guard let record = recordMetadata(at: mid) else { return [] }
            if compare(record.keyRange, to: sought) < 0 {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var output: [String] = []
        var index = low
        while index < count, output.count < limit {
            guard let record = recordMetadata(at: index) else { break }
            let key = Array(data[record.keyRange])
            guard key.starts(with: sought) else { break }
            let display = String(decoding: data[record.displayRange], as: UTF8.self)
            if output.last != display { output.append(display) }
            index += 1
        }
        return output
    }

    private struct Metadata {
        var keyRange: Range<Int>
        var displayRange: Range<Int>
        var contentStart: Int
        var contentLength: Int
    }

    private func recordMetadata(at index: Int) -> Metadata? {
        guard index >= 0, index < count else { return nil }
        let tablePosition = offsetTableOffset + index * 8
        let recordOffset = Int(data.readUInt64LE(at: tablePosition))
        guard recordOffset >= 0, recordOffset + Self.indexHeaderSize <= data.count else { return nil }
        let keyLength = Int(data.readUInt16LE(at: recordOffset))
        let displayLength = Int(data.readUInt16LE(at: recordOffset + 2))
        let relativeContentOffset = Int(data.readUInt64LE(at: recordOffset + 4))
        let contentLength = Int(data.readUInt32LE(at: recordOffset + 12))
        let keyStart = recordOffset + Self.indexHeaderSize
        let displayStart = keyStart + keyLength
        guard displayStart + displayLength <= dataOffset else { return nil }
        return Metadata(
            keyRange: keyStart..<(keyStart + keyLength),
            displayRange: displayStart..<(displayStart + displayLength),
            contentStart: dataOffset + relativeContentOffset,
            contentLength: contentLength
        )
    }

    private func compare(_ range: Range<Int>, to sought: [UInt8]) -> Int {
        let keyCount = range.count
        let shared = min(keyCount, sought.count)
        for offset in 0..<shared {
            let lhs = data[range.lowerBound + offset]
            let rhs = sought[offset]
            if lhs < rhs { return -1 }
            if lhs > rhs { return 1 }
        }
        if keyCount < sought.count { return -1 }
        if keyCount > sought.count { return 1 }
        return 0
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func readUInt64LE(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(self[offset + index]) << UInt64(index * 8)
        }
        return value
    }
}
