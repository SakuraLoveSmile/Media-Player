# MP-S80：快退/快进时长设置

状态：待体验（自动验证通过，横竖屏真机手感待人工确认）。
用户目标：播放器里「后退」与「前进」按钮的跳转时长可分别设置，而不是固定 10 秒。

## 决定

- **后退与前进步长分设**：两个按钮都用得多但习惯不同（快退常要更短以回看一句台词，快进常要更长以跳过片头），一个共用值总要迁就一方。因此 `PlaybackSettings` 存两个独立字段。
- **预设 5 / 10 / 15 / 30 / 60 秒，默认均 10 秒**：覆盖「一句台词」到「跳过广告/片头」的常用跨度；默认 10 秒与旧行为完全一致，升级不改变手感。
- **只改这两个按钮**：进度条拖拽（`seekOnDrag`）、滑动手势、续播阈值、一起看同步都不动，避免一次改动牵动手感已定的多条交互。
- **存储仍为 `player.playbackSettings.v1`**，只加两个键。旧 JSON 缺键、非数字、非预设值（含手工改坏的备份）统一回退 10 秒，`normalizeSeekStepSeconds` 是唯一入口。
- **图标随预设走**：Material 有 5/10/30 秒专用字形，15/60 秒没有，用通用 `Icons.replay_rounded` / `Icons.forward_rounded`，避免图标数字与真实步长不符。
- **测试锚点保留** `player-seek-back-10` / `player-seek-forward-10`：这两个 key 沿用旧名以免大面积改测试，但名字不再代表运行时步长，运行时以 tooltip「后退 N 秒」「前进 N 秒」与 `state.playbackSettings` 为准。

## 改动

- `lib/data/playback/playback_settings.dart`：新增 `defaultSeekStepSeconds`（10）、`seekStepPresets`（`[5, 10, 15, 30, 60]`）、`seekBackSeconds`、`seekForwardSeconds`、`normalizeSeekStepSeconds`，接入 `fromJson` / `toJson` / `copyWith`。
- `lib/app/playback_settings.dart`：新增 `setSeekBackSeconds` / `setSeekForwardSeconds`，都走现有 `_persist`；写失败时抛错，内存状态不更新。
- `lib/features/settings/player_settings_page.dart`：「交互」之后新增「快进/快退」`AppSection`，后退/前进各一行 `ChoiceChip`（key `settings-seek-back-<秒>` / `settings-seek-forward-<秒>`），加载中禁用，footer 说明下次打开播放器生效，保存失败复用原有 snackbar。
- `lib/features/player/player_page.dart`：`_seekTarget` / `_seekIcon` 两个私有方法统一竖屏与横屏 transport 的取目标值与图标逻辑；后退钳到 0，前进钳到 `state.duration`，duration 为零时不钳；tooltip 显示实际秒数。

## 自动验证

- `(cd services/watch_together && dart pub get)`、`flutter pub get`、`bash tool/check_layering.sh`、`flutter analyze`（No issues found）、`flutter test`（全量套件通过）。
- 新增 `test/data/playback/playback_settings_test.dart`：默认值、预设表、JSON round-trip、旧 JSON 缺键回退、非数字/非预设值回退、`normalizeSeekStepSeconds`、`copyWith` 只改一侧。
- `test/app/player_settings_page_test.dart`：两行 chip 全预设存在、默认 10 秒选中、分方向保存且互不影响、重新打开回读选中状态、写失败保留旧选中并弹 snackbar、分区顺序在「交互」之后「播放/缓存」之前。
- `test/app/player_page_test.dart`：横屏自定义 5/30 秒的 tooltip 与实际 seek、横屏前进越过片尾钳到 duration、duration 未知时不钳、竖屏自定义 5/30 秒含片头（后退钳 0）与片尾（前进钳 duration）边界、15/60 秒使用通用箭头字形；原 ±10 秒默认用例保留并通过。

## 待人工体验

- 横竖屏真机上的实际跳转手感（30/60 秒是否过长、5 秒是否够回看一句台词）。
- 15/60 秒的通用箭头图标在深色画面上是否足够清晰、易与 10 秒专用字形区分。
- 设置页新增分区后，小屏滚动是否需要调整（当前在 800×2000 画布下不溢出）。
