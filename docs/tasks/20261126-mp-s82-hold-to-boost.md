# MP-S82：长按画面临时加速播放

状态：待体验（自动验证通过，横竖屏真机按住手感待人工确认）。
用户目标：播放页按住画面约 0.5 秒，倍速临时升到 2.0x 并在画面中央提示；松手恢复原来的倍率。

## 决定

- **临时倍率取 `max(按住前倍率, 2.0)`**：1.0x / 1.25x / 1.5x 按住都升到 2.0x；已经更快的 3.0x 按住不降速，胶囊如实显示「3.0x 加速中」。这样「按住＝更快」的手感恒成立，不会出现按住反而变慢。
- **按住前倍率只在按住开始时锁存一次**（`_holdBaseRate`），松手／取消时用它恢复。选择「先加速值、后基础值」两次写入而不是直接改引擎参数，是为了让倍速改动仍然只走 `PlayerController.setRate`，会话上报与一起看的 1 倍强制逻辑一条都不绕过。
- **不新增持久化**：临时倍率是手势，不是偏好，因此不写 `PlaybackSettings`、不进任何 store，也不改 `PlaybackEngine` 接口。
- **复用中央状态胶囊**：长按提示与亮度／音量／seek 共用同一个 `Center(child: _indicator())` 与同一套黑色胶囊样式，画面里不会同时出现两种居中提示。按住期间不再叠加拖拽指示器，拖拽一旦开始就立刻结束按住（把倍率还回去），避免同一根手指同时占两个状态。
- **只在页面提供 `onHoldStart` 时才注册长按识别**：`PlayerGestureLayer` 的 `onLongPressStart/End/Cancel` 全部由 `_holds` 决定是否为 null。未提供时识别器根本不参与 gesture arena，单击／上下拖拽／横滑 seek 的既有仲裁与手感完全不变。
- **一起看不提供个人加速**：房间路径下页面传 `onHoldStart = null`（`_holdEnabled => widget.watchRoomId == null`），所以没有长按识别、没有胶囊，也没有个人倍率写入；倍速仍只由 `WatchPlaybackCoordinator` → `PlayerController.setRate` 的「一起看时播放速度固定为 1 倍」拒绝与提示负责，同步协议未触碰。
- **取消与释放等价**：`onLongPressCancel` 与 `onLongPressEnd` 走同一恢复路径；`PlayerGestureLayer.dispose()` 也补了兜底，锁屏／切横竖屏／退出播放把图层拆掉时同样把倍率还回去，不会把用户留在临时倍率上。

## 改动

- `lib/features/player/player_gestures.dart`：新增 `kPlayerHoldMinRate`（2.0）与 `holdRateFor`；`PlayerGestureLayer` 新增可选 `onHoldStart` / `onHoldEnd` / `holdRate`，接上 `onLongPressStart` / `onLongPressEnd` / `onLongPressCancel`；新增 `_holding` 状态与中央「{rate}x 加速中」胶囊；拖拽开始与 `dispose()` 都会先结束按住。
- `lib/features/player/player_page.dart`：新增 `_holdBaseRate`、`_beginHold`、`_endHold`、`_holdEnabled`；横屏与竖屏两处 `PlayerGestureLayer` 都接上按住回调（一起看为 null），并传 `holdRateFor(state.rate)` 供胶囊显示。
- `test/features/player/player_gestures_test.dart`：`pumpLayer` 支持按住回调与 `holdRate`；新增 7 条用例。
- `test/app/player_page_test.dart`：`pumpPlayer` 支持 `room` / `watchTogether`（并补了 `RoomOnlyWatch`、`StaticApiSession` 两个测试替身）；新增「press-and-hold speed boost (S82)」组 5 条用例。
- 本记录。

## 自动验证

- `(cd services/watch_together && /Users/sakurasep/devsdk/flutter/bin/dart pub get)`、`bash tool/check_layering.sh`、`/Users/sakurasep/devsdk/flutter/bin/flutter analyze`、`/Users/sakurasep/devsdk/flutter/bin/flutter test` 四条独立执行，退出码均为 0（analyze 为 No issues found，全量测试通过）。
- 手势层新增用例：按住只触发一次开始、松手触发结束、取消触发结束、按住期间显示「2.0x 加速中」且胶囊为深色样式、3.0x 基数的胶囊文案、未提供回调时长按不进 arena（仍按单击结算）、单击不触发按住、上下拖拽与横滑 seek 不触发按住、`holdRateFor` 的 `max(base, 2.0)` 语义。
- 页面新增用例：横屏与竖屏各一条 `1.25x → 2.0x → 1.25x`，断言 `FakePlaybackEngine.rates` 的实际序列恰为 `[2.0, 1.25]` 且胶囊文案为「2.0x 加速中」、松手后胶囊消失；3.0x 按住不写任何倍率、胶囊显示「3.0x 加速中」、结束后仍是 3.0x；快速按住立即松手写入顺序为 `[2.0, 1.25]`；一起看房间下按住不出现胶囊、不产生任何倍率写入。
- 范围检查：`git status --porcelain` 只列出本任务的两个源文件、两个测试文件与 `docs/tasks/` 下本记录（另有调度台生成的 `.pi/goal/` 目标工件）。

## 待人工体验

- 横屏／竖屏真机上 0.5 秒的触发延迟是否合适（更快会更容易误触，更慢会显得迟钝）。
- 2.0x 的实际加速手感与中央胶囊的位置、可读性。
- 单击显隐、上下拖拽亮度/音量、横滑 seek、按钮点击在按住之后都没有误触。
- 一起看下按住画面确认不产生个人加速，倍速提示仍只有「一起看时播放速度固定为 1 倍」。
