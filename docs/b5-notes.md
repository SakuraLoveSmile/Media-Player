# B5 播放编排与 F3 播放页

- 日期：2026-10-28
- 范围：PlaybackInfo 协商、播放 URL 回退、PlaybackEngine、会话上报、续播、`/Sessions` 直连核对、播放页 UI
- 结论：**macOS 与 Android（Mi 10）release 实机连真实 Emby 均已验证：起播正常、服务端无 `TranscodingInfo`、暂停状态跨心跳保持、退出位置按实际进度落盘、续播误差 <1s、退出后会话归零**。Windows 本阶段未实测。

## 1. 截图

`docs/screenshots/f3-player.jpg` —— macOS release 播放页：画面在播（`49:39 / 01:32:24`），右上「直连播放」标签，底部播放/暂停、进度条、音量、返回。片名与画面内文字已遮盖。

## 2. 环境与基线

| 项 | 值 |
|---|---|
| SDK | Flutter 3.47.7 / Dart 3.13.5（`~/devsdk/flutter`） |
| 播放内核 | media_kit 1.2.6 / media_kit_video 2.0.1 / media_kit_libs_video 1.0.7 |
| 构建 | `flutter build macos --release`，93.5 MB，universal，ad-hoc 签名，App Sandbox 关闭，`network.client` 存在 |
| 服务器 | 已授权 LAN endpoint（Emby 4.10.1.0），测试账号，凭据只在运行时注入 |
| 样本 | sample-1（Movie，1:32:24）；Android 另用 2:22:03 与 1:39:59 两条 |
| 代码 | `3403c53`（T5-BUG-1）、`b579178`（T5-BUG-2）、`835cd51`（上报追踪开关） |

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

### 3.1 Android（Mi 10，Android 16 / API 36，release）

连续采样（每 3 秒一次 `GET /Sessions`），不再依赖事后推断：

| 项 | 结果 | 证据 |
|---|---|---|
| 起播 | PASS | 画面正常；位置 1602.7 → 1608.7 递增 |
| 直连判定 | PASS | `PlayMethod=DirectPlay`，**无 `TranscodingInfo`** → `videoDirect=true` |
| 暂停（跨心跳） | PASS | `IsPaused=true` 连续保持 27 秒 / 跨 2 个心跳，位置冻结 1607.6 |
| 恢复 | PASS | `IsPaused=false`，位置继续推进 |
| seek | PASS | 1609 → 4122.4（拖动约 2513s） |
| 退出位置 | PASS | 客户端 `Stopped` 上报 3378.834s，服务端该条目 `PlaybackPositionTicks` **tick 级一致** |
| 续播 | PASS | 退出 1463.9s → 重进首帧 1464.7s，差 <1s |
| 退出会话 | PASS | `NowPlayingItem` 在 15 秒内清空，无残留 |

样本说明：续播证据取自 1:39:59 影片，退出位置与阈值对照取自 2:22:03 影片（条目 `40377`），两者都超过了服务端的续播百分比阈值。

## 4. 缺陷与修复

### 4.1 T5-BUG-1（S2，`3403c53`）

- 现象：暂停后即时上报 `IsPaused=true`，但服务端在下一个 10s 心跳后回到 `false`。
- 根因：`SessionReporter` 的心跳固定发送 `paused: false`，覆盖了最近的暂停/恢复事件。
- 修复：上报器持有最近暂停态，`started` 重置为 `false`，`progress` 入队前更新，心跳读取该值；`stopped` 仍发 `false`。
- 回归测试：暂停 → 心跳仍为 `true`；恢复 → 心跳为 `false`（变异自检：心跳改回硬编码 `false` 时 `Expected: true / Actual: false`）。
- 复现：Android 连续采样中暂停跨 2 个心跳仍为 `true`。

### 4.2 T5-BUG-2（S1，`b579178`）

- 现象：Android 在播放到 68.9% 处退出后，服务端 `PlaybackPositionTicks` 变成 0，续播点丢失（macOS 同流程正常）。
- 根因：页面卸载时 `Video` 视图先销毁，libmpv 让位置流发出 0，控制器再读 `engine.snapshot.position` 就拿到 0，`Stopped` 带了 0。
- 修复：控制器维护「最后一次可信位置」（只在 > 0 时更新，起播按 `startAt` 重置），新增幂等 `stop()`，页面返回时先 `await stop()` 再 pop；心跳与 `Stopped` 共用同一位置来源。
- 回归测试：引擎先发 100s 再发 0s → 上报必须是 100s；显式 `stop()` + `dispose()` 只发一次。
- 验证：`835cd51` 的 `PLAYBACK_TRACE` 在 release 包上打出实际载荷（`[report] ... posTicks=...`），确认退出时发送的是 3378.834s，服务端 tick 级一致。

### 4.3 服务端语义：低于阈值的位置会被清成 0

- 在 2:22:03 影片（`40377`，8523.2s）上退出于 **21.271s（0.25%）**，服务端记录为 0、`Played=false`；同一条目退出于 **3378.834s（39.6%）** 时，服务端 tick 级精确保留。
- 结论：这是 Emby 的续播百分比阈值行为，不是客户端缺陷。验收时必须让退出点超过阈值，否则会把正常的服务端清理误判成上报失败。
- 取证教训：核对位置归属必须用**条目 id**，不能只按时长匹配——本轮一度按时长把 3378.834s 归到另一部影片上，导致误判为「写错条目」。

## 5. 判定口径

`PlayState.PlayMethod` 是客户端自己上报的值；服务端唯一的独立信号是 **`TranscodingInfo` 是否出现**。因此本阶段的直连结论以「无 `TranscodingInfo`」为主证据、`PlayMethod` 为辅证，已回填契约 §9。

## 6. 测试与质量门

- 190 项测试通过（B5/F3 新增 69 项）；`flutter analyze` 无告警；`tool/check_layering.sh` → `layering ok`。
- 媒体内核类型只出现在 `lib/data/playback/media_kit_engine.dart` 与 `lib/main.dart`；`grep media_kit lib/features` 为空。
- 各卡变异自检覆盖：重试次数、串行队列、`Stopped` 幂等、`videoDirect` 未知时不得为 true、续播阈值、音量 ×100 换算、重试即重建控制器、退出位置不得被 0 覆盖、追踪行脱敏。
- 真机取证工具：`--dart-define=PLAYBACK_TRACE=true` 会在每次上报前打一行脱敏载荷（itemId 前 6 位、ticks、暂停态、playSessionId 长度）；默认关闭，正常构建零输出。

## 7. 未覆盖

1. Windows 播放实机：当前没有可用目标机或 runner，CI 构建产物不计为真机验收，`M2` 三平台门只关掉 macOS 与 Android。
2. `Transcode` 分支：全程未触发转码，`TranscodingInfo.IsVideoDirect/IsAudioDirect` 的取值仍未实测。
3. `transcodingReasons` 字段名（未触发转码）。
4. WAN（frp HTTPS）下的码率上限与 `forceDirectOnWan` 回退。
5. PGS、HDR10、外挂字幕（B6）、HLS、`/Sessions/Capabilities/Full`。
6. 详情页/季集页未实现：库页点 Series 时播放页给出「需先选分集」，不是缺陷。
7. 播放失败/重试的实机路径（仅 widget 测试覆盖）。
8. Android 播放页未留截图（GUI 取证遵守「不做系统级合成输入」，仅用服务端与会话证据）。
