# MP-TT01：Tigerest-Theater 功能复刻

状态：待体验。用户目标：创建分支，对比 Tigerest-Theater，把适合 MediaPlayer 的功能完整接入。

## 基线、范围与决定

- 主目录：`/Users/sakurasep/Documents/Code/Project/Personal Project/MediaPlayer`，main HEAD `2f765b70a2fc2650bf45308f273b8c1b91dd8812`，已有大量未提交 Yamby 改动。原目录保留；本工作树复制当前 tracked/untracked 内容，不提交或归属为本次成果。
- 分支：`codex/feat/20261114-mp-tt01-theater-features`；工作树：`/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer/20261114-feat-mp-tt01-theater-features`。目标为供用户审阅体验，未授权合并、推送或发布。
- 当前代码基线指纹：根目录 `.task-baseline-mp-tt01.json`，覆盖 lib/test/docs/tool。最终新增差异以该清单核对，不能用整个 git diff 充当本任务改动。
- 参考仓库：<https://github.com/Tigerest/Tigerest-Theater>，本机 `/tmp/tigerest-theater-reference-20261114`。只借鉴行为，独立 Flutter 实现，不复制 GPL 源文件或着色器。
- 本次选择：原始媒体下载、暂停/恢复/重试/重启恢复、管理与确认删除、离线本地播放；MPV 画质预设、白名单配置编辑、逐行校验、恢复默认、复制给 AI、持久化和播放应用。
- UI 继承现有 AppPage/AppSection，不更换风格。下载保存在应用 support/offline，索引不持久化 URL/token/headers；下载与恢复核实当前服务器和账号权限；离线播放不触发远端协商或观看上报。外置字幕/弹幕不随视频保存。
- 画质采用内置 MPV 参数实现影视/动画等预设，不宣称等价 87 个 shader；仅开放画质白名单，窗口、脚本、文件路径、生命周期及认证参数由应用管理。

## 对比结论

当前基线已有首页推荐、继续观看、搜索、收藏、详情、多服务器、弹幕、字幕样式、手势、连播、定时关闭、投屏；不重复造功能。

| 参考功能 | 决定与依据 |
| --- | --- |
| 下载与离线媒体 | 引入；参考 docs/wiki/Downloads.md、src/system/SystemComponent.cpp、native/offline.js；现有仅更新包下载和字幕缓存 |
| MPV 预设与配置编辑 | 引入；参考 src/player/MpvConfigManager.cpp、MpvConfDocument/MpvConfEditor；现有只有 GPU-Next/deband/YUV420 开关 |
| 一起看/公共评论/消息/共享弹幕纠正 | 依赖作者专属服务与账号，不连接这些服务；如另做自建服务需独立业务与部署设计 |
| RIFE AI 补帧 | 依赖 Windows NVIDIA/CoreML/Metal 组件和模型，未纳入当前 Flutter 参数实现 |
| 设置搜索/首页观看排序 | 本次未选，保留为后续候选 |

## 实现步骤、归属与验收

T1 主 agent：冻结范围、隔离基线、共享接入（AppServices/providers/routes、启动/设置/详情/单集入口），维护唯一记录并做组合态核验。

T2 离线 worker (Sol/high)：独占 data/offline、features/offline 与对应测试（通用按钮最终放 lib/ui）。接口 OfflineRepository(directory, session)、initialize/entries/enqueue/pause/resume/remove/completedFile；OfflinePage(repository, createEngine)、OfflineDownloadButton(repository,item,sourceId)。支持本地 HTTP 隔离夹具，测试权限、跨账号、Range/长度、暂停恢复、重启与删除。本地播放器使用 PlaybackEngine，不依赖在线会话。

T3 画质 worker (Sol/high)：独占 mpv_config、PlaybackSettings/controller、mpv_settings_page、player_controller 和配置测试。主 agent 提供可选 MpvConfigEngine.applyMpvConfig(Map<String,String>) 与 MediaKitEngine 实现。配置只允许明确校验的画质属性，提交错误时保留旧配置；每次应用完整默认值以清理旧选项。

T2/T3 接口冻结后并行，不同时修改同一文件；不再派生。只读 analyst 已核实差距、参考实现入口与许可。后续 reviewer 只读检查实际组合态的下载安全和配置边界，主 agent 修正并运行适用检查。

验收：
1. 电影指定版本或单集创建下载，管理页见进度；暂停/恢复/失败重试/重启可恢复且文件内容完整。
2. 无权限/其他账号不能恢复；索引无凭据，错误不暴露 URL，拒绝不安全路径与重定向。
3. 完成后本地播放；断网启动/登录页仍有离线入口；删除确认只删除本地副本。
4. MPV 页切预设、输入有效/无效配置，按行提示且错误不能保存，恢复与重开持久化正确；新播放实际传入完整属性并清理旧值。
5. 既有分层守卫、analyze、flutter test；真实界面检查新入口与编辑器/离线管理，记录设备和实测限制。构建/mock 不冒充真实服务器下载/断网播放效果。

## 验证与剩余工作

- 分层守卫通过；最终 `flutter analyze --no-pub`：No issues found；最终 `flutter test --no-pub`：1441/1441 通过；`git diff --check` 通过。日志 `/tmp/mp-tt01-analyze-final.log`、`/tmp/mp-tt01-full-tests-final.log`。未升级依赖。
- 本次新增测试包含19项离线状态/HTTP/widget、11项画质解析/编辑器/controller、2项真实router登录/启动失败离线入口。HTTP均loopback、文件均临时目录，未访问真实Emby账号。
- macOS 原生 smoke构建与运行通过：`flutter run -d macos -t tool/theater_smoke.dart --no-pub`。合成640×360 H264/AAC视频（12秒）经本地HTTP下载完成1.2MB，关闭测试服务器后从离线列表播放，实际观察彩条画面与0:12/0:12终态；未声称真实影片人耳音质验收。
- 原生MPV页实测选择影视预设、编辑器拒绝 `vo=gpu`（第1行红字且保存禁用）、合法 `brightness=5 / scale=lanczos` 校验2项并成功保存。界面沿现有样式，无新增布局溢出；部分AX树受Flutter原生桥错误影响，采用实际截图/坐标核对。未做与参考shader的视觉等价比较。
- 本机打包libmpv实际接受全部预设属性；MediaKitEngine对写入属性读回校验，避免media_kit丢弃原生返回码导致静默失败。在线和离线配置应用/失败回退有单测覆盖。
- 单次初始全量因新增entry测试把文件IO放入fakeAsync而挂起，已改为tester.runAsync，独立2项及最终全量通过；初轮离线权限夹具修改中的失败已由最终全量替代。未跳过/删除用例或降低门禁。

### 主目录并发更新与基线刷新

本任务期间原主目录继续推进Yamby，六份文件发生变化：series_widgets/series_page/season_page、player_page/player_portrait及player_page_test。初复制基线存在旧S26测试与S78页面不一致，首轮全量出现相关失败。保留原目录不写入；将六份原目录当前一致版本同步到本工作树，再重接下载按钮和qualityWarning，不单改断言。初始指纹保留 `.task-baseline-mp-tt01-initial.json`，刷新基线 `.task-baseline-mp-tt01.json`。最终1441项全部通过，原主目录单独播放器101项也通过（只作旁证，不替代组合态）。

### 体验入口与限制

- 设置→下载与离线媒体；电影详情下载选中版本，季页单集下载；登录页与启动失败页均可进入离线副本。
- 设置→MPV播放器→画质预设与自定义配置。仅内置画质参数，不包含GLSL包或AI补帧。
- `tool/theater_smoke.dart` 为隔离演示，使用 `/tmp/mp-tt01-fixture.mp4`、临时下载目录、内存设置、loopback服务，不是正常应用入口。正常构建入口为lib/main.dart。
- 仍未实测真实Emby4.10下载权限/多版本选源与真实大文件WAN续传；STRM及远程源明确拒绝。Android/Windows原生界面尚未验证，不能以macOS或unit测试代替。
- 用户未确认验收；未提交、推送、合并、发布。此工作树包含已有未提交基线与本次新增代码，须保留供审阅，未满足合并后清理条件。临时原生验证进程已停止，本地合成夹具和下载文件仍在临时目录，未触及用户数据。
- 本次候选文件指纹见 `mp-tt01-candidate-files.json`（仅包含代码/测试/架构文档与演示入口，任务记录自身不包含在指纹中）；分支HEAD仍2f765b7，证据适用于未提交组合态。

最终补证：lib/main.dart 正常入口 macOS Debug 构建通过，产物 `build/macos/Build/Products/Debug/Media Player.app`。独立审查已逐项复核修复的三处下载/离线偏好缺口。仅本次增量的可读补丁为 `mp-tt01-changes.patch`，相对于记录的当前未提交基线生成，供审阅，不意味着已有用户基线被提交。

Android Debug 构建通过（59.9秒），产物 `build/app/outputs/flutter-apk/app-debug.apk`；未安装到手机，不触及设备原应用或数据。日志 `/tmp/mp-tt01-android-build.log`。Windows 构建未运行。增量补丁中的 player_page 只包含本次 qualityWarning 插入（其基底以候选去除此插入重建，避免收录原目录继续发生的无关修改）；其余文件按保存的基线逐字核对生成。


## 2026-11-17 交付恢复

本任务与 MP-WT01 同一组合态，用户已授权提交、推送、合入 main 与发布测试版。当前状态为实现中；本轮统一整合、验证、发布和旧工作树保全/收尾记录维护于 [MP-WT01 本轮交付记录](20261114-mp-wt01-watch-together.md#2026-11-17-提交整合与测试版发布)，此处历史“未授权/未发布”不再描述本轮授权。
