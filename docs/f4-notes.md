# F4：反馈组件与在线更新

- 日期：2026-11-02（本地 Asia/Taipei；验证跨至 11-03 凌晨）
- 范围：接入 Feedback 组件（`feedback_widget` 0.8.4；2026-11-16 升级到 0.9.1 并接入宿主诊断日志，见 §6；2026-11-23 升级到 0.10.0，见 §7；同日升级到 0.11.0 并把设置迁到宿主，见 §8；同日升级到 0.14.0，见 §9；同日升级到 0.15.0 并把安卓返回交给组件，见 §10；2026-11-24 升级到 0.16.0 并托管灵感球边缘反射，见 §11；同日升级到 0.17.0 并在唤醒触点示范手绘圈选，见 §12）、设置页、GitHub Releases 在线更新、发布工作流
- 版本：`v0.2.3`（`0.2.3+5`）已发布，升级 `feedback_widget` 至 0.8.6；更新日志改为每版手写
- 结论：**`v0.2.0`–`v0.2.3` 均已发布；0.8.6 的灵感球背景更新已随 v0.2.3 上线，真机体验待确认**

## 1. 已确认的决定

| 项 | 决定 | 依据 |
|---|---|---|
| 反馈组件版本 | `feedback_widget` **0.17.0**，Git tag `v0.17.0`（commit `9b8ddcdeac85b105587bd1052bbe758d8a8a130e`，`flutter/feedback` 子目录；0.17.0 起唤醒后示范手绘圈选，新版圈选、灵感球边缘反射、关闭前确认与组件接管安卓返回沿用） | Feedback 仓库最新正式标签；public 仓库用 HTTPS Git 依赖，CI 无需 deploy key |
| 宿主诊断日志 | `FeedbackDiagnosticsRecorder` 收集 dio 请求事件（方法 + 归一化路径、状态码、耗时）与 Flutter/平台错误；`buildFeedbackConfig` 默认挂 `logProvider`，面板打开时导出 JSONL，失败/无事件不阻断提交 | Feedback integration.md §5.6「宿主日志接入是必过的接入验收项」；只写白名单标量，请求体、凭据、完整 URL 与异常文本不进入缓冲 |
| 反馈服务 | 生产地址 `https://feedback.xn--fhqths51enha.cn`，`appId = dev.mediaplayer.media_player`，`appName = Media Player` | 迁移前的历史决定（当时与 Android applicationId 一致）。应用标识已统一为 `cn.sakuralovesmile.mediaplayer`，此 appId 保持不变：它是反馈服务端侧的软件主键，改动会使历史反馈与面板登录态落到新软件下 |
| 反馈默认开关 | release/profile 默认开启；debug 与 `flutter test` 默认关闭；可用 `FEEDBACK_ENABLED` / `FEEDBACK_API_BASE` / `FEEDBACK_APP_ID` / `FEEDBACK_APP_NAME` 覆盖 | 开发与既有测试不受影响；发布构建显式传 `--dart-define` |
| 反馈入口 | 亮色主题、视口截图；入口样式由用户在「设置 → 反馈」选择，默认光束唤醒（双指长按 / ⌘·Ctrl+Shift+F），可切回右侧灵感球；面板设置页只留服务器设置；播放页隐藏入口；登录页服务器地址/用户名包 `FeedbackCaptureMask` | 与 app 亮色主题一致；避免遮挡播放控件；截图不泄露地址/账号；设置集中在宿主，避免两处重复 |
| 更新源 | GitHub Releases API（`SakuraLoveSmile/Media-Player`，public），只接受正式 Release | 用户确认：不引入仓库内清单与镜像维护；API 匿名限额足够个人使用 |
| 更新入口 | 启动静默检查（仅 release/profile，发现更新弹一次弹窗）+ 设置页手动「检查更新」 | 兼顾“自动发现”与可手动重试 |
| 安装范围 | Android APK / macOS zip / Windows zip 三平台原地更新 | 契约目标三平台；iOS/Linux 不在范围 |
| Android 签名 | 发布使用固定 keystore secret `ANDROID_KEYSTORE_BASE64`（alias `androiddebugkey`，密码 `android`），本地无 key.properties 时回退 debug key | 在线更新必须跨版本同签名才能覆盖安装 |

## 2. 实现映射

| 能力 | 文件 |
|---|---|
| 反馈编译期配置 / provider / 页面标签白名单 / `logProvider` | `lib/app/feedback_config.dart` |
| 宿主诊断日志（记录器、dio 拦截器、异常捕获） | `lib/app/feedback_diagnostics.dart`、`lib/app/providers.dart`、`lib/main.dart` |
| 反馈浮层（外层 Navigator + 控制器生命周期 + 返回键） | `lib/app/feedback_layer.dart` |
| 灵感球设置的宿主存储与状态（v0.8.4 增补） | `lib/app/feedback_orb_settings.dart`、`lib/app/services.dart`（复用 `KeyValueStore`） |
| 根接线（浮层挂载、页面标签同步、启动静默检查、弹窗触发） | `lib/app/app.dart`、`lib/app/router.dart` |
| 设置页（关于 / 检查更新 / 问题反馈） | `lib/features/settings/settings_page.dart` |
| 更新弹窗（说明、进度、安装/重试/取消） | `lib/features/settings/update_dialog.dart` |
| 版本与更新状态机 | `lib/app/update_providers.dart` |
| GitHub Release 解析、版本比较、资产选择 | `lib/data/update/update_models.dart` |
| 检查 / 下载 / SHA-256 校验 | `lib/data/update/update_service.dart` |
| Android / macOS / Windows 安装器 | `lib/data/update/update_installer.dart` |
| 登录页设置入口与敏感区遮挡 | `lib/features/login/login_page.dart` |
| 媒体库页设置入口 | `lib/features/library/library_page.dart` |
| Android 安装权限、固定签名配置 | `android/app/src/main/AndroidManifest.xml`、`android/app/build.gradle.kts` |
| 发布流水线 | `.github/workflows/release.yml`、`docs/release.md` |
| 用户可读更新日志 | `release/notes/vX.Y.Z.md`（GitHub Release 正文 + 应用内更新弹窗），流水线缺文件即失败 |

关键行为：

- 设置页顶部「关于」显示 `package_info_plus` 的 `version+buildNumber`；未加载时回退
  `AppConfig.appVersion`。
- 手动检查：`checking` 时禁用并显示「检查中…」；`idle` → 「当前已是最新版本」；
  `available` → 更新弹窗；`error` → SnackBar 显示原因。启动静默检查失败不打扰用户。
- 下载显示字节进度；取消回到 `available`；完成后校验 GitHub `digest`，不匹配删除文件并报错。
- `dismiss()` 清理临时下载目录；`generation` 计数保证取消/关闭后的迟到回调不覆盖新状态。
- 资产名是契约：`MediaPlayer-android.apk`、`MediaPlayer-windows-x64.zip`、
  `MediaPlayer-macos.zip`；缺失对应资产时弹窗提供「打开下载页」。
- 本地联调可用 `--dart-define=UPDATE_API_BASE=http://127.0.0.1:<port>` 指向 mock GitHub API；
  生产构建不传该值。


### 2.1 灵感球设置的宿主托管（v0.8.4 增补）

- 设置页「反馈」分组新增两项：
  - **灵感球样式**：小把手（默认）/ 球体贴边 / 隐藏。0.8.5 起「隐藏」只作用于待机
    （收起）状态：完整球先显示，闲置 5 秒后不显示收起入口；已开启的唤醒手势仍可唤醒，
    也可从「问题反馈」打开面板改回。
  - **唤醒灵感球**：双指长按 / 三指上滑 / 双指双击，可多选，默认关闭；只在 App 内生效，
    松手后再拖球截图。
- 组件 v0.8.4 新增 `FeedbackWidget.orbIdleStyle/onOrbIdleStyleChanged` 与
  `wakeGestures/onWakeGesturesChanged`。宿主提供值 + 回调后，组件不再自行持久化；面板内
  「设置 → 灵感球 / 唤醒方式」与设置页读写同一份宿主值，不会出现两套偏好。
- v0.8.5 修正「隐藏」语义（只隐藏待机收起入口，不再取消唤醒手势/完整球），偏好键与
  编解码保持兼容。
- v0.8.6 修复灵感球背景残留：完整球/贴边球/小把手可见期间持续更新背景，切页或内容变化
  后不再停在旧画面；采样串行、成功后间隔 250ms，面板打开/隐藏/后台/卸载时停止，失败退回
  透明轮廓。组件无新增公共接口或配置，数据库 schema 仍为 14。
- 持久化复用 App 已有的 `KeyValueStore`（`AppServices.store`，契约 §7；macOS ad-hoc 为
  0600 文件、其余平台走平台安全存储），键为 `feedback.orb_idle_style.v1` /
  `feedback.wake_gestures.v1`。未知/损坏值回退默认；写入失败保留旧值，设置页提示
  「保存失败，请稍后重试」，面板内改动失败只记录日志。
- 存储失败时提供读取兜底（默认值），设置页显示「读取失败，点击重试」；加载中显示「读取中…」。
- 并发写入按最新状态合并（同时修改样式与手势不会互相覆盖），由单元测试覆盖。
- 真实打包 app 的界面截图：[设置页新增分组](screenshots/f4-orb-settings.png)、
  [灵感球样式弹窗](screenshots/f4-orb-style-dialog.png)。
- 更新日志改为每个版本手写 `release/notes/vX.Y.Z.md`（GitHub Release 正文 + 应用内更新弹窗）；
  发布前用本地 mock 在真实包上核对排版：[更新弹窗中的更新日志](screenshots/f4-update-notes.png)。

## 3. 验证记录

| 项目 | 结果 | 证据 |
|---|---|---|
| `flutter analyze`（全仓） | 通过，零问题 | 见本轮执行记录 |
| `flutter test`（全仓） | 通过，308 项 | 含原 190 项 + 反馈/更新 105 项 + 灵感球设置 13 项 |
| `tool/check_layering.sh` | 通过 | — |
| 反馈组件行为 | 22 项测试（配置 15 + 浮层 7） | 挂载、orb 语义、导航不重建、config 更新、控制器 open/close、返回键三分支 |
| 更新内核 | 65 项测试 | 本地 127.0.0.1 HTTP：有更新/已最新/404/限流/下载进度/SHA-256 成功与失败/取消；macOS 安装脚本用真实 bash+ditto+open stub 执行验证替换与清理 |
| 设置页/弹窗 | 15 项测试 | 版本显示、无更新/失败 SnackBar、检查中禁用、反馈入口显示/隐藏、各状态按钮与进度 |
| 应用接线 | 4 项测试 | 登录页设置入口、手动检查→弹窗、反馈浮层挂载与反馈入口、面板回调→宿主存储回传 |
| 灵感球设置 | 13 项测试 | 默认值/加载/损坏回退/持久化/并发合并/写失败保留旧值；设置页样式与手势选择、隐藏样式、失败 SnackBar；浮层透传与隐藏入口 |
| macOS release 构建 | 通过 | `build/macos/.../Release/Media Player.app`（96.2MB）；`Info.plist` = `0.2.0` / `2`；bundle 内含 `packages/feedback_widget/shaders/orb_lens.frag`；entitlements 含 `network.client` |
| Android release 构建 | 通过 | `flutter build apk --release`（固定测试 keystore）：`versionCode=2` / `versionName=0.2.0` / `targetSdk=36`，含 `REQUEST_INSTALL_PACKAGES`，APK 使用临时固定 keystore 签名（CN=MediaPlayer Test）；构建后已删除临时 keystore 与 `android/app/key.properties` |
| 打包后真实 E2E（macOS） | 通过 | 见 §3.1；截图 `screenshots/f4-update-dialog.png` |
| 真实 GitHub 发布 | 通过 | `v0.2.0` 正式 Release（非草稿/非预发布），三资产齐全：Android 99,274,510B / Windows 34,132,606B / macOS 37,002,579B；APK 签名证书与本地 debug keystore 一致（`766b6a19…`），`versionCode=2`；macOS zip 为 `0.2.0/2` |
| 真机更新安装 | 待体验 | 本轮只在一次性 app 副本上验证了 macOS 全链路；真机需安装旧包后由 Release 升级 |

### 3.1 macOS 打包后在线更新全链路（本地 mock GitHub API）

本节使用最终依赖（`feedback_widget` 0.8.4）的 release 构建复跑通过。

环境：macOS arm64；`flutter build macos --release`，`--dart-define=UPDATE_API_BASE=http://127.0.0.1:18123`
仅本次本地验证使用，生产构建不传；反馈走生产服务的真实 dart-define。
把 release `.app` 复制到 `/tmp`（旧包 `0.2.0+2`），另复制一份改 `Info.plist` 为 `0.2.1/3`
经 `ditto` 打成 `MediaPlayer-macos.zip`，本地 mock 服务（Python `http.server`）返回
GitHub Releases `latest` JSON、资产 `digest`（SHA-256）与 zip 字节。

1. 启动打包后的旧 app：`GET /repos/SakuraLoveSmile/Media-Player/releases/latest`
   （`User-Agent: MediaPlayer/0.2.0`）→ 自动弹出「发现新版本 v0.2.1」，显示更新说明、
   资产名与大小（35.2 MB）。截图：`screenshots/f4-update-dialog.png`。
2. 点击「立即更新」→ `GET /download/MediaPlayer-macos.zip`（`User-Agent: MediaPlayer-updater`）
   → 下载完成并经 SHA-256 校验 → 按钮变为「立即安装」。
3. 点击「立即安装」→ 旧进程退出 → 后台脚本 `ditto` 替换当前 `.app`、清除 quarantine、
   重新打开；路径不变，`Info.plist` 变为 `0.2.1/3`，新进程请求版本时
   `User-Agent: MediaPlayer/0.2.1`；解压临时目录被清理。
4. 全部 E2E 使用一次性 `/tmp` app 副本与本地 mock 服务，结束后已删除；
   未触碰真实 GitHub、未发布任何 Release、未改动本机已安装的 app。

### 3.2 真实 Release 核验（v0.2.0）

- `app-ci`（analyze-test / Android / macOS / Windows）在 tag 前的 `aae388c` 全绿。
- 发布流水线 `release` 全部 5 个 job success：tag 校验、三平台构建、创建 Release。
- `GET /repos/SakuraLoveSmile/Media-Player/releases/latest` 返回 `v0.2.0`，`draft=false`、
  `prerelease=false`；三个资产的 `digest` 与下载复算 SHA-256 一致。
- 下载的 CI APK：`versionCode=2`、`versionName=0.2.0`、签名证书 SHA-256 与本机
  `~/.android/debug.keystore` 相同（可在本地 debug 安装上直接覆盖）；macOS zip 解包后
  `Info.plist=0.2.0/2` 且包含 feedback 着色器。
- 下载地址：<https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0>。

### 3.3 灵感球设置的本地核验（已随 v0.2.1 发布）

- `flutter analyze` 零问题；全仓 308 项测试通过；`check_layering.sh` 通过。
- macOS release 构建通过（`0.2.1+3`，96.3MB）；在真实打包 app 中打开「设置」确认新增分组
  显示「当前：小把手 / 当前：已关闭」，并打开样式弹窗核对了三个选项的文案与选中状态
  （截图见 §2.1）。
- 与 v0.8.4 面板内设置共用宿主值：面板内改动会回写同一存储键，下次启动恢复。

### 3.4 真实 Release 核验（v0.2.1）

- tag `v0.2.1`（commit `557d67b`）的 `release` 流水线 5 个 job 全部 success；`app-ci` 在
  同一提交上 analyze-test / Android / macOS / Windows 全绿。
- 最新 Release 为 `v0.2.1`（非草稿/非预发布），三资产齐全：
  - `MediaPlayer-android.apk` 99,520,478B（`sha256:154c0fa4…`），`versionCode=3`、
    `versionName=0.2.1`，签名证书与本地 debug keystore 相同；
  - `MediaPlayer-windows-x64.zip` 34,153,677B（`sha256:3703c922…`）；
  - `MediaPlayer-macos.zip` 37,039,531B（`sha256:2926d226…`），解包后 `0.2.1/3`，含反馈着色器。
- 下载复算 SHA-256 与 GitHub digest 一致；三个 latest 下载链接均返回 200。
- 下载地址：<https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.1>。

### 3.5 真实 Release 核验（v0.2.2）

- 依赖 `feedback_widget` 0.8.5（tag `v0.8.5`，commit `95e4a9c`）；`app-ci` 在 tag 前提交
  `32e94e3` 全绿，release 流水线 5 个 job 全部 success。
- 最新 Release 为 `v0.2.2`（非草稿/非预发布），三资产齐全：
  - `MediaPlayer-android.apk` 99,520,478B（`sha256:f4aad54e…`），`versionCode=4`、
    `versionName=0.2.2`，签名证书与本地 debug keystore 相同；
  - `MediaPlayer-windows-x64.zip` 34,154,904B（`sha256:2f127730…`）；
  - `MediaPlayer-macos.zip` 37,048,264B（`sha256:0bd2fed5…`），解包后 `0.2.2/4`。
- 下载复算 SHA-256 与 GitHub digest 一致；三个 latest 链接均返回 200。
- 设置页「隐藏」说明与真实 app 截图已更新为新语义；下载地址：
  <https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.2>。

### 3.6 真实 Release 核验（v0.2.3）

- 依赖 `feedback_widget` 0.8.6（tag `v0.8.6`，commit `a345ca6`）；`app-ci` 在 tag 前提交
  `2423dc9` 全绿，release 流水线 5 个 job 全部 success。
- 最新 Release 为 `v0.2.3`（名称 `Media Player v0.2.3`，非草稿/非预发布），三资产齐全：
  - `MediaPlayer-android.apk` 99,520,478B（`sha256:13e05b92…`），`versionCode=5`、
    `versionName=0.2.3`，签名证书与本地 debug keystore 相同；
  - `MediaPlayer-windows-x64.zip` 34,153,027B（`sha256:d8860c6b…`）；
  - `MediaPlayer-macos.zip` 37,050,046B（`sha256:47270e01…`），解包后 `0.2.3/5`。
- **更新日志**：Release 正文与 `release/notes/v0.2.3.md` 逐字一致（已发布后核对），
  不再使用自动生成的提交清单；发布流水线对缺失/空文件 fail-closed。
- 发布前用本地 mock GitHub API 在真实打包 app 上检查了弹窗排版：
  [更新弹窗中的更新日志](screenshots/f4-update-notes.png)。
- 下载复算 SHA-256 与 GitHub digest 一致；三个 latest 链接均返回 200；地址：
  <https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.3>。

## 4. 未闭环与后续

1. **真实发布**：已完成 `v0.2.0`（`aae388c`）、`v0.2.1`（`557d67b`）、`v0.2.2`
   （`32e94e3`）与 `v0.2.3`（`2423dc9`）。后续每个版本必须先在
   `release/notes/vX.Y.Z.md` 写面向用户的更新日志；发布步骤见 `docs/release.md`。
2. **真机安装**：Android 首次需要系统「安装未知应用」授权；macOS 替换安装目录需要写权限；
   Windows 更新脚本尚未真实执行。
3. **反馈线上闭环**：真实账号登录、截图提交、管理端确认来源（需要反馈服务账号）。
   macOS ad-hoc 构建下，反馈组件的登录令牌仍写入 Keychain；重建后签名变化可能再次
   询问钥匙串访问（Emby 凭据走的是 0600 文件回退，反馈组件未暴露替代令牌存储入口）。
4. **F4 原契约项**：设置页的「添加第二地址」（`adoptAddress`）与 macOS 回退路径重启恢复
   仍未实现，本次设置页只覆盖关于/更新/反馈三项。
5. 更新渠道（正式/测试）未实现；当前只读正式 Release。

## 5. 回退

- 移除 `pubspec.yaml` 的 `feedback_widget`、`package_info_plus`、`crypto`、`archive`、
  `open_filex`、`url_launcher` 依赖并 `flutter pub get`；
- 删除 `lib/app/feedback_*.dart`、`lib/app/update_providers.dart`、`lib/data/update/`、
  `lib/features/settings/` 与对应测试；
- 还原 `app.dart`/`router.dart`/`app_routes.dart`/登录页/库页的接线，AppConfig 与 pubspec
  版本回退到 `0.1.0+1`；
- 已发布的 Release 不回改；Android 已用新 key 安装的包需卸载重装。

## 6. feedback_widget 0.9.1 与宿主日志接入（2026-11-16）

- 升级：`feedback_widget` 从 v0.8.6（`a345ca67`）到 **v0.9.1**（`f63dda82`）；`pubspec.yaml` 与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步，`pubspec.lock` 的 resolved-ref 已更新。0.9.1 修复能力未确认时的单图限制与 Windows 宿主 `pub get`，宿主 API 兼容。
- 宿主诊断日志（integration.md §5.6 必过项）：新增 `lib/app/feedback_diagnostics.dart`
  - `FeedbackDiagnosticsRecorder`（至多 200 条 / 256KiB、白名单字段）记录 dio 请求的方法 + 归一化路径、状态码、耗时与失败；`FeedbackDioInterceptor` 挂在主 dio 与弹幕 dio 上，请求体、请求头、完整 URL 与 query 不进入缓冲；
  - `FeedbackExceptionCapture` 在 `main` 安装，记录 Flutter/平台错误并原样转发原处理链；
  - `buildFeedbackConfig` 默认 `logProvider = provideFeedbackDiagnostics`，面板打开时导出 `media-player-diagnostics.jsonl`；无事件时为空，采集失败不阻断提交。
- 本地验证：`flutter analyze` 无问题；`flutter test` **1517 项通过**（新增 diagnostics 8 项：路径归一化/去 query、状态与失败记录、JSONL 导出、config 默认与覆盖）。验证使用 Flutter 3.47.7 / Dart 3.13.5（与 CI 一致）。
- 发布：提交 `1e1740b`（发布准备）与 `b2a72db`（功能），签名标签 `v0.4.5`；main CI [43889746106](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/43889746106) 4 job 成功；发布流水线 [43891165511](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/43891165511) 首跑因 Android NDK 下载损坏失败，重跑失败 job 后全部成功。
- [Release v0.4.5](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.5)：2026-11-16T15:12:40Z 公开，非草稿、非预发布、Latest；3 个资产 `MediaPlayer-android.apk` / `MediaPlayer-windows-x64.zip` / `MediaPlayer-macos.zip`，body 为用户向日志 `release/notes/v0.4.5.md`。
- 尚未验证：真机安装新包后提交一条反馈并在管理后台预览日志附件；Windows 更新安装未在真机执行（Release 构建已通过 vendoring 构建）。

## 7. feedback_widget 0.10.0 同步（2026-11-23）

- 升级：`feedback_widget` 从 v0.9.1（`f63dda82`）到 **v0.10.0**（tag `v0.10.0`，commit `bd5a235`）；`pubspec.yaml` 与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步到同一 commit，`pubspec.lock` 的 resolved-ref 与 version 已更新为 0.10.0。
- 默认值变化与宿主选择：0.10.0 把组件默认入口从「贴边标签」改成「光束唤醒」（双指长按 700ms 或 ⌘/Ctrl+Shift+F 唤出后先圈选），默认截图改为视口截图。本应用的 `buildFeedbackConfig` 一直显式传 `FeedbackLauncherMode.orb` + `FeedbackCaptureMode.viewport`，入口、截图与待机行为保持原样，**不启用光束唤醒**；是否切换属于产品决定，不与本次同步混做。
- 用户可感知：反馈面板「设置」新增「唤醒效果」，可选七种灵感球入场动画（`FeedbackOrbEntrance`，默认小珠浮现），按应用保存在本机；已开启唤醒手势时，灵感球在双指中点浮现并播放该动画（0.9.1 只是把球恢复成完整球）。
- 宿主 API 兼容，无需改代码：新增的「入口样式」「唤醒动效」偏好只在宿主 `launcherMode == beam` 时出现在面板里；唤醒手势与截图开关解耦（`_wakeAvailable` 改按入口模式判定）；`FeedbackWakeShortcut` 已加入 `FeedbackConfig` 但没有从包入口导出，宿主暂时无法改快捷键（本应用 orb 模式，无影响）；`decodeWakeGestures(null)` 改为回落「双指长按」，但宿主已托管唤醒手势，不读该默认值。
- 本地验证：`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1627 项通过**；`services/watch_together` 的 `dart pub get` ok。工具链 Flutter 3.47.7 / Dart 3.13.5（与 CI 一致）。
- 版本与发布：`0.4.9+1795400157`（tag `v0.4.9`），发布记录见 §7.1。

### 7.1 发布记录（2026-11-23）

- 提交 `9b5566d`（升级）与 `a754574`（用户日志），签名标签 `v0.4.9`（`0.4.9+1795400157`）。
- main CI [45099392114](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45099392114) 4 个 job 成功（analyze-test / android / windows / macos）；发布流水线 [45100035119](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45100035119) 全部 job 成功（validate、三平台构建、一起看镜像、发布 Release）。
- [Release v0.4.9](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.9)：2026-11-23T02:32:42Z 公开，非草稿、非预发布、Latest；3 个资产 `MediaPlayer-android.apk`（118,027,081 B）、`MediaPlayer-windows-x64.zip`（35,451,432 B）、`MediaPlayer-macos.zip`（43,471,885 B），均带 `sha256:` digest；body 为用户向日志 `release/notes/v0.4.9.md`。
- 尚未验证：真机从 0.4.8 测试包覆盖安装并走完「检查更新 → 下载 → 安装」；反馈面板「设置 → 唤醒效果」的真机预览（含手势唤出时的入场动画）；Windows 更新安装（Release 构建已通过）。
## 8. feedback_widget 0.11.0 与设置迁到宿主（2026-11-23）

- 升级：`feedback_widget` 从 v0.10.0（`bd5a235`）到 **v0.11.0**（tag `v0.11.0`，commit `a6c940c`）；`pubspec.yaml`、`pubspec.lock` 与两处 Windows CI vendoring 同步到同一 commit。
- 为什么升：0.11.0 之前入口样式 / 唤醒动效 / 灵感球入场只能写组件本机偏好，面板强行渲染、宿主无法接管，同一组设置同时出现在宿主设置页和组件面板里。0.11.0 把这三项也做成可选宿主值（与 0.8.4 的待机样式、唤醒手势同一语义），并新增 `hideSettings`。
- 本应用的接法：`lib/app/feedback_orb_settings.dart` 升级为五项宿主设置（`launcherStyle` / `wakeVisual` / `orbEntrance` / `idleStyle` / `wakeGestures`）并持久化；`lib/app/app.dart` 把五个值传给反馈层、不再传面板回调；`feedback_layer.dart` 设 `hideSettings: true`。面板设置页只剩服务器设置，五个选择都在「设置 → 反馈」。
- 重建时序（接入要点）：组件拿到宿主值后不会自己改值——用户在宿主设置页改选 → 控制器写盘并更新 provider → `FeedbackWidget` 用新值重建才生效。`FeedbackOrbSettings` 是不可变值对象、`updateShouldNotify` 逐字段比较，重建不会重置面板草稿。
- 默认值与体验变化：默认 `launcherStyle = beam` + 唤醒方式「双指长按」（沿用 0.11.0 默认），升级后不再有常驻灵感球；桌面用 ⌘/Ctrl+Shift+F，移动端双指长按，也可在设置里一键切回灵感球。`buildFeedbackConfig` 仍保留 `launcherMode: orb` + `captureMode: viewport`，作为设置未就绪时的回退。
- 设置页：新增「反馈入口」「唤醒动效」「唤醒效果」，原「唤醒灵感球」改名「唤醒方式」；`灵感球样式` 与 `唤醒效果` 只在入口为灵感球时显示，`唤醒动效` 只在光束唤醒时显示。
- 本地验证：`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1629 项通过**（含改写后的宿主设置、设置页切换、接线用例）；Flutter 3.47.7 / Dart 3.13.5。
- 上游配套：Feedback 仓库提交 `fd48f69` 在接入指南 §1.2 步骤表新增「宿主设置托管」一行、§4.2.1 补「接入时就接管」口径，并让 `examples/flutter` 演示宿主托管（analyze 通过、40 项示例测试通过，本机独立复跑）。
- 发布：`0.4.10+1795411788`（tag `v0.4.10`），记录见 §8.1。
### 8.1 发布记录（2026-11-23）

- 提交 `a758895`（升级 + 设置迁移 + 版本准备 `0.4.10+1795411788`），签名标签 `v0.4.10`。
- main CI [45118352219](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45118352219) 4 个 job 成功；发布流水线 [45119104092](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45119104092) 全部 job 成功。
- [Release v0.4.10](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.10)：2026-11-23T05:45:37Z 公开、非草稿、非预发布、Latest；三个资产 `MediaPlayer-android.apk`（117,568,665 B）、`MediaPlayer-windows-x64.zip`（35,406,352 B）、`MediaPlayer-macos.zip`（43,383,208 B）均带 `sha256:` digest，正文为用户向日志 `release/notes/v0.4.10.md`。
- 尚未验证：真机从 0.4.9 覆盖安装到 0.4.10 并走完「检查更新 → 下载 → 安装」；双指长按唤醒与水波纹/波光、七种入场动画的真机观感；Windows 更新安装（Release 构建已通过）。

## 9. feedback_widget 0.14.0 同步（2026-11-23）

- 升级：`feedback_widget` 从 v0.11.0（`a6c940c`）到 **v0.14.0**（tag `v0.14.0`，commit `b8c0065`）；`pubspec.yaml` 的 Git `ref`、`pubspec.lock` 与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步到同一 commit。
- 中间版本对本应用无影响：0.12.0 只重做管理后台，0.13.0 只改 Web 组件（`launcher-mode=auto`、桌面 `⌥`/`Alt` 拖拽唤醒、首次使用提示），Flutter 包两版都未改；本应用是 Flutter 宿主，`pubspec.lock` 的 version 直接从 0.11.0 跳到 0.14.0。
- 行为变更（破坏性）：**关闭面板 = 放弃本次未提交的反馈**。关闭按钮 / Esc / 宽屏遮罩 / 宿主 `controller.close()` 都会清空正文、截图、手动图片、日志与上一次提交留下的任务态，面板回到「新建反馈」撰写页；下次呼出按 `captureMode` 重新截图，不再恢复关闭时留下的旧图和草稿。保留访问令牌与登录态、额度、「我的反馈」数据与各家设置；已发出的提交不撤回；截图失败 / 重拍取消 / 提交失败 / 401 / 额度用尽等非关闭中断仍保留草稿。同一会话换图走面板内「重新截图」。
- 宿主无需改代码：v0.11.0→v0.14.0 的 Flutter 公开属性 / 方法 / 事件未变（diff 只动 `panel.dart` 内部与 `widget.dart` 注释），`lib/app/feedback_layer.dart` 的接线、`feedbackControllerProvider` 与 `handleFeedbackBackPop` 原样可用。
- 体验取舍：Android 系统返回键走宿主的 `handleFeedbackBackPop` → `controller.close()`，与组件关闭按钮同义，因此按返回键会丢弃已输入内容。这是 0.14.0 上游的既定语义（已知代价是「误关闭会丢已输入文字」），本应用不加二次确认，保持与组件一致（0.15.0 起改由组件接管并弹确认，见 §10）。
- 接入要求复核（接入指南 §4.2.1 / §9.2，0.14.0 起为必过项）：五项外观设置（入口样式、唤醒方式、唤醒效果、灵感球待机样式、唤醒动效）在 §8 已迁到「设置 → 反馈」并持久化，`hideSettings: true`，启动与改选后回传组件——本次没有新增设置项，只确认仍满足。
- 本地验证：`services/watch_together` 的 `dart pub get` ok；`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1629 项通过**。工具链 Flutter 3.47.7 / Dart 3.13.5（与 CI 一致）。
- 尚未验证：真机「截图 → 不提交关闭 → 再次唤醒」重新截图且回到空白撰写页的手感（组件上游同样把真机复验列为遗留项）；Windows CI 的 vendoring 需等下一次流水线才能证明新 SHA 可用。

## 10. feedback_widget 0.15.0 与安卓返回归组件（2026-11-23）

- 升级：`feedback_widget` 从 v0.14.0（`b8c0065`）到 **v0.15.0**（tag `v0.15.0`，commit `fad2562`）；`pubspec.yaml` 的 Git `ref`、`pubspec.lock` 与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步到同一 commit。
- 0.15.0 新增：①关闭前确认——面板里有**用户亲手写 / 加**的内容（正文、手动添加或编辑过的图片、手动添加的日志）时，关闭按钮 / Esc / 宽屏遮罩 / 安卓返回先弹「放弃这次反馈？」，「继续编辑」原样留下、「放弃」才关闭并丢弃；只有自动截图或自动采集日志时不弹窗。②Flutter 端 `FeedbackWidget.didPopRoute` 接管安卓返回键 / 返回手势，面板打开时走同一条确认并消费事件。公开属性 / 方法 / 事件与 HTTP 契约未变。
- 宿主要改的地方：本应用原来在 `AppShell.didPopRoute` 里先调 `controller.close()` 再返回 true，那是**程序化关闭**——0.15.0 明确它不弹确认，于是安卓返回会绕开「放弃这次反馈？」静默丢掉已写的字（和面板内关闭按钮不一致）。现在 `handleFeedbackBackPop` 只管宿主自己的导航栈：外层 navigator 上有截图预览 / 确认弹窗时 pop 掉并返回 true，其余一律返回 false，把事件交给组件。
- 观察者链（这条链是本次接线的根据，测试 `test/app/feedback_back_test.dart` 钉住）：`AppShell`（在 `MaterialApp` 之前注册，最先收到）→ `WidgetsApp`（用 router 时返回 false）→ `FeedbackWidget`（挂在 app router 之上，面板打开时确认并返回 true，宿主页面不被 pop）→ router 的 `RootBackButtonDispatcher`（面板关闭时才 pop 宿主页面）。`handlePopRoute` 按注册顺序询问观察者，第一个返回 true 的中断派发。
- 副作用与边界：按返回键在有内容的面板里不再立即关闭（多一步确认），无内容时行为与 0.14.0 相同；返回键关闭面板仍然先于路由 pop，不会把页面弹掉；确认弹窗本身按返回 = 「继续编辑」。桌面 Esc 一直由组件内部处理，不经过宿主。
- 本地验证：`services/watch_together` 的 `dart pub get` ok；`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1632 项通过**（新增 3 项返回键端到端用例，返回键单元用例按新语义改写）。工具链 Flutter 3.47.7 / Dart 3.13.5。
- 尚未验证：Android 真机 / 返回手势的体感（含确认弹窗与输入法同时出现时的高度）；Windows CI 的新 vendoring SHA 需等下一次流水线。

### 10.1 发布记录（2026-11-24）

- 提交 `c2a94f8`（0.14/0.15 两轮升级 + 版本准备 `0.4.12+1795484103`），签名标签 `v0.4.12`（GPG Good signature）。
- 本次是 `v0.4.11-pilot.1795421811` 之后的首个正式版：同时带上一起并入 main 的两项 Kaneo 改动——外观设置移入二级菜单「设置 → 外观」，一起看服务地址的中文域名规范化为 punycode（界面仍显示中文）。
- main CI [45306402775](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45306402775) 4 个 job 成功（analyze-test / android / windows / macos）；发布流水线 [45307396168](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45307396168) 全部 job 成功（validate、三平台构建、一起看镜像、发布 Release）。
- [Release v0.4.12](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.12)：2026-11-24T01:53:51Z 公开、非草稿、非预发布、Latest；三个资产 `MediaPlayer-android.apk`（117,568,669 B）、`MediaPlayer-macos.zip`（43,397,930 B）、`MediaPlayer-windows-x64.zip`（35,410,246 B）均带 `sha256:` digest，正文为用户向日志 `release/notes/v0.4.12.md`。
- 尚未验证：真机从 0.4.10 覆盖安装到 0.4.12 并走完「检查更新 → 下载 → 安装」；安卓真机返回键与「放弃这次反馈？」确认弹窗的观感（含输入法弹出时的高度）；Windows 更新安装（Release 构建已通过）。

## 11. feedback_widget 0.16.0 与灵感球边缘反射（2026-11-24）

- 升级：`feedback_widget` 从 v0.15.0（`fad2562`）到 **v0.16.0**（tag `v0.16.0`，commit `abc22328`）；`pubspec.yaml` 的 Git `ref`、`pubspec.lock` 与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步到同一 commit。
- 0.16.0 新增：①灵感球「边缘反射」开关（`orbReflectionEnabled` / `onOrbReflectionChanged`），按应用记住、默认开启；关闭后球缘不再映出翻转的文字与图标、边缘反光减弱，球心的玻璃折射与拖动变形照旧。②水波纹沿当前页面向外扩散、文字线条随波峰轻微弯折，浅色页面上波光更清晰。③新版圈选：选区可整体拖动、拖四角缩放、在同一张截图上重画；选框贴近底边时底部按钮让位并延续截图底色。公开属性/方法/事件与 HTTP 契约未变，`didPopRoute` 与提交链路没动，关闭前确认与安卓返回归组件继续沿用 §10 的接线。
- 宿主要改的地方：本应用 `hideSettings: true`，外观设置全部由「设置 → 反馈」托管（§8、§9 的必过项）。0.16.0 这个开关在组件里属于灵感球设置，面板隐藏后用户无从改选，所以第六项也搬到宿主：`FeedbackOrbSettings.reflectionEnabled`（默认 `true`，键 `feedback.orb_reflection.v1`，值损坏/缺失回落开启）→ `FeedbackOverlay.orbReflectionEnabled` → 组件；设置页在「灵感球」分组新增「边缘反射」开关，与组件面板的分组一致（只在灵感球入口下显示，光束唤醒下没有球体可看）。宿主只传值、不传回调：面板设置已隐藏，不存在面板内改选。
- 本地验证：`services/watch_together` 的 `dart pub get` ok；`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1639 项通过**（新增：边缘反射默认值与持久化、设置页开关落盘；`feedback_layer_test` 补了宿主值透传断言）。工具链 Flutter 3.47.7 / Dart 3.13.5（与 CI 一致）。
- 尚未验证：真机上关掉「边缘反射」后球缘观感、以及新版圈选（拖动缩放、重画、底部按钮让位）的手感；Windows CI 的新 vendoring SHA 需等下一次流水线才能证明。

### 11.1 发布记录（2026-11-24）

- 提交 `093b949`（0.16.0 升级 + 宿主托管边缘反射 + 版本准备 `0.4.14+1795506051`），签名标签 `v0.4.14`（GPG Good signature）。
- 版本顺延：`v0.4.13-pilot.1795504512` 已占用 0.4.13。正式版若取 0.4.13，pilot 用户收不到这次更新（正式 Release 没有构建号，同版本不算更新），因此取 0.4.14；先例是 pilot 0.4.11 → 正式 0.4.12。
- main CI [45350118659](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45350118659) 4 个 job 成功（analyze-test / android / windows / macos）；Windows 通过同时证明 0.16.0 的新 vendoring SHA 可用。发布流水线 [45351156164](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45351156164) 全部 job 成功（validate、三平台构建、一起看镜像、发布 Release）。
- [Release v0.4.14](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.14)：2026-11-24T07:59:17Z 公开、非草稿、非预发布、Latest；三个资产 `MediaPlayer-android.apk`（117,732,625 B）、`MediaPlayer-macos.zip`（43,408,708 B）、`MediaPlayer-windows-x64.zip`（35,417,682 B）均带 `sha256:` digest，正文为用户向日志 `release/notes/v0.4.14.md`。
- 尚未验证：真机上「边缘反射」开关关闭后的球缘观感与新版圈选（拖动缩放、重画、底部让位）的手感；从 0.4.12 覆盖安装到 0.4.14 并走完「检查更新 → 下载 → 安装」（三平台）；Windows 更新安装。
## 12. feedback_widget 0.17.0 与唤醒触点的手绘圈选示范（2026-11-24）

- 升级：`feedback_widget` 从 v0.16.0（`abc22328`）到 **v0.17.0**（tag `v0.17.0`，commit `9b8ddcdeac85b105587bd1052bbe758d8a8a130e`）；`pubspec.yaml` 的 Git `ref`、`pubspec.lock`（`resolved-ref` 与 `version: "0.17.0"`）与两处 Windows CI vendoring（`.github/workflows/app-ci.yml`、`.github/workflows/release.yml`）同步到同一 commit。
- 0.17.0 新增（`CHANGELOG.md` 与 `flutter/feedback/lib/src/capture_selection.dart` 的 diff 为据）：水波纹 / 波光结束后，在刚才的触点附近画一个青绿色手绘圈，示范怎么圈出问题位置；双指唤醒时示例出现在两指中间。每次唤醒只演示一次，用户落指即接管、点「重画」可直接重新圈选；开启系统「减少动态效果」时只显示静态提示，不做动画。
- 宿主无需改代码：v0.16.0→v0.17.0 的 Flutter 侧只改 `capture_selection.dart`（新增 `_LassoGuidePainter` 与引导层、`_guideDismissed` 状态），公开属性 / 方法 / 事件、`didPopRoute`、提交链路与 HTTP 契约均未变；`lassoFirst` 由组件在 `widget.dart` 内部决定，宿主传的外观设置（§11 的六项、`hideSettings: true`）原样沿用。
- 本地验证：`services/watch_together` 的 `dart pub get` ok；`./tool/check_layering.sh` ok；`flutter analyze` 无问题；`flutter test` **1639 项通过**。本次没有新增测试：0.17.0 只动组件内部渲染，宿主测试对公开 API 与宿主设置透传的断言（§11 那批）原样覆盖，`pub get` 后解析到的包已确认是 `9b8ddcde`（`version: "0.17.0"`，含 `feedback-lasso-guide` 引导层）。工具链 Flutter 3.47.7 / Dart 3.13.5（与 CI 一致）。
- 尚未验证：真机上唤醒后手绘圈选示范的观感（示例位置、双指唤醒时落在两指中间、「减少动态效果」下的静态提示、落指即接管与「重画」）；Windows CI 的新 vendoring SHA `9b8ddcde` 需等本次流水线才能证明。

### 12.1 发布记录（2026-11-24）

- 提交 `5eda330`（0.17.0 升级 + 版本准备 `0.4.15+1795510761`），签名标签 `v0.4.15`（GPG Good signature）。
- main CI [45361272608](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45361272608) 4 个 job 成功（analyze-test / windows / macos / android）；Windows 通过同时证明 0.17.0 的新 vendoring SHA `9b8ddcde` 可用。发布流水线 [45362800363](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45362800363) 全部 job 成功（validate、三平台构建、一起看镜像、发布 Release）。
- [Release v0.4.15](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.15)：2026-11-24T09:19:29Z 公开、非草稿、非预发布、Latest；三个资产 `MediaPlayer-android.apk`（117,732,625 B）、`MediaPlayer-macos.zip`（43,423,327 B）、`MediaPlayer-windows-x64.zip`（35,422,001 B）均带 `sha256:` digest，正文为用户向日志 `release/notes/v0.4.15.md`。
- 标签推送同时触发的 app-ci [45362800233](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/45362800233)（同一提交 `5eda330`）首轮 analyze-test 失败在 `test/data/offline/offline_repository_test.dart`「resume refuses another account and redirect never forwards token」：`expectLater(..., throwsStateError)` 实际未抛（1636 passed / 1 failed / 2 skipped）。本地单跑该用例 5 次、整文件 3 次均通过，同一提交的 main CI 也全绿，重跑失败 job 后 4 个 job 全部成功（1637 passed / 2 skipped）；判定为既有的偶发不稳定用例，与本次反馈组件升级无关，根因尚未定位。
- 尚未验证：真机上唤醒后手绘圈选示范的观感（示例位置、双指唤醒时落在两指中间、「减少动态效果」下的静态提示、落指即接管与「重画」）；从 0.4.14 覆盖安装到 0.4.15 并走完「检查更新 → 下载 → 安装」（三平台）；Windows 更新安装。
