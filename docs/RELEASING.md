# 发布指南

## 本地构建

```bash
swift test
./scripts/build_app.sh
./scripts/package_dmg.sh
```

## 修改应用身份

发布前修改 `scripts/build_app.sh` 中的：

- `CFBundleIdentifier`
- `CFBundleShortVersionString`
- `CFBundleVersion`

同时修改 DMG 文件名和 README 中的版本。

## 签名

本机安装由 `scripts/build_app.sh` 使用固定的 **Apple Development** 证书签名，避免每次临时 ad-hoc 签名改变应用身份，引发钥匙串重复询问。可用 `TRANSLATEDESK_CODESIGN_IDENTITY` 指定另一台开发机的证书；无有效证书时构建明确失败，不会降级为临时签名。

```bash
./scripts/install_app.sh --system
codesign --verify --deep --strict /Applications/TranslateDesk.app
```

成功安装后会清理 `dist/TranslateDesk.app` 构建副本，本机只保留 `/Applications/TranslateDesk.app` 可启动应用。

以上仅用于本机开发安装；**公开分发**需要另外使用 `Developer ID Application` 签名并完成公证，不应直接复用 Apple Development 签名。钥匙串中的现有 API Key 不迁移、不导出。

## Notarization

建议使用 `notarytool`：

```bash
xcrun notarytool submit dist/TranslateDesk-1.6.0.dmg \
  --keychain-profile "AC_NOTARY" \
  --wait

xcrun stapler staple dist/TranslateDesk-1.6.0.dmg
```

## GitHub Release

1. 合并通过 CI 的版本分支。
2. 创建版本标签：

```bash
git tag v1.6.0
git push origin v1.6.0
```

3. 上传 notarized DMG。
4. Release Notes 至少说明：
   - 新增或修改的服务商。
   - 配置 schema 是否变化。
   - 是否需要迁移 Keychain 或配置。
   - 隐私与网络请求变化。

## 发布前服务检查

对每个内置外部服务确认：

- 当前 API 地址和请求格式。
- 使用条款和可接受用途。
- 免费额度、速率限制和商业发布限制。
- 数据保留和隐私政策。
- 是否需要在 App 内提供归属或免责声明。
