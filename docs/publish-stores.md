# 应用商店发布凭证获取指南

本文档介绍如何在各大应用商店为 CI/CD 流程生成所需的凭证，并存入 GitHub Secrets 供 publish-stores 工作流使用。

## Apple App Store

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)。
2. 在“用户与访问”中选择 **密钥** 标签页，点击“生成 API 密钥”。
3. 记录生成的 **API Key**（如 ABCD1234EF），同时保存下载的 .p8 私钥文件。
4. 在页面底部可看到 **Issuer ID**，复制备用。
5. 将私钥内容与 API Key 分别写入 GitHub Secret：
   - `APP_STORE_API_KEY`：API Key 字符串（例如 ABCD1234EF）。
   - `APP_STORE_ISSUER_ID`：Issuer ID 字符串。
6. 在 Xcode 中为 Runner 目标启用 **Network Extension** 和 **App Groups** 能力，
   对应的 entitlements 可参考 `ios/Runner/Runner.entitlements`。确保 Podfile 中
   已设置 `platform :ios, '14.0'`。
7. 如需提交 **macOS** 版本，请将 `macos/Podfile` 的平台设置调整为 `platform :osx,
   '12.0'`，并在 `Runner.xcodeproj` 中统一 `MACOSX_DEPLOYMENT_TARGET` 为 12.0。
   同时在 `macos/Runner/Release.entitlements` 启用 `com.apple.security.app-
   sandbox` 与 `com.apple.security.network.server` 权限。

## Google Play

1. 访问 [Google Play Console](https://play.google.com/console) 并选择应用。
2. 在“设置 → 开发者帐号 → 服务帐号”中点击“创建服务帐号”，跳转到 Google Cloud 页面。
3. 创建服务帐号后，授予 **Release Manager** 权限，并生成 JSON 格式的密钥文件。
4. 将该 JSON 文件内容存入 GitHub Secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`。

## Microsoft Store

1. 登录 [Azure 门户](https://portal.azure.com/)，在 **Azure Active Directory** 中注册一个应用程序。
2. 记录该应用的 **Tenant ID** 与 **Client ID**。
3. 在“证书与密码”页面生成一个客户端密码（Client Secret），并复制其值。
4. 前往 [合作伙伴中心](https://partner.microsoft.com/) 将上面创建的应用与 Microsoft Store 帐号关联，授予 API 权限。
5. 在 GitHub Secrets 中配置以下变量：
   - `MS_STORE_TENANT_ID`：Azure Tenant ID。
   - `MS_STORE_CLIENT_ID`：注册应用的 Client ID。
   - `MS_STORE_CLIENT_SECRET`：创建的 Client Secret。

完成凭证配置后，如需发布到 Microsoft Store，请确保构建流程额外生成 `.msix` 包（见 `windows-build.md` 第 6 步），
工作流会自动上传该文件到 Microsoft Store。

配置完成后，publish-stores 工作即会使用这些凭证自动上传构建产物，并在部署后输出对应的测试链接。

## 🔐 GitHub Secrets 配置建议

将以上信息配置在 GitHub Secrets 中，方便 GitHub Actions 流水线调用：

| Secret 名称                     | 对应平台     | 建议说明             |
|-------------------------------|--------------|----------------------|
| `APP_STORE_API_KEY`           | Apple        | Key ID               |
| `APP_STORE_ISSUER_ID`         | Apple        | Issuer ID            |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Play | 完整 JSON Key        |
| `MS_STORE_TENANT_ID`          | Microsoft    | Azure Tenant ID      |
| `MS_STORE_CLIENT_ID`          | Microsoft    | Azure 应用 Client ID |
| `MS_STORE_CLIENT_SECRET`      | Microsoft    | Azure 应用 Secret    |

---

如需使用这些密钥进行发布，请参考 `publish.yml` 工作流和文档中对应的 CI 配置。
