# F4：反馈组件与在线更新

- 日期：2026-11-02（本地 Asia/Taipei；验证跨至 11-03 凌晨）
- 范围：接入 Feedback 组件（`feedback_widget` 0.8.4）、设置页、GitHub Releases 在线更新、发布工作流
- 版本：`v0.2.1`（`0.2.1+3`）已发布；本轮升级 `feedback_widget` 至 0.8.5 并准备发布 `v0.2.2`（`0.2.2+4`）
- 结论：**`v0.2.0` 与 `v0.2.1` 均已发布；灵感球设置增补已随 `v0.2.1` 上线，真机体验待确认**

## 1. 已确认的决定

| 项 | 决定 | 依据 |
|---|---|---|
| 反馈组件版本 | `feedback_widget` 0.8.5，Git tag `v0.8.5`（commit `95e4a9c818d4bc248433b5f2b5f0eabb7581298a`，`flutter/feedback` 子目录；0.8.5 修正「隐藏」样式语义，宿主托管参数与 0.8.4 相同） | Feedback 仓库最新正式标签；public 仓库用 HTTPS Git 依赖，CI 无需 deploy key |
| 反馈服务 | 生产地址 `https://feedback.xn--fhqths51enha.cn`，`appId = dev.mediaplayer.media_player`，`appName = Media Player` | 与 Android applicationId 一致；服务端首次提交自动发现软件 |
| 反馈默认开关 | release/profile 默认开启；debug 与 `flutter test` 默认关闭；可用 `FEEDBACK_ENABLED` / `FEEDBACK_API_BASE` / `FEEDBACK_APP_ID` / `FEEDBACK_APP_NAME` 覆盖 | 开发与既有测试不受影响；发布构建显式传 `--dart-define` |
| 反馈入口 | 亮色主题、右侧灵感球（orb）+ 视口截图；播放页隐藏悬浮球；登录页服务器地址/用户名包 `FeedbackCaptureMask` | 与 app 亮色主题一致；避免遮挡播放控件；截图不泄露地址/账号 |
| 更新源 | GitHub Releases API（`SakuraLoveSmile/Media-Player`，public），只接受正式 Release | 用户确认：不引入仓库内清单与镜像维护；API 匿名限额足够个人使用 |
| 更新入口 | 启动静默检查（仅 release/profile，发现更新弹一次弹窗）+ 设置页手动「检查更新」 | 兼顾“自动发现”与可手动重试 |
| 安装范围 | Android APK / macOS zip / Windows zip 三平台原地更新 | 契约目标三平台；iOS/Linux 不在范围 |
| Android 签名 | 发布使用固定 keystore secret `ANDROID_KEYSTORE_BASE64`（alias `androiddebugkey`，密码 `android`），本地无 key.properties 时回退 debug key | 在线更新必须跨版本同签名才能覆盖安装 |

## 2. 实现映射

| 能力 | 文件 |
|---|---|
| 反馈编译期配置 / provider / 页面标签白名单 | `lib/app/feedback_config.dart` |
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
  编解码保持兼容；本轮升级后同步更新了设置项说明与浮层测试。
- 持久化复用 App 已有的 `KeyValueStore`（`AppServices.store`，契约 §7；macOS ad-hoc 为
  0600 文件、其余平台走平台安全存储），键为 `feedback.orb_idle_style.v1` /
  `feedback.wake_gestures.v1`。未知/损坏值回退默认；写入失败保留旧值，设置页提示
  「保存失败，请稍后重试」，面板内改动失败只记录日志。
- 存储失败时提供读取兜底（默认值），设置页显示「读取失败，点击重试」；加载中显示「读取中…」。
- 并发写入按最新状态合并（同时修改样式与手势不会互相覆盖），由单元测试覆盖。
- 真实打包 app 的界面截图：[设置页新增分组](screenshots/f4-orb-settings.png)、
  [灵感球样式弹窗](screenshots/f4-orb-style-dialog.png)。

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

## 4. 未闭环与后续

1. **真实发布**：已完成 `v0.2.0`（`aae388c`）与 `v0.2.1`（`557d67b`）。
   在线更新体验：v0.2.0 用户应在启动/检查更新时看到 v0.2.1，并完成下载与安装；
   设置页新增「灵感球样式 / 唤醒灵感球」。发布步骤见 `docs/release.md`。
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
