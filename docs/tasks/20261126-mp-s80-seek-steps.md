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

## Review 修复轮（小数解码 + 60 秒去留）

- **60 秒预设保留：经用户本轮明确授权。** 冻结计划原文只列 5/10/15/30，Review 报告把 60 秒列为偏离项；用户在本轮答复中明确选择「保留 60 秒」，因此 `seekStepPresets` 维持 `<int>[5, 10, 15, 30, 60]`，设置页 chip 行、播放器 transport、既有 60 秒相关用例都不改。这是经授权的范围决定，不是未处理的偏离项。冻结计划 `artifacts/plan/08083bbd-c7ba-47d7-b78f-823b83e14dc3/plan.md` 本身不改写。
- **小数与非有限值一律回退 10 秒。** 旧实现先 `toInt()` 再查预设表，`5.5 → 5`、`10.9 → 10`、`30.5 → 30`、`60.5 → 60`，把手工改坏的值伪装成合法步长；而且 `NaN` / `±Infinity` 会直接抛 `UnsupportedError`。现在顺序是：`raw is! num` → 回退 10；`!raw.isFinite` → 回退 10（必须先拦，`truncate()` / `toInt()` 对非有限值会抛错）；`raw != raw.truncate()` → 回退 10；最后才判断是否属于 `seekStepPresets`。回退理由与非法值一致：无法确认用户意图时用默认手感，而不是猜一个更接近的合法预设。整数值 `double`（`5.0`、`30.0`）仍按整数接受，因为 JSON 数字常以 double 形式回来。

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
- 小数/非有限值补齐（Review 修复轮）：`5.5`、`10.9`、`15.5`、`30.5`、`60.5`、`0.5`、`9.5`、`NaN`、`±Infinity` 全部回退 10，并显式断言不落入 `5`/`10`/`15`/`30`/`60` 等合法预设；`5.0`、`10.0`、`15.0`、`30.0`、`60.0` 仍被接受为对应预设；`fromJson` 走同一路径。
- Review 修复轮改动仅限 `lib/data/playback/playback_settings.dart`、`test/data/playback/playback_settings_test.dart`、本记录三个文件；设置页、播放器 transport、`PlaybackSettingsController` setter、存储 key 均未触碰。

## 待人工体验

- 横竖屏真机上的实际跳转手感（30/60 秒是否过长、5 秒是否够回看一句台词）。
- 15/60 秒的通用箭头图标在深色画面上是否足够清晰、易与 10 秒专用字形区分。
- 设置页新增分区后，小屏滚动是否需要调整（当前在 800×2000 画布下不溢出）。
