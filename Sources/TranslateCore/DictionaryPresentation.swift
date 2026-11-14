import Foundation

public struct DictionaryPresentation: Hashable, Sendable {
    public var headword: String
    public var pronunciation: String?
    public var senses: [DictionarySense]
    public var relatedTerms: [String]
    public var rawText: String

    public init(
        headword: String,
        pronunciation: String? = nil,
        senses: [DictionarySense],
        relatedTerms: [String] = [],
        rawText: String
    ) {
        self.headword = headword
        self.pronunciation = pronunciation
        self.senses = senses
        self.relatedTerms = relatedTerms
        self.rawText = rawText
    }
}

public struct DictionarySense: Hashable, Sendable {
    public var number: String?
    public var heading: String?
    public var definitions: [DictionaryDefinition]
    public var notes: [String]

    public init(
        number: String? = nil,
        heading: String? = nil,
        definitions: [DictionaryDefinition] = [],
        notes: [String] = []
    ) {
        self.number = number
        self.heading = heading
        self.definitions = definitions
        self.notes = notes
    }
}

public struct DictionaryDefinition: Hashable, Sendable {
    public var text: String
    public var translation: String?
    public var examples: [DictionaryExample]

    public init(text: String, translation: String? = nil, examples: [DictionaryExample] = []) {
        self.text = text
        self.translation = translation
        self.examples = examples
    }
}

public struct DictionaryExample: Hashable, Sendable {
    public var source: String
    public var translation: String?

    public init(source: String, translation: String? = nil) {
        self.source = source
        self.translation = translation
    }
}

public enum DictionarySenseCategory: String, CaseIterable, Hashable, Sendable {
    case verb
    case noun
    case adjective
    case adverb
    case pronoun
    case preposition
    case conjunction
    case determiner
    case interjection
    case phrase
    case idiom
    case other

    public var displayName: String {
        switch self {
        case .verb: return "动词"
        case .noun: return "名词"
        case .adjective: return "形容词"
        case .adverb: return "副词"
        case .pronoun: return "代词"
        case .preposition: return "介词"
        case .conjunction: return "连词"
        case .determiner: return "限定词与数量词"
        case .interjection: return "感叹与交际用语"
        case .phrase: return "短语与固定搭配"
        case .idiom: return "习语"
        case .other: return "其他释义"
        }
    }
}

public struct DictionarySenseGroup: Identifiable, Hashable, Sendable {
    public var id: String { category.rawValue }
    public var category: DictionarySenseCategory
    public var senses: [DictionarySense]

    public init(category: DictionarySenseCategory, senses: [DictionarySense]) {
        self.category = category
        self.senses = senses
    }

    public var title: String { category.displayName }
}

public extension DictionaryPresentation {
    /// A stable, presentation-ready grouping used by the result UI. Keeping this
    /// in TranslateCore makes the classification reusable by future views and
    /// avoids reparsing dictionary text during every SwiftUI refresh.
    var senseGroups: [DictionarySenseGroup] {
        DictionarySenseGrouper.group(senses)
    }
}

public enum DictionarySenseGrouper {
    public static func group(_ senses: [DictionarySense]) -> [DictionarySenseGroup] {
        var order: [DictionarySenseCategory] = []
        var grouped: [DictionarySenseCategory: [DictionarySense]] = [:]

        for sense in senses {
            let category = category(for: sense.heading)
            if grouped[category] == nil { order.append(category) }
            grouped[category, default: []].append(sense)
        }

        return order.compactMap { category in
            guard let values = grouped[category], !values.isEmpty else { return nil }
            return DictionarySenseGroup(category: category, senses: values)
        }
    }

    public static func category(for heading: String?) -> DictionarySenseCategory {
        guard let heading else { return .other }
        let value = heading.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Check the more specific phrase categories before plain verb/noun.
        if value.contains("idiom") { return .idiom }
        if value.contains("phrasal") || value.contains("phrase") || value.contains("expression") {
            return .phrase
        }
        // Check words that contain another part-of-speech name first:
        // "adverb" contains "verb" and "pronoun" contains "noun".
        if containsAny(value, ["adverb", "[adv", " adv "]) { return .adverb }
        if containsAny(value, ["pronoun", "[pron"]) { return .pronoun }
        if containsAny(value, ["adjective", "[adj", " adj "]) { return .adjective }
        if containsAny(value, ["preposition", "[prep"]) { return .preposition }
        if containsAny(value, ["verb", "[v]", "[v ", "[vi]", "[vt]", "[aux", "modal"]) { return .verb }
        if containsAny(value, ["noun", "[n]", "[n ", "n count", "n uncount", "n var", "n mass", "proper noun"]) { return .noun }
        if containsAny(value, ["conjunction", "[conj"]) { return .conjunction }
        if containsAny(value, ["determiner", "[det", "[quant", "quantifier", "number"]) { return .determiner }
        if containsAny(value, ["interjection", "[interj", "[convention", "[exclamation", "greeting"]) { return .interjection }
        return .other
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }
}

public enum DictionaryPresentationParser {
    public static func parse(_ result: DictionaryLookupResult) -> DictionaryPresentation {
        guard let body = result.entry.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else {
            return parseStructured(result)
        }

        switch result.dictionaryID {
        case "cambridge-en-zh":
            return parseCambridge(body: body, headword: result.entry.term)
        case "collins-cobuild-en":
            return parseCollins(body: body, headword: result.entry.term)
        case "collins-han-en":
            return parseHanEnglish(body: body, headword: result.entry.term)
        default:
            return parseGeneric(body: body, headword: result.entry.term)
        }
    }

    private static func parseStructured(_ result: DictionaryLookupResult) -> DictionaryPresentation {
        let definitions = result.entry.englishDefinitions.enumerated().map { index, definition in
            DictionaryDefinition(
                text: definition,
                translation: index == 0 ? result.entry.translations["zh"] : nil,
                examples: index == 0 ? result.entry.examples.map { DictionaryExample(source: $0) } : []
            )
        }
        let fallback = definitions.isEmpty && !result.entry.translations.isEmpty
            ? [DictionaryDefinition(text: result.entry.translations.values.sorted().joined(separator: "；"))]
            : definitions
        return DictionaryPresentation(
            headword: result.entry.term,
            senses: [DictionarySense(definitions: fallback)],
            rawText: result.entry.bodyText ?? result.entry.englishDefinitions.joined(separator: "\n")
        )
    }

    private static func parseCambridge(body: String, headword: String) -> DictionaryPresentation {
        var lines = normalizedLines(body)
        let normalizedHeadword = normalized(headword)

        // Large Cambridge entries begin with a table of contents ("1. verb ...").
        // The actual entry starts at the first standalone sense number.
        if lines.first.map(isOutlineLine) == true,
           let firstSense = lines.firstIndex(where: isStandaloneNumber) {
            lines.removeFirst(firstSense)
        }

        var senses: [DictionarySense] = []
        var current: SenseBuilder?
        var relatedTerms: [String] = []
        var inRelatedTerms = false
        var index = 0

        func flushCurrent() {
            guard let builder = current, !builder.isEmpty else {
                current = nil
                return
            }
            senses.append(builder.build())
            current = nil
        }

        while index < lines.count {
            let line = lines[index]

            if line.caseInsensitiveCompare("Related Phrases/Idioms") == .orderedSame {
                flushCurrent()
                inRelatedTerms = true
                index += 1
                continue
            }

            if inRelatedTerms {
                if isStandaloneNumber(line) {
                    inRelatedTerms = false
                    continue
                }
                if !line.isEmpty { relatedTerms.append(line) }
                index += 1
                continue
            }

            if isStandaloneNumber(line) {
                flushCurrent()
                current = SenseBuilder(number: line)
                index += 1
                if index < lines.count, normalized(lines[index]) == normalizedHeadword {
                    index += 1
                }
                if index < lines.count, !lines[index].hasPrefix("›") {
                    current?.heading = cleanedHeading(lines[index])
                    index += 1
                }
                continue
            }

            if current == nil {
                current = SenseBuilder()
                if normalized(line) == normalizedHeadword {
                    index += 1
                    continue
                }
                current?.heading = cleanedHeading(line)
                index += 1
                continue
            }

            // A phrase immediately followed by a definition marker is a Cambridge
            // sub-entry. Give it its own visual section instead of flattening it.
            if index + 1 < lines.count,
               !line.hasPrefix("›"),
               lines[index + 1].hasPrefix("›"),
               !containsCJK(line) {
                flushCurrent()
                current = SenseBuilder(heading: cleanedHeading(line))
                index += 1
                continue
            }

            if line.hasPrefix("›") {
                let definitionText = line.dropFirst().trimmingCharacters(in: .whitespaces)
                var translation: String?
                if index + 1 < lines.count, containsCJK(lines[index + 1]) {
                    translation = lines[index + 1]
                    index += 1
                }
                current?.definitions.append(
                    DefinitionBuilder(text: definitionText, translation: translation)
                )
                index += 1
                continue
            }

            if current?.definitions.isEmpty == true {
                current?.notes.append(line)
                index += 1
                continue
            }

            if containsCJK(line), var last = current?.definitions.popLast() {
                if let bilingual = splitBilingualLine(line) {
                    last.examples.append(DictionaryExample(source: bilingual.source, translation: bilingual.translation))
                } else if var example = last.examples.popLast(), example.translation == nil {
                    example.translation = line
                    last.examples.append(example)
                } else if last.translation == nil {
                    last.translation = line
                } else {
                    last.examples.append(DictionaryExample(source: line))
                }
                current?.definitions.append(last)
            } else {
                current?.appendExample(line)
            }
            index += 1
        }

        flushCurrent()
        let pronunciation = firstPronunciation(in: lines)
        return DictionaryPresentation(
            headword: headword,
            pronunciation: pronunciation,
            senses: senses.isEmpty ? parseGeneric(body: body, headword: headword).senses : senses,
            relatedTerms: relatedTerms,
            rawText: body
        )
    }

    private static func parseCollins(body: String, headword: String) -> DictionaryPresentation {
        let lines = normalizedLines(body)
        var senses: [DictionarySense] = []
        var current: SenseBuilder?

        func flushCurrent() {
            guard let builder = current, !builder.isEmpty else {
                current = nil
                return
            }
            senses.append(builder.build())
            current = nil
        }

        for line in lines {
            if isCollinsHeading(line, headword: headword) {
                flushCurrent()
                current = SenseBuilder(heading: cleanedCollinsHeading(line))
                continue
            }

            if current == nil {
                current = SenseBuilder()
            }

            if current?.definitions.isEmpty == true {
                current?.definitions.append(DefinitionBuilder(text: line))
            } else if line.hasPrefix("=") || line.hasPrefix("(") {
                current?.notes.append(line)
            } else {
                current?.appendExample(line)
            }
        }

        flushCurrent()
        return DictionaryPresentation(
            headword: headword,
            senses: senses.isEmpty ? parseGeneric(body: body, headword: headword).senses : senses,
            rawText: body
        )
    }

    /// Collins 汉英正文包含中文义项 + 英文对应词，以及逐行配对的双语例句。
    private static func parseHanEnglish(body: String, headword: String) -> DictionaryPresentation {
        var lines = normalizedLines(body)
        if lines.first.map({ normalized($0) == normalized(headword) }) == true {
            lines.removeFirst()
        }

        var senses: [DictionarySense] = []
        var current: DictionarySense?

        func flush() {
            if let current, !current.definitions.isEmpty {
                senses.append(current)
            }
            current = nil
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            // “安排to deploy”, “【自;信】interface”, “译员translator; interpreter”.
            if let boundary = line.firstIndex(where: { $0.isASCII && $0.isLetter }),
               boundary > line.startIndex {
                let heading = String(line[..<boundary]).trimmingCharacters(in: .whitespaces)
                let meaning = String(line[boundary...]).trimmingCharacters(in: .whitespaces)
                if containsCJK(heading), !meaning.isEmpty {
                    flush()
                    current = DictionarySense(
                        heading: heading,
                        definitions: [DictionaryDefinition(text: meaning)]
                    )
                    index += 1
                    continue
                }
            }

            if current == nil {
                if containsCJK(line), index + 1 < lines.count,
                   !containsCJK(lines[index + 1]) {
                    current = DictionarySense(
                        heading: line,
                        definitions: [DictionaryDefinition(text: lines[index + 1])]
                    )
                    index += 2
                } else {
                    current = DictionarySense(definitions: [DictionaryDefinition(text: line)])
                    index += 1
                }
                continue
            }

            if containsCJK(line), index + 1 < lines.count,
               !containsCJK(lines[index + 1]) {
                var sense = current!
                var definition = sense.definitions.removeLast()
                definition.examples.append(DictionaryExample(source: line, translation: lines[index + 1]))
                sense.definitions.append(definition)
                current = sense
                index += 2
                continue
            }

            current?.notes.append(line)
            index += 1
        }
        flush()
        return DictionaryPresentation(headword: headword, senses: senses, rawText: body)
    }

    private static func parseGeneric(body: String, headword: String) -> DictionaryPresentation {
        var lines = normalizedLines(body)
        if lines.first.map({ normalized($0) == normalized(headword) }) == true {
            lines.removeFirst()
        }
        guard let first = lines.first else {
            return DictionaryPresentation(headword: headword, senses: [], rawText: body)
        }
        let examples = lines.dropFirst().map { DictionaryExample(source: $0) }
        return DictionaryPresentation(
            headword: headword,
            senses: [DictionarySense(definitions: [DictionaryDefinition(text: first, examples: examples)])],
            rawText: body
        )
    }

    private static func normalizedLines(_ body: String) -> [String] {
        body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isStandaloneNumber(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private static func isOutlineLine(_ value: String) -> Bool {
        guard let dot = value.firstIndex(of: ".") else { return false }
        let prefix = value[..<dot]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber)
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF: return true
            default: return false
            }
        }
    }

    private static func splitBilingualLine(_ value: String) -> (source: String, translation: String)? {
        guard let boundary = value.firstIndex(where: { character in
            character.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF: return true
                default: return false
                }
            }
        }) else { return nil }
        let source = value[..<boundary].trimmingCharacters(in: .whitespaces)
        let translation = value[boundary...].trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty, !translation.isEmpty else { return nil }
        return (source, translation)
    }

    private static func firstPronunciation(in lines: [String]) -> String? {
        for line in lines {
            guard let start = line.firstIndex(of: "/") else { continue }
            let remainder = line[line.index(after: start)...]
            guard let relativeEnd = remainder.firstIndex(of: "/") else { continue }
            let value = remainder[..<relativeEnd].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return "/\(value)/" }
        }
        return nil
    }

    private static func cleanedHeading(_ value: String) -> String {
        var output = value
        if let firstSlash = output.firstIndex(of: "/") {
            let tail = output[output.index(after: firstSlash)...]
            if let secondSlash = tail.firstIndex(of: "/") {
                output.removeSubrange(firstSlash...secondSlash)
            }
        }
        output = output.replacingOccurrences(of: " uk us ", with: " ")
        output = output.replacingOccurrences(of: "  ", with: " ")
        return output.trimmingCharacters(in: .whitespaces)
    }

    private static func isCollinsHeading(_ value: String, headword: String) -> Bool {
        let lower = value.lowercased()
        let term = headword.lowercased()
        return (lower == term || lower.hasPrefix(term + " ")) && value.contains("[") && value.contains("]")
    }

    private static func cleanedCollinsHeading(_ value: String) -> String {
        guard let opening = value.firstIndex(of: "["),
              let closing = value[opening...].firstIndex(of: "]") else {
            return value
        }
        var result = String(value[opening...closing])
        let suffix = value[value.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        if !suffix.isEmpty { result += " · \(suffix)" }
        return result
    }
}

private struct SenseBuilder {
    var number: String?
    var heading: String?
    var definitions: [DefinitionBuilder] = []
    var notes: [String] = []

    init(number: String? = nil, heading: String? = nil) {
        self.number = number
        self.heading = heading
    }

    var isEmpty: Bool {
        number == nil && heading == nil && definitions.isEmpty && notes.isEmpty
    }

    mutating func appendExample(_ value: String) {
        guard var last = definitions.popLast() else {
            notes.append(value)
            return
        }
        last.examples.append(DictionaryExample(source: value))
        definitions.append(last)
    }

    func build() -> DictionarySense {
        DictionarySense(
            number: number,
            heading: heading,
            definitions: definitions.map(\.value),
            notes: notes
        )
    }
}

private struct DefinitionBuilder {
    var text: String
    var translation: String?
    var examples: [DictionaryExample] = []

    var value: DictionaryDefinition {
        DictionaryDefinition(text: text, translation: translation, examples: examples)
    }
}
