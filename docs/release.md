# 发布与在线更新（F4）

本文记录 MediaPlayer 的发布流水线、产物命名与在线更新约定。客户端实现见
`lib/data/update/`、`lib/app/update_providers.dart` 与 `lib/features/settings/`。

## 1. 更新源与版本规则

- 客户端只查 **GitHub Releases**：`GET https://api.github.com/repos/SakuraLoveSmile/Media-Player/releases/latest`
  （`lib/data/update/update_service.dart`）。
- 只接受**正式 Release**（`draft=false`、`prerelease=false`），标签必须是 `vX.Y.Z`，
  且 `X.Y.Z` 严格大于当前 `PackageInfo.version`。
- 没有 Release（HTTP 404）按「暂无发布版本」处理，不是错误。
- 每个 Release 必须带三个资产，名字是更新契约的一部分，不能改：

  | 平台 | 资产名 |
  |---|---|
  | Android | `MediaPlayer-android.apk` |
  | Windows x64 | `MediaPlayer-windows-x64.zip` |
  | macOS | `MediaPlayer-macos.zip` |

- 下载后必须通过 GitHub 资产 `digest`（`sha256:<64 hex>`）校验；缺校验值或校验失败
  一律拒绝安装。GitHub API 的匿名限额为 60 次/小时/IP，正常使用（启动静默检查 +
  手动检查）远低于该额度；401/403/429 会显示「GitHub 请求受限」。

## 2. 版本号与构建号

`pubspec.yaml` 的 `version: X.Y.Z+N` 是唯一版本源：

- `X.Y.Z` 必须与即将打出的 tag `vX.Y.Z` 完全一致，否则发布工作流在构建前 fail-closed。
- `N` 是 Android `versionCode`，必须**严格递增**（覆盖安装需要）。
- 应用内版本显示与 Emby 客户端 `Version` 头来自 `package_info_plus` 的
  `version+buildNumber`；`AppConfig.appVersion` 仍需同步更新（契约 §1.4）。

## 3. Android 签名（在线更新的前提）

跨版本覆盖安装要求**同一签名**。仓库里的 `android/app/build.gradle.kts` 在
`android/app/key.properties` 存在时使用固定 release keystore，否则回退 debug key
（本地 `flutter run --release` 可用，但不能用于发布）。

发布前需在仓库配置 secret（只需一次）：

```bash
base64 -i ~/.android/debug.keystore | gh secret set ANDROID_KEYSTORE_BASE64 \
  -R SakuraLoveSmile/Media-Player
```

约定（与 Music 的固定 debug keystore 相同）：

- alias：`androiddebugkey`
- store/key 密码：`android`
- 必须与**已经安装在手机上的包**使用同一把 keystore；换 key 会导致在线更新装不上，
  只能卸载重装一次。

## 4. 发布步骤

1. 更新 `pubspec.yaml` 版本（例如 `0.2.1+3`）、`AppConfig.appVersion`、README/文档。
2. 本地质量门（见 `docs/dev-setup.md`）：

   ```bash
   export LANG=en_US.UTF-8
   ~/devsdk/flutter/bin/flutter pub get
   ~/devsdk/flutter/bin/flutter analyze
   ~/devsdk/flutter/bin/flutter test
   ./tool/check_layering.sh
   ```

3. 提交并推送 `main`，确保目标提交上的 `app-ci` 通过。
4. 打标签并推送（标签必须指向已验证的提交）：

   ```bash
   git tag v0.2.1
   git push origin v0.2.1
   ```

5. `.github/workflows/release.yml` 自动执行：
   - `validate`：tag 必须等于 `v<pubspec version>`；
   - `build-android` / `build-windows` / `build-macos`：对齐生产反馈服务参数构建；
   - `publish`：校验三个资产齐全后 `gh release create --verify-tag --generate-notes`。
     已存在同名 Release 时直接失败，**绝不覆盖**已发布对象。
6. 在 Release 页面核对三个资产、`digest` 与 Release 说明；客户端启动/设置页
   「检查更新」应能看到新版本并完成下载安装。

也可以手动在 Actions 里 `workflow_dispatch` 并填 `tag_name`（标签需已存在且指向目标提交）。

## 5. 各平台安装行为

| 平台 | 行为 |
|---|---|
| Android | 下载 APK → 交给系统安装器（需要 `REQUEST_INSTALL_PACKAGES` 与系统「安装未知应用」授权）。安装完成后回到应用。 |
| macOS | `ditto` 解压 → 后台脚本等待进程退出 → 替换当前 `.app` → 清除 quarantine → 重新打开。应用会退出一次。 |
| Windows | 解压 zip → PowerShell 脚本等待进程退出 → 覆盖安装目录 → 重新启动。应用会退出一次。 |

安装目录不可写时客户端会提示改用下载页手动安装，不会尝试提权。

## 6. 本地验证（不发布也能跑）

- `flutter test test/data/update`：用 `127.0.0.1` 上的真实 HTTP 服务覆盖
  「发现更新 / 已最新 / 404 / 限流 / 下载校验 / 校验失败 / 取消」与 macOS 安装脚本语义。
- `flutter test test/app/app_wiring_test.dart`：登录页 → 设置页 → 检查更新 → 更新弹窗的整条接线。
- 真实 Release 的线上检查必须在发布后进行：`flutter build macos --release` 安装旧包，
  再发布新版本，确认「启动静默提示 → 下载 → 重启」。
- 需要不碰真实 GitHub 做端到端联调时，用 `--dart-define=UPDATE_API_BASE=http://127.0.0.1:<port>`
  指向本地 mock GitHub API（生产构建不传该值）；F4 的 macOS 全链路就是这样验证的，
  过程见 `docs/f4-notes.md` §3.1。
