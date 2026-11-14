import Foundation

/// Accent selection and dictionary audio metadata shared by the macOS UI and tests.
public enum EnglishAccent: String, CaseIterable, Codable, Sendable {
    case american = "en-US"
    case british = "en-GB"

    public var title: String {
        switch self {
        case .american: "美音"
        case .british: "英音"
        }
    }
}

public struct EnglishPronunciationEntry: Decodable, Sendable {
    public struct Phonetic: Decodable, Sendable {
        public let text: String?
        public let audio: String?
    }

    public let word: String?
    public let phonetic: String?
    public let phonetics: [Phonetic]?

    /// An accent-specific transcription is only labelled when the audio URL
    /// identifies that accent. Generic transcriptions remain unlabelled.
    public func localizedIPA(for accent: EnglishAccent) -> String? {
        phonetics?.first { item in
            Self.matches(item.audio, accent: accent) && !(item.text?.isEmpty ?? true)
        }?.text
    }

    public func ipa(for accent: EnglishAccent) -> String? {
        localizedIPA(for: accent)
            ?? phonetic?.nilIfEmpty
            ?? phonetics?.compactMap { $0.text?.nilIfEmpty }.first
    }

    public func audioURL(for accent: EnglishAccent) -> URL? {
        phonetics?.compactMap { item -> URL? in
            guard Self.matches(item.audio, accent: accent),
                  let raw = item.audio,
                  let url = URL(string: raw),
                  url.scheme == "https",
                  url.host == "api.dictionaryapi.dev" else { return nil }
            return url
        }.first
    }

    private static func matches(_ audio: String?, accent: EnglishAccent) -> Bool {
        guard let audio, let url = URL(string: audio) else { return false }
        let filename = url.lastPathComponent.lowercased()
        switch accent {
        case .american:
            return filename.hasSuffix("-us.mp3") || filename.hasSuffix("_us.mp3")
        case .british:
            return filename.hasSuffix("-uk.mp3") || filename.hasSuffix("-gb.mp3")
                || filename.hasSuffix("_uk.mp3") || filename.hasSuffix("_gb.mp3")
        }
    }
}

/// Only a single English headword (optionally prefixed by "to") may show
/// a word-level IPA. Do not misleadingly attach one word's IPA to a phrase.
public enum EnglishMeaningHeadword {
    public static func extract(from meaning: String) -> String? {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.lowercased().hasPrefix("to ")
            ? String(trimmed.dropFirst(3))
            : trimmed
        guard candidate.range(
            of: "^[A-Za-z][A-Za-z'-]{0,63}$",
            options: .regularExpression
        ) != nil else { return nil }
        return candidate.lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
