import SwiftUI

struct ResultCard: View {
    let title: String
    let systemImage: String
    let text: String
    let primary: Bool
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Button(action: onSpeak) { Image(systemName: "speaker.wave.2") }
                    .buttonStyle(.borderless)
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                if primary {
                    Button(action: onReplace) {
                        Label("替换", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onReplace) {
                        Label("替换", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(text)
                .font(primary ? .body : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.background.opacity(primary ? 0.9 : 0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.12)))
    }
}

struct OfflineDictionaryCard: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("离线词典", systemImage: "books.vertical")
                        .font(.headline)
                    if let source = entry.sourceName, !source.isEmpty {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    SpeechService.shared.speak(entry.word)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(entry.word).font(.title3.bold())
                if let phonetic = entry.phonetic, !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let part = entry.partOfSpeech, !part.isEmpty {
                    Text(part)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let definition = entry.englishDefinition, !definition.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("英英释义").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(definition.replacingOccurrences(of: "\\n", with: "\n"))
                        .textSelection(.enabled)
                }
            }
            if let translation = entry.chineseDefinition, !translation.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("中文释义").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(translation.replacingOccurrences(of: "\\n", with: "\n"))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TermsCard: View {
    let terms: [TranslationTerm]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("单词与词组", systemImage: "text.book.closed")
                .font(.headline)

            ForEach(terms) { term in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(term.text).font(.body.bold())
                        if let part = term.partOfSpeech, !part.isEmpty {
                            Text(part).font(.caption).foregroundStyle(.secondary)
                        }
                        if let phonetic = term.phonetic, !phonetic.isEmpty {
                            Text(phonetic).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            SpeechService.shared.speak(term.text)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(term.englishDefinition)
                    Text(term.chineseDefinition).foregroundStyle(.secondary)
                    ForEach(term.examples.prefix(2), id: \.self) { example in
                        Text("• \(example)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let note = term.usageNote, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if term.id != terms.last?.id { Divider() }
            }
        }
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ExplanationCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("为什么这样表达", systemImage: "lightbulb")
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OutputSectionHeader: View {
    let number: Int
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}


struct TranslationUnavailableCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "network.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("暂未生成翻译")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QueryExplanationCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("释义与用法", systemImage: "magnifyingglass")
                .font(.headline)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}
