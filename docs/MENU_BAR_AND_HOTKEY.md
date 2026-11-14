# 菜单栏与全局快捷键

## 默认行为

- TranslateDesk 启动后显示主窗口，并常驻 macOS 菜单栏。
- 全局快捷键为 `Option + A`。
- 无论当前位于哪个应用，按下快捷键都会显示主窗口并聚焦输入框。
- 关闭按钮和黄色最小化按钮都会把窗口隐藏到菜单栏。
- 只有菜单栏中的“退出 TranslateDesk”会结束进程。

## 快捷键冲突

全局快捷键使用 macOS Carbon Hot Key API 注册，不要求辅助功能权限。如果其他应用已经独占 `Option + A`，注册会失败，应用会显示可读错误提示。退出冲突应用后重新启动 TranslateDesk 即可重试。

## 安装

```bash
./install.sh
```

默认安装到 `/Applications`；权限不足时会请求管理员密码。也可安装到用户目录：

```bash
./install.sh --user
```

## 登录后自动启动

当前用户的 macOS 系统登录项包含唯一一条 `TranslateDesk`，路径为 `/Applications/TranslateDesk.app`。无需额外 LaunchAgent、重复启动脚本或开机前系统守护进程；首次配置后在 macOS「系统设置 → 通用 → 登录项与扩展」管理。应用仍通过菜单栏和 `Option + A` 操作。

首次更换为稳定 Apple Development 签名后，Keychain 可能需要重新授权一次访问原 API Key。请在确认提示确实来自 TranslateDesk 时选择允许；不要关闭钥匙串保护。日常使用不需要管理员密码，只有缺少 `/Applications` 写权限的**安装**过程才会请求管理员授权。
