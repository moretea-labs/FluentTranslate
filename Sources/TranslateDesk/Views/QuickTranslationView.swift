#if os(macOS)
import SwiftUI
import TranslateCore

/// Quick lookup uses the same AppModel as the full workspace, without a
/// second translation pipeline or another set of persisted results.
struct QuickTranslationView: View {
    @EnvironmentObject private var model: AppModel
    let onOpenMain: () -> Void
    let onClose: () -> Void
    let onPinnedChange: (Bool) -> Void

    @State private var pinned = false
    @State private var editorFocused = false

    private let accent = Color(red: 0.43, green: 0.37, blue: 0.77)
    private let languages = [
        ("auto", "自动"), ("zh", "中文"), ("en", "英语"), ("ja", "日语"),
        ("ko", "韩语"), ("fr", "法语"), ("de", "德语"), ("es", "西班牙语")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Picker("原文语言", selection: $model.sourceLanguage) {
                    ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                .frame(width: 90)
                Button {
                    model.swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption)
                }
                .help("交换翻译方向")
                .accessibilityLabel("交换源语言和目标语言")
                Picker("译文语言", selection: $model.targetLanguage) {
                    Text("中英自动").tag("auto")
                    ForEach(languages.filter { $0.0 != "auto" }, id: \.0) {
                        Text($0.1).tag($0.0)
                    }
                }
                .frame(width: 100)

                Spacer(minLength: 4)
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    pinned.toggle()
                    onPinnedChange(pinned)
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .foregroundStyle(pinned ? accent : Color.secondary)
                }
                .help(pinned ? "取消固定" : "固定窗口")
                .accessibilityLabel(pinned ? "取消固定小窗" : "固定小窗")

                Button(action: onOpenMain) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("展开为完整工作区")
                .accessibilityLabel("展开完整工作区")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .help("关闭快速翻译")
                .accessibilityLabel("关闭快速翻译")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .buttonStyle(.borderless)
            .padding(.leading, 73)
            .padding(.trailing, 16)
            .frame(height: 52)

            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    SubmitTextEditor(
                        text: $model.sourceText,
                        isFocused: $editorFocused,
                        focusRequestID: model.inputFocusRequest,
                        onSubmit: { Task { await model.performPrimaryAction() } },
                        onAccurateSubmit: { Task { await model.translateAccurate() } }
                    )
                    .frame(height: inputHeight)
                    .background(Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if model.sourceText.isEmpty && !editorFocused {
                        Text("输入或选取文本，按 Return 翻译")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 8) {
                    Text(model.detectedRouteSummary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.detectedRouteSummary)
                    Spacer(minLength: 6)
                    if model.hasPendingInputChanges {
                        Text("按 Return 更新")
                            .foregroundStyle(.orange)
                    }
                    if !model.sourceText.isEmpty {
                        Button("清空") { model.clearWorkspace() }
                            .buttonStyle(.plain)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }

                    if let result = model.selectedResult {
                        Text(result.translatedText)
                            .font(.system(size: 21, weight: .medium))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(result.providerName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if model.isLoading {
                        Text("正在翻译…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let dictionary = model.dictionaryResults.first {
                        let presentation = model.presentation(for: dictionary)
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(presentation.headword)
                                    .font(.system(size: model.selectedResult == nil ? 19 : 15,
                                                  weight: .semibold))
                                if let pronunciation = model.displayedIPA(for: presentation) {
                                    Text(pronunciation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    model.speak(presentation.headword)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.borderless)
                                .help("朗读单词")
                            }

                            ForEach(Array(presentation.senses.prefix(2).enumerated()), id: \.offset) { _, sense in
                                if let definition = sense.definitions.first {
                                    if dictionary.dictionaryID == "collins-han-en" {
                                        EnglishMeaningLine(
                                            text: definition.text,
                                            fontSize: 14,
                                            showsIPA: true
                                        )
                                    } else {
                                        Text(definition.translation ?? definition.text)
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(.top, model.selectedResult == nil ? 4 : 2)
                    }

                    if !model.isLoading,
                       model.selectedResult == nil,
                       model.dictionaryResults.isEmpty,
                       model.errorMessage == nil {
                        Text(model.sourceText.isEmpty ? "选中任意应用中的文字后按 ⌥A" : "按 Return 开始查询")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 19)
                .padding(.vertical, 19)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 18) {
                Button {
                    model.speak(spokenText)
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                .disabled(spokenText.isEmpty)

                Button {
                    model.copy(copyText)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .disabled(copyText.isEmpty)

                Spacer()
                if let speechStatus = model.speechStatus {
                    Text(speechStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if model.copyFeedback != nil {
                    Label("已复制", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Button("展开完整工作区", action: onOpenMain)
                    .foregroundStyle(accent)
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .padding(.horizontal, 19)
            .frame(height: 48)
        }
        .background(.regularMaterial)
        .tint(accent)
        .onExitCommand(perform: onClose)
    }

    private var inputHeight: CGFloat {
        model.sourceText.count > 130 || model.sourceText.contains("\n") ? 100 : 64
    }

    private var copyText: String {
        if let translated = model.selectedResult?.translatedText {
            return translated
        }
        return model.dictionaryResults.first.map { model.presentation(for: $0).rawText } ?? ""
    }

    private var spokenText: String {
        model.selectedResult?.translatedText ?? model.dictionaryResults.first.map {
            model.presentation(for: $0).headword
        } ?? ""
    }
}
#endif
