#if os(macOS)
import SwiftUI
import TranslateCore

struct TranslationWorkspaceView: View {
    let onCompact: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var showContext = false
    @State private var tone: ExpressionTone = .normal
    @State private var editorFocused = false

    private let languages = [
        ("auto", "自动识别"), ("zh", "中文"), ("en", "英语"), ("ja", "日语"),
        ("ko", "韩语"), ("fr", "法语"), ("de", "德语"), ("es", "西班牙语")
    ]

    private let accent = Color(red: 0.43, green: 0.37, blue: 0.77)

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = geometry.size.width >= 1120
            let sideBySide = geometry.size.width >= (showsSidebar ? 1120 : 940)

            HStack(spacing: 0) {
                if showsSidebar {
                    sidebar
                        .frame(width: 198)
                        .frame(maxHeight: .infinity)
                        .background(.regularMaterial)
                        .background(accent.opacity(0.045))
                }

                VStack(spacing: 0) {
                    header(showSidebar: showsSidebar)
                    if sideBySide {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 18) {
                                inputCard(wide: true)
                                primaryActionBar
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, 28)
                            .padding(.trailing, 24)
                            .padding(.vertical, 26)
                            .background(Color.primary.opacity(0.018))

                            VStack(spacing: 0) {
                                resultToolbar
                                resultPane
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 25)
                        }
                    } else {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 14) {
                                inputCard(wide: false)
                                primaryActionBar
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .padding(.bottom, 20)

                            resultToolbar
                            resultPane
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .tint(accent)
        .overlay(alignment: .bottom) {
            if let message = model.copyFeedback ?? model.speechStatus {
                Label(message, systemImage: model.copyFeedback == nil ? "speaker.wave.2" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.copyFeedback)
    }

    private var resultPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Color.clear.frame(height: 1).id("result-start")
                    if let error = model.errorMessage {
                        errorBanner(error)
                    }
                    if hasResultFilters {
                        resultFilterBar
                    }
                    if shouldShowEmptyState {
                        emptyState
                    }
                    if model.shouldShowTranslations && model.isLoading && model.results.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在获取翻译…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }

                    // Put the actionable translation first, even for English words
                    // with long dictionary entries. Dictionary-only mode remains
                    // dictionary-first, and input never scrolls with the results.
                    if model.lastAnalysis?.shouldTranslate == true {
                        translationSection
                        dictionarySection
                    } else {
                        dictionarySection
                        translationSection
                    }
                    expressionActionSection
                    expressionSection
                }
                .padding(.horizontal, 30)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.lastSubmittedText) { _, value in
                guard !value.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("result-start", anchor: .top)
                }
            }
            .onChange(of: model.results.map(\.id)) { _, ids in
                guard !ids.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("result-start", anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let logo = AppBrand.logoImage() {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 29, height: 29)
                } else {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 29, height: 29)
                }
                Text(AppBrand.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 32)

            VStack(spacing: 5) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.workspaceMode = mode
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: mode))
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                            Text(mode.displayName)
                                .font(.system(size: 13, weight: model.workspaceMode == mode ? .semibold : .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(model.workspaceMode == mode ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            model.workspaceMode == mode ? accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.workspaceMode == mode ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(.bottom, 16)
        }
    }

    private func icon(for mode: WorkspaceMode) -> String {
        switch mode {
        case .smart: return "sparkle.magnifyingglass"
        case .translation: return "character.bubble"
        case .dictionary: return "text.book.closed"
        case .expression: return "wand.and.stars"
        }
    }

    private func header(showSidebar: Bool) -> some View {
        HStack(spacing: 14) {
            if showSidebar {
                Text(model.workspaceMode.displayName)
                    .font(.system(size: 20, weight: .semibold))
            } else {
                brandLine
                Spacer(minLength: 8)
                modePicker.frame(width: 292)
                settingsButton
            }
            Spacer(minLength: 0)
            if model.isLoading && showSidebar {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理")
            }
            Button(action: onCompact) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(.borderless)
            .help("缩小为快捷翻译窗口")
            .accessibilityLabel("缩小为快捷窗口")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .frame(height: 66)
    }

    private var brandLine: some View {
        HStack(spacing: 7) {
            Text("TranslateDesk")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理翻译")
            }
        }
    }

    private var settingsButton: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .frame(width: 25, height: 25)
        }
        .buttonStyle(.borderless)
        .help("服务和词典设置")
        .accessibilityLabel("设置")
        .keyboardShortcut(",", modifiers: .command)
    }

    private var modePicker: some View {
        Picker("工作方式", selection: $model.workspaceMode) {
            ForEach(WorkspaceMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }

    private var resultToolbar: some View {
        HStack(spacing: 10) {
            Text(model.workspaceMode == .dictionary ? "词典释义" :
                 model.workspaceMode == .expression ? "表达结果" : "译文与释义")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if model.workspaceMode == .smart || model.workspaceMode == .translation {
                Picker("译文语言", selection: $model.targetLanguage) {
                    Text("中英自动").tag("auto")
                    ForEach(languages.filter { $0.0 != "auto" }, id: \.0) {
                        Text($0.1).tag($0.0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 126)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    private func inputCard(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Text(model.workspaceMode == .dictionary ? "查词" :
                     model.workspaceMode == .expression ? "输入" : "原文")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if model.workspaceMode == .smart || model.workspaceMode == .translation {
                    Picker("原文语言", selection: $model.sourceLanguage) {
                        ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 116)
                    Button {
                        model.swapLanguages()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("交换语言；有结果时填入译文")
                    .accessibilityLabel("交换源语言和目标语言")
                }
            }
            .controlSize(.small)

            ZStack(alignment: .topLeading) {
                SubmitTextEditor(
                    text: $model.sourceText,
                    isFocused: $editorFocused,
                    focusRequestID: model.inputFocusRequest,
                    onSubmit: { Task { await model.performPrimaryAction() } },
                    onAccurateSubmit: { Task { await model.translateAccurate() } }
                )
                .frame(height: editorHeight(wide: wide))
                .background(Color.clear)
                .help("Return 翻译 · Shift+Return 换行 · Command+Return 高质量翻译")

                if model.sourceText.isEmpty && !editorFocused {
                    Text(model.inputPlaceholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                Text(model.detectedRouteSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(model.detectedRouteSummary)
                Spacer(minLength: 0)
                Button(showContext ? "收起上下文" : "上下文") {
                    withAnimation(.easeInOut(duration: 0.18)) { showContext.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(showContext ? .primary : .secondary)
                if !model.sourceText.isEmpty || !model.lastSubmittedText.isEmpty {
                    Button("清空") { model.clearWorkspace() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("清空输入和结果")
                }
            }
            .font(.caption)
            if showContext {
                TextField("补充语境（可选）", text: $model.contextText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(17)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.68),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Small queries use a one-line editor; paragraphs retain a scrollable
    /// multi-line field without introducing a separate compact mode.
    private func editorHeight(wide: Bool) -> CGFloat {
        let value = model.sourceText
        let lineCount = value.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
        if wide {
            return lineCount <= 3 && value.count <= 180 ? 218 : 280
        }
        if lineCount == 1 && value.count <= 60 { return 76 }
        return lineCount <= 3 && value.count <= 180 ? 112 : 156
    }

    private var primaryActionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.performPrimaryAction() }
            } label: {
                Text(model.primaryActionTitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.isLoading || model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if model.workspaceMode != .expression {
                if let provider = model.accurateProvider, model.isProviderEnabledAndReady(provider) {
                    Button {
                        Task { await model.translateAccurate() }
                    } label: {
                        Text("高质量")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("使用 \(provider.displayName) 进行按次翻译")
                    .disabled(model.isLoading || model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Menu {
                    ForEach(model.enabledTranslationProviders) { provider in
                        Button("使用 \(provider.displayName)") {
                            Task { await model.translate(using: provider.id) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("其他翻译方式")
                .accessibilityLabel("其他翻译方式")
                .disabled(model.isLoading || model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer(minLength: 0)
            if model.hasPendingInputChanges {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
                    .help("原文已修改，按 Return 更新结果")
            }
        }
    }

    @ViewBuilder
    private var dictionarySection: some View {
        let visibleResults = model.dictionaryResults.filter { model.shouldShowDictionary($0.dictionaryID) }
        if !visibleResults.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("词典释义", subtitle: "\(visibleResults.count) 本")
                ForEach(visibleResults) { result in
                    let presentation = model.presentation(for: result)
                    DictionaryResultCard(
                        result: result,
                        presentation: presentation,
                        pronunciation: model.displayedIPA(for: presentation),
                        collapsed: model.isDictionaryCollapsed(result.dictionaryID),
                        defaultFirstGroupExpanded: model.workspaceMode == .dictionary || result.dictionaryID == "cambridge-en-zh",
                        isGroupExpanded: { groupID, defaultValue in
                            model.isDictionaryGroupExpanded(
                                dictionaryID: result.dictionaryID,
                                groupID: groupID,
                                defaultValue: defaultValue
                            )
                        },
                        isGroupFullyExpanded: { groupID in
                            model.isDictionaryGroupFullyExpanded(
                                dictionaryID: result.dictionaryID,
                                groupID: groupID
                            )
                        },
                        onToggleCollapsed: {
                            model.toggleDictionaryCollapsed(result.dictionaryID)
                        },
                        onSetGroupExpanded: { groupID, expanded in
                            model.setDictionaryGroupExpanded(
                                dictionaryID: result.dictionaryID,
                                groupID: groupID,
                                expanded: expanded
                            )
                        },
                        onSetGroupFullyExpanded: { groupID, expanded in
                            model.setDictionaryGroupFullyExpanded(
                                dictionaryID: result.dictionaryID,
                                groupID: groupID,
                                expanded: expanded
                            )
                        },
                        onSetAllGroupsExpanded: { groupIDs, expanded in
                            model.setAllDictionaryGroups(
                                dictionaryID: result.dictionaryID,
                                groupIDs: groupIDs,
                                expanded: expanded
                            )
                        },
                        onSetAllGroupDetailsExpanded: { groupIDs, expanded in
                            model.setAllDictionaryGroupDetails(
                                dictionaryID: result.dictionaryID,
                                groupIDs: groupIDs,
                                expanded: expanded
                            )
                        },
                        onResetLayout: {
                            model.resetDictionaryLayout(dictionaryID: result.dictionaryID)
                        },
                        onCopy: model.copy,
                        onSpeak: model.speak
                    )
                }
            }
        } else if model.workspaceMode == .dictionary,
                  model.lastAnalysis?.shouldLookupDictionary == true,
                  !model.dictionarySuggestions.isEmpty,
                  !model.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                Text("没有精确匹配，可以试试")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.dictionarySuggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            Task { await model.useDictionarySuggestion(suggestion) }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        if model.shouldShowTranslations && !model.results.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("翻译", subtitle: model.results.count > 1 ? "\(model.results.count) 个服务结果" : nil)
                ForEach(model.results) { result in
                    TranslationResultCard(
                        result: result,
                        selected: model.selectedResultID == result.id,
                        onSelect: { model.selectedResultID = result.id },
                        onCopy: { model.copy(result.translatedText) }
                    )
                }
            }
            .id("translation-results")
        }
    }

    @ViewBuilder
    private var expressionActionSection: some View {
        if (model.shouldShowTranslations || model.shouldShowExpressions) && model.selectedResult != nil {
            HStack(spacing: 10) {
                Text("表达优化")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("语气", selection: $tone) {
                    ForEach(ExpressionTone.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(width: 118)

                Button {
                    Task { await model.optimize(scene: .daily, tone: tone) }
                } label: {
                    Text("优化当前翻译")
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoading)

                Menu("更多场景") {
                    Button("地道表达") { Task { await model.optimize(scene: .daily, tone: tone) } }
                    Button("Teams 快速消息") { Task { await model.optimize(scene: .teams, tone: tone) } }
                    Divider()
                    Button("邮件正文") { Task { await model.optimize(scene: .email, tone: tone, scope: .body) } }
                    Button("完整工作邮件") { Task { await model.optimize(scene: .email, tone: tone, scope: .fullEmail) } }
                }
                .disabled(model.isLoading)
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var expressionSection: some View {
        if model.shouldShowExpressions && !model.expressionResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("表达优化", subtitle: model.workspaceMode == .expression ? "按输入场景由 AI 生成，不经过普通翻译/词典流程" : "相同场景和语气会更新原结果，不重复堆叠")
                ForEach(model.expressionResults) { result in
                    ExpressionResultCard(result: result) { model.copy($0) }
                }
            }
        }
    }

    private var resultFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                resultFilterChip(title: "全部", systemImage: "", count: totalResultCount, key: ResultFilterKey.all)
                ForEach(model.dictionaryResults) { result in
                    resultFilterChip(title: shortDictionaryName(result), systemImage: "", count: 1,
                                     key: ResultFilterKey.dictionary(result.dictionaryID))
                }
                if !model.results.isEmpty || (model.isLoading && model.lastAnalysis?.shouldTranslate == true) {
                    resultFilterChip(title: "翻译", systemImage: "", count: model.results.count,
                                     key: ResultFilterKey.translation)
                }
                if !model.expressionResults.isEmpty {
                    resultFilterChip(title: "表达", systemImage: "", count: model.expressionResults.count,
                                     key: ResultFilterKey.expression)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func resultFilterChip(
        title: String,
        systemImage: String,
        count: Int,
        key: String
    ) -> some View {
        let selected = model.selectedResultFilterKey == key
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                model.selectResultFilter(key)
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if key == ResultFilterKey.translation && count == 0 && model.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.caption.weight(selected ? Font.Weight.semibold : Font.Weight.regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background(selected ? accent.opacity(0.10) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var hasResultFilters: Bool {
        model.dictionaryResults.count + model.results.count + model.expressionResults.count > 1
    }

    private var totalResultCount: Int {
        model.dictionaryResults.count + model.results.count + model.expressionResults.count
    }

    private func shortDictionaryName(_ result: DictionaryLookupResult) -> String {
        switch result.dictionaryID {
        case "cambridge-en-zh": return "Cambridge"
        case "collins-han-en": return "Collins 汉英"
        case "collins-cobuild-en": return "Collins 英英"
        case "built-in-basic": return "基础词典"
        default: return result.dictionaryName
        }
    }

    private var emptyState: some View {
        Text(model.workspaceMode == .dictionary ? "输入单词查看释义" :
             model.workspaceMode == .expression ? "输入内容以优化表达" : "译文和词典结果将在这里显示")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).textSelection(.enabled)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var shouldShowEmptyState: Bool {
        model.lastSubmittedText.isEmpty
            && model.dictionaryResults.isEmpty
            && model.results.isEmpty
            && model.expressionResults.isEmpty
            && model.errorMessage == nil
    }

    private var routeIcon: String {
        if model.workspaceMode == .expression {
            return "wand.and.stars"
        }
        let analysis = model.currentAnalysis
        switch (analysis.shouldLookupDictionary, analysis.shouldTranslate) {
        case (true, true): return "character.book.closed.fill"
        case (true, false): return "text.book.closed"
        case (false, true): return "arrow.left.arrow.right"
        default: return "return"
        }
    }
}
#endif
