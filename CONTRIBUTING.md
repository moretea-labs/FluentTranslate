# Contributing

感谢参与 TranslateDesk。

## 开发流程

```bash
git checkout -b feature/your-change
swift test
```

提交前请确保：

- UI 不直接调用第三方 API。
- 新服务通过 Provider 协议接入。
- 结果始终包含真实服务来源。
- API Key 不进入源码、测试快照或配置样例。
- 新增协议解析时带单元测试。
- 不让 AI 表达重新成为默认翻译流程的一部分。

## Commit 建议

```text
feat(provider): add provider adapter
fix(router): preserve actual fallback provider
 docs(config): document custom gateway headers
```

## Pull Request 内容

PR 应说明：

- 用户问题。
- 路由或配置变化。
- 网络请求和隐私影响。
- 测试证据。
- 配置迁移方式。
