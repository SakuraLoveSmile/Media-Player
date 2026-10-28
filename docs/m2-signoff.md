# M2 签核记录

- 日期：2026-10-28
- 门定义：契约 §8 —— LAN 下 `videoDirect=true`；续播误差 ≤5s；控制项完整
- 结论：**M2 已签核，范围为 macOS + Android。Windows 拆为独立的 M2-W 门，条件已冻结（契约 §8.1），当前 open。**

M2 的原条件是「三平台」。本次不以 macOS/Android 的结果代签 Windows，因此把门拆成两条：`M2`（已签）与 `M2-W`（待签）。在 M2-W 签核前，任何文档不得表述为「三平台直连通过」。

## 1. 签核范围与证据

| 平台 | 直连 | 暂停/恢复跨心跳 | 续播 | 控制项 | 证据 |
|---|---|---|---|---|---|
| macOS（release，Apple Silicon） | PASS：`PlayMethod=DirectPlay`，无 `TranscodingInfo` | PASS：+13s 两次读一致 | PASS：误差 0s | PASS | `docs/b5-notes.md` §3；`docs/screenshots/f3-player.jpg` |
| Android（Mi 10，API 36，release） | PASS：同上 | PASS：保持 27s / 跨 2 个心跳 | PASS：1463.9s → 1464.7s，<1s | PASS（widget 测试 + 会话状态） | `docs/b5-notes.md` §3.1 |
| Windows（Win11 x64） | **未验收** | 未验收 | 未验收 | 未验收 | 无；仅 CI 构建产物 |

补充实测（两个平台一致）：退出位置由客户端 `Stopped` 上报后由服务端精确保留；退出后 `NowPlayingItem` 清空；低于库续播阈值（实测 0.25%）的退出会被服务端清零，高于阈值（39.6% / 56.3%）则 tick 级保留。

## 2. M2 签核依据的提交

| 提交 | 内容 |
|---|---|
| `acd2213` | 契约 §10.9：播放实现附录 |
| `018402b` | PlaybackInfo 协商与 URL 四级回退 |
| `f3c4399` | 会话上报与 `/Sessions` 直连核对 |
| `1ad8057` | PlaybackEngine 与 media_kit 实现 |
| `2b276be` | 播放页控制器与 UI |
| `254590e` | 重试即重建控制器 |
| `3403c53` | T5-BUG-1：暂停状态跨心跳保持 |
| `b579178` | T5-BUG-2：退出位置不得被 0 覆盖 |
| `835cd51` | 可选的上报追踪（默认关闭） |

质量门：`flutter test` 190 项通过；`flutter analyze` 零问题；`tool/check_layering.sh` 通过；CI（analyze-test / android / macos / windows）在 `cf1694d` 四项 success。

## 3. M2-W（Windows）：验收条件与当前状态

条件全文见契约 §8.1，这里只列执行清单：

1. 环境：Win11 x64、同 LAN、release 构建、产物内含 libmpv DLL。
2. W1 登录与库可用。
3. W2 起播：画面 + `duration>0` + 两个时刻 position 递增。
4. W3 控制项齐全。
5. W4 直连：唯一匹配会话 `PlayMethod ∈ {DirectPlay, DirectStream}` 且无 `TranscodingInfo`；`Transcode` 时读 `IsVideoDirect`。
6. W5/W6 暂停与恢复各跨一个心跳仍保持状态。
7. W7 seek 后 15s 内 UI 与服务端位置差 ≤2s。
8. W8 退出后会话数归零。
9. W9 退出点超过续播阈值，服务端位置与上报值 tick 级一致。
10. W10 重进误差 ≤5s 且出现续播提示。
11. W11 二次退出无悬挂会话。

当前状态：**open**。原因：没有可用的 Windows 目标机或 runner；CI 只产出构建、未运行 GUI，不能替代。

## 4. 签核后仍未闭环的事项

1. M2-W（Windows 播放实机）。
2. WAN（frp HTTPS）：码率上限、`forceDirectOnWan` 回退、同 token 跨端点。
3. `Transcode` 分支：`TranscodingInfo.IsVideoDirect/IsAudioDirect` 实际取值（全程未触发转码）。
4. PGS、HDR10、60–80 Mbps 样本。
5. 外挂字幕与轨道切换（B6）、播放调优 hwdec/tone mapping（B7）。
6. 详情页/季集页：库页点 Series 目前提示「需先选分集」，不是缺陷但仍是功能缺口。
7. Windows 库页/播放页 UI 实机与真实 >60 条分页。
