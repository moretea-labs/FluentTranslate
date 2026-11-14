# 本地词典实现

## 当前内置数据

TranslateDesk 1.6.0 使用三份从用户提供 MDX 文件转换得到的只读索引：

1. `cambridge-en-zh.tdict`
   - Cambridge English-Chinese 双解
   - 63,762 个可查询词头
   - 约 23.5 MiB
2. `collins-han-en.tdict`
   - Collins 汉英大词典
   - 86,145 个可查询词头
   - 约 12 MiB
3. `collins-cobuild-en.tdict`
   - Collins COBUILD 高阶英英
   - 33,261 个可查询词头
   - 约 16.1 MiB

原始 MDX 不会随代码包重复保存。两本词典没有配套 MDD，因此图片、CSS、JavaScript 和音频引用在转换阶段被移除，文字释义、词性、音标、语法标签、例句和短语被保留。

## 查询顺序

```text
DictionaryCatalog
  1. Cambridge English-Chinese 双解
  2. Collins 汉英大词典
  3. Collins COBUILD 高阶英英
  4. 内置基础工作词表
```

每个命中结果独立展示。智能模式下中英文单词或短语同时进行精确本地词典查询和常规翻译；仅在词典实际命中时展示词典卡片。汉英义项和双语例句独立配对展示；完整句子优先走翻译，避免将词典的某个单义误用为整句译文。词典没有收录的“测试”等词仍由配置的翻译服务处理。

## `.tdict` 格式

`.tdict` 是为当前个人应用生成的只读格式，不是通用词典标准。

```text
Header
Offset table (UInt64 × entry count)
Sorted variable-length index records
UTF-8 text bodies
```

每个索引记录保存：

- 规范化词头
- 原始显示词头
- 正文偏移
- 正文长度

查询时：

1. 文件以 `Data(mappedIfSafe:)` 方式映射。
2. 对 UTF-8 规范化词头执行二分查找。
3. 只构造命中正文对应的字符串。
4. 完全匹配失败时，从 lower-bound 位置返回前缀建议。

因此不会把约 52 MiB 正文全部复制到 Swift 字典中，也不会重新解析 MDX。

## MDX 转换

安装依赖：

```bash
python3 -m pip install -r requirements-mdict.txt
```

执行：

```bash
python3 scripts/import_mdict.py input.mdx output.tdict
```

转换器支持本次三本词典实际使用的：

- MDX 1.2 / 2.0
- UTF-8
- zlib
- LZO 1.x block
- `@@@LINK=` 重定向
- 重复词头合并
- HTML 转可读纯文本

它不是完整的通用 MDict 导入器。加密词典、MDX 3.x、MDD 资源以及特殊脚本词典未承诺兼容。

## 个人使用注意

这些生成数据来自用户个人提供的词典文件。代码可以继续维护，但不要把 `Sources/TranslateCore/Resources/*.tdict` 上传到公开仓库或公开发行包。
