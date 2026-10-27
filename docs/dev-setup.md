# 开发环境与构建

本文件记录**实测可用**的工具链路径与命令。目的是让任何一台机器都能复现同一套构建，而不是依赖当前 shell 的 PATH。

## 1. Flutter SDK

- 使用：`~/devsdk/flutter/bin/flutter`，版本 **3.47.7 stable / Dart 3.13.5**。
- **不要**使用 PATH 中的 `flutter`：当前指向 `~/.local/bin/flutter` = 3.41.3，channel `[user-branch]`、来源不可复现，构建行为与本项目不一致。

验证：

```bash
~/devsdk/flutter/bin/flutter --version   # 必须是 3.47.7
```

所有文档与 CI 中的命令都以该绝对路径为准；CI 通过 `subosito/flutter-action` 固定 `flutter-version: '3.47.7'`。

> 升级 Flutter 时必须同时修改 `.github/workflows/app-ci.yml`、`.github/workflows/windows-smoke.yml` 与本文件，并在三平台各跑一次构建。

## 2. 依赖

```bash
cd <repo>
~/devsdk/flutter/bin/flutter pub get
```

- `pubspec.lock` 已入库，禁止在未说明原因的情况下 `pub upgrade`。
- media_kit 三件套锁死：`media_kit 1.2.6` / `media_kit_video 2.0.1` / `media_kit_libs_video 1.0.7`（B2 实测组合，含 libmpv）。
- 不引入 codegen（freezed/json_serializable）与 mock 框架；模型手写 `fromJson`，测试用 fake。

## 3. 平台前置

| 平台 | 要求 | 状态 |
|---|---|---|
| macOS | Debug/Release entitlements 均含 `com.apple.security.network.client` | 已写入 `macos/Runner/*.entitlements` |
| Android | `INTERNET` 权限 + 应用级 `usesCleartextTraffic="true"`（LAN HTTP） | 已写入 `android/app/src/main/AndroidManifest.xml` |
| Windows | 无额外配置（media_kit 自带 libmpv dll） | — |

- Android release 包联网必须依赖上面的 `INTERNET` 权限；只加在 debug/profile manifest 里会导致 release 版所有请求失败。
- 全局明文是已知的安全放宽：WAN 必须走 HTTPS，LAN 才允许 HTTP。

## 4. 构建

```bash
export LANG=en_US.UTF-8     # CocoaPods 在非 UTF-8 locale 下会告警

# macOS
~/devsdk/flutter/bin/flutter build macos --debug     # 日常验证
~/devsdk/flutter/bin/flutter build macos --release   # 交付

# Android（release 必须拆 ABI，否则单包 >200 MB）
~/devsdk/flutter/bin/flutter build apk --release --split-per-abi

# Windows
~/devsdk/flutter/bin/flutter build windows --release
```

产物位置：

| 平台 | 路径 |
|---|---|
| macOS | `build/macos/Build/Products/Release/media_player.app` |
| Android | `build/app/outputs/flutter-apk/app-<abi>-release.apk` |
| Windows | `build/windows/x64/runner/Release/` |

## 5. 质量门

```bash
./tool/check_layering.sh      # 分层守卫：features 不得直接 import dio/media_kit，core/data 不得 import features
~/devsdk/flutter/bin/flutter analyze
~/devsdk/flutter/bin/flutter test
```

三平台构建与上述检查由 `.github/workflows/app-ci.yml` 在 push 时执行；`spike/windows_smoke/` 有独立的 `windows-smoke.yml`，两者的路径过滤互不触发。

## 6. 平台的已知坑

| 现象 | 原因 | 处理 |
|---|---|---|
| macOS 所有网络加载报 `Operation not permitted` | 默认 entitlements 只有 `network.server` | 两份 entitlements 都加 `network.client`（已修） |
| `flutter analyze` 报 `spike/` 下文件 | 根工程与 spike 的嵌套 pubspec | `analysis_options.yaml` 排除 `spike/**`（已配） |
| Android 模拟器网络流 position 恒为 0 | 模拟器特有 | 以真机（Mi 10）为准 |
| Gradle 首次构建 5–10 分钟 | 无缓存 | CI 使用 `cache: true`；本地可忽略 |
| CocoaPods locale 告警 | 终端非 UTF-8 | `export LANG=en_US.UTF-8` |

## 7. 验收命令（B1）

```bash
./tool/check_layering.sh
~/devsdk/flutter/bin/flutter analyze              # No issues found
~/devsdk/flutter/bin/flutter test                 # 4 tests pass
codesign -d --entitlements :- build/macos/Build/Products/Release/media_player.app | grep network.client
~/Library/Android/sdk/build-tools/36.0.0/aapt2 dump xmltree --file AndroidManifest.xml \
  build/app/outputs/flutter-apk/app-debug.apk | grep usesCleartextTraffic
```
