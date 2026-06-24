# v6 本地优先数据链路

1. Enter 后立即取消上一请求，并同步查询本地 SQLite。
2. 本地命中后立即更新查询区，明确显示“英英释义”和“中文释义”。
3. 准确翻译 Provider 独立选择：OpenAI Compatible、DeepL、LibreTranslate、MyMemory。
4. 使用非 AI 翻译 Provider 时，只有开启“AI 上下文查询”或“表达”才继续调用 AI。
5. 发送给 AI 的本地词典提示严格截断，只包含词头、词性和短释义，避免上传整篇 Collins 词条。
6. 表达关闭时要求返回空表达数据；AI 查询关闭时要求返回空查询数据。
7. 新查询会取消旧请求，网络失败不会覆盖已出现的本地结果。

## Provider 建议

- 单词/短语：本地词典命中即可完成查询，不需要 API。
- 普通准确翻译：优先 DeepL API Free 或自建 LibreTranslate。
- 无 Key 免费回退：MyMemory，仅建议短文本。
- 技术文本、语境解释和表达优化：OpenAI Chat Completions 兼容接口。
