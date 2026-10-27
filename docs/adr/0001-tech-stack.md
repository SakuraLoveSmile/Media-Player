# ADR 0001：三平台 Emby 客户端技术栈

- 状态：Accepted（M0，2026-10-27）
- 决策：Flutter stable + media_kit/libmpv 单代码库，覆盖 Android / Windows / macOS
- 关联：`docs/contracts/emby-client-contract-v1.1.md`、`docs/m0-signoff.md`

## 背景

- 目标产品是连接局域网 Emby Server 的媒体库客户端，首阶段完成"连接 → 浏览 → 播放"。
- 平台：Android 手机/平板、Windows x64、macOS（Apple Silicon）。
- 网络：局域网 HTTP 直连；公网经 frp HTTPS 反向代理访问同一台 Emby。
- 硬要求：LAN 下视频直连（不转码），HEVC/MKV/PGS 等真实片源可播。
- 约束：独立新项目；暂无 Apple Developer ID；单人维护为主。

## 决策

采用 **Flutter stable + Dart + Riverpod + media_kit（libmpv）**：

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.47.7 stable / Dart 3.13.5 |
| 状态 / 路由 | flutter_riverpod + go_router |
| 网络 | dio（认证头拦截器） |
| 播放 | media_kit 1.2.6 + media_kit_video 2.0.1 + media_kit_libs_video |
| 存储 | flutter_secure_storage（token，macOS 可回退文件）+ shared_preferences（配置） |
| 辅助 | cached_network_image、wakelock_plus、path_provider、package_info_plus |
| 工程 | 单 package + feature 分层；锁定 `pubspec.lock`；固定唯一 SDK |

### 版本基线

- **使用** `~/devsdk/flutter`：3.47.7 stable，官方 remote，2026-10-08 发布。
- **不使用** PATH 当前指向的 `~/flutter`：3.41.3，channel 为 `[user-branch]`、remote 为 unknown source，不可复现。
- B1 需将构建脚本/CI 固定到 3.47.7；可选 fvm 锁定版本。
- 其余依赖在 B1 解析后以 `pubspec.lock` 为准；media_kit 系版本显式锁定，不随 pub 升级漂移。

### 关键工程约束

- 播放内核必须隐藏在 `PlaybackEngine` 接口后，UI 与业务层不得直接依赖 media_kit 类型。
- 端点解析（LAN/WAN）集中在 `EndpointResolver`，业务层不得自行拼接 base URL。
- 直连判定以 Emby 会话状态为准，不以本地 URL 形态推断。
- media_kit 平台下限：Android 5.0+（API 21）、macOS 10.9+、Windows 7+；性能验证必须用 release 构建，Android 使用 `--split-per-abi`。

## 备选方案

| 方案 | 结论 | 原因 |
|---|---|---|
| Flutter + media_kit | **采用** | 一套代码覆盖三平台；libmpv 覆盖 MKV/HEVC/PGS/HLS；已有 Flutter+media_kit 的 Emby 客户端先例（medio） |
| Flutter + fvp（libmdk） | 播放层备选 | 同样全平台、硬件解码；作为 media_kit 维护停滞或平台兼容失败时的替换项 |
| Tauri 2 + hls.js | 不采用 | 包体小、Rust 顺手，但 WebView 编解码受限，MKV/HEVC/PGS 不可靠，只能重度依赖转码，违背直连硬要求 |
| Compose Multiplatform | 不采用 | 桌面播放生态弱，macOS 为 JVM 应用，包体与体验不占优 |
| 三端原生（Media3 / AVPlayer / LibVLC） | 后续升级路径 | 兼容性最好，但 3 套 UI + 3 套播放，首阶段成本过高 |
| React Native / .NET MAUI | 不采用 | Windows/macOS 视频与 Emby 生态不成熟 |

## 后果

正面：

- 一套 UI 与业务代码覆盖三平台，迭代成本最低。
- libmpv 对直连片源（MKV/HEVC/PGS/多音轨/HLS）覆盖度高，满足 LAN 直连要求。
- 播放层可替换（fvp），不会被单一包锁死。

负面 / 需接受：

- 随包分发 libmpv（LGPL 2.1+ 构建）：需动态链接、保留 LGPL 声明与可替换性说明；分发前复核。
- 安装包体积增大（Android 每 ABI 数十 MB，桌面约百 MB 级）。
- media_kit 发布节奏慢（1.2.6 为 2025-12），需锁定版本并保留替换方案。
- media_kit 的 macOS 插件尚未支持 Swift Package Manager；Flutter 3.47.7 已告警"未来将变为错误"。当前经 CocoaPods 可正常构建，但升级 Flutter 前必须确认 SPM 支持。
- macOS 无 Developer ID：只能 ad-hoc 签名、不公证，Gatekeeper 需用户手动放行。
- Android TV、iOS、Linux 不在首阶段范围；TV 端如后续需要，建议单独评估 ExoPlayer。

## 环境约束（M0 实测）

- macOS 27.0.1 arm64；仅安装 Xcode 27.0 beta（`/Applications/Xcode-beta.app`）；macOS debug 构建已通过。
- Android SDK 36.0.0 / platform android-37.0 / build-tools 36.0.0；JDK 17（Temurin 17.0.20.1）已配置给 Flutter；Android license 状态未知，需接受。
- CocoaPods 1.17.0；终端需 UTF-8 locale 才能避免告警。
- 已连接测试机：Mi 10（Android 16 / API 36）；另用 headless arm64 模拟器（Android 36）完成运行时冒烟。
- media_kit 冒烟：macOS 与 Android arm64 模拟器均成功播放本地 6s H.264/AAC 测试片（duration 6023ms，position 到 6.0s）。
- 网络预检（macOS）：HTTP MP4、HEVC Main10 MKV（1280x720）、HLS、外挂 SRT、Header 鉴权全部通过；HTTP Range 需服务端支持（本地测试服务器补 206 后 MP4 可播）。
- **macOS App Sandbox 必须包含 `com.apple.security.network.client`**；Flutter 默认模板只有 `network.server`，缺失时所有网络播放报 `Operation not permitted`（已实测）。Debug/Release 两份 entitlements 都要加。
- Android 模拟器：本地 asset 可播，但网络流 position 恒为 0（模拟器特有）。**Mi 10 真机已通过 HEVC 4K MKV 直连**（query/header 两种鉴权、3840×2160、无 FATAL），模拟器结果不作为验收依据。
- **Windows 已闭环**：`windows-latest` CI 完成 `flutter analyze/test` + `build windows --release` 并上传 artifact；Win11 x64 真机（i7-14650HX / RTX 5060 Laptop / 1920×1080）release 冒烟直连 HEVC 4K MKV 与 H.264 1080p MKV，`errors=[]`。未覆盖纯核显与 HDR 环境。

## 重新评估触发条件

1. B2 直连 PoC 在任一目标平台失败（HEVC MKV + PGS）。
2. media_kit 出现阻塞性缺陷且 6 个月无修复。
3. 需要 Android TV 完整遥控、Dolby Vision/HDR10+ 完整支持、或 iOS/Linux。
4. LGPL 合规评估不通过，且无法通过替换 libmpv 构建解决。
