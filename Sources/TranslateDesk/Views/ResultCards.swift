#if os(macOS)
import SwiftUI
import TranslateCore

struct DictionaryResultCard: View {
    let result: DictionaryLookupResult
    let presentation: DictionaryPresentation
    let pronunciation: String?
    let collapsed: Bool
    let defaultFirstGroupExpanded: Bool
    let isGroupExpanded: (String, Bool) -> Bool
    let isGroupFullyExpanded: (String) -> Bool
    let onToggleCollapsed: () -> Void
    let onSetGroupExpanded: (String, Bool) -> Void
    let onSetGroupFullyExpanded: (String, Bool) -> Void
    let onSetAllGroupsExpanded: ([String], Bool) -> Void
    let onSetAllGroupDetailsExpanded: ([String], Bool) -> Void
    let onResetLayout: () -> Void
    let onCopy: (String) -> Void
    let onSpeak: (String) -> Void

    private var groups: [DictionarySenseGroup] { presentation.senseGroups }
    private var relatedGroupID: String { "related-terms" }
    private var allGroupIDs: [String] {
        groups.map(\.id) + (presentation.relatedTerms.isEmpty ? [] : [relatedGroupID])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dictionaryHeader
                .padding(.vertical, 9)

            if !collapsed {
                dictionaryContent
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .padding(.vertical, 4)
    }

    private var dictionaryHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button(action: onToggleCollapsed) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.bold())
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(collapsed ? "展开这本词典" : "收起这本词典")

                Text(result.dictionaryName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                dictionaryTypeBadge
                Spacer()

                Text("\(presentation.senses.count) 词义")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button { onSpeak(presentation.headword) } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .help("使用 macOS 系统语音朗读词头")

                Menu {
                    Button("复制词头") { onCopy(presentation.headword) }
                    Button("复制完整释义") { onCopy(presentation.rawText) }
                    Divider()
                    Button("展开所有分类") {
                        if collapsed { onToggleCollapsed() }
                        onSetAllGroupsExpanded(allGroupIDs, true)
                    }
                    Button("收起所有分类") {
                        onSetAllGroupsExpanded(allGroupIDs, false)
                    }
                    Button("展开所有词义与例句") {
                        if collapsed { onToggleCollapsed() }
                        onSetAllGroupsExpanded(allGroupIDs, true)
                        onSetAllGroupDetailsExpanded(allGroupIDs, true)
                    }
                    Divider()
                    Button("恢复默认摘要布局") {
                        onResetLayout()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.headword)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)
                if let pronunciation {
                    Text(pronunciation)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if collapsed {
                    Text("已收起 · 点击左侧箭头展开")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var dictionaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if groups.isEmpty {
                Text(presentation.rawText)
                    .font(.system(size: 15.5))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    DictionarySenseGroupView(
                        group: group,
                        englishMeanings: result.dictionaryID == "collins-han-en",
                        expanded: isGroupExpanded(group.id, index == 0 && defaultFirstGroupExpanded),
                        fullyExpanded: isGroupFullyExpanded(group.id),
                        accent: accentColor,
                        onSetExpanded: { onSetGroupExpanded(group.id, $0) },
                        onSetFullyExpanded: { onSetGroupFullyExpanded(group.id, $0) }
                    )
                }
            }

            if !presentation.relatedTerms.isEmpty {
                DictionaryRelatedTermsView(
                    terms: presentation.relatedTerms,
                    expanded: isGroupExpanded(relatedGroupID, false),
                    fullyExpanded: isGroupFullyExpanded(relatedGroupID),
                    accent: accentColor,
                    onSetExpanded: { onSetGroupExpanded(relatedGroupID, $0) },
                    onSetFullyExpanded: { onSetGroupFullyExpanded(relatedGroupID, $0) }
                )
            }
        }
    }

    private var dictionaryTypeBadge: some View {
        Text(result.dictionaryID == "cambridge-en-zh" ? "英汉双解"
             : result.dictionaryID == "collins-han-en" ? "汉英"
             : result.dictionaryID == "collins-cobuild-en" ? "英英" : "本地")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var dictionaryIcon: String {
        result.dictionaryID == "cambridge-en-zh" ? "character.book.closed.fill" : "text.book.closed.fill"
    }

    private var accentColor: Color {
        result.dictionaryID == "cambridge-en-zh" ? .accentColor : .secondary
    }
}

/// One pronunciation affordance directly beside the English meaning,
/// shared by the detailed and quick translation views.
struct EnglishMeaningLine: View {
    @EnvironmentObject private var model: AppModel
    let text: String
    let fontSize: CGFloat
    let showsIPA: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(size: fontSize, weight: showsIPA ? .medium : .regular))
                .lineSpacing(3)
                .textSelection(.enabled)
                .layoutPriority(1)

            if showsIPA, let ipa = model.ipaForEnglishMeaning(text) {
                Text(ipa)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)

            Button {
                model.speak(text)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("朗读英文（\(model.englishAccent.title)）：\(text)")
            .accessibilityLabel("朗读英文：\(text)")
        }
    }
}

private struct DictionarySenseGroupView: View {
    let group: DictionarySenseGroup
    let englishMeanings: Bool
    let expanded: Bool
    let fullyExpanded: Bool
    let accent: Color
    let onSetExpanded: (Bool) -> Void
    let onSetFullyExpanded: (Bool) -> Void

    private var previewSenseLimit: Int {
        switch group.category {
        case .verb, .noun: return 3
        default: return 2
        }
    }

    private var visibleSenses: ArraySlice<DictionarySense> {
        group.senses.prefix(fullyExpanded ? group.senses.count : previewSenseLimit)
    }

    private var hiddenSenseCount: Int {
        max(0, group.senses.count - previewSenseLimit)
    }

    private var hasHiddenExamples: Bool {
        group.senses.contains { sense in
            sense.definitions.contains { $0.examples.count > 2 }
        }
    }

    private var hasHiddenDetails: Bool {
        hiddenSenseCount > 0 || hasHiddenExamples
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    onSetExpanded(!expanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(group.senses.count) 词义")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !expanded {
                        Text(group.senses.prefix(3).compactMap {
                            $0.definitions.first?.text
                        }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(visibleSenses.enumerated()), id: \.offset) { index, sense in
                        DictionarySenseView(
                            sense: sense,
                            englishMeanings: englishMeanings,
                            showAllExamples: fullyExpanded,
                            accent: accent
                        )
                        if index < visibleSenses.count - 1 {
                            Spacer(minLength: 3)
                        }
                    }

                    if hasHiddenDetails {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                onSetFullyExpanded(!fullyExpanded)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: fullyExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                Text(fullyExpanded ? "恢复该分类摘要" : detailButtonTitle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.leading, 0)
                .padding(.bottom, 9)
            }
        }
    }

    private var detailButtonTitle: String {
        if hiddenSenseCount > 0 {
            return "展开该分类全部 \(group.senses.count) 个词义"
        }
        return "展开该分类全部例句"
    }

    private var categoryIcon: String {
        switch group.category {
        case .verb: return "figure.run"
        case .noun: return "square.text.square"
        case .adjective: return "paintbrush"
        case .adverb: return "speedometer"
        case .pronoun: return "person.text.rectangle"
        case .preposition: return "arrow.left.and.right"
        case .conjunction: return "link"
        case .determiner: return "number"
        case .interjection: return "bubble.left"
        case .phrase: return "text.quote"
        case .idiom: return "quote.bubble"
        case .other: return "text.alignleft"
        }
    }
}

private struct DictionaryRelatedTermsView: View {
    let terms: [String]
    let expanded: Bool
    let fullyExpanded: Bool
    let accent: Color
    let onSetExpanded: (Bool) -> Void
    let onSetFullyExpanded: (Bool) -> Void

    private var visibleTerms: ArraySlice<String> {
        terms.prefix(fullyExpanded ? terms.count : 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    onSetExpanded(!expanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Text("相关短语与习语")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(terms.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 11)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(visibleTerms.joined(separator: "  ·  "))
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    if terms.count > 10 {
                        Button(fullyExpanded ? "恢复短语摘要" : "显示全部 \(terms.count) 条短语") {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                onSetFullyExpanded(!fullyExpanded)
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.leading, 0)
                .padding(.bottom, 9)
            }
        }
    }
}

private struct DictionarySenseView: View {
    let sense: DictionarySense
    let englishMeanings: Bool
    let showAllExamples: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if sense.number != nil || sense.heading != nil {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    if let number = sense.number {
                        Text(number)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, minHeight: 22)
                    }
                    if let heading = sense.heading, !heading.isEmpty {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            ForEach(Array(sense.definitions.enumerated()), id: \.offset) { definitionIndex, definition in
                VStack(alignment: .leading, spacing: 8) {
                    if englishMeanings {
                        EnglishMeaningLine(text: definition.text, fontSize: 16, showsIPA: true)
                    } else {
                        Text(definition.text)
                            .font(.system(size: 16, weight: .medium))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }

                    if let translation = definition.translation, !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: 17, weight: .semibold))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .padding(.leading, 10)
                    }

                    let visibleExamples = showAllExamples
                        ? definition.examples
                        : Array(definition.examples.prefix(2))
                    if !visibleExamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(visibleExamples.enumerated()), id: \.offset) { _, example in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(example.source)
                                        .font(.system(size: 14.5))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if let translation = example.translation, !translation.isEmpty {
                                        if englishMeanings {
                                            EnglishMeaningLine(text: translation, fontSize: 14.5, showsIPA: false)
                                        } else {
                                            Text(translation)
                                                .font(.system(size: 14.5))
                                                .foregroundStyle(Color.primary.opacity(0.82))
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }

                            if !showAllExamples && definition.examples.count > visibleExamples.count {
                                Text("另有 \(definition.examples.count - visibleExamples.count) 个例句")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, 10)
                        .padding(.vertical, 3)
                    }
                }

                if definitionIndex < sense.definitions.count - 1 {
                    Spacer(minLength: 3)
                }
            }

            if !sense.notes.isEmpty {
                Text(sense.notes.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

struct TranslationResultCard: View {
    let result: TranslationResult
    let selected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void

    @State private var showMetadata = false

    private var isShortResult: Bool {
        result.translatedText.count <= 80 && !result.translatedText.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(result.providerName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let model = result.modelName, !model.isEmpty {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if result.fromCache {
                    Text("缓存").font(.caption2).foregroundStyle(.secondary)
                }
                if result.fallbackOccurred {
                    Text("已回退").font(.caption2).foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                if selected {
                    Text("当前")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("当前翻译结果")
                } else {
                    Button("设为当前", action: onSelect)
                        .font(.caption)
                        .buttonStyle(.link)
                }
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制译文")
                .accessibilityLabel("复制译文")
                Button {
                    showMetadata.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("查看服务详情")
                .accessibilityLabel("服务详情")
                .popover(isPresented: $showMetadata, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("翻译服务").font(.headline)
                        Text("实际服务：\(result.providerName)")
                        Text("服务 ID：\(result.providerID)")
                        Text("配置来源：\(result.credentialSource == .builtIn ? "预置服务" : result.credentialSource.displayName)")
                        if let requested = requestedProviderDebugLine {
                            Text(requested)
                        }
                        Text("回退状态：\(result.fallbackOccurred ? "已发生" : "未发生")")
                        if let reason = result.fallbackReason, result.fallbackOccurred {
                            Text("回退原因：\(reason)")
                        }
                        if let latency = result.latencyMilliseconds {
                            Text("耗时：\(latency) ms")
                        }
                    }
                    .font(.caption)
                    .padding(14)
                    .frame(width: 300, alignment: .leading)
                }
            }

            Text(result.translatedText)
                .font(.system(size: isShortResult ? 23 : 18,
                              weight: isShortResult ? .medium : .regular))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var requestedProviderDebugLine: String? {
        guard let requestedProviderID = result.requestedProviderID else { return nil }
        let requestedName = result.requestedProviderName ?? requestedProviderID
        if requestedProviderID == result.providerID {
            return "路由请求：\(requestedName)"
        }
        return "路由请求：\(requestedName) → 实际使用 \(result.providerName)"
    }
}

struct ExpressionResultCard: View {
    let result: ExpressionResult
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(result.scene.displayName, systemImage: sceneIcon)
                    .font(.headline)
                Text(result.tone.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Button("复制") { onCopy(result.primaryText) }.buttonStyle(.link)
            }
            Text(result.primaryText)
                .font(.system(size: 16.5))
                .lineSpacing(4)
                .textSelection(.enabled)
            if !result.alternatives.isEmpty {
                ForEach(Array(result.alternatives.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .top, spacing: 10) {
                        Text("备选 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        Text(value).textSelection(.enabled)
                        Spacer()
                        Button { onCopy(value) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Text("\(result.providerName) · \(result.modelName ?? "未返回模型") · \(result.credentialSource.displayName) · 基于 \(result.baseTranslationProviderName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private var sceneIcon: String {
        switch result.scene {
        case .daily: return "message"
        case .teams: return "bubble.left.and.bubble.right"
        case .email: return "envelope"
        }
    }
}
#endif
