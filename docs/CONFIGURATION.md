# 配置说明

## 配置与密钥分离

TranslateDesk 使用两套存储：

1. `config.json`：保存服务名称、地址、模型、能力、路由和启用状态。
2. macOS Keychain：保存 API Key。

配置文件可以备份或提交配置模板，Keychain 内容不能通过仓库泄漏。

## AppConfiguration

```json
{
  "schemaVersion": 1,
  "defaultPresetID": "local-first",
  "accurateProviderID": "deepl-user",
  "cacheEnabled": true,
  "presets": [],
  "expressionRouting": {},
  "providers": []
}
```

### defaultPresetID

默认翻译按钮使用的预设 ID。

### accurateProviderID

“准确翻译”按钮绑定的具体服务商 ID。按钮会显示该服务商名称；未启用时按钮不可用。

### cacheEnabled

控制外部翻译结果缓存。缓存键包含：

```text
服务商 ID + 源语言 + 目标语言 + 原文 + 上下文
```

因此同一文本使用不同服务时不会互相污染。

## TranslationPreset

```json
{
  "id": "recommended-quality",
  "displayName": "推荐质量",
  "localFirst": true,
  "fallbackEnabled": true,
  "providerOrder": ["deepl-user", "mymemory-public"]
}
```

- `localFirst`：先查本地词典。
- `providerOrder`：外部服务调用顺序。
- `fallbackEnabled`：第一个服务失败后是否继续尝试后续服务。

回退后结果卡会显示实际服务和失败原因，而不是继续显示原服务名称。

## ProviderConfiguration

```json
{
  "id": "openai-compatible-user",
  "displayName": "公司 AI 网关",
  "kind": "openAICompatible",
  "baseURL": "https://gateway.example.com/v1/chat/completions",
  "enabled": true,
  "credentialSource": "userConfigured",
  "secretReference": "provider.openai-compatible-user.apiKey",
  "model": "company-model",
  "capabilities": [
    "contextualTranslation",
    "dailyExpression",
    "teamsExpression",
    "emailExpression"
  ],
  "timeoutSeconds": 30,
  "customHeaders": {
    "X-Client": "TranslateDesk"
  },
  "options": {}
}
```

### kind

支持：

- `local`
- `myMemory`
- `deepL`
- `libreTranslate`
- `openAICompatible`

### credentialSource

- `local`：不离开设备。
- `builtIn`：应用已附带可调用配置。
- `userConfigured`：使用用户自己的端点或 Key。

这是结果卡展示的配置来源，不等于收费状态。具体费用仍由服务商账户决定。

### capabilities

支持的能力值：

- `dictionary`
- `translation`
- `contextualTranslation`
- `dailyExpression`
- `teamsExpression`
- `emailExpression`
- `explanation`

UI 只应把服务展示在它实际支持的操作中。

### customHeaders

适合公司网关、代理层或特殊认证头。不要在这里直接写 API Key，因为该文件是明文。

### options

服务专属参数：

- MyMemory：`contactEmail`
- DeepL：`accountType`（`free` / `pro`）、`modelType`

## ExpressionRouting

```json
{
  "dailyProviderID": "local-ai",
  "teamsProviderID": "company-openai",
  "emailProviderID": "company-openai"
}
```

三个场景可以使用不同服务。这样日常表达可以使用本地模型，工作内容则可以走公司合规网关。

## Keychain 引用

每个需要密钥的服务通过 `secretReference` 定位 Keychain 项目：

```text
service: com.greyson.translatedesk
account: provider.<provider-id>.apiKey
```

删除配置不会自动删除 Keychain 项。正式产品可以增加“彻底删除服务及凭据”的二次确认操作。

## 自建 LibreTranslate

点击“添加服务 → 自建 LibreTranslate”，默认地址为：

```text
http://localhost:5000/translate
```

按实际部署地址修改。实例不要求 Key 时可以留空；要求 Key 时保存到 Keychain。

## 运行时可用性与连接测试

- 设置页会根据当前配置即时判断服务是否“可用”“未启用”或“需补全配置”。
- `DeepL` 和 `OpenAI 兼容服务` 需要有效 API Key；`OpenAI 兼容服务` 还必须填写模型名称。
- `LibreTranslate` 可以不填 Key；如果实例要求 Key，再保存到 Keychain。
- 每个非本地服务都可以单独执行“测试连接”。测试结果只展示服务状态，不会写入用户输入内容。

## 自定义 AI 网关

OpenAI 兼容适配器当前需要：

- 完整 Chat Completions URL。
- `Bearer` API Key。
- 模型名称。
- 响应包含 `choices[0].message.content`。

表达优化提示模型返回严格 JSON：

```json
{
  "primary": "推荐表达",
  "alternatives": ["备选表达"]
}
```

服务未返回 JSON 时，应用会把完整文本作为主结果展示。
