# FluentTranslate macOS MVP v5

A menu-bar translation and language-query app for macOS. Press **Option + A** in any application to capture selected text and open the floating panel.

## Default output

1. **翻译**: faithful translation through an OpenAI-compatible API.
2. **查询**: built-in offline dictionary result plus AI grammar/usage analysis when an API is available.
3. **表达**: natural workplace, polite, concise, daily or formal rewrites. This module can be disabled.

Press **Enter** to query. Use **Shift + Enter** or **Option + Enter** for a newline.

## What is included in v5

- Global shortcut `⌥A`.
- Selected-text capture and replacement through macOS Accessibility permission.
- Built-in local Collins COBUILD 3rd database converted from the MDX supplied for this project.
- 33,320 offline English entries; no network or API is required for exact word/phrase lookup.
- Optional ECDICT merge for phonetics and Chinese definitions.
- OpenAI Chat Completions compatible API adapter for OpenAI and conforming third-party services.
- Configurable endpoint, API key and model. API key is stored in Keychain.
- The endpoint field accepts either a service root URL or a complete Chat Completions URL.
- Flexible parsing for string or text-part `choices[0].message.content` responses.
- Optional LibreTranslate pipeline.
- System English pronunciation, history, copy and replace.

## Build

```bash
cd FluentTranslate
./scripts/build_app.sh
open dist/FluentTranslate.app
```

On first launch, enable the app in:

```text
System Settings → Privacy & Security → Accessibility
```

## Configure a third-party API

Open Settings and fill in:

- Format: `OpenAI Chat Completions`
- Endpoint: a service root such as `https://example.com`, or its complete `/v1/chat/completions` URL
- API Key: optional for local services
- Model: the exact model identifier supported by that provider

The first implementation intentionally targets the widely supported Chat Completions shape:

```json
{
  "model": "provider-model-name",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ],
  "stream": false
}
```

The response must expose `choices[0].message.content` as a string or an array of text parts.

## Offline dictionary behavior

The built-in dictionary is searched before the network request. If no API is configured or the API fails, an exact English word/phrase lookup still returns its local definition instead of failing the whole query.

To add ECDICT:

```bash
python3 scripts/import_ecdict.py /path/to/ecdict.csv
```

The generated database is written to:

```text
~/Library/Application Support/FluentTranslate/ecdict.sqlite
```

To convert another unencrypted MDX dictionary:

```bash
python3 -m pip install readmdict lzokay
python3 scripts/import_mdict.py dictionary.mdx output.sqlite --source-name "My Dictionary"
```

The current app automatically discovers the bundled database and the standard ECDICT path. Importing arbitrary converted databases through the UI is reserved for a later version.

## Important dictionary notice

The supplied `.mdx` and `.mdd` are one dictionary package, not two dictionaries. The MDX contains entries; the MDD contains referenced assets such as images. FluentTranslate v5 uses the MDX text and system speech, so the MDD is not required at runtime.

The converted Collins database is included only because it was supplied for this personal project. It is not open-source content. Remove `Sources/FluentTranslate/Resources/Dictionaries/collins_cobuild3.sqlite` before public or commercial distribution unless you have the necessary content licence.

## v6 本地优先与 Provider 拆分

- 本地词典结果在网络请求完成前立即显示。
- 查询卡片明确区分英英释义与中文释义。
- 准确翻译可选 OpenAI 兼容、DeepL、LibreTranslate、MyMemory。
- AI 上下文查询与表达优化可分别关闭，以减少 Token。
- 新查询会取消旧请求；网络失败时保留本地结果。
- AI 仅接收截断后的词典提示，不再上传完整词条正文。

## v7 本地优先与手动 AI

默认使用“本地优先”预设：

- 英文单词或短语命中本地词典时，直接显示英英/中文释义，并使用中文释义作为翻译，不发起远程请求。
- 完整句子只调用所选基础翻译服务。
- AI 查询与 AI 表达不随 Enter 自动调用，需在结果区分别点击“AI 深入查询”或“AI 优化表达”。
- 基础翻译缓存 90 天，AI 查询/表达缓存 30 天。

内置预设：

- 本地优先：本地词典 + MyMemory，AI 手动调用。
- 免费极速：本地词典 + MyMemory，AI 手动调用。
- 推荐质量：本地词典 + DeepL，AI 手动调用。
- 完全本地：本地词典 + `127.0.0.1:5000` LibreTranslate，AI 手动调用。
- 自定义：保留用户自己的 Provider 配置。
