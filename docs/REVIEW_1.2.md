# 1.2.0 代码与性能 Review

## 已解决的问题

### 1. 查询只有演示词典

已替换为两本真实词典索引：Cambridge 双解和 Collins 英英。原有 6 条工作词表没有删除，作为最后兜底。

### 2. 每次查询解析 MDX 会慢

运行时不读取 MDX。两本词典预转换为 `.tdict`，文件通过内存映射打开，词头使用二分查找。测试环境中两本资源创建和首轮验证合计为几十毫秒，普通精确词头查询通常低于毫秒级并显示为 0–1 ms。

### 3. 词典和翻译混淆

英文单词仍会同时触发查词与翻译，但结果分区：

- Cambridge / Collins / 内置词表属于“词典查询”。
- MyMemory / DeepL / 其他服务属于“翻译结果”。
- AI 改写只在用户主动操作后出现。

### 4. 长词条破坏页面

正文超过 7,000 字符时默认显示摘要，可展开完整释义。`run` 等多义词不会在第一次渲染时占满整个页面。

### 5. 未命中没有下一步

完全匹配失败后使用同一二进制索引返回前缀建议。例如输入 `appl` 会提供 `apple`。

### 6. 手工打包漏掉资源

`build_app.sh` 会把两份 `.tdict` 复制到 `TranslateDesk.app/Contents/Resources`，任意一份缺失都会让构建直接失败。

## 当前性能路径

```text
输入英文单词
   ↓
InputAnalyzer（内存）
   ↓
DictionaryCatalog
   ├─ Cambridge mmap + binary search
   ├─ Collins mmap + binary search
   └─ built-in hash lookup
   ↓ 立即显示词典结果
TranslationRouter
   └─ 缓存或一个远程翻译服务
```

本地词典结果不需要等待远程翻译。远程服务失败时，已命中的词典正文仍保留。

## 已知限制

1. 两本 MDX 没有配套 MDD，因此没有图片和真人发音。
2. 当前没有通用词典导入 UI；词典更换需要运行转换脚本并替换资源。
3. 建议是前缀匹配，不是编辑距离模糊纠错。
4. Linux 环境无法实际运行 SwiftUI、AppKit 和 Keychain；已执行 macOS 目标语法解析，但最终布局仍需在 Mac 上打开确认。
5. 词典资源仅适合个人本地使用，不应公开分发。
