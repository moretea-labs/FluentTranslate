# TranslateDesk

一款面向 macOS 的本地优先查词、翻译与表达优化工具。它使用一个统一输入框，但明确区分“词典查询结果”和“翻译结果”：英文单词默认同时查词并翻译，中文、英文短语和句子自动选择翻译方向。准确翻译和 AI 表达只在用户主动调用时执行。

> 本仓库公开的是应用源码。个人词典数据 `Sources/TranslateCore/Resources/*.tdict` 不随 GitHub 提供；它们可能受第三方版权保护。未另行取得相应授权时，不应公开再分发词典或含词典的应用安装包。

## 为什么这样设计

TranslateDesk 不是欧路词典的完整替代品，也不是只有一个翻译按钮的极简工具。产品边界是：

- 一个输入框完成大多数操作。
- 查词和翻译是两类结果，分别展示。
- 智能模式负责判断意图，用户不需要每次先选模式。
- “查词”和“翻译”模式仍然保留，用于手动覆盖自动判断。
- 不默认并行调用多个远程服务或 AI。

默认流程是：

```text
本地词典 / 本地缓存
        ↓ 未命中
默认预设中的第一个可用翻译服务
        ↓
展示结果、实际服务商和配置来源
        ↓ 用户主动选择
准确翻译 / 指定服务 / AI 表达优化
```

## 已实现功能

- **智能主动作**：中文自动译为英文；英文短语和句子自动译为中文；英文单词自动查词并翻译。
- **回车即执行**：`Return` 执行，`Shift+Return` 换行，`Command+Return` 调用准确翻译。
- **三种工作方式**：智能、查词、翻译；默认使用智能模式。
- **词典与翻译分区**：中文释义、英英解释和例句显示在词典卡片；机器翻译显示在独立翻译卡片。
- **结果快速筛选**：可一键只看 Cambridge、Collins、基础词典、翻译或表达结果；切换不重新查询，筛选习惯会在后续查询中复用。
- **结构化词典排版**：自动识别词性、词义、中文翻译、例句、短语和语法标签，不再把 MDX 内容显示为一整段纯文本。
- **按词性分类与折叠**：动词、名词、形容词、短语等分类独立展示；整本词典、单个分类及分类完整内容都可分别收缩和展开。
- **布局偏好复用**：每本词典的整体折叠、分类展开和摘要/全文状态会保存，查询下一个词时继续使用相同阅读习惯。
- **结构化结果缓存**：每次查询只解析一次词典正文，筛选和折叠复用已内化的结构化结果。
- **系统朗读**：词典卡片可调用 macOS 系统语音朗读词头，不依赖缺失的 MDD 音频。
- **新查询替换旧主结果**：避免结果无限堆叠；准确翻译和指定服务结果仍可追加对比。
- **结果状态保护**：输入已修改但尚未重新执行时会明确提示；直接调用准确翻译不会再混入上一轮查询结果。
- **键盘与反馈**：`Command+L` 聚焦并全选输入框，提交后自动滚动到结果，复制后显示确认提示。
- **两本完整本地词典**：内置 Cambridge English-Chinese 双解和 Collins COBUILD 高阶英英，按顺序分别展示。
- **内存映射索引**：约 9.7 万可查询词头使用二进制索引精确定位，不在启动或查询时重新解析 MDX。
- **前缀建议**：完全匹配失败时给出相近词头，点击即可重新查询。
- **低成本默认翻译**：预置 MyMemory，首次运行无需 API Key 即可翻译。
- **透明服务商信息**：结果展示服务商、模型、`本地 / 应用内置 / 用户配置`、缓存命中和回退情况。
- **准确翻译**：默认预留 DeepL，可在设置中配置 Key、API Free/Pro 地址和质量策略。
- **指定服务重新翻译**：结果页可以直接选择当前已启用的服务商。
- **场景化 AI 表达**：分为地道表达、Teams 快速消息、邮件正文和完整工作邮件。
- **独立 AI 路由**：日常、Teams、邮件可以分别绑定不同 OpenAI 兼容服务。
- **自定义服务**：可以添加多个 OpenAI 兼容端点或自建 LibreTranslate。
- **安全凭据**：API Key 保存到 macOS Keychain，不进入 `config.json`，也不会提交到 Git。
- **缓存和回退**：相同请求按服务商分别缓存；主服务失败时记录失败原因并透明回退。
- **可测试核心层**：翻译路由和服务适配器与 SwiftUI 解耦，可在 macOS/Linux 执行测试。

## 默认服务配置

| 用途 | 默认配置 | 首次是否可用 |
|---|---|---:|
| 本地单词查询 | Cambridge 双解 → Collins 英英 → 内置工作词表 | 是 |
| 默认翻译 | MyMemory | 是 |
| 准确翻译 | DeepL | 配置 Key 后可用 |
| 备用翻译 | LibreTranslate | 配置实例后可用 |
| AI 翻译与表达 | OpenAI 兼容服务 | 配置地址、模型和 Key 后可用 |

“应用内置”表示软件已经提供接口配置，不代表第三方服务没有自己的使用条款或限额。发布者应在正式发行前确认各服务的授权、配额和隐私要求。

## 系统要求

- macOS 14 或更高版本
- Xcode 16 或兼容 Swift 5.10 Package 的版本
- 运行测试时可使用 Swift 5.10 以上工具链

## 快速开始

### 方式一：Xcode 运行

```bash
git clone https://github.com/moretea-labs/FluentTranslate.git
cd FluentTranslate
open Package.swift
```

在 Xcode 中选择 `TranslateDesk` Scheme，然后运行。

### 方式二：生成 macOS App

```bash
./scripts/build_app.sh
open dist/TranslateDesk.app
```

### 方式三：生成 DMG

```bash
./scripts/package_dmg.sh
```

安装到 Applications：

```bash
./scripts/install_app.sh
# 或安装到 ~/Applications
./scripts/install_app.sh --user
```

产物位于：

```text
dist/TranslateDesk-1.6.0.dmg
```

当前脚本使用 ad-hoc 签名，适合本地测试。公开分发时请使用 Apple Developer ID 签名并完成 notarization，详见 [发布指南](docs/RELEASING.md)。

## 第一次使用

1. 打开应用，保持默认“智能”模式。
2. 输入内容后直接按 `Return`：
   - 中文内容：翻译为英文。
   - 英文单词：查询已加载词典，并显示独立翻译结果。
   - 英文短语或句子：翻译为中文。
3. `Shift+Return` 用于输入换行；`Command+Return` 快速调用准确翻译；`Command+L` 随时聚焦并全选输入框。
4. 结果卡片会明确显示实际服务，例如 `MyMemory · 应用内置`。
5. 对结果不满意时，可以点击：
   - **准确翻译**：调用设置中绑定的准确翻译服务。
   - **指定服务**：直接选择某个服务商重新翻译。
   - **优化表达**：基于当前选中结果生成地道表达、Teams 消息或邮件。

AI 表达不会随基础翻译自动执行，因此普通查询不会消耗 AI Token。

## 本地词典

当前版本已经把以下两本用户提供的 MDX 词典预转换并随应用加载：

| 查询顺序 | 词典 | 可查询词头 | 内容 |
|---:|---|---:|---|
| 1 | Cambridge English-Chinese (Simplified) Dictionary | 63,762 | 英汉双解、音标、词性、例句和短语文字 |
| 2 | Collins COBUILD Advanced Learner's English Dictionary 3rd | 33,261 | 英英释义、语法标签和例句文字 |
| 3 | 内置基础词典 | 6 | 原有工作常用词兜底 |

输入英文单词后，应用会按上表顺序查询，并为每本命中的词典显示独立卡片。机器翻译仍然显示在单独的“翻译结果”区域。

两份原始文件没有配套 `.mdd`，因此转换时保留了所有可读取文字，并移除了缺失的图片、CSS、脚本和音频引用，避免出现破图或无效资源。当前版本不提供通用的 MDX 导入界面；若需要重新生成内置数据，可执行：

```bash
python3 -m pip install -r requirements-mdict.txt
python3 scripts/import_mdict.py /path/to/dictionary.mdx output.tdict
```

`.tdict` 使用内存映射和有序二进制索引。应用不会在每次启动时解压整本词典，也不会在查询时扫描 MDX。详细说明见 [本地词典说明](docs/DICTIONARIES.md)。

## 配置 DeepL

1. 打开“服务设置”。
2. 展开 `DeepL`。
3. 保持 API Free 地址：

```text
https://api-free.deepl.com/v2/translate
```

DeepL API Pro 用户可改为：

```text
https://api.deepl.com/v2/translate
```

4. 输入 API Key，点击“保存 Key”。
5. 启用 DeepL，并将“准确翻译服务”选择为 DeepL。
6. 保存配置。

默认 `modelType` 是 `prefer_quality_optimized`，可以在用户配置文件的 `options` 中修改。

## 配置 OpenAI 兼容服务

1. 打开“服务设置”，展开 `OpenAI 兼容服务`。
2. 填写 API 地址，例如：

```text
https://api.openai.com/v1/chat/completions
```

也可以填写 Azure/OpenRouter/公司网关/本地兼容服务的完整 Chat Completions 地址。
3. 填写该服务实际支持的模型名称。
4. 输入 API Key 并保存。
5. 启用服务。
6. 在“AI 表达路由”中分别选择地道表达、Teams 和邮件所使用的服务。

需要多个模型或网关时，点击“添加服务 → OpenAI 兼容服务”。每个服务都有独立 ID、地址、模型和 Key。

## 配置文件位置

运行后，应用配置保存在：

```text
~/Library/Application Support/TranslateDesk/config.json
```

翻译缓存保存在：

```text
~/Library/Application Support/TranslateDesk/translation-cache.json
```

API Key 不在上述文件中，而是在 macOS Keychain 中，以服务 ID 对应的 `secretReference` 保存。

仓库中的 [默认配置示例](config/default-config.json) 可以用于理解格式，但运行时会在用户目录生成独立副本。

详细字段说明见 [配置文档](docs/CONFIGURATION.md)。

## 架构

```text
SwiftUI UI
 ├─ TranslationWorkspaceView
 └─ SettingsView
          ↓
       AppModel
          ↓
 ┌──────────────────────────────┐
 │ TranslateCore                │
 │                              │
 │ TranslationRouter            │
 │ ExpressionRouter             │
 │ ProviderFactory              │
 │ TranslationCache             │
 │ DictionaryCatalog            │
 │ IndexedDictionarySource      │
 │ LocalDictionary              │
 └──────────────────────────────┘
          ↓
 ┌──────────┬─────────┬───────────────┬──────────────────┐
 │ MyMemory │ DeepL   │ LibreTranslate│ OpenAI Compatible│
 └──────────┴─────────┴───────────────┴──────────────────┘
```

核心原则：

- UI 不直接调用第三方 API。
- 预设负责路由，服务商负责执行。
- 请求服务和实际服务分别记录，回退不会被隐藏。
- 普通翻译与表达优化使用不同的数据模型和缓存语义。
- API Key 只由 `SecretResolving` 获取。

更完整的说明见 [架构文档](docs/ARCHITECTURE.md)。

## 测试

```bash
swift test
```

当前 24 个测试覆盖：

- 中文、英文单词和英文句子的智能意图识别。
- 查词模式不会误调用翻译。
- Cambridge 与 Collins 资源加载、固定顺序和词条数量。
- 双解与英英词条查询、变形词查询和前缀建议。
- Cambridge/Collins 词典正文的结构化分段、双语例句拆分和长词条边界。
- 词性分类顺序、同类词义合并及真实 `run` 词条的动词/名词分组。
- 结果筛选键和词典布局偏好的持久化往返验证。
- 默认配置编码与解码。
- 本地中文释义和英英解释。
- MyMemory 请求与响应解析。
- DeepL 缺少 Key 时回退到 MyMemory，并记录真实来源。
- OpenAI 兼容服务的场景化表达 JSON 解析。

## 本地使用检查

- [ ] 在 Mac 上执行 `python3 scripts/verify_tdict.py` 和 `swift test`。
- [ ] 执行 `scripts/build_app.sh` 后，用 `apple`、`running` 和中文句子各验证一次。
- [ ] 确认 `Contents/Resources` 中存在两份 `.tdict`。
- [ ] 不要把 API Key 写入源码或配置样例。
- [ ] 不要把内置 `.tdict` 词典数据推送到公开仓库。

## 文档

- [配置说明](docs/CONFIGURATION.md)
- [架构说明](docs/ARCHITECTURE.md)
- [使用逻辑 Review](docs/UX_REVIEW.md)
- [1.4.0 查询筛选与折叠 Review](docs/UX_REVIEW_1.4.md)
- [1.3.0 词典排版与交互 Review](docs/UX_REVIEW_1.3.md)
- [1.2.0 代码与性能 Review](docs/REVIEW_1.2.md)
- [本地词典与转换格式](docs/DICTIONARIES.md)
- [发布指南](docs/RELEASING.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [English README](README.en.md)

## License

MIT


## 菜单栏与全局快捷键

TranslateDesk 现在以菜单栏应用方式运行：

- 默认全局快捷键：`Option + A`
- 在任意应用中按 `Option + A`，会显示 TranslateDesk 并聚焦输入框
- 点击窗口关闭按钮或黄色最小化按钮，只会隐藏到菜单栏，不会退出
- 点击菜单栏的词典图标可以重新打开或退出应用
- 如果 `Option + A` 已被其他应用占用，TranslateDesk 会在窗口中显示注册失败提示

一键安装：

```bash
./install.sh
```

安装到当前用户目录、无需管理员权限：

```bash
./install.sh --user
```
