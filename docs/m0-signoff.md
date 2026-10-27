# M0 签核记录

- 日期：2026-10-27
- 阶段：M0（选型 + 契约 + 环境就绪）
- 结论：**M0 已签核；B2 直连在 macOS、Android 真机（Mi 10）、Windows 11 x64 三平台均通过（真实 Emby 4.10.1，H.264 / HEVC 4K）；WAN、PGS/HDR 未闭环。**

## 1. M0 完成定义

1. 技术栈选定并写入 ADR。
2. 前后端共用契约冻结（端点、模型、直连策略、验收门）。
3. 本机工具链实测：至少 macOS 与 Android 能构建。
4. 明确 M1 开工顺序、依赖与外部输入。

## 2. 已冻结决策

| 项 | 决策 |
|---|---|
| 框架 | Flutter 3.47.7 stable / Dart 3.13.5 |
| 播放 | media_kit 1.2.6 + media_kit_video 2.0.1 + media_kit_libs_video（libmpv） |
| 平台 | Android 手机/平板、Windows x64、macOS Apple Silicon |
| 网络 | 同一 Emby 的 LAN HTTP + WAN frp HTTPS，双端点自动选路 |
| 直连 | LAN 下视频不得转码；允许音频单独转码 |
| WAN | 默认码率上限 30 Mbps；超限转码；可开"强制直连" |
| macOS 分发 | ad-hoc 签名、不公证、内测期关闭 Sandbox |
| 范围外 | Android TV、iOS、Linux、下载、投屏、搜索、音乐/照片 |
| 播放层 | 必须封装在 `PlaybackEngine` 后，可替换 fvp |

## 3. 环境审计（实测）

| 项 | 结果 | 证据 / 动作 |
|---|---|---|
| Flutter（构建用） | 通过 | `~/devsdk/flutter` = 3.47.7 stable，官方 remote，Dart 3.13.5 |
| Flutter（PATH 当前） | 不采用 | `~/flutter` = 3.41.3，channel `[user-branch]`、remote unknown source；B1 固定到 3.47.7 |
| macOS 构建 | 通过 | Flutter `build macos --debug` 成功，产物 `m0_smoke.app` |
| Xcode | 可用但有风险 | 仅安装 Xcode 27.0 beta（`/Applications/Xcode-beta.app`）；macOS 27.0.1 |
| Android 构建 | 通过 | Flutter `build apk --debug` 成功（含 media_kit/libmpv，四 ABI），首次 Gradle 构建 292s |
| Android 运行时 | 通过 | arm64 模拟器（Android 36）加载 libmpv 成功，本地 6s H.264/AAC 测试片播放至 6013ms |
| Android SDK | 通过 | SDK 36.0.0 / platform android-37.0 / build-tools 36.0.0 |
| JDK | 通过 | Temurin 17.0.20.1，已由 Flutter 配置指向 |
| Android license | 未确认 | `flutter doctor` 显示 license unknown；构建未阻塞，仍需执行 `flutter doctor --android-licenses` |
| CocoaPods | 通过 | 1.17.0；终端 locale 非 UTF-8 时有告警，构建前设 `LANG=en_US.UTF-8` |
| adb / 测试机 | 通过 | adb 37.0.1；Mi 10（Android 16 / API 36）曾连接；当前用 headless AVD（Android 36 / arm64）做运行时验证 |
| Windows 构建 | 通过 | GitHub Actions `windows-latest`：`flutter analyze/test` + `build windows --release` 成功，产出 `windows-smoke-x64` artifact |
| Windows 运行时 | 通过 | Win11 x64 真机（26200，i7-14650HX / RTX 5060 Laptop / 1920×1080）：HEVC 4K MKV 与 H.264 1080p MKV 均直连播放，`errors=[]`，exit 0 |
| Git 仓库 | 未初始化 | 工作目录为空；由 B1 初始化 |

## 4. 冒烟构建记录

- 临时工程：`/tmp/m0_smoke_47951`（一次性验证，不入库）。
- `flutter create --platforms=android,macos`：exit 0。
- `flutter build macos --debug`：exit 0，产物 `build/macos/Build/Products/Debug/m0_smoke.app`。
- `flutter build apk --debug`：exit 0，产物约 220 MiB（四 ABI + libmpv，debug）。
- 已知告警：
  - Gradle 首次构建 629s；引入 media_kit 后增量构建 292s；CI 必须缓存 Gradle/pub。
  - "SDK XML versions up to 3 but version 4 encountered"：工具版本不同步告警，未阻塞。
- **未做**：真实 Emby 播放（属 B2，需外部输入）。

### 4.1 media_kit 集成冒烟（新增）

- 依赖解析：`media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`。
- macOS：`build macos --debug` 成功；运行本地 6s H.264/AAC 测试片，`duration=6023ms`，position 从 33ms 递增到 1033ms+，无 `M0_ERROR`。
- macOS 告警：`media_kit_video` / `media_kit_libs_macos_video` 不支持 Swift Package Manager，当前走 CocoaPods；未来 Flutter 版本可能将其变为错误，升级前必须复核。
- macOS 非阻塞告警：直接运行 .app 二进制时出现一次 `sandbox_extension_issue_file_to_process ... Operation not permitted`，播放未受影响；正式验证用 `flutter run` 或 `open`。
- Android：`build apk --debug` 成功，产物 229.7 MB（四 ABI + libmpv）；首次 Gradle 构建 292s。
- Android 运行时：arm64 模拟器上 `libmpv.so` 加载成功，`M0_OPEN_OK`，duration 6023ms，position 递增至 6013ms，无 FATAL/AndroidRuntime 错误。
- **未验证**：HEVC/PGS/HDR/高码率与 Emby 直连流，仍属 B2。

### 4.2 网络/编解码预检（pre-B2，非 Emby）

- 本地 HTTP 服务：MP4、HEVC Main10 MKV（1280x720）、HLS、外挂 SRT；受保护路径要求 `X-Test-Token`。
- macOS 4/4 通过：HTTP MP4 6023ms；HEVC MKV 8023ms（1280x720，Header 200，SRT tracks=2）；HLS 6013ms；无 `M0_ERROR`。
- **关键发现**：Flutter macOS 默认 Debug entitlements 只有 `network.server`，没有 `network.client`；缺失时所有网络播放报 `Operation not permitted`。B1/F4 必须给 Debug 与 Release 都加 `com.apple.security.network.client`。
- Android 模拟器：asset 通过；网络流 position 恒为 0（模拟器特有）。**真机 Mi 10（Android 16）已通过 HEVC 4K MKV 直连**，query/header 两种鉴权均可用，position 12.3s/13.2s，3840×2160，无 FATAL。
- 测试服务器：`SimpleHTTPRequestHandler` 默认不支持 Range，导致 MP4 无法 seek；补 206 后 macOS 通过。Emby 本身支持 Range，B2 按真实服务器验证。
- 真实 Emby（4.10.1）：macOS 与 Mi 10 直连 H.264 1080p、HEVC Main10 4K（MP4）、HEVC 4K（MKV）均通过；URL `api_key` 与 `X-Emby-Token` header 两种鉴权都可用；详见 `docs/b2-poc.md`。
- Windows 真机（Win11 x64）：Release 冒烟通过，HEVC 4K MKV 3840×2160、H.264 1080p MKV 1920×1080 均为 `directPlay=True`、无 `TranscodingUrl`，`errors=[]`，460 条位置更新；详见 `docs/b2-poc.md`。
- 仍未验证：PGS、HDR10、60–80 Mbps、WAN。

## 5. 未闭环项

### 5.1 阻塞 B2 / T2（需要用户提供）

1. ~~Emby LAN 地址与只读账号~~（已提供；仅用于本地测试，不写入仓库）。
2. Emby WAN 地址（frp HTTPS）。
3. PGS / HDR10 / 60–80 Mbps 样本（HEVC 4K 已在库内找到；PGS 未发现）。
4. frp 线路实际的上行带宽（用于校准 WAN 默认 cap）。
5. ~~Windows 10/11 x64 测试机或 CI runner~~（已提供 Win11 x64 真机 + CI runner，冒烟通过）。

### 5.2 工程内动作（B1 处理）

1. 固定 Flutter 3.47.7（fvm 或绝对路径），禁止使用 PATH 中的 3.41.3。
2. 接受 Android SDK licenses。
3. 构建脚本设置 `LANG=en_US.UTF-8`。
4. 初始化 Git 仓库并提交 `docs/`。
5. 建立三平台构建脚本；Windows CI 构建与产物上传已就绪（`.github/workflows/windows-smoke.yml`），沿用即可。
6. macOS Debug/Release entitlements 增加 `com.apple.security.network.client`（已实测必需）。
7. Android 允许 LAN 明文 HTTP：F4 用 networkSecurityConfig 或 `usesCleartextTraffic`，release 也要覆盖。

## 6. M1 开工顺序（待输入到位后）

| 顺序 | 卡 | 角色 | 依赖 |
|---|---|---|---|
| 1 | B1 工程脚手架 | 后端 | 无 |
| 2 | B2 直连 PoC（栈门） | 后端 | B1 + 样本/账号 |
| 3 | B3 端点解析、认证与存储 | 后端 | B1 |
| 4 | B4 媒体库查询层 | 后端 | B3 |
| 5 | F1 双地址配置与登录 | 前端 | B3 |
| 6 | T1 契约与单元测试 | 测试 | B3、B5（可先起 fixtures） |

- B2 必须 Day 1 出结论；任一平台直连 HEVC MKV + PGS 失败即触发备选播放内核评估。
- F1/F2 可在契约冻结后用 fake repository 并行开发。
- M1 Gate：LAN 登录 + 浏览 + 三平台直连 PoC 通过。

## 7. M0 新发现的风险

1. **WAN 验证缺位**：frp HTTPS 链路（证书、码率、DNS/端口）是当前最大未闭环项，不能用 LAN 结果推断公网可用。
2. **Xcode beta**：macOS 构建已通过，但正式发布前应换稳定版 Xcode 复测。
3. **首次 Gradle 构建慢**：CI 必须缓存 Gradle/pub，否则每次流水线 10 分钟起步。
4. **debug APK 约 220 MiB**（四 ABI + libmpv）：release 必须做 ABI 拆分/App Bundle，目标 ≤80 MB/ABI。
5. **Flutter 双 SDK**：PATH 指向不可复现的 3.41.3，必须固定 3.47.7，否则"我这能跑"无法复现。
6. **media_kit 发布节奏慢**：锁版本 + 播放层抽象，不随 pub 升级漂移。
7. **macOS 网络权限**：默认模板缺 `network.client`，会让 LAN Emby 完全不可用；已实测，B1/F4 必须补。
8. **Android 模拟器网络播放异常**：duration 能解析但 position 恒为 0；真机 Mi 10 已通过，模拟器结果不作为验收依据。
9. **Windows 覆盖面窄**：仅一台 RTX 5060 Laptop + 独显直连环境通过，未覆盖纯核显机器、HDR 显示与多显示器缩放；M1 需至少再跑一次非开发机环境。

## 8. 签核

| 项 | 结论 |
|---|---|
| 技术栈 | 通过（条件：B2 直连 PoC 三平台通过） |
| 契约 v1.1 | 冻结，可据此开发 |
| macOS 工具链 | 通过 |
| macOS 网络预检 | 通过（HTTP / HEVC MKV / HLS / 外挂 SRT / Header 鉴权） |
| B2 直连（macOS + Android 真机） | 通过（H.264 1080p / HEVC Main10 4K / HEVC 4K MKV；详见 `b2-poc.md`） |
| Android 工具链 | 通过（含 media_kit 构建与模拟器本地播放） |
| Android 网络预检 | 通过（Mi 10：HEVC 4K MKV；query/header） |
| Windows 工具链 | 通过（CI `windows-latest`：analyze/test/release build + artifact） |
| B2 直连（Windows 真机） | 通过（Win11 x64：HEVC 4K MKV / H.264 1080p MKV，`directPlay=True`，`errors=[]`） |
| 外部输入 | LAN+账号、Windows 真机已提供；WAN、PGS/HDR 样本未提供 |

**下一步**：提供 5.1 中的 WAN 地址与 PGS/HDR/高码率样本后，按第 6 节顺序进入 M1；B2 直连门已在 macOS / Android Mi 10 / Windows 11 x64 三平台达成，可直接进入 B1 + B3/B4。
