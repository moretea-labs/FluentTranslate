import AppKit
import Foundation
import CSQLite

final class LocalDictionaryService {
    static let shared = LocalDictionaryService()

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluentTranslate", isDirectory: true)
    }

    private var ecdictDatabaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("ecdict.sqlite")
    }

    private var bundledDatabaseURL: URL? {
        if let packageURL = Bundle.module.url(
            forResource: "collins_cobuild3",
            withExtension: "sqlite",
            subdirectory: "Dictionaries"
        ) ?? Bundle.module.url(forResource: "collins_cobuild3", withExtension: "sqlite") {
            return packageURL
        }

        let appResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Dictionaries", isDirectory: true)
            .appendingPathComponent("collins_cobuild3.sqlite")
        if let appResourceURL, FileManager.default.fileExists(atPath: appResourceURL.path) {
            return appResourceURL
        }
        return nil
    }

    var status: DictionaryStatus {
        let metadata = bundledDatabaseURL.flatMap(readMetadata)
        return DictionaryStatus(
            bundledAvailable: bundledDatabaseURL != nil,
            bundledName: metadata?["source_name"],
            bundledEntryCount: metadata?["entry_count"].flatMap(Int.init),
            ecdictAvailable: FileManager.default.fileExists(atPath: ecdictDatabaseURL.path)
        )
    }

    func lookup(_ rawText: String) -> DictionaryEntry? {
        let text = dictionaryLookupKey(rawText)
        guard isLookupCandidate(text) else { return nil }

        let bundled = bundledDatabaseURL.flatMap { lookupBundled(text, databaseURL: $0) }
        let ecdict = FileManager.default.fileExists(atPath: ecdictDatabaseURL.path)
            ? lookupECDICT(text, databaseURL: ecdictDatabaseURL)
            : nil

        switch (bundled, ecdict) {
        case let (bundled?, ecdict?):
            return DictionaryEntry(
                word: bundled.word,
                phonetic: ecdict.phonetic ?? bundled.phonetic,
                englishDefinition: bundled.englishDefinition ?? ecdict.englishDefinition,
                chineseDefinition: ecdict.chineseDefinition,
                partOfSpeech: ecdict.partOfSpeech ?? bundled.partOfSpeech,
                exchange: ecdict.exchange,
                sourceName: [bundled.sourceName, ecdict.sourceName]
                    .compactMap { $0 }
                    .joined(separator: " + ")
            )
        case let (bundled?, nil):
            return bundled
        case let (nil, ecdict?):
            return ecdict
        case (nil, nil):
            return nil
        }
    }

    func revealDatabaseFolder() {
        try? FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([applicationSupportDirectory])
    }

    private func dictionaryLookupKey(_ value: String) -> String {
        let trimCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,!?;:()[]{}<>\"“”‘’"))
        return value.trimmingCharacters(in: trimCharacters)
    }

    private func isLookupCandidate(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 100 else { return false }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count <= 8 else { return false }
        return text.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func lookupBundled(_ text: String, databaseURL: URL) -> DictionaryEntry? {
        withReadOnlyDatabase(databaseURL) { db in
            let sql = """
            SELECT headword, plain_text, source_name
            FROM dictionary_entries
            WHERE normalized_headword = ?
            ORDER BY length(headword) ASC
            LIMIT 1;
            """
            guard let row = queryOne(db: db, sql: sql, value: normalized(text), columnCount: 3) else {
                return nil
            }

            return DictionaryEntry(
                word: row[0] ?? text,
                phonetic: nil,
                englishDefinition: row[1].map(cleanDictionaryText),
                chineseDefinition: nil,
                partOfSpeech: nil,
                exchange: nil,
                sourceName: row[2]
            )
        }
    }

    private func lookupECDICT(_ text: String, databaseURL: URL) -> DictionaryEntry? {
        withReadOnlyDatabase(databaseURL) { db in
            let sql = """
            SELECT word, phonetic, definition, translation, pos, exchange
            FROM stardict
            WHERE lower(word) = lower(?)
            LIMIT 1;
            """
            guard let row = queryOne(db: db, sql: sql, value: text, columnCount: 6) else {
                return nil
            }

            return DictionaryEntry(
                word: row[0] ?? text,
                phonetic: row[1],
                englishDefinition: row[2],
                chineseDefinition: row[3],
                partOfSpeech: row[4],
                exchange: row[5],
                sourceName: "ECDICT"
            )
        }
    }

    private func withReadOnlyDatabase<T>(_ url: URL, body: (OpaquePointer) -> T?) -> T? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return nil
        }
        defer { sqlite3_close(database) }
        return body(database)
    }

    private func queryOne(
        db: OpaquePointer,
        sql: String,
        value: String,
        columnCount: Int32
    ) -> [String?]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, transient)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return (0..<columnCount).map { index in
            guard let cString = sqlite3_column_text(statement, index) else { return nil }
            let result = String(cString: cString)
            return result.isEmpty ? nil : result
        }
    }

    private func readMetadata(_ url: URL) -> [String: String]? {
        withReadOnlyDatabase(url) { db in
            let sql = "SELECT key, value FROM dictionary_metadata;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                return nil
            }
            defer { sqlite3_finalize(statement) }

            var result: [String: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let keyCString = sqlite3_column_text(statement, 0),
                      let valueCString = sqlite3_column_text(statement, 1) else {
                    continue
                }
                result[String(cString: keyCString)] = String(cString: valueCString)
            }
            return result
        }
    }

    private func cleanDictionaryText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "◆", with: "")
            .replacingOccurrences(of: "◇", with: "")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
