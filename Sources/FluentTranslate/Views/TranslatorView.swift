import AppKit
import SwiftUI

struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    let closePanel: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.showHistory {
                historyView
            } else {
                translatorBody
            }
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "character.book.closed.fill")
                .font(.title3)
            Text("FluentTranslate")
                .font(.headline)
            Text("⌥A")
                .font(.caption.monospaced())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

            Spacer()

            Button {
                appState.showHistory.toggle()
            } label: {
                Label(appState.showHistory ? "返回" : "历史", systemImage: appState.showHistory ? "chevron.left" : "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var translatorBody: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("原文")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()

                    Picker("表达场景", selection: $settings.expressionStyle) {
                        ForEach(ExpressionStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SubmitTextEditor(
                    text: $appState.inputText,
                    submitEnabled: !appState.isLoading,
                    onSubmit: { appState.translate() }
                )
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 115, maxHeight: 160)

                HStack {
                    Text("Enter 查询；Shift/Option + Enter 换行；选中文字后按 ⌥A。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") {
                        appState.inputText = ""
                        appState.output = nil
                        appState.errorMessage = nil
                    }
                    .buttonStyle(.borderless)

                    Button {
                        appState.translate()
                    } label: {
                        if appState.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("查询", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isLoading)
                }
            }

            if let error = appState.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(.red)
                .padding(10)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            if let output = appState.output {
                outputView(output)
            } else if !appState.isLoading {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("等待处理")
                        .font(.headline)
                    Text("默认先显示本地查询与基础翻译；AI 查询和表达按需调用。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(18)
    }

    private func outputView(_ output: TranslationOutput) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                OutputSectionHeader(
                    number: 1,
                    title: "翻译",
                    subtitle: "忠实保留原意、数字、条件和语气",
                    systemImage: "character.bubble"
                )

                if output.accurateTranslation.isEmpty {
                    TranslationUnavailableCard(message: "本地查询已完成。单词或短语命中本地词典时，不再额外调用翻译 API。")
                } else {
                    ResultCard(
                        title: "准确翻译",
                        systemImage: "checkmark.seal",
                        text: output.accurateTranslation,
                        primary: true,
                        onCopy: { appState.copy(output.accurateTranslation) },
                        onReplace: { replace(output.accurateTranslation) },
                        onSpeak: { speak(output.accurateTranslation) }
                    )
                }

                Divider().padding(.vertical, 2)

                OutputSectionHeader(
                    number: 2,
                    title: "查询",
                    subtitle: "释义、语法、词组、例句和发音",
                    systemImage: "text.book.closed"
                )

                if let query = output.queryExplanation, !query.isEmpty {
                    QueryExplanationCard(text: query)
                }

                if let entry = output.offlineEntry {
                    OfflineDictionaryCard(entry: entry)
                }

                if !output.terms.isEmpty {
                    TermsCard(terms: output.terms)
                }

                HStack {
                    Button {
                        appState.runAIQuery()
                    } label: {
                        Label(output.queryExplanation?.isEmpty == false || !output.terms.isEmpty ? "重新 AI 查询" : "AI 深入查询", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isAILoading)

                    Button {
                        appState.runAIExpression()
                    } label: {
                        Label(hasExpressionContent(output) ? "重新生成表达" : "AI 优化表达", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isAILoading)

                    if appState.isAILoading {
                        ProgressView().controlSize(.small)
                        Text("AI 正在补充…").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if hasExpressionContent(output) {
                    Divider().padding(.vertical, 2)

                    OutputSectionHeader(
                        number: 3,
                        title: "表达",
                        subtitle: "按真实场景优化自然度与礼貌程度",
                        systemImage: "sparkles"
                    )

                    if !output.recommendedExpression.isEmpty {
                        ResultCard(
                            title: "推荐表达 · \(settings.expressionStyle.rawValue)",
                            systemImage: "sparkles",
                            text: output.recommendedExpression,
                            primary: false,
                            onCopy: { appState.copy(output.recommendedExpression) },
                            onReplace: { replace(output.recommendedExpression) },
                            onSpeak: { speak(output.recommendedExpression) }
                        )
                    }

                    alternatives(output)

                    if !output.explanation.isEmpty {
                        ExplanationCard(text: output.explanation)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func hasExpressionContent(_ output: TranslationOutput) -> Bool {
        !output.recommendedExpression.isEmpty
            || !output.politeAlternative.isEmpty
            || !output.conciseAlternative.isEmpty
            || !output.formalAlternative.isEmpty
            || !output.explanation.isEmpty
    }

    @ViewBuilder
    private func alternatives(_ output: TranslationOutput) -> some View {
        let values = [
            ("更礼貌", output.politeAlternative),
            ("更简洁", output.conciseAlternative),
            ("正式邮件", output.formalAlternative)
        ].filter { !$0.1.isEmpty }

        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("其他表达", systemImage: "slider.horizontal.3")
                    .font(.headline)
                ForEach(values, id: \.0) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(item.1)
                            .textSelection(.enabled)
                        Spacer()
                        Button { appState.copy(item.1) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .padding(14)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var historyView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近 \(appState.history.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空历史", role: .destructive) { appState.clearHistory() }
                    .buttonStyle(.borderless)
            }
            .padding(16)
            Divider()

            if appState.history.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("暂无历史")
                        .font(.headline)
                    Spacer()
                }
            } else {
                List(appState.history) { item in
                    Button {
                        appState.useHistory(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.input)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Text(historyPreview(item.output))
                                .lineLimit(2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyPreview(_ output: TranslationOutput) -> String {
        if !output.recommendedExpression.isEmpty {
            return output.recommendedExpression
        }
        return output.accurateTranslation
    }

    private func replace(_ text: String) {
        appState.replaceSelection(with: text) {
            if settings.closeAfterReplace {
                closePanel()
            }
        }
    }

    private func speak(_ text: String) {
        let language = settings.englishVariant == .american ? "en-US" : "en-GB"
        SpeechService.shared.speak(text, language: language)
    }
}
