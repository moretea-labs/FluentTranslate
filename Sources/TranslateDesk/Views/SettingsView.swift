#if os(macOS)
import SwiftUI
import TranslateCore
#if canImport(Translation)
import Translation
#endif

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleLanguagePackSetupView: View {
    private let english = Locale.Language(identifier: "en")
    private let chinese = Locale.Language(identifier: "zh")
    @State private var configuration: TranslationSession.Configuration?
    @State private var installed = false
    @State private var isPreparing = false
    @State private var message = "检查中英文语言包…"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("中英离线翻译")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(installed ? "已安装" : "下载语言包") {
                isPreparing = true
                message = "准备系统语言包…"
                if configuration == nil {
                    configuration = TranslationSession.Configuration(source: english, target: chinese)
                } else {
                    configuration?.source = english
                    configuration?.target = chinese
                    configuration?.invalidate()
                }
            }
            .disabled(installed || isPreparing)
        }
        .task { await refreshStatus() }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                let reverse = await LanguageAvailability().status(from: chinese, to: english)
                if reverse != .installed && session.sourceLanguage == english {
                    // Install the opposite direction only if Apple needs a second language model.
                    configuration = TranslationSession.Configuration(source: chinese, target: english)
                } else {
                    await refreshStatus()
                    isPreparing = false
                }
            } catch {
                message = error.localizedDescription
                isPreparing = false
            }
        }
    }

    private func refreshStatus() async {
        let availability = LanguageAvailability()
        let forward = await availability.status(from: english, to: chinese)
        let reverse = await availability.status(from: chinese, to: english)
        installed = forward == .installed && reverse == .installed
        message = installed ? "中英双向翻译可离线使用" : "首次使用需要下载 Apple 系统语言包"
    }
}
#endif

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingProviderKeys: [String: String] = [:]

    var body: some View {
        Form {
            Section("本地词典") {
                ForEach(Array(model.loadedDictionaries.enumerated()), id: \.element.id) { index, dictionary in
                    HStack(spacing: 12) {
                        Image(systemName: index == 0 ? "1.circle.fill" : "\(index + 1).circle")
                            .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dictionary.displayName)
                                .fontWeight(.semibold)
                            Text(dictionary.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let count = dictionary.entryCount {
                            Text("\(count.formatted()) 词头")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Label("已加载", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text("中英文词条会从适用的本地词典查询；在线翻译与词典释义分别展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if #available(macOS 15.0, *) {
                Section("系统翻译") {
                    AppleLanguagePackSetupView()
                }
            }

            Section("发音") {
                Picker("英语口音", selection: $model.englishAccent) {
                    Text("美音").tag(EnglishAccent.american)
                    Text("英音").tag(EnglishAccent.british)
                }
                .pickerStyle(.segmented)
            }

            Section("默认路由") {
                Picker("默认翻译预设", selection: $model.configuration.defaultPresetID) {
                    ForEach(model.configuration.presets) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                }
                Picker("准确翻译服务", selection: optionalBinding(\.accurateProviderID)) {
                    Text("未配置").tag("")
                    ForEach(translationProviders) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                Toggle("启用翻译缓存", isOn: $model.configuration.cacheEnabled)
            }

            Section {
                HStack {
                    Text("翻译预设")
                    Spacer()
                    Button("添加预设") { model.addPreset() }
                }
                ForEach($model.configuration.presets) { $preset in
                    PresetEditorView(preset: $preset, providers: translationProviders)
                }
            }

            Section("AI 表达路由") {
                routePicker("地道表达", keyPath: \.dailyProviderID, capability: .dailyExpression)
                routePicker("Teams 快速消息", keyPath: \.teamsProviderID, capability: .teamsExpression)
                routePicker("工作邮件", keyPath: \.emailProviderID, capability: .emailExpression)
            }

            Section {
                HStack {
                    Text("服务商")
                        .font(.title3.bold())
                    Spacer()
                    Menu("添加服务") {
                        Button("OpenAI 兼容服务") { model.addOpenAICompatibleProvider() }
                        Button("自建 LibreTranslate") { model.addLibreTranslateProvider() }
                    }
                }
                ForEach($model.configuration.providers) { $provider in
                    ProviderEditorView(provider: $provider, apiKey: pendingKeyBinding(for: provider.id))
                }
            }

            Section {
                HStack {
                    Text("配置文件")
                    Spacer()
                    Text(StoragePaths.configuration.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存配置") { saveSettings() }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onDisappear { saveSettings() }
    }

    private func saveSettings() {
        for provider in model.configuration.providers {
            let value = pendingProviderKeys[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            model.saveSecret(value, for: provider)
            pendingProviderKeys.removeValue(forKey: provider.id)
        }
        model.saveConfiguration()
    }

    private func pendingKeyBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: { pendingProviderKeys[providerID] ?? "" },
            set: { pendingProviderKeys[providerID] = $0 }
        )
    }

    private var translationProviders: [ProviderConfiguration] {
        model.configuration.providers.filter {
            $0.kind != .local && ($0.capabilities.contains(.translation) || $0.capabilities.contains(.contextualTranslation))
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<AppConfiguration, String?>) -> Binding<String> {
        Binding(
            get: { model.configuration[keyPath: keyPath] ?? "" },
            set: { model.configuration[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func routePicker(
        _ title: String,
        keyPath: WritableKeyPath<ExpressionRouting, String?>,
        capability: ProviderCapability
    ) -> some View {
        Picker(title, selection: Binding(
            get: { model.configuration.expressionRouting[keyPath: keyPath] ?? "" },
            set: { model.configuration.expressionRouting[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )) {
            Text("未配置").tag("")
            ForEach(model.configuration.providers.filter { $0.capabilities.contains(capability) }) { provider in
                Text(provider.displayName).tag(provider.id)
            }
        }
    }
}

private struct ProviderEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var provider: ProviderConfiguration
    @Binding var apiKey: String
    @State private var revealAdvanced = false
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("显示名称", text: $provider.displayName)
                if provider.kind != .local && provider.kind != .appleSystem {
                    if provider.kind == .deepL {
                        Picker("DeepL API 类型", selection: deepLTierBinding) {
                            Text("Free").tag("free")
                            Text("Pro").tag("pro")
                        }
                        .pickerStyle(.segmented)
                        Text("切换账号类型会自动改用 DeepL 对应的官方端点。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("API 地址", text: $provider.baseURL)
                }
                if provider.kind == .openAICompatible {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("模型名称")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("例如 deepseek-chat / gpt-4o-mini / qwen-plus", text: openAIModelBinding)
                                .textFieldStyle(.roundedBorder)
                            Menu("常用模型") {
                                Button("DeepSeek Chat · deepseek-chat") { provider.model = "deepseek-chat" }
                                Button("DeepSeek Reasoner · deepseek-reasoner") { provider.model = "deepseek-reasoner" }
                                Button("OpenAI Mini · gpt-4o-mini") { provider.model = "gpt-4o-mini" }
                                Button("Qwen Plus · qwen-plus") { provider.model = "qwen-plus" }
                                Button("Qwen Turbo · qwen-turbo") { provider.model = "qwen-turbo" }
                                Divider()
                                Button("清空模型名称", role: .destructive) { provider.model = nil }
                            }
                        }
                        Text("OpenAI 兼容服务必须填写服务商支持的模型 ID；只配置 API 地址和 Key 不够。")
                            .font(.caption)
                            .foregroundStyle(provider.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? Color.secondary : Color.orange)
                    }
                }
                if provider.secretReference != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SecureField(model.hasSecret(for: provider) ? "已保存 API Key，输入新值可替换；留空不会清除" : "API Key", text: $apiKey)
                                .onSubmit { savePendingKey() }
                            Button("保存 Key") { savePendingKey() }
                                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if model.hasSecret(for: provider) {
                                Button("清除 Key", role: .destructive) { model.clearSecret(for: provider) }
                            }
                        }
                        Text(model.hasSecret(for: provider) ? "Key 已保存。输入新值并保存可替换；不输入不会覆盖原配置。" : "未保存 Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if provider.supportsConnectionCheck {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Button {
                                savePendingKey()
                                Task { await model.testProviderConnection(provider) }
                            } label: {
                                if connectionStatus == .checking {
                                    Label("测试中…", systemImage: "arrow.triangle.2.circlepath")
                                } else {
                                    Text("测试连接")
                                }
                            }
                            connectionFeedback
                            Spacer()
                        }
                        runtimeSummary
                    }
                }

                Toggle("高级配置", isOn: $revealAdvanced)
                    .toggleStyle(.switch)
                if revealAdvanced {
                    Stepper("超时：\(Int(provider.timeoutSeconds)) 秒", value: $provider.timeoutSeconds, in: 3...120, step: 1)
                    TextField("自定义请求头 JSON（当前通过配置文件维护）", text: .constant(""))
                        .disabled(true)
                    Text("能力：\(provider.capabilities.map(\.rawValue).sorted().joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("服务 ID：\(provider.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if provider.id.hasPrefix("openai-compatible-") || provider.id.hasPrefix("libretranslate-") {
                    Button("删除这个服务", role: .destructive) { model.removeProvider(id: provider.id) }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: $provider.enabled).labelsHidden()
                Button {
                    toggleExpanded()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName).fontWeight(.semibold)
                            HStack(spacing: 6) {
                                Text("\(provider.kind.rawValue) · \(provider.credentialSource.displayName)")
                                if provider.kind != .local {
                                    availabilityBadge
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        if provider.secretReference != nil {
                            Label(model.hasSecret(for: provider) ? "已配置" : "缺少 Key",
                                  systemImage: model.hasSecret(for: provider) ? "checkmark.circle" : "key")
                                .font(.caption)
                                .foregroundStyle(model.hasSecret(for: provider) ? Color.green : Color.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "点击收起服务配置" : "点击展开服务配置")
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpanded.toggle()
        }
    }

    private var deepLTierBinding: Binding<String> {
        Binding(
            get: { provider.deepLAccountType.rawValue },
            set: { tier in
                provider.setDeepLAccountType(DeepLAccountType(rawValue: tier) ?? .free)
            }
        )
    }

    private var openAIModelBinding: Binding<String> {
        Binding(
            get: { provider.model ?? "" },
            set: { value in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                provider.model = normalized.isEmpty ? nil : normalized
            }
        )
    }

    private var connectionStatus: ProviderConnectionStatus {
        model.connectionStatus(for: provider)
    }

    private var providerRuntimeStatus: ProviderRuntimeStatus {
        model.runtimeStatus(for: provider)
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        Text(availabilityText)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(availabilityColor.opacity(0.12), in: Capsule())
            .foregroundStyle(availabilityColor)
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .checking:
            Label("正在验证服务响应", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var runtimeSummary: some View {
        Label(runtimeSummaryText, systemImage: runtimeSummaryIcon)
            .font(.caption)
            .foregroundStyle(runtimeSummaryColor)
    }

    private var availabilityText: String {
        if providerRuntimeStatus.isReady {
            return provider.enabled ? "可用" : "未启用"
        }
        return "需补全配置"
    }

    private var availabilityColor: Color {
        if providerRuntimeStatus.isReady {
            return provider.enabled ? .green : .secondary
        }
        return .orange
    }

    private var runtimeSummaryText: String {
        if providerRuntimeStatus.isReady {
            return provider.enabled ? "当前配置完整，保存后可立即参与路由。" : "当前配置完整，但未启用，不会参与运行时路由。"
        }
        return providerRuntimeStatus.issues.joined(separator: " · ")
    }

    private var runtimeSummaryIcon: String {
        providerRuntimeStatus.isReady ? "checkmark.shield" : "exclamationmark.triangle"
    }

    private var runtimeSummaryColor: Color {
        providerRuntimeStatus.isReady ? .secondary : .orange
    }

    private func savePendingKey() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.saveSecret(value, for: provider)
        apiKey = ""
    }
}
private struct PresetEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var preset: TranslationPreset
    let providers: [ProviderConfiguration]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                TextField("预设名称", text: $preset.displayName)
                Toggle("本地优先", isOn: $preset.localFirst)
                Toggle("失败时尝试下一个服务", isOn: $preset.fallbackEnabled)

                Text("服务顺序").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(preset.providerOrder.enumerated()), id: \.element) { index, providerID in
                    HStack {
                        Text(providerName(providerID))
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == preset.providerOrder.count - 1)
                        Button { preset.providerOrder.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }

                Menu("添加服务到预设") {
                    ForEach(providers.filter { !preset.providerOrder.contains($0.id) }) { provider in
                        Button(provider.displayName) { preset.providerOrder.append(provider.id) }
                    }
                }
                if preset.id.hasPrefix("custom-") {
                    Button("删除这个预设", role: .destructive) { model.removePreset(id: preset.id) }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Text(preset.displayName).fontWeight(.semibold)
                Spacer()
                Text(routeSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var routeSummary: String {
        let names = preset.providerOrder.map { providerName($0) }
        return ((preset.localFirst ? ["本地"] : []) + names).joined(separator: " → ")
    }

    private func providerName(_ id: String) -> String {
        providers.first(where: { $0.id == id })?.displayName ?? id
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard preset.providerOrder.indices.contains(index), preset.providerOrder.indices.contains(destination) else { return }
        preset.providerOrder.swapAt(index, destination)
    }
}

#endif
