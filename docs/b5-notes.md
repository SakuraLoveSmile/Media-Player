# B5 播放编排与 F3 播放页

- 日期：2026-10-28
- 范围：PlaybackInfo 协商、播放 URL 回退、PlaybackEngine、会话上报、续播、`/Sessions` 直连核对、播放页 UI
- 结论：**macOS release 实机连真实 Emby：起播正常、服务端无 `TranscodingInfo`、暂停/恢复状态跨心跳保持、seek 与服务端位置差 0.819s、续播误差 0s、退出后会话归零**。Android 与 Windows 本阶段未实测。

## 1. 截图

`docs/screenshots/f3-player.jpg` —— macOS release 播放页：画面在播（`49:39 / 01:32:24`），右上「直连播放」标签，底部播放/暂停、进度条、音量、返回。片名与画面内文字已遮盖。

## 2. 环境与基线

| 项 | 值 |
|---|---|
| SDK | Flutter 3.47.7 / Dart 3.13.5（`~/devsdk/flutter`） |
| 播放内核 | media_kit 1.2.6 / media_kit_video 2.0.1 / media_kit_libs_video 1.0.7 |
| 构建 | `flutter build macos --release`，93.5 MB，universal，ad-hoc 签名，App Sandbox 关闭，`network.client` 存在 |
| 服务器 | 已授权 LAN endpoint（Emby 4.10.1.0），测试账号，凭据只在运行时注入 |
| 样本 | sample-1（Movie，时长 1:32:24） |
| 代码 | `3403c53`（含 T5-BUG-1 修复） |

## 3. 实测矩阵（macOS release）

| 项 | 结果 | 证据 |
|---|---|---|
| 起播 | PASS | libmpv 画面可见；duration 5544s；position 49:56 → 50:23 递增 |
| 控制项 | PASS | 播放/暂停、进度条、音量、返回、直连状态标签齐全 |
| 直连判定 | PASS | 唯一匹配会话 `PlayMethod=DirectPlay`，**无 `TranscodingInfo`** → `videoDirect=true` |
| 暂停（跨心跳） | PASS | 即时与 +13s 两次读取 `IsPaused=true`，位置稳定 2846.927s |
| 恢复（跨心跳） | PASS | 即时与 +13s 两次读取 `IsPaused=false` |
| seek | PASS | UI 2904s，服务端 2904.819s，差 0.819s |
| 首次退出 | PASS | 该 `DeviceId + NowPlayingItem` 匹配会话数 0（`Stopped` 生效） |
| 续播 | PASS | 退出 48:24 → 重进 48:24，误差 **0s**，UI 显示「已从 mm:ss 继续播放」 |
| 二次退出 | PASS | 匹配会话数 0 |

## 4. 缺陷：T5-BUG-1（S2，已修 `3403c53`）

- 现象：暂停后即时上报 `IsPaused=true`，但服务端在下一个 10s 心跳后回到 `false`。
- 根因：`SessionReporter` 的心跳固定发送 `paused: false`，覆盖了最近的暂停/恢复事件。
- 修复：上报器持有最近暂停态，`started` 重置为 `false`，`progress` 入队前更新，心跳读取该值；`stopped` 仍发 `false`。
- 回归测试：暂停 → 心跳仍为 `true`；恢复 → 心跳为 `false`（变异自检：心跳改回硬编码 `false` 时 `Expected: true / Actual: false`）。

## 5. 判定口径

`PlayState.PlayMethod` 是客户端自己上报的值；服务端唯一的独立信号是 **`TranscodingInfo` 是否出现**。因此本阶段的直连结论以「无 `TranscodingInfo`」为主证据、`PlayMethod` 为辅证，已回填契约 §9。

## 6. 测试与质量门

- 180 项测试通过（B5/F3 新增 59 项）；`flutter analyze` 无告警；`tool/check_layering.sh` → `layering ok`。
- 媒体内核类型只出现在 `lib/data/playback/media_kit_engine.dart` 与 `lib/main.dart`；`grep media_kit lib/features` 为空。
- 各卡变异自检覆盖：重试次数、串行队列、`Stopped` 幂等、`videoDirect` 未知时不得为 true、续播阈值、音量 ×100 换算、重试即重建控制器。

## 7. 未覆盖

1. Android（Mi 10）与 Windows 的播放实机：release 包已产出/安装，但本阶段未在设备上完成交互验收，`M2` 三平台门只关掉 macOS。
2. `Transcode` 分支：全程未触发转码，`TranscodingInfo.IsVideoDirect/IsAudioDirect` 的取值仍未实测。
3. `transcodingReasons` 字段名（未触发转码）。
4. WAN（frp HTTPS）下的码率上限与 `forceDirectOnWan` 回退。
5. PGS、HDR10、外挂字幕（B6）、HLS、`/Sessions/Capabilities/Full`。
6. 详情页/季集页未实现：库页点 Series 时播放页给出「需先选分集」，不是缺陷。
7. 播放失败/重试的实机路径（仅 widget 测试覆盖）。
