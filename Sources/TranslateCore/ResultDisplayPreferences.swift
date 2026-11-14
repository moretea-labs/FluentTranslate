import Foundation

public struct ResultDisplayPreferences: Codable, Equatable, Sendable {
    public var selectedFilterKey: String
    public var collapsedDictionaryIDs: Set<String>
    public var groupExpansion: [String: Bool]
    public var groupDetailExpansion: [String: Bool]

    public init(
        selectedFilterKey: String = ResultFilterKey.all,
        collapsedDictionaryIDs: Set<String> = [],
        groupExpansion: [String: Bool] = [:],
        groupDetailExpansion: [String: Bool] = [:]
    ) {
        self.selectedFilterKey = selectedFilterKey
        self.collapsedDictionaryIDs = collapsedDictionaryIDs
        self.groupExpansion = groupExpansion
        self.groupDetailExpansion = groupDetailExpansion
    }
    /// Filtering is specific to one query. Smart queries start with a short
    /// dictionary summary; explicit dictionary mode retains the user's layout.
    public mutating func resetForNewQuery(summarizeDictionaries: Bool) {
        selectedFilterKey = ResultFilterKey.all
        if summarizeDictionaries {
            collapsedDictionaryIDs.removeAll()
            groupExpansion.removeAll()
            groupDetailExpansion.removeAll()
        }
    }
}

public enum ResultFilterKey {
    public static let all = "all"
    public static let translation = "translation"
    public static let expression = "expression"

    public static func dictionary(_ dictionaryID: String) -> String {
        "dictionary:\(dictionaryID)"
    }

    public static func dictionaryID(from key: String) -> String? {
        let prefix = "dictionary:"
        guard key.hasPrefix(prefix) else { return nil }
        let value = String(key.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}

public final class ResultDisplayPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "TranslateDesk.ResultDisplayPreferences.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func load() -> ResultDisplayPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(ResultDisplayPreferences.self, from: data) else {
            return ResultDisplayPreferences()
        }
        return value
    }

    public func save(_ value: ResultDisplayPreferences) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
