import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var apiKey = ""
    @State private var deepLKey = ""

    private var dictionaryStatus: DictionaryStatus { LocalDictionaryService.shared.status }

    var body: some View {
        Form {
            Section("使用预设") {
                Picker("模式", selection: $settings.usagePreset) {
                    ForEach(UsagePreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: settings.usagePreset) { settings.applyPreset($0) }
                Text("本地优先：单词和短语命中词典时不联网；句子只做基础翻译，AI 查询和表达由结果区按钮单独触发。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("结果与调用策略") {
                Picker("准确翻译服务", selection: $settings.translationProvider) {
                    ForEach(TranslationProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("AI 仅手动调用", isOn: $settings.manualAIOnly)
                Text("当前版本默认不会在查询时自动调用 AI。AI 查询与 AI 表达是两个独立操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("OpenAI 兼容 API") {
                TextField("服务地址或完整接口地址", text: $settings.aiEndpoint)
                SecureField("API Key（本地服务可留空）", text: $apiKey)
                    .onChange(of: apiKey) { settings.aiAPIKey = $0 }
                TextField("模型名称", text: $settings.aiModel)
                Picker("英文风格", selection: $settings.englishVariant) {
                    ForEach(EnglishVariant.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("用于直接翻译，或在 DeepL/LibreTranslate/MyMemory 翻译后补充语境解释和表达。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("DeepL") {
                TextField("接口", text: $settings.deepLEndpoint)
                SecureField("DeepL API Key", text: $deepLKey)
                    .onChange(of: deepLKey) { settings.deepLAPIKey = $0 }
            }

            Section("LibreTranslate / MyMemory") {
                TextField("LibreTranslate 接口", text: $settings.libreEndpoint)
                SecureField("LibreTranslate Key（可留空）", text: $settings.libreAPIKey)
                TextField("MyMemory 邮箱（可选，提高免费额度）", text: $settings.myMemoryEmail)
                HStack { TextField("源语言", text: $settings.sourceLanguage); TextField("目标语言", text: $settings.targetLanguage) }
            }

            Section("本地离线词典") {
                Toggle("启用离线查询", isOn: $settings.offlineDictionaryEnabled)
                HStack {
                    Label(dictionaryStatus.summary, systemImage: dictionaryStatus.bundledAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Spacer()
                    Button("打开数据目录") { LocalDictionaryService.shared.revealDatabaseFolder() }
                }
                Text("英英释义、中文释义、音标和词性优先从本地读取，不发送完整词典正文给 AI。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("内置 Collins 数据仅适合个人本地使用；公开发布前应移除或取得授权。")
                    .font(.caption).foregroundStyle(.orange)
            }

            Section("交互") {
                Toggle("选中文字并按 ⌥A 后自动查询", isOn: $settings.autoCapture)
                Toggle("替换原文后关闭窗口", isOn: $settings.closeAfterReplace)
                LabeledContent("提交", value: "Enter")
                LabeledContent("换行", value: "Shift/Option + Enter")
            }
        }
        .formStyle(.grouped).padding(8)
        .onAppear { apiKey = settings.aiAPIKey; deepLKey = settings.deepLAPIKey }
    }
}
