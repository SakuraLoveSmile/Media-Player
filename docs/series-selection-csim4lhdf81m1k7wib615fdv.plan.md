# 剧集选季与单集播放

任务标识：`csim4lhdf81m1k7wib615fdv/872fd957-3f0d-4b31-9ea5-8277d92fef0f`。

以下保留用户提供的冻结计划正文；其中“本轮只交付计划”“未开始”等描述为冻结时历史状态，本次实际执行情况追加在文末，不改变原验收目标。

## 冻结计划正文

让用户从媒体库进入剧集，选择季和分集后正常播放；退出播放器后回到刚才的季，能够继续选集，并沿用现有续播和进度上报。

本轮只交付计划，以下实施和验证均未执行。所有文件路径相对任务仓库根。实施只使用调度核心登记的本任务分支/worktree；开始时复核分支、基线和保留改动，不另建或切换工作区。根 AGENTS.md 缺失，项目约束以现有 README、开发文档和用户提供的约定为依据。执行记录继续维护在本计划中。

**已确定的实现方向**

当前链路是“媒体库海报 → /player/:itemId → PlayerController”，整部剧的 Series 条目在播放器被拦截。补齐后的链路为：

媒体库中的 Series → /series/:seriesId → LibraryService.item/seasons → 按所选 seasonId 查询 episodes → /player/:episodeId → 现有播放、续播与上报流程。

电影继续使用原播放入口。季集数据复用 docs/contracts/emby-client-contract-v1.1.md §2 的现有接口，不新增服务端接口、依赖或持久化结构。所有请求继续经过现有认证仓储，使用同一 ResolvedEndpoint；播放继续遵守 LAN 视频不转码及既有片源选择规则。

本次交付手动选季、选集和单集播放闭环；自动连播、下一集推荐和片源版本选择不作为本次新增行为。正常播放会按现有机制更新 Emby 对应单集的观看进度，选集页本身只读取数据。

**交互与页面规格**

以下为本次规划选择，视觉继承 lib/app/app.dart、lib/features/library/library_page.dart；附件作为阻断现象证据，历史媒体库截图作为样式参考。

- 新增 SeriesPage，使用现有亮色 Material 3 的 Scaffold、AppBar、ColorScheme 和 TextTheme。页面从上到下为返回按钮与剧名、可选简介、季选择条、单列分集列表。内容水平留白 16，底部留白 24；简介最多三行。媒体库原有网格、海报和设置入口保持原样。
- 季选择沿用媒体库 ChoiceChip：横向滚动、间距 8、选择条高度 56。长季名限制单行并省略，保留完整语义标签。默认选编号最小的正数季；没有正数季时选排序后的第一季。特别篇编号 0 可正常选择。季和集按 indexNumber 数值升序排列，缺失编号放末尾，同编号保持服务端原顺序。
- 分集使用 ListView.builder 和 Material ListTile，每行可点击，显示集号、名称、可用时长及观看状态，尾部使用播放图标。名称最多两行；缺失集号时直接显示名称。已看状态来自 UserData.Played；存在进度时展示观看位置，最终起播位置仍由播放器重新读取详情决定。整行操作提供明确的播放语义，沿用原生焦点与键盘激活行为。
- 手机和桌面均使用同一单列列表，宽屏增加可用文本空间；不依赖固定卡片宽高。季名横向滚动，分集纵向滚动，长文本不得挤出操作区。
- 初次加载显示进度；没有季显示“暂无可观看的季”，所选季没有分集显示“这一季暂无分集”。请求失败显示实际错误和手动重试，不伪装为空列表。切季时清空上一季分集并显示加载状态；刷新已有列表时保留内容。401 回登录，403 提示权限不足且不自动重试。
- 媒体库通过 push 打开选集页，选集页通过 push 打开播放器。返回播放器前先完成现有 Stopped 流程；返回后保留季选择和滚动位置，并刷新该季观看状态。再次返回媒体库时保留原库和滚动位置。选集页直接进入且没有可返回页面时，返回媒体库。
- 单集点击设置导航互斥，防止双击叠加播放器。播放结束后由用户继续选择其他分集。

**T1：准备路由契约和测试数据（未开始，主 agent）**

独占 lib/core/router/app_routes.dart、test/app_test.dart，以及 test/support/fake_library_service.dart、fake_playback_service.dart、fake_playback_reporter.dart。

1. 新增 /series 路径和 seriesFor(seriesId)，保留 playerFor 的现有语义；补充路由生成用例。
2. 扩展 FakeLibraryService，支持显式详情映射、按剧查询季、按季查询分集，并记录请求参数。item() 优先使用显式详情，再保留既有 itemsByView 查找行为；新增字段默认值保持旧测试可用。季集查询也遵守现有 failure/unauthorized 开关。
3. 新用例必须使用真实的 Series、Season、Episode 类型，不能继续用默认 Movie 的假剧集验证选集入口。延迟响应使用测试内 Completer 或局部 fake 子类。
4. 播放 fake 记录实际传入的 itemId，上报 fake 记录各次报告对应的 itemId，供联合用例验证从点击到上报始终指向所选单集。
5. 冻结 T2/T3 的接口：SeriesController({required String seriesId, required LibraryService library})；提供 state、load()、selectSeason(String seasonId)、refreshEpisodes() 和 dispose()。SeriesState 至少包含 series、seasons、selectedSeasonId、episodes、loading、episodesLoading、error、episodesError、unauthorized。错误字段区分整页加载失败和当前季分集失败。

完成条件：测试准备能够表示两季、特别篇、不同观看进度和延迟响应，既有电影夹具行为保持可用。

**T2：实现季集状态与异步规则（未开始，状态负责人 worker）**

独占新增 lib/features/series/series_controller.dart、test/features/series/series_controller_test.dart；只读参考 LibraryService、MediaItem、EmbyException 和现有 LibraryController。T1 完成后可与 T3 并行，自行完成本模块，不继续拆分。

1. load() 读取剧集详情和季列表，按上述规则选择默认季，再查询该季分集；无季时不请求分集。入口条目不是 Series 时显示明确错误和返回入口。
2. selectSeason() 使用真实 seasonId 调用 episodes(seriesId: ..., seasonId: ...)，实现数值排序；不套用媒体库每页 60 条的客户端截断。重复选择正在加载的同一季不重复请求，失败后允许重试。
3. 每次切季或刷新分配递增请求序号；仅当前请求可更新分集、加载状态及普通错误。覆盖 A→B→A 的乱序响应，不能只比较 seasonId。销毁后不通知界面；认证失效仍遵守现有清会话和回登录流程。
4. refreshEpisodes() 保留当前选季和已有内容，成功后用服务端数据更新观看状态；失败显示可重试错误，不伪造已看或续播状态。
5. 单测覆盖默认季、特别篇、缺失编号、无季、空季、请求参数、超过 60 集、乱序成功与失败、重试、401/403，以及请求完成前销毁。

完成条件：状态变化符合页面规格，任何已过期响应都不能覆盖当前季。

**T3：实现可操作的选集页面（未开始，界面负责人 worker）**

独占新增 lib/features/series/series_page.dart、test/app/series_page_test.dart；只读参考现有媒体库页面和本计划的共享接口。T1 完成后与 T2 并行，依据冻结接口开发，最终可运行验证依赖 T2 交付。

1. 通过 bootstrapProvider 获取现有 services.library，创建和销毁 SeriesController；保持 features 不直接依赖 Dio、media_kit 或其他 feature 的实现文件。
2. 按上述视觉与状态规格实现标题、简介、季选择和分集列表。为列表设置稳定的季标识，避免刷新和播放返回时丢失滚动位置。
3. 点击分集后等待播放器路由返回，再在页面和会话仍有效时刷新当前季。导航期间防重复点击；页面离开或登录失效后不再发起刷新。
4. 界面用例覆盖选择不同季、播放参数、双击互斥、空态、加载失败重试、窄屏长名称和列表末项可达。使用明确的 Future 完成条件，不用固定等待掩盖异步问题。

完成条件：页面能通过现有服务接口操作真实类型的季集数据，并按规格返回。

**T4：接通入口并保留播放器保护（未开始，主 agent）**

独占 lib/app/router.dart、lib/features/library/library_page.dart、lib/features/player/player_controller.dart、lib/features/player/player_page.dart、lib/app/feedback_config.dart，以及对应的 library_page_test.dart、player_page_test.dart、player_controller_test.dart、feedback_config_test.dart。T2/T3 完成后接入联合流程；路由和播放器局部改动可提前准备。

1. 注册 /series/:seriesId。媒体库按 item.type 分流：Series push 到选集页，Movie 沿用现有播放器入口。不要把库内全部 Episode 展平到海报网格。
2. 保留 PlayerController 对 Series 的播放协商拦截。为该状态增加可选 selectionSeriesId，仅在拦截整部剧时设置，文案改为“请选择分集后播放”。PlayerPage 提供“选择分集”按钮，通过替换当前播放器路由打开对应选集页，使旧入口也能恢复操作；不得向 Series 发 PlaybackInfo。
3. 播放器返回提示改为通用“返回”，继续复用现有先 stop() 再 pop 的退出路径。每次单集播放使用独立 engine/reporter，续播仍遵守未看完且位置严格大于 10 秒的规则。
4. 在反馈页面类别白名单加入固定 series 类别，保持剥离条目编号和查询参数的现有逻辑。
5. 联合用例验证：从媒体库点击 Series 时尚无播放协商；选定第二季某集后，协商、engine 和各类报告使用同一 episodeId；返回后仍选中第二季，观看信息刷新；再播另一集使用新会话；双击只进入一个播放器。保留 Series 拦截测试，并新增 Episode 起播和续播边界用例。
6. 回归电影播放、退出上报幂等、401 回登录和媒体库分页，不删除或放宽既有断言来适配新实现。

完成条件：用户主路径与旧 Series 播放入口均可到达选集操作，电影行为无回归。

**T5：验证最终组合态并记录体验入口（未开始，主 agent）**

T2/T3 可以按独占文件并行，T4 联合验证依赖二者完成；共享测试支持文件只由主 agent 写入。各实现负责人先核对自己的交付，最终用户路径由主 agent 亲自验证。本轮并行工具启动失败，若实施环境仍不可用，按上述依赖串行完成，不新增工作树。

在核心已准备 Flutter 3.47.7 和离线依赖缓存的任务工作树执行以下命令；缺少环境时记录具体阻塞，不在本轮安装或联网补齐。分层守卫、分析和全量测试是项目现有质量门。

```verify
./tool/check_layering.sh
~/devsdk/flutter/bin/flutter analyze --no-pub
~/devsdk/flutter/bin/flutter test --no-pub
LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub
~/devsdk/flutter/bin/flutter build apk --debug --no-pub
```

自动检查的成功标准是全部命令退出成功、分层守卫无违规、分析无问题、新旧测试通过且两个目标产物构建成功。测试只使用 fake、内存存储和既有本地测试服务。构建结果单独记录，不代替实际播放证据；现有三平台发布门禁继续沿用。

原生验收使用已有隔离测试设备/系统测试账号及已授权的 Emby 测试会话，避免覆盖用户现用应用和数据。Android 使用本任务 app-debug.apk；macOS 使用本任务 Debug/Media Player.app，核对启动对象确实来自本次构建。

1. 在 Android 真机从媒体库进入剧集，看到季和分集；切至另一季或特别篇，滚动到最后一集，确认全部可访问。无多季真实样本时，相关边界保留为模拟验证，不写成真实服务通过。
2. 选择有片源的单集，确认出现画面和声音，暂停、继续、拖动可用；LAN 下通过现有直连判定和服务端会话确认视频未转码，不能仅根据成功起播判断直连。
3. 播放超过续播阈值后退出，确认回到原季与原列表位置、旧会话结束；重开同一集，从服务器保存的位置继续。再选另一集，确认内容和进度没有串集。
4. 返回媒体库，确认原库和滚动位置保留；播放一部电影验证原路径。用原生返回按钮及 Android 系统返回各走一次退出路径。
5. macOS 原生应用复核选季、选集、播放和返回；在手机竖屏与桌面窗口检查长标题、季选择条和错误状态是否溢出。Windows 若未构建或实测，明确记录未验证，不沿用历史签核。

主 agent 将新的页面入口和“媒体库→季集查询→单集播放器”调用关系补充到 docs/README.md；实际命令结果、产物路径、设备环境、测试样本、必要截图及剩余问题追加到本计划执行记录。保留历史签核的原适用范围。

必要验证未完成时记录为“实现中”；适用自动检查与真实路径验证完成后为“待体验”，用户明确确认后才能记为“已验收”。设备、授权测试会话或样本缺失只暂停对应验证，继续其他可完成项，不用 mock 成功替代真实播放。本轮及模型执行阶段不提交、推送或合并；验证后交调度核心冻结评审版本。

## 执行记录（2026-11-04，Asia/Taipei）

- 状态：**实现中**。T1–T4 的代码及测试已写入，必要的 Flutter 运行验证和原生播放验收受环境阻断，不能标记为待体验或已验收。
- 工作区：`/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-kaneopilot/managed-worktrees/csim4lhdf81m1k7wib615fdv/branch`；分支 `kaneo/csim4lhdf81m1k7wib615fdv`；基线 HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时索引与工作区均无改动。本次验证对象是该基线加本任务未提交差异及新增文件，不是基线单独的历史结果。
- 全程使用该工作树；未创建/切换分支或工作树，未 commit、push、reset、stash、rebase、合并、发布。工作树留给调度台冻结和评审，尚未合并，不属于合并后清理阶段。
- 实际并行：主 agent 完成 T1 后，T2 与 T3 使用两个 `worker`（6.1 Sol / high）分别独占上述状态/页面与各自测试；未派生下级任务。共享测试 fake、路由、播放器和执行记录由主 agent 唯一写入。所有测试数据为内存 fake，没有新端口、数据库或真实媒体服务进程。
- T1：增加 series 路由生成；fake 支持显式详情、季集映射、请求参数和各类播放上报的 itemId。原电影夹具继续可用，媒体库 Shows 夹具改为真实 Series；不改变既有断言。
- T2：实现冻结接口、稳定排序、默认季、完整分集查询、请求序号、刷新保留内容、401/403 区分、重试与销毁保护；新增相应控制器测试。
- T3：新增亮色 Material 3 选集页、横向季选择和单列分集、观看信息、错误与空态、按季滚动保存、push 互斥及返回刷新；新增 11 个 widget 场景，包括 320×640 长文本和 75 集末项。
- T4：接通媒体库 Series push，保留电影入口；旧 Series 播放路由以按钮替换为选集页，仍不进行播放协商；续播规则和每集 engine/reporter 工厂沿用。主 agent 新增真实 appRouter 联合用例：第二季第 75/76 集、双击只开一次、单集详情重新决定 125 秒续播、协商/engine/Started/Progress/Stopped 同一 itemId、等待 Stopped 完成才返回刷新、季和两级滚动位置保留、下一集独立会话。新增 Episode 严格 10 秒边界、已看从头播、旧入口恢复、播放 401 回登录及反馈类别脱敏用例。保留电影、退出幂等与分页回归断言；没有删除、跳过用例或降低门禁。
- 架构与体验入口已补充到 `docs/README.md`。体验路径：媒体库剧集海报 → 季选择 → 点击分集 → 播放器“返回” → 原季；本轮没有实际原生体验通过证据。

### 本轮环境与已执行的辅助检查

- 宿主 Darwin arm64。`~/devsdk/flutter/bin/cache/dart-sdk/bin/dart --version` 退出 0，Dart 3.13.5；既有 package_config 标注 Flutter 3.47.7。任务开始时缺少 `.dart_tool`；核对主工作区 `pubspec.yaml` 与 `pubspec.lock` 和本工作树完全相同后，只在本任务 `.dart_tool/package_config.json` 复用其已有离线缓存路径，`media_player` 的 `../` 仍解析到本工作树。没有 pub get、pub upgrade、安装 SDK、依赖更新或联网补齐。
- 主 agent 的 `~/devsdk/flutter/bin/cache/dart-sdk/bin/dart analyze lib test` 退出 0，`No issues found!`，覆盖最终组合源码与测试。此辅助检查不是冻结 Flutter analyze 命令的替代通过记录。
- 两个负责人分别执行自己的 Dart format 和 scoped analyze，均退出 0；其 Flutter 单文件测试尝试均退出 1，报 `/Users/sakurasep/devsdk/flutter/bin/cache/lockfile` 无写权限，用例未执行。没有绕过权限、修改 SDK 或降低检查要求。
- 主 agent 的 `git diff --check` 退出 0。
- `~/Library/Android/sdk/platform-tools/adb devices -l` 退出 1：ADB 无法启动 smartsocket listener，`Operation not permitted`，无法枚举并确认隔离测试设备；未安装或覆盖现用应用。
- 当前进程未注入任何名称包含 EMBY 的测试环境变量；本轮没有可核验的授权测试会话、真实多季/片源样本或截图。不读取用户现用应用数据，不把历史签核计为本任务通过。
- 原生验收 1–5 均未完成：画面/声音、暂停/继续/拖动、LAN 服务端会话无视频转码、服务器进度落盘与重开续播、Android 系统返回、macOS 原生长标题与错误界面、Windows 本轮构建/运行均未验证。自动/下一集行为不属于新增范围。
- 预期构建产物为 `build/macos/Build/Products/Debug/Media Player.app` 与 `build/app/outputs/flutter-apk/app-debug.apk`；首轮构建后实际核对两者均不存在，没有可运行交付物或发布证据。
- 当前工具清单没有 `SubmitGoalReport`，本机也无同名命令；无法提交该专用 Goal 报告。最终答复仍须返回逐条冻结命令的真实整数退出码，并明确此报告通道缺口，不能声称已提交。

### 冻结验证命令结果

首轮全部修改完成后，主 agent 已按顺序以五次独立终端调用执行，实际结果如下。四条 Flutter 命令均在 SDK 启动阶段失败：`update_engine_version.sh` 第 71/78 行无法写入 `/Users/sakurasep/devsdk/flutter/bin/cache/engine.stamp.tmp.<pid>` 和 `engine.realm`，报 `Operation not permitted`，退出 1；分析器、测试和平台构建均未开始。属于沙箱外 SDK 写入权限阻塞，不能记为源码检查通过，也没有安装或联网修补环境。

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | passed；layering ok |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 1 | failed；SDK 缓存写入被拒绝 |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 1 | failed；SDK 缓存写入被拒绝，用例未运行 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 1 | failed；SDK 缓存写入被拒绝，无产物 |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 1 | failed；SDK 缓存写入被拒绝，无产物 |

首轮结果绑定的源码/测试快照：对 `lib` 与 `test` 的所有 `.dart` 按相对路径排序，逐一以 `路径 + NUL + 文件内容 + NUL` 输入 SHA-256，得到 `074bd7fab8304a497df54d5e818e17cb2b05ec327e29fb4ca0eb9d7f7170d85d`。记录结果时没有再修改源码。为遵守“验证后有文件编辑须重跑全部命令”，本执行记录为最后文件编辑，随后再次逐条独立执行全部五条冻结命令；最后一轮的原始工具结果及最终 JSON 为最终退出码来源，之后不再写文件。

下一步由调度台提供能够运行原文 Flutter 命令的 SDK 缓存写入条件及 `SubmitGoalReport` 工具，再运行冻结检查并以本任务产物完成隔离 Android/macOS 的原生验收。原生验收所需测试会话与样本也须可核验；历史签核、辅助静态分析和未运行的 fake 用例不能替代这些证据。任务继续为“实现中”，不缩减原计划范围。

## 重新执行记录（2026-11-05，Asia/Taipei）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/3b1f97fc-622b-4cb8-bffb-a392391b7bd4`；冻结计划哈希：`a94f5f4786ffd50c253ee2e63b6121ee2425ad81b459020cd1257fa39c64ec60`。上文冻结正文和历史记录保留原状，本节只追加本次实际结果。
- 状态：**实现中**。已完成本轮代码核对及必要修正，但 Flutter 运行检查、平台构建和真实播放验收仍受环境阻断。
- 开始及结束时均为用户指定原工作树，分支 `kaneo/csim4lhdf81m1k7wib615fdv`，HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时有 15 个已跟踪文件的未暂存改动，以及本计划、series 源码和测试等未跟踪成果；暂存区为空，全部保留。没有新建或切换分支/worktree，没有提交、推送、合并或发布。该工作树保留给调度核心冻结评审，不进入合并后清理。
- T1/T4：主 agent 亲自复核路由生成和注册、真实 Series 入口、旧播放器拦截及替换入口、单集详情重新决定续播、独立 engine/reporter、同一 episodeId 的协商/Started/Progress/Stopped、等待 Stopped 后返回、季和媒体库滚动保存、电影与分页回归、401、反馈类别脱敏。沿用已有实现与断言，没有删除测试、放宽预期或更改门禁；联合路径尚未运行通过。
- T2/T3 实际并行使用两个 `worker`（gpt-6.1-sol / high），分别独占 controller/其测试、page/其测试，无下级分派；共享文件和记录由主 agent 维护。T2 新增季列表阶段 401/403 不查询分集、不自动重试，以及等待季列表时销毁不通知、不继续请求分集的测试；既有 controller 无需源码修正。T3 修复系统返回后延迟 bootstrap 仍可能请求数据、播放器返回时会话被替换仍可能刷新旧数据的问题，并补齐系统返回、延迟初始化、刷新保留内容及手动重试、320 宽/1.5 倍文字、会话替换与失效、整页路由替换的 7 项界面回归场景。保留原视觉规格和全部已有测试断言。
- 环境：Darwin arm64；本地 SDK 的 `bin/cache/flutter.version.json` 为 Flutter 3.47.7 stable / Dart 3.13.5，直接 Dart 版本命令退出 0。本轮 SDK cache 可写，原文 Flutter 命令的新阻塞为 `/Users/sakurasep/.config/flutter/tool_state` 不在允许写入范围；没有修改宿主配置、变更权限、安装或联网补齐环境。
- 离线元数据：任务已有 `.dart_tool/package_config.json`，缺 `package_graph.json`；主 agent 核对主工作区与本任务 `pubspec.yaml`、`pubspec.lock` 字节完全相同后，仅复用其已有本地 `.dart_tool/package_graph.json` 到本工作树。未修改依赖声明、锁文件或持久化数据。
- 辅助诊断：负责人各自格式化及 scoped Dart analyze 退出 0；主 agent 的 `~/devsdk/flutter/bin/cache/dart-sdk/bin/dart analyze lib test` 退出 0，`No issues found!`，`git diff --check` 退出 0。为隔离工具配置，另用 `XDG_CONFIG_HOME=/tmp/series-main-csim4lhdf81m1k7wib615fdv-config` 运行 library_page、player_page、player_controller、series_controller 四个文件的局部 Flutter test，退出 1：每个文件均在 `FlutterTesterTestDevice.start` 绑定 `127.0.0.1:0` 时遭遇 `Operation not permitted`，实际执行 0 条用例。这些辅助诊断不替代冻结命令，也不能报告测试通过。
- 原生验收：本次 `~/Library/Android/sdk/platform-tools/adb devices -l` 退出 1，无法创建 smartsocket listener（`Operation not permitted`），未确认隔离设备，未安装或覆盖用户应用；环境未提供 EMBY 测试变量或可核验的测试会话/媒体样本。macOS 与 Android 本次构建产物均不存在。原生验收 1–5 的画面/声音、操作、LAN 服务端无视频转码、进度落盘/续播、系统返回及窗口视觉均未验证，没有截图或真实播放通过证据。Windows 本轮未构建、未实测，历史签核不扩展到本次功能。
- 体验入口及调用关系仍见 `docs/README.md`：媒体库剧集海报 → `/series/:seriesId` → 选择季与分集 → `/player/:episodeId` → 返回原季。页面只读取观看数据，上报继续由单集播放器负责。

### 本次冻结验证的实际结果

全部源码修改结束后，主 agent 按原顺序以五次独立终端调用执行，实际退出码如下；没有用局部诊断或文字代替命令。四项 Flutter 命令均在工具启动时失败，分析器、测试主体及平台编译尚未启动，属于环境失败。

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 1 | 无法写入 `~/.config/flutter/tool_state` |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 1 | 同上，测试主体未运行 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 1 | 同上，无 macOS 产物 |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 1 | 同上，无 APK 产物 |

本轮 lib/test Dart 源码快照 SHA-256（算法同上次执行记录）：`35c2d5a47c5126db647ec6295423dc67ddba985d991cfd22d471e7c32fc20aa1`。本节与文档入口是最后的人工文件编辑；随后再次逐条独立执行全部五条冻结命令，最终工具原始退出码和 CLI JSON 是封版检查结果，之后不再修改文件。

剩余工作：调度环境需允许原文 Flutter 命令写入工具配置及运行本地测试监听，再完成全部冻结检查、生成本任务两端产物，并提供可核验的隔离设备/授权测试会话与样本以执行原生验收。没有未决产品选择；本次按当前请求只向 Codex CLI 返回 JSON，不依赖历史记录提及但当前未要求的 `SubmitGoalReport`。本任务没有新增服务、端口或数据库；辅助配置只位于任务专用临时目录。

## 重新执行记录（2026-11-06，Asia/Taipei）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/43875508-417f-4483-9df0-699ed0e8b031`；冻结计划哈希：`a94f5f4786ffd50c253ee2e63b6121ee2425ad81b459020cd1257fa39c64ec60`。冻结正文及历史记录保持原样，仅追加本节实测结果。
- 状态：**实现中**。T1–T4 已实现并通过本轮全量自动测试；T5 的两端构建及原生真实播放验收尚受环境阻断，不能标记为待体验或已验收。
- 工作树仍为本文件前述原执行目录，分支 `kaneo/csim4lhdf81m1k7wib615fdv`，HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时已有 15 个跟踪文件的未暂存修改，以及本计划、series 源码和测试等未跟踪成果，暂存区为空；全部保留，没有新建或切换分支/worktree、提交、推送、合并、发布或清理其他成果。工作树留给调度核心冻结评审，尚不进入合并后清理。
- 实际并行：两个 `worker`（gpt-6.1-sol / high）分别独占 T2 的 controller/测试、T3 的 page/测试，无下级派发；共享文件、播放器、联合用例和本记录由主 agent 唯一写入。T2 复核稳定排序、默认正数季、特别篇、完整集数、请求序号、乱序与刷新、401/403、销毁保护，无需修改。主 agent 亲自复核 T1/T4 路由、媒体类型分流、Series 协商拦截和旧入口恢复、续播边界、独立播放会话、反馈脱敏及联合用户路径。
- 本轮修复：真实执行页面测试后，既有“播放器内会话失效回登录”用例失败，原因是会话流在静止界面注册了 post-frame 回调却未请求新帧；`SeriesPage._toLogin()` 增加 `ensureVisualUpdate()`，保留原失效断言。另补 Tab 聚焦分集行、Enter 播放的键盘回归；页面的 19 项 widget 测试全部通过。
- 联合测试首跑发现滚动完成后布局尚未更新，`Show 16` 文本中心仍在 800×600 视口外，点击未到达海报。主 agent 在媒体库和分集列表的 `scrollUntilVisible()` 后补 `pumpAndSettle()`，等待实际布局完成；没有删除或放宽任何断言、跳过用例或使用固定等待替代条件。修复后的联合用例实际通过：第二季第 75/76 集、双击互斥、重新读取详情后 125 秒续播、同一 episodeId 的协商/engine/Started/Progress/Stopped、Stopped 完成后才返回刷新、原季和两级滚动位置保留、下一集独立会话。
- 环境为 Darwin arm64、Flutter 3.47.7 stable / Dart 3.13.5；离线 package_config/package_graph 已存在。本轮原文 Flutter 分析及测试已能运行，不沿用前两轮的失败结论。启动早期的一次局部测试工具调用因 Flutter 的 Azure 元数据探测访问 `169.254.169.254` 被白名单拒绝，未取得进程退出码；主 agent 的辅助测试使用标准 `CI=true` 避免该探测，后续五条冻结命令均按原文执行并获得真实退出码。未安装 SDK、更新依赖、pub get/upgrade、联网补齐缓存或更改门禁。

### 本轮自动检查的实测结果

源码修改完成后，主 agent 按冻结顺序以五次独立终端调用执行：

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!` |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | 363 项全部通过，覆盖新旧测试、fake 与本地测试服务 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 1 | Xcode 无法解析 Swift Package：任务的 `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` 不存在；同时无法写入用户目录下的 DerivedData/日志及临时结果包，CoreSimulator 服务连接失败 |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 1 | 无法写入 `~/.gradle/wrapper/dists/gradle-9.3.1-all/9ot9r568e8zfvvd4mn8rbu1j0/gradle-9.3.1-all.zip.lck`，`Operation not permitted`；Gradle 编译未开始 |

- `git diff --check` 退出 0；本轮未产生额外跟踪文件改动。上述构建问题属于环境和生成缓存阻塞，没有修改项目平台配置来绕过冻结命令或扩大宿主权限。
- 本轮源码/测试快照 SHA-256（算法同历史执行记录）：`b309ce0fc5eb9836d7fb33ae8f8fd49f88a8bf32025d84be4b455f539eaaf05c`，对象是基线加保留及本轮未提交成果，不是单独的 HEAD。
- 为遵守“验证后不再改文件”，本节是最后的人工文件编辑；随后再次按原顺序、独立调用全部五条冻结命令。最终原始终端结果及 CLI JSON 作为封版检查的退出码来源，之后不再修改文件。

### 原生验收与剩余工作

- `adb devices -l` 本轮退出 0，识别到 Mi 10；只读用户枚举也退出 0，但未确认专用隔离测试用户/设备。没有安装、覆盖或启动用户现用应用，没有读取其凭据或媒体进度数据。
- 当前未注入 EMBY 测试变量；既有 smoke 工具要求运行时注入 `EMBY_LAN_URL`、`EMBY_USER`、`EMBY_PASS`，仓库未提供可核验的授权测试会话/样本。本轮未创建新服务或数据库，自动测试只使用内存 fake 和既有本地测试服务。
- 实际核对 `build/macos/Build/Products/Debug/Media Player.app`、`build/app/outputs/flutter-apk/app-debug.apk` 均不存在；原生验收 1–5 未完成。画面/声音、暂停/继续/拖动、LAN 服务端确认视频无转码、真实服务器进度与重开续播、Android 系统返回及两端原生长文本/错误视觉均未实测，无截图或真实播放通过证据。Windows 本轮未构建、未运行，历史签核不扩展到本功能。
- 体验入口及实际调用关系已在 `docs/README.md`：媒体库剧集海报 → `/series/:seriesId` → 选季/选集 → `/player/:episodeId` → 返回原季；观看数据仍由服务器读取，播放及进度上报仍使用现有播放器链路。
- 下一步需要在满足 Xcode/SPM 生成资源和 Gradle 缓存写入条件的环境完成两端原文构建，再用本任务产物及可核验的隔离设备/测试账号、授权 Emby 会话与样本执行原生验收。没有未决产品选择；本轮按执行/环境失败交付，保留完整范围和现场，不把 mock 或历史结果当作真实播放验收。

## 重新执行记录（2026-11-07，Asia/Taipei）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/52044e49-bee9-4d69-a746-e184061dc89f`；冻结计划哈希：`a94f5f4786ffd50c253ee2e63b6121ee2425ad81b459020cd1257fa39c64ec60`。本节只追加执行证据，冻结正文、范围、验收目标及历史记录不变。
- 状态：**实现中**。T1–T4 的实现已核对并通过本轮自动检查；两端 Debug 产物已生成，T5 的真实设备与服务验收仍缺少可用设备和运行时授权测试会话，不能标记为待体验或已验收。
- 工作区：沿用原执行路径、分支 `kaneo/csim4lhdf81m1k7wib615fdv` 和 HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时暂存区为空，已有 15 个跟踪文件的未暂存改动、本计划、series 源码及测试和 `.pi/` 等未跟踪成果；全部保留。未新建或切换分支/worktree，未提交、推送、合并或发布。任务工作树继续交调度核心冻结评审，尚不满足合并后清理条件。
- 按 T2/T3 实际使用两名 `worker`（gpt-6.1-sol / high）并行，分别独占 controller/单测与 page/页面测试，不继续派生；共享支持、播放器、联合路径及执行记录由主 agent 负责。T2 静态复核符合冻结接口、排序、默认季、特别篇、完整集数、请求序号、乱序、重试、刷新、401/403 和销毁保护，无需重写。T3 补充两季各 40 集的独立滚动恢复用例，验证进入新季从头、s1→s2→s1→s2 分别恢复原位置，无需改页面源码。
- 主 agent 亲自核对媒体类型分流、Series 协商拦截及旧入口恢复、单集续播边界、每次独立 engine/reporter、Stopped 后才返回刷新、反馈类别脱敏及完整联合路径。先运行五个受影响页面/controller 文件的局部测试，97 项全部通过；随后全量测试 364 项通过，覆盖第二季第 75/76 集、协商/engine/各类报告的 episodeId 一致性、双击互斥、125 秒续播、观看状态刷新、原季及两级滚动位置保留、电影、401 和媒体库分页。未删除、跳过或放宽既有断言；新增滚动测试使用真实 Flutter 滚动状态和异步完成条件。
- 环境：Flutter 3.47.7 stable / Dart 3.13.5，Xcode 27.0（27A5237l），已有 JDK 17 与 Android 工具链。没有另行安装 SDK、执行 pub get/upgrade 或修改依赖版本、平台配置、检查门禁。原文 Android build 自身发起 media_kit 四个架构 JAR 下载，macOS build 自身执行 CocoaPods 安装步骤；因此不把本次构建描述为完全无网络的离线验证。`pubspec.lock` 及 macos/android 跟踪文件没有新增差异。

### 本轮自动检查与产物

全部代码修改结束后，主 agent 在当前任务工作树逐条、独立调用冻结命令。下表为记录编辑前各命令最近一次实际结果；最后文件编辑后还会按冻结顺序完整重跑，最终原始终端退出码及 CLI JSON 为封版结果来源。

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!` |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | 364 项全部通过 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本工作树的 Debug/Media Player.app |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本工作树的 app-debug.apk |

- macOS 首次原文构建退出 1：读取工程信息的 `xcodebuild -list` 子进程被终止，退出 -9。`xcrun xcodebuild -version` 退出 0；随后在 macos 目录以 `-disableAutomaticPackageResolution -list` 查询同一本地包图退出 0，确认工程及本地 Swift 包可读，基于这一新证据重跑原文构建，退出 0 并生成应用。构建日志含既有插件尚未采用 SPM、宏重定义及 Swift 编译诊断，但最终命令成功；未以诊断输出替代实际退出码，也未改平台配置绕过构建。
- Android 产物：`build/app/outputs/flutter-apk/app-debug.apk`，219194168 字节，记录时 SHA-256 `c924f77adb3c3fd71073833ed7cdb962552d46ac5b6956a7028316ecf747241e`。
- macOS 产物：`build/macos/Build/Products/Debug/Media Player.app`，bundle ID `dev.mediaplayer.mediaPlayer`；记录时主可执行文件 SHA-256 `ac893c1a82f93fee45f3e32b97f310a5fa6644e1e8366c7f6b9a0eadbd8861b4`。上述路径与指纹来自本工作树产物，不代表已启动或播放验收，最终重建可能更新产物指纹。
- 本轮 lib/test Dart 快照 SHA-256（算法同历史记录）：`b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`，绑定当前 HEAD 加保留及本轮未提交成果。分支、HEAD 与保留范围已复核，`git diff --check` 退出 0。

### 原生验收与下一步

- `adb devices -l` 本轮退出 0，但设备列表为空。当前未注入任何 `EMBY_` 测试变量；既有测试说明和 smoke 工具要求凭据在运行时注入，不能沿用历史会话作为本轮可用会话证据。未安装、覆盖、启动用户现用应用，未读取其凭据或修改真实媒体进度；未另建服务或数据库。
- 原生验收 1–5 尚未执行：Android 真机的季集访问、声音与画面、暂停/继续/拖动、LAN 服务端确认视频未转码、退出后进度落盘/续播、系统返回，以及 macOS 原生选季选集/播放/返回和两端视觉仍缺实测。没有相关截图或真实服务通过证据；窄屏长文本、特别篇、超过 60 集和返回位置只报告本轮模拟测试通过。Windows 未构建、未实测，历史签核不扩展到本功能。
- 体验入口和实际调用关系继续见 `docs/README.md`：媒体库 Series 海报 → `/series/:seriesId` → LibraryService 详情/季/分集查询 → `/player/:episodeId` → Stopped 完成后返回原季并刷新观看信息。选集页只读取数据，播放、续播和上报沿用单集播放器与现有端点/认证规则。
- 下一步：提供可核验的隔离 Android 设备/系统测试账号与授权 Emby 测试会话、可播放剧集/电影样本，使用本任务两端产物完成原生验收。当前没有未决产品选择；自动检查通过不替代这部分验收，任务因验收环境缺失继续保持实现中。
- 本节为最后一次人工文件编辑。随后由主 agent 逐条、独立重跑全部五条冻结命令；之后不再修改源码、测试、文档或执行记录，最终结果交 Codex CLI 输出文件接收。

## 重新执行记录（2026-11-07，执行 b6f88006）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/b6f88006-64dc-4a84-a981-91d6455e9509`；冻结计划哈希：`a94f5f4786ffd50c253ee2e63b6121ee2425ad81b459020cd1257fa39c64ec60`。仅追加本节执行证据，冻结正文、范围及历史记录保持原样。
- 状态：**实现中**。T1–T4 的保留实现经本轮重新核对及实测，无需新增代码修改；五项自动检查首轮全部成功，两端 Debug 产物已生成。T5 原生验收缺少隔离设备/系统测试账号及运行时授权 Emby 测试会话，尚未达到待体验或已验收条件。
- 全程沿用用户指定原工作树、分支 `kaneo/csim4lhdf81m1k7wib615fdv`、HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时索引为空，已有 15 个跟踪文件的未暂存改动，以及本计划、series 源码/测试、`.pi/` 等未跟踪成果；全部保留。本轮只人工追加本执行记录，未另建/切换分支或 worktree，未提交、推送、合并、发布。工作树继续留给调度核心冻结评审，尚不进入合并后清理。
- 实际使用两个 `worker`（gpt-6.1-sol / high）并行复核 T2/T3，分别独占 controller/单测和 page/页面测试，未派生下级任务；共享支持、播放器、联合验证及本记录由主 agent 负责。两位负责人均未修改文件：T2 的 27 项控制器测试退出 0；T3 的 20 项页面测试退出 0，其两份文件的只读格式检查退出 0。
- 主 agent 亲自检查 T1/T4 的真实类型分流、Series 协商拦截及旧入口恢复、单集详情决定续播、独立 engine/reporter、Stopped 后返回刷新、反馈类别脱敏和两层滚动保留。实际运行 library_page、player_page、player_controller 三个文件的 50 项测试，退出 0；联合用例验证第二季第 75/76 集、双击互斥、125 秒续播、同一 episodeId 的协商/engine/各类上报、等待 Stopped 完成、观看状态刷新及原季/媒体库滚动位置恢复。没有删除、跳过或放宽断言，没有修改门禁。
- 环境：Darwin arm64，Flutter 3.47.7 stable / Dart 3.13.5，Xcode 27.0（27A5237l），既有 JDK 17 与 Android SDK；使用调度环境注入的本次 `.pi/kanpilot/codex/b6f88006-64dc-4a84-a981-91d6455e9509/` 工具缓存。未手动安装 SDK、执行 pub get/upgrade 或修改依赖、平台配置、持久化结构。冻结 macOS 构建自行执行 `pod install`；不把平台构建描述为完全无网络的离线验证。自动测试仅使用 fake、内存存储及既有本地测试服务。

### 本轮自动检查与产物

主 agent 已在当前任务工作树按冻结顺序、逐条独立调用以下命令，取得真实退出码。下表记录本执行记录编辑前的实测结果；本节是最后一次人工文件编辑，随后将再次逐条执行全部五项，封版结果由原始终端输出及最终 CLI JSON 接收，之后不再改文件。

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!` |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | 364 项全部通过 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本任务 Debug/Media Player.app |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本任务 app-debug.apk |

- Android 产物：`build/app/outputs/flutter-apk/app-debug.apk`，记录时 219194168 字节，SHA-256 `72ae20e1f3059252eca26b1167f52979b18ce91d805129ae9359c2f161bd75da`。
- macOS 产物：`build/macos/Build/Products/Debug/Media Player.app`，bundle ID `dev.mediaplayer.mediaPlayer`。构建日志提示 media_kit 插件尚未采用 SPM；Android 有既有 SDK XML 版本兼容告警，两条构建实际均退出 0，未为消除告警改动配置。产物路径已核对，但未启动或进行真实播放；最终重建后以实际文件为准。
- `git diff --check` 本轮退出 0。当前 104 个 lib/test Dart 文件按历史记录算法计算的 SHA-256 为 `b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`，与任务开始时保留源码一致；验证对象是当前 HEAD 加保留未提交成果，历史通过未代替本轮运行。

### 原生验收缺口与解除条件

- `~/Library/Android/sdk/platform-tools/adb devices -l` 本轮退出 0，但列表为空；没有可核验的隔离 Android 设备/系统测试用户。本次进程没有注入任何 `EMBY_` 测试变量，也没有提供本轮授权会话或可播放样本。已通过异步问题请求补齐这些条件或由用户使用本任务产物完成原生验收；目前未取得回答。
- 原生验收 1–5 均未执行：两端真实季集访问、手机竖屏/桌面窗口长标题与错误状态、画面/声音、暂停/继续/拖动、LAN 服务端会话确认视频未转码、服务器保存进度与重开续播、跨集不串进度、电影回归及 Android 系统返回仍需实测。特别篇、超过 60 集、键盘与两级滚动仅有本轮模拟验证；没有新截图或真实服务通过证据。Windows 本轮未构建、未实测，历史签核不扩展到本功能。
- 未安装、覆盖或启动用户现用应用，未读取其凭据或改动真实媒体进度；未新建真实服务、端口或数据库。macOS 应用也需使用已确认隔离的系统测试账号，避免复用用户现用应用的同 bundle ID 存储。
- 体验入口及调用关系已在 `docs/README.md`：媒体库 Series 海报 → `/series/:seriesId` → LibraryService 详情/季/分集 → `/player/:episodeId` → 等待 Stopped 后返回原季并刷新。下一步提供可核验的隔离 Android/macOS 测试环境、运行时授权 Emby 会话、可播放剧集和电影样本，使用以上本任务产物完成原生验收 1–5，并提供真实播放、续播及服务端无视频转码证据后解除阻塞。没有未决产品选择，当前成果保留，不能用自动检查或产物生成提前标记完成。

## 原生验收准备续记（2026-11-07，执行 b6f88006）

- 状态仍为**实现中**。用户已明确 Mi 10 是专用测试设备、选择在应用内手动登录 Emby 测试账号，并指定剧集样本《雍正王朝》。本次只继续原冻结任务；macOS 隔离系统账号、电影样本及手动登录完成确认尚未提供，相关问题已异步发出。
- 重新核对原工作树、分支 `kaneo/csim4lhdf81m1k7wib615fdv`、HEAD `33778190efee71c8b741a65abcb817347a2b90be`、空索引及保留改动，均与前次一致；未另建/切换 worktree 或分支。T1–T4 源码/测试没有新增修改，lib/test 快照仍为 `b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`，`git diff --check` 退出 0。此前已完成的 T2/T3 并行复核和自动验证保留原适用范围，本次主 agent 亲自准备原生设备。
- Android 环境：Mi 10，序列号 `8085d06e`，Android 16，1080×2340，当前系统用户 0。用户已确认整台设备为专用测试设备，因此本次安装不再等待重复授权。
- 首次 `adb install -r -t` 退出 1，Android 返回 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。只读证书核对确认：设备旧应用为 0.2.2 / versionCode 4，使用本机既有 `~/.android/debug.keystore` 的证书（SHA-256 `766b6a19522b4da7a46729ee552ec0b16ca9a6fedf3d6e9affd4acd6a92cad98`）；任务缓存自动生成的 debug key 证书不同。没有卸载应用、清理数据或修改源码来绕过签名校验。
- 安全恢复：只把本任务缓存 `config/.android/debug.keystore` 改为指向上述已核验既有调试密钥的符号链接，原任务生成密钥保留为同目录 `debug.before-device-signing.keystore`，没有修改全局密钥。`./gradlew :app:signingReport --offline --console=plain` 的实际输出确认了原任务缓存签名位置，退出 0；未安装工具或更新依赖、平台配置。辅助 apksigner 首次因 PATH 中损坏的 jenv Java shim 未启动，随后直接使用既有 JDK 17 的 apksigner.jar，核对成功；没有修改宿主 PATH、jenv 或 SDK。
- 原文 `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` 本次重建退出 0；重建后的证书与旧应用一致。第二次覆盖安装退出 0（`Success`），`am start -W` 退出 0（`Status: ok`），进程和 MainActivity 存在，原应用数据保留。任务 APK 与设备安装后的 base.apk SHA-256 均为 `7b31bc7e9f22e7190d00c2ec3795d545494f9fef79e420763f0f5fb0ef81e8e0`，确认启动对象来自本任务构建，版本为 0.2.3 / versionCode 5、Debug。
- 设备旧 APK 的代码归档位于 `.pi/kanpilot/codex/b6f88006-64dc-4a84-a981-91d6455e9509/native-acceptance/installed-before-login-prep.apk`，只归档安装包，未复制或读取应用私有凭据/进度数据。初次启动截图位于同目录 `android-startup-wn2h27eh.png`，画面全黑；随后 `dumpsys power` 确认设备为 Dozing，已发送唤醒键。唤醒后的 UI 只报告系统锁屏/AOD 包，尚未看到媒体库或登录页；已请用户解锁手机并完成登录。UI 诊断仅输出固定屏幕标记和包名，没有记录原始界面文字、服务器地址、用户名、密码或 token。
- 当前只完成安装与启动准备，不能记为季集页面或真实播放验收通过。未点击分集、发起播放或更新服务器观看进度；《雍正王朝》的季/集将在用户确认登录后自行定位。画面/声音、暂停/继续/拖动、LAN 服务端无视频转码、服务器进度落盘与续播、跨集进度、返回/滚动、电影及 macOS 原生路径仍待验证；多季/特别篇若无真实样本，继续按冻结计划仅报告模拟边界。Windows 本轮未构建、未实测。
- 下一步及解除条件：用户解锁 Mi 10 并确认已登录授权测试账号（或确认自动恢复的账号可用于本次测试且允许更新观看进度）；明确 macOS 隔离账号并指定一部可播放、允许更新进度的电影。取得这些条件后继续原生验收 1–5，不要求用户重复提供已确认的设备或剧集信息，也不索取聊天中的密码/token。
- 本节为本次最后一次人工文件编辑。记录前本轮已实际执行的冻结命令仅为上述 APK 重建（退出 0）；随后主 agent 将按原文逐条、独立执行全部五条冻结命令，最终原始终端退出码及 CLI JSON 为封版结果，验证后不再改文件。当前没有提交、推送、合并或发布，任务工作树继续保留给调度核心和后续原生验收。

## 原生路径实测续记（2026-11-07，执行 b6f88006）

- 状态：**实现中**。用户已确认 Mi 10 解锁并登录授权 Emby 测试账号、当前 macOS 账号为专用测试账号，允许主 agent 自行从测试库选择电影。上述条件不再是缺口；本节记录主 agent 的真实原生操作，自动测试和历史签核不代替这些结果。冻结计划正文未修改。
- 工作树、分支和 HEAD 与上节相同，索引为空，原有 15 个跟踪文件改动及全部未跟踪成果保留。业务源码与测试没有新增修改，104 个 lib/test Dart 文件快照仍为 `b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`；`git diff --check` 实际退出 0。本次只更新文档索引、追加本记录及任务局部 UI 诊断/截图，不新增工作树、分支、服务或持久化结构，不提交、推送、合并或发布。
- 本执行此前的 T2/T3 两名 worker 并行复核及其测试结果保留原适用范围。本次另由 `reviewer`（gpt-6.1-sol / high）独立只读检查实际差异、季集状态、认证/媒体仓储、播放器生命周期及联合测试，未发现可明确复现的实质缺陷；未编辑文件、运行冻结检查或操作设备。全部以下原生路径均由主 agent 操作和核对。

### Android：已取得的真实证据

- 环境：Mi 10 / Android 16，序列号 `8085d06e`，用户 0，1080×2340 竖屏。使用本任务 Debug APK（0.2.3+5，包名 `dev.mediaplayer.media_player`），安装包和设备 base.apk 的 SHA-256 已核对一致：`7b31bc7e9f22e7190d00c2ec3795d545494f9fef79e420763f0f5fb0ef81e8e0`。本次没有卸载、清数据、读取私有 token/密码或改动账号配置；截图和 UIAutomator 只用于已授权测试应用。
- 在“国产剧”库滚动到《雍正王朝》，由海报进入新选集页，看到真实简介、所选季和单列分集。此样本服务器只返回一个季（季名“雍正王朝”），实际滚动到第 44 集，末项可以访问；不能将此记录写成多季/特别篇或超过 60 集的真实通过。相关边界仍只有本执行的模拟测试证据。
- 第 43 集“雍正亲自审问弘时”真实显示视频画面，进度推进，时长 44:37。暂停后两次读取仍为 01:28；真实滑块拖动到 10:01 后恢复，进度继续推进，随后在 12:30 暂停。App 返回按钮退出后，回到原季、原滚动位置，列表重新查询后显示“时长 44:37 · 已观看 12:30”。
- 重开第 43 集，出现“已从 12:30 继续播放”，之后实测推进到 13:10。使用 Android 系统返回退出，仍回原季/原列表位置，并刷新为“已观看 13:10”。这提供本次服务器进度保存、重新读取详情及续播的真实客户端证据，未以本地乐观写入代替。
- 随后选择第 44 集“雍正皇帝去世”，画面与上集不同，从 00:06 / 44:56 起播，没有沿用第 43 集的 13 分钟位置。正常退出后，第 43 集仍为 13:10，第 44 集显示其独立时长；低百分比观看未保留续播点符合既有服务端阈值语义，不伪造进度。
- 由选集页返回媒体库，仍选“国产剧”，《雍正王朝》海报 bounds 仍为 `[386,1723][694,2274]`，与进入前一致。页面标题、简介三行、省略、季 chip、分集行和末项在本次手机竖屏截图可见，没有发现操作区溢出；人工长标题/错误态的完整矩阵尚未覆盖。
- 按用户授权选择“动画电影”中的《超级马力欧兄弟大电影》，沿原电影入口直接进入播放器，真实显示画面，并从服务器原存 52:50 续播，推进到 54:46 / 01:32:24。通过 App 返回正常退出，回到原“动画电影”库和海报位置。测试账号的对应单集与电影进度已按正常播放流程更新。
- 手机当前已退出全部播放器，停在“动画电影”媒体库。系统媒体音量原值 0/150；尝试设置 30 的命令虽返回成功，实际读回仍是 0，没有据此宣称声音正常。已向用户询问用实体音量键调高后的真实听音结果，尚未收到答复；收尾设置回 0，读回确认 0。`stay_on_while_plugged_in` 原值及当前值均为 15，未修改。

### macOS 与服务端：当前缺口

- 已从本任务 `build/macos/Build/Products/Debug/Media Player.app` 启动并通过进程绝对路径确认运行对象，bundle ID `dev.mediaplayer.mediaPlayer`，PID 89292，窗口 800×632。记录时主可执行文件 SHA-256 为 `e7bcc56a4939c5d03d6cd77db072887f4a57fac4e276191e241daec9c7445fa7`；之后冻结重建如改变指纹，以最终工具结果为准。
- 最初辅助功能访问实际被系统拒绝（-1728），经用户操作后，本次 `AXIsProcessTrusted()` 为 true，窗口读取和正常鼠标点击可用，权限不再作为待确认缺口。屏幕录制预检为 true，无需另要屏幕录制权限。Flutter 内容未暴露完整 AX 树，因此使用前台 PID/窗口核对后的区域截图和正常系统输入；不把别的窗口当成本应用证据。
- 本任务 macOS 应用仍在用户手填的登录页，显示“无法连接服务器，请检查地址与网络 / lan: 无法连接”。对表单端点的无凭据 `/System/Info/Public` 只读请求超时；辅助功能恢复后再次点击登录仍是同一错误，未继续盲目重试。已请用户核对测试服地址及 Mac 网络、在应用内完成登录并回复进入媒体库。未索取聊天中的凭据，也未尝试读取或复制 Android 私有会话。桌面端季集、真实播放、声音和返回仍未验收。
- Android 播放页实际显示“直连播放”，这是现有 `/Sessions` probe 根据 `PlayState.PlayMethod` 得出的界面判定。既有文档明确该字段可能来自客户端上报，因此本次仍缺独立的 `TranscodingInfo`/视频未转码证据，以及退出后匹配会话停止的服务端观察，不能仅凭画面成功或该标签宣称此门通过。已请用户提供本次测试的脱敏服务端观察，或可用的只读测试会话方式；不要求发送 token/密码。
- Windows 本轮未构建、未实测；旧三平台发布门禁和历史签核的适用范围不变。当前缺口只暂停依赖的原生验收，不降低冻结标准或将状态提前记为待体验/已验收。

### 证据位置、检查与下一步

截图位于 `.pi/kanpilot/codex/b6f88006-64dc-4a84-a981-91d6455e9509/native-acceptance/`，此目录为本任务缓存，不包含导出的应用私有凭据。关键证据：

| 文件 | 本次观察 |
| --- | --- |
| `android-series-entry.png`、`android-series-top.png`、`android-series-last-episode.png` | 剧集入口、页面布局和真实第 44 集末项 |
| `android-episode43-playing.png`、`android-episode43-paused.png` | 第 43 集真实画面与暂停 |
| `android-episode43-progress-refreshed.png` | 原季/原位置，服务端刷新为 12:30；SHA-256 `2fc673aecf09f73380aa57e94aab014bf7c907328af75a592983706e4911a377` |
| `android-episode43-resumed.png`、`android-system-back-preserved.png` | 12:30 续播，系统返回后仍选原季并更新为 13:10 |
| `android-episode44-playing.png` | 不同单集内容、00:06 / 44:56；SHA-256 `c5673da46dc3d56bf5e0ed57bb8a3934cf4fb0766c300a442bac9a4a538c48fe` |
| `android-library-return-preserved.png` | 媒体库选中项和原海报位置保留 |
| `android-movie-playing.png`、`android-movie-return-library.png` | 电影原入口、独立续播和返回 |
| `macos-login-error-redacted.png`、`macos-login-retry-redacted.png` | 目标应用登录连接错误；地址及账号字段已遮蔽，原始截图不保留 |

本执行先前五项冻结命令均真实退出 0（分层无违规、分析无问题、364 项测试通过及两端 Debug 构建成功），原始结果见前节，不将这些历史退出码冒充本轮封版重跑。当前体验入口仍为“媒体库 → 剧集 → 选季/选集 → 单集播放器 → 返回原季”，详见 `docs/README.md`。

本节及文档索引为最后文件编辑；随后主 agent 将在当前工作树逐条、独立执行全部五条冻结命令，最终原始终端退出码和 CLI JSON 为本轮封版结果，检查结束后不再编辑文件。若用户补充新的原生观察或登录条件导致需要记录/修复，则在下一次最后编辑后重新完整验证。

解除条件：macOS 应用进入授权测试媒体库后，主 agent 继续桌面原生选季/选集/播放/返回与窗口视觉核验；用户确认手机实际声音，提供服务端无视频转码和退出会话停止的脱敏证据（可配合重新播放）；完成剩余必要真实路径后再进入“待体验”，只有用户明确确认才记“已验收”。现有成果和本任务工作树保留，等待这些具体条件，不重复询问已确认的隔离设备、账号范围或电影选片授权。

## 重新执行记录（2026-11-07，执行 f9e2e018）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/f9e2e018-a965-48cf-a1b8-cb6b507adc40`；冻结计划哈希：`a94f5f4786ffd50c253ee2e63b6121ee2425ad81b459020cd1257fa39c64ec60`。本节只追加实际执行记录，不修改冻结正文或验收条件。
- 状态：**实现中**。T1–T4 的保留实现经本轮复核及自动验证，无需修复；T5 两端原生验收仍缺下述操作条件和真实证据，不能标记为待体验或已验收。
- 开始及首轮检查后均核对原工作树、分支 `kaneo/csim4lhdf81m1k7wib615fdv`、HEAD `33778190efee71c8b741a65abcb817347a2b90be`、空索引、15 个跟踪文件的未暂存改动，以及本计划、series 源码/测试、`.pi/` 等未跟踪成果。全部保留，未另建或切换 worktree/分支，未提交、推送、合并或发布；工作树保留给调度核心冻结评审，尚不进入合并后清理。
- 实际使用两名 `worker`（gpt-6.1-sol / high）并行核查 T2/T3，分别独占 controller/控制器测试和 page/页面测试，不派生下级任务；两位负责人均未修改文件。主 agent 亲自核对 T1 路由与 fake、T4 分流/播放器保护/续播/上报及真实 appRouter 联合用例，负责共享文件和本记录。模块测试串行使用 Flutter，避免 SDK 锁争用；没有新建数据库或真实媒体服务，自动测试仅用 fake、内存存储及既有本地测试服务。
- T2 实测：`~/devsdk/flutter/bin/flutter test --no-pub test/features/series/series_controller_test.dart`，退出 0，27 项通过。T3 实测：`~/devsdk/flutter/bin/flutter test --no-pub test/app/series_page_test.dart`，退出 0，20 项通过；其两份文件的只读 Dart format 检查退出 0，0 changed。
- 主 agent 实测：`~/devsdk/flutter/bin/flutter test --no-pub test/app/library_page_test.dart test/app/player_page_test.dart test/features/player/player_controller_test.dart`，退出 0，50 项通过。联合用例覆盖第二季第 75/76 集、点击 Series 时不协商播放、双击互斥、单集详情决定 125 秒续播、协商/engine/Started/Progress/Stopped 的同一 episodeId、等待 Stopped 后刷新、原季与两级滚动保留及下一次独立会话；保留电影、401、分页和退出幂等断言，没有删/跳测试、放宽预期或降低门禁。
- 本轮没有新增业务源码或测试改动。104 个 lib/test Dart 文件的 SHA-256 为 `b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`，与保留实现一致；算法为依相对 POSIX 路径排序后，逐文件累加“路径、NUL、文件字节、NUL”。证据对应当前 HEAD 加全部保留未提交成果，历史测试没有代替本轮执行。`git diff --check` 退出 0。

### 本轮自动检查与产物

环境为 macOS 27.0.1 arm64、Flutter 3.47.7 / Dart 3.13.5、Xcode 27.0（27A5237l），沿用已准备的 JDK 17、Android SDK 和本执行 `.pi/kanpilot/codex/f9e2e018-a965-48cf-a1b8-cb6b507adc40/` 工具缓存。没有手动安装 SDK、执行 pub get/upgrade、修改依赖或平台源码。为沿用历史已核验的测试设备签名，仅将本执行原本不存在的 `config/.android/debug.keystore` 链接到既有 `~/.android/debug.keystore`，未改全局密钥或删除其他缓存。

主 agent 在当前任务工作树按原文、以五次独立终端调用实际执行了首轮检查：

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!` |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | 364 项全部通过 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本任务 Debug/Media Player.app |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本任务 app-debug.apk |

- Android 产物：`build/app/outputs/flutter-apk/app-debug.apk`，记录时 219298515 字节，SHA-256 `0719be29fd15ae6474d337aed72e316835cad63dc8250dc2fb4c4cd70d88a750`。
- macOS 产物：`build/macos/Build/Products/Debug/Media Player.app`，bundle ID `dev.mediaplayer.mediaPlayer`；记录时主可执行文件 SHA-256 `5f0f49ad970b978387b1f3f66bf6322714bb64fc3429f4d5e3bb6f39b5f78112`。最终重建后以实际产物为准；这些构建指纹不代表已启动本轮产物或完成真实播放。
- macOS 构建自动运行了 `pod install` 并提示 media_kit 插件尚未支持 SPM；Android 有既有 SDK XML 版本兼容告警，约 95 秒构建成功。两条命令实际均退出 0，没有为消除告警修改配置；不把平台构建描述为完全无网络验证。

### 本轮原生条件核验与剩余工作

- 沿用已有明确授权：Mi 10 是专用测试设备，当前 macOS 账号是专用测试账号，Android 已手动登录授权 Emby 测试账号，剧集样本《雍正王朝》，允许从测试库自行选择电影。不重复申请这些授权，也不读取或迁移应用私有凭据。
- `~/Library/Android/sdk/platform-tools/adb devices -l` 退出 0，确认 Mi 10（`8085d06e`）在线；系统版本查询为 Android 16，当前用户 0。电源状态为 Dozing，发送唤醒键后 UIAutomator 实际只见 `com.android.systemui`、`com.miui.aod` 和系统插件，未见测试应用页面，设备仍需用户解锁。诊断只输出包名和固定界面标记，临时远端 XML 已删除；没有导出账号、地址、密码、token 或私有数据。
- macOS 既有本任务应用进程 89292 仍来自此工作树 Debug/Media Player.app。本轮原生辅助脚本实际因 `AXIsProcessTrusted() == false` 退出 133，随后独立权限查询退出 0，确认辅助功能与 `CGPreflightScreenCaptureAccess()` 均为 false。属于当前执行宿主的系统权限缺口；历史曾获得权限不能代替本次实际状态。没有继续盲目输入、截图或把该辅助脚本退出解释为产品崩溃。本轮无法确认 macOS 是否已解除历史 `lan: 无法连接` 登录错误，需在任务应用内确认进入测试媒体库后继续。
- 上节 Android 真实画面/暂停/拖动/服务端进度刷新/续播/跨集隔离/电影及返回证据仍保留其原范围；本轮没有重新播放、更新真实媒体进度或新装覆盖设备应用，也没有新的原生截图或真实路径通过声明。当前未注入任何 `EMBY` 测试变量，仍无独立服务端会话观察；不能从播放页“直连播放”标签推出服务器无视频转码或退出后匹配播放会话已停止。
- 未完成项：Android 实际声音；macOS 新产物的登录、选季/选集、真实画面与声音、播放控制及返回；手机/桌面长标题和错误态剩余视觉矩阵；与测试播放匹配的服务端无视频转码及退出会话停止证据。多季/特别篇与超过 60 集目前只有模拟证据；Windows 本轮未构建、未实测，历史签核不扩展到本功能。
- 已异步请求用户补齐具体条件，尚未收到答复：解锁 Mi 10 并通过实体音量键确认单集实际声音；为当前执行宿主恢复 macOS 辅助功能和屏幕录制访问，并在本任务应用中登录至授权测试库；配合一次播放提供脱敏服务端会话证据，或提供无需在聊天暴露凭据的只读测试会话入口。条件齐备后主 agent 继续原生验收 1–5，收到对应声音、桌面和服务端证据后解除阻塞。现有成果保留，状态保持实现中。
- 体验入口与实际调用关系已在 `docs/README.md`：媒体库 Series → `/series/:seriesId` → LibraryService 详情/季/分集 → `/player/:episodeId` → Stopped 后返回原季并刷新。选集页只读，单集沿用现有续播、认证端点和上报流程。

本节为本次最后一次人工文件编辑。上述首轮结果已经实测；主 agent 随后将按冻结原文逐条、独立重跑全部五项，最终命令输出、真实退出码和 CLI JSON 为封版结果，验证结束后不再修改源码、测试、文档或记录。若新条件带来必要修复或补记，在新的最后编辑后重新执行全部冻结命令。
## 封版执行记录（2026-11-07，执行 24f0e112）

- 本次任务标识：`csim4lhdf81m1k7wib615fdv/24f0e112-1728-4078-bf2d-a277e413ec5f`。冻结正文、验收目标与历史记录保持原样，本节只追加本轮实际执行与实测证据。
- 计划哈希：本轮开始时计划文件整文件 SHA-256 为 `7e315ed5293a6573e4d52603b2cc9b2c46cbd68547a404332b81160ae6a284e9`；冻结正文（第 1–110 行，含 `verify` 块）SHA-256 为 `a5b450655b4820d263b52dec7c3c51a8af9d4c6377f0827eaefb6b2b2408d562`，本节追加后再次计算仍为该值，确认冻结正文未被改动。历史记录中的 `a94f5f47…` 属当时文件快照，本轮不沿用。
- 状态：**实现中**。五条冻结自动检查全部真实退出 0，两端 Debug 产物生成，Android 真机主路径（选季选集、单集播放、暂停/继续/拖动、服务端位置续播、两种返回、电影原入口）已实测；但声音听感、服务端无视频转码与退出会话停止观察、macOS 原生路径仍缺本轮证据，因此不记为待体验或已验收。
- 工作区：沿用原执行路径，分支 `kaneo/csim4lhdf81m1k7wib615fdv`，HEAD `33778190efee71c8b741a65abcb817347a2b90be`。开始时与结束时均为 15 个跟踪文件的未暂存改动加本计划、`lib/features/series/`、`test/features/series/`、`test/app/series_page_test.dart`、`.pi/` 等未跟踪成果，全部保留；`git worktree list` 中除既有主工作区、本任务工作树与既有 pool 槽位外未新增工作树，未切换分支，未 commit、push、merge 或发布。
- 代码复核与修复：本轮核对 `series_controller.dart` 的请求序号（`_episodeRequest`）、销毁保护、401 触发的会话失效与其它在途请求作废、刷新保留内容，以及 `series_page.dart` 的播放导航互斥（`_openingPlayer`）、返回后会话同一性与路由最新性校验、按季 `PageStorageKey` 滚动保留，未发现需要修复的缺陷，因此未修改任何源码或测试；104 个 lib/test Dart 文件快照仍为 `b44028e201ffd88b06f4871facd4936f31884b0a7ee156d9dea3d4e7ca10a42b`。为取得第二意见共派发三次只读复核子代理，均因宿主模型标识不受支持或子代理连接中断未取得结论，不计为已完成项。
- 文档：`docs/README.md` 增加逐字入口链路“入口与调用关系：媒体库 → `/series/:seriesId` → 季集查询 → `/player/:episodeId` → 返回原季。”，原有页面、控制器与播放器调用关系说明保留。

### 本轮自动检查（本记录编辑前，五次独立终端调用）

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok` |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!`，`Analyzing branch...` 15.8s |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | `+364: All tests passed!`，无失败，日志无跳过计数 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本工作树 `build/macos/Build/Products/Debug/Media Player.app` |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本工作树 `build/app/outputs/flutter-apk/app-debug.apk` |

- 环境：macOS 27.0.1 arm64，Flutter 3.47.7 stable / Dart 3.13.5（`bin/cache/flutter.version.json`），Xcode 27.0，既有 JDK 17 与 Android 工具链；未安装或升级 SDK，未执行 `pub get/upgrade`，未修改依赖、平台工程或质量门。macOS 构建自身运行 `pod install` 并提示 media_kit 插件尚未采用 SPM，Android 有既有 SDK XML 版本告警，两条命令实际均退出 0，未为消除告警改配置。
- 本节为本轮最后一次人工文件编辑；随后按冻结原文逐条、独立重跑全部五条，最终原始终端输出与 CLI JSON 为封版退出码来源，之后不再修改源码、测试、文档或记录。

### 产物与指纹（本轮首次构建后实测）

- Android：`build/app/outputs/flutter-apk/app-debug.apk`，219298515 字节，SHA-256 `0719be29fd15ae6474d337aed72e316835cad63dc8250dc2fb4c4cd70d88a750`。
- macOS：`build/macos/Build/Products/Debug/Media Player.app`，bundle ID `dev.mediaplayer.mediaPlayer`，主可执行文件 `Contents/MacOS/Media Player` SHA-256 `4577105be082de30011e440a5c0fa4fd60749f8e5d7ac0d8eedf252942735232`。
- 封版重建会更新产物指纹，以最终产物实际文件为准。产物存在、构建退出 0 或播放页“直连播放”标签都不作为真实播放、无视频转码或服务端会话已停止的证据。

### Android 真机原生实测（Mi 10 / Android 16，序列号 `8085d06e`，用户 0，1080×2340 竖屏）

- 启动对象核对：设备 `pm path` 指向的 `base.apk` SHA-256 为 `0719be29fd15ae6474d337aed72e316835cad63dc8250dc2fb4c4cd70d88a750`，与本轮构建 APK 完全一致；`versionName=0.2.3`、`versionCode=5`、Debug，包名 `dev.mediaplayer.media_player`。未卸载、未清数据、未读取应用私有 token/密码，也未改动账号配置；沿用用户已确认的专用测试设备与已手动登录的授权 Emby 测试账号。
- T5-1：设备解锁且应用前台。从“国产剧”媒体库点击《雍正王朝》海报进入选集页，读到剧名、三行简介、已选中的单季 chip“雍正王朝”和第 1 集起的单列分集；连续上滑后第 44 集“雍正皇帝去世”可见可及，为末集。该样本服务端只返回一个季，因此多季切换、特别篇编号 0 与超过 60 集的真实通过仍未覆盖，只保留既有模拟测试结论。
- T5-2：点击第 43 集“雍正亲自审问弘时”，OCR 读到标题、`直连播放`、`已从 20:39 继续播放` 与 `21:57 / 44:37`；相邻两次截图像素差异 25.0%（画面在变化）。暂停后时间码由 23:42 停在 23:43，4.5 秒后仍为 23:43；再次点击后 5 秒推进到 23:48。点击进度条约 75% 处后跳到 35:08，6 秒后为 35:15，两帧像素差异 21.4%。`dumpsys audio` 显示存在 `state:started` 的 `OpenSL ES AudioPlayer`（`usage=USAGE_MEDIA`，44100Hz），`settings get system volume_music_speaker` 为 79，说明系统侧确有音频输出活动；但本轮无人耳听音确认，声音不算已验证。
- T5-3：应用内返回后回到原季、原滚动区域，第 43 集刷新为“时长 44:37 · 已观看 35:26”，退出后 `dumpsys audio` 中 `state:started` 计数为 0。重开第 43 集读到 `已从 35:26 继续播放` 与 `35:27 / 44:37`，即按服务端保存位置续播。再选第 44 集，标题为“雍正皇帝去世”，从 `00:01 / 44:56` 起播，未沿用第 43 集位置；返回后第 43 集为 35:28，跨集未串进度。服务端自身保存的进度值未直接观测，以上是客户端重新读取详情后的显示结果。
- T5-4：选集页返回媒体库后仍选中“国产剧”，《雍正王朝》海报位置与进入前逐像素一致（整屏像素差异比例 0.001），库与滚动位置保留。切到“动画电影”后点击《超级马力欧兄弟大电影》，沿电影原入口直接进入播放器，读到 `已从 54:50 继续播放` 与 `54:50 / 01:32:24`，返回后仍为“动画电影”库。Android 系统返回（`input keyevent 4`）在播放器内走通退出到原季，应用内返回按钮同样走通；两条退出路径均在退出后无残留 `state:started` 音频会话。本机系统媒体音量保持原值 79，未修改设备设置。
- 证据目录：`.pi/kanpilot/codex/24f0e112-1728-4078-bf2d-a277e413ec5f/native-acceptance/`，含 17 张本任务截图、`ocr-log.txt`（逐图 OCR 文本）与本记录引用的实测数值；截图与 OCR 只涉及已授权测试应用界面，不含服务器地址、账号、密码或 token。

### 未验证缺口与解除条件

- 声音：仅取得系统音频会话与音量设置证据，缺人耳听音确认。
- 服务端：缺独立的无视频转码（`TranscodingInfo`/视频直连）与退出后匹配播放会话已停止的服务端观察；客户端“直连播放”标签按契约不计为该项证据。解除需用户提供脱敏服务端观察或可用的只读测试会话入口，不需在聊天中发送 token/密码。
- macOS：本任务应用进程（PID 89292，来自本工作树 Debug 产物）仍在运行，但本轮 `AXIsProcessTrusted()` 与 `CGPreflightScreenCaptureAccess()` 均为 false，`osascript` 返回 -1728，`screencapture` 报 `could not create image from rect`，且历史状态下应用仍停在登录连接失败页；桌面端选季、选集、真实播放、返回与窗口视觉本轮未验证。解除需为当前执行宿主开放辅助功能与屏幕录制，并在本任务应用中登录到授权测试媒体库。
- 真实样本：多季切换、特别篇编号 0、超过 60 集只有模拟测试证据；手机长标题/错误态的完整视觉矩阵未覆盖；Windows 本轮未构建、未实测，历史签核不扩展到本功能。
- 无未决产品选择。上述缺口只暂停对应项，不降低冻结标准：状态保持**实现中**，现有成果与本工作树继续保留给调度核心冻结评审；用户明确确认后才可记“已验收”。

## 重新执行记录（2026-11-08，执行 34a8fc16）

- 本次任务标识：`csim4lhdf81m1k7wib615fdv/34a8fc16-3c1d-41d8-9b27-d447529257b2`。冻结正文、验收目标与历史记录保持原样，本节只追加本轮实际执行与实测证据。
- 计划哈希：本轮编辑前整文件 SHA-256 为 `cb897680349bbe68c164dda09c615ed9b0a5f536e2221b74ef74140cd97081d3`；冻结正文（第 1–110 行，含 `verify` 块）SHA-256 为 `a5b450655b4820d263b52dec7c3c51a8af9d4c6377f0827eaefb6b2b2408d562`，本节追加后再次计算仍为该值，确认冻结正文未被改动。历史记录中的 `a94f5f47…` 属首次快照，本轮不沿用。
- 状态：**实现中**。五条冻结自动检查本轮全部真实退出 0，两端 Debug 产物生成；但手机听音、服务端无视频转码与退出后会话停止、macOS 原生路径、多季切换与特别篇 0 及超 60 集真实样本、Windows 仍未取得证据，因此不记为待体验或已验收。
- 工作区：沿用原执行路径，分支 `kaneo/csim4lhdf81m1k7wib615fdv`，HEAD `33778190efee71c8b741a65abcb817347a2b90be`。本轮未创建或切换工作树与分支，未 commit、push、merge、tag 或发布；开始与结束均为 15 个跟踪文件的未暂存改动加 `lib/features/series/`、`test/features/series/`、`test/app/series_page_test.dart`、`.pi/` 与本计划等未跟踪成果，全部保留，未丢弃或回退任何改动。
- 代码复核：只读复核确认 `AppRoutes.series`/`seriesFor`（`lib/core/router/app_routes.dart`）、路由 `/series/:seriesId`（`lib/app/router.dart`）、媒体库按 `item.type` 分流（`lib/features/library/library_page.dart`）、`SeriesController`/`SeriesPage`、`PlayerController` 对 Series 的早返回拦截（带 `selectionSeriesId`、不请求 PlaybackInfo）与 `PlayerPage`「选择分集」入口均成立，并由 `test/features/series/series_controller_test.dart`、`test/app/series_page_test.dart`、`test/features/player/player_controller_test.dart`、`test/app/library_page_test.dart`、`test/app/player_page_test.dart` 中的具名用例覆盖。本轮未发现属于本功能链路的真实缺陷，因此未修改任何源码或测试。
- 文档：`docs/README.md` 第 24 行仍保留逐字入口链路“入口与调用关系：媒体库 → `/series/:seriesId` → 季集查询 → `/player/:episodeId` → 返回原季。”。
- 原生与设备：按本轮确认，未安装、未启动、未操作任何真机或桌面应用，未触碰 Mi 10，未尝试 macOS 原生操作。

### 本轮自动检查（本记录编辑前，五次独立终端调用）

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok`，无违规行 |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!`，`Analyzing branch...` 7.8s |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | `+364: All tests passed!`，无失败，日志无跳过计数 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本工作树 `build/macos/Build/Products/Debug/Media Player.app` |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本工作树 `build/app/outputs/flutter-apk/app-debug.apk` |

- 环境：macOS 27.0.1 arm64，Flutter 3.47.7 stable / Dart 3.13.5，沿用既有 Xcode、JDK 17 与 Android 工具链；未安装或升级 SDK，未执行 `pub get/upgrade`，未修改依赖、平台工程、签名或质量门。macOS 构建提示 media_kit 插件尚未采用 SPM，实际退出 0，未为消除告警改配置。
- 本节为本轮最后一次人工文件编辑；随后按冻结原文逐条、独立重跑全部五条，最终退出码为封版来源，之后不再修改源码、测试、文档或记录。

### 产物与指纹（本轮实测）

- Android：`build/app/outputs/flutter-apk/app-debug.apk`，219298515 字节，SHA-256 `0719be29fd15ae6474d337aed72e316835cad63dc8250dc2fb4c4cd70d88a750`。
- macOS：`build/macos/Build/Products/Debug/Media Player.app`，主可执行文件 `Contents/MacOS/Media Player` SHA-256 `4577105be082de30011e440a5c0fa4fd60749f8e5d7ac0d8eedf252942735232`。
- 两处产物均位于 `.gitignore` 的 `**/build/` 忽略范围内，不改变 `git status --porcelain`。产物存在、构建退出 0 或测试通过都不作为真实播放、无视频转码或服务端会话已停止的证据。

### 未验证缺口（本轮未推进，未降级记录）

- 声音：仍缺人耳听音确认。
- 服务端：仍缺独立的无视频转码（`TranscodingInfo`/视频直连）与退出后匹配播放会话已停止的服务端观察。
- macOS：原生选季、选集、播放、返回与窗口视觉本轮未验证。
- 真实样本：多季切换、特别篇编号 0、超过 60 集的真实服务端通过仍只有模拟测试证据。
- Windows：未构建、未实测，历史签核不扩展到本功能。

## Android 真实播放补证与封版记录（2026-11-08，执行 8d4fb649）

- 本次执行标识：`csim4lhdf81m1k7wib615fdv/8d4fb649-c83e-4f40-a203-24920b1db7d9`。冻结正文、验收目标与历史记录保持原样，本节只追加本轮实际执行与实测证据。
- 计划哈希：本节追加前整文件 SHA-256 为 `c863282f288a27e1d64d7327a8fb22be33c5ee93fe19c3e512eb52e0cdd367d9`；冻结正文（第 1–110 行，含 `verify` 块）SHA-256 在本次执行前后均为 `a5b450655b4820d263b52dec7c3c51a8af9d4c6377f0827eaefb6b2b2408d562`，确认冻结正文与既有历史记录未被改写或删除。
- 状态：**待体验**。五条冻结自动检查全部真实退出 0；Android 主路径（选季选集、单集播放、暂停/继续/拖动、服务端位置续播、两种返回、跨集独立、电影原入口）本轮实测；声音经用户当场听音确认；服务端在同一活动中关联到唯一活动播放且无 `TranscodingInfo`，退出后该活动播放清零。按冻结标准不记为“已验收”。
- 工作区：沿用原执行路径，分支 `kaneo/csim4lhdf81m1k7wib615fdv`，HEAD `d2be80ad3659635bc39ddac7717a3821b857b09b`。开始时工作区仅 `?? .pi/`；两份既有 `.pi/goal/` 证据文件 SHA-256 复核仍为 `2f11fb2f7d69b27a57abcecb67d290a83266cfa373fd84aedb1f8e6fc37bbab3` 与 `71eedf3542e0cc69ccbf6b589e6e76452afc30c211064c54cf8cb71b1dd1bd6c`。未创建或切换工作树/分支，未 commit、push、merge、tag 或发布。
- 环境修复（不涉及源码）：本轮开始时 `build/` 不存在，且 `.flutter-plugins-dependencies` 指向已删除的旧执行 pub 缓存、`.dart_tool/` 缺失，导致 `flutter build apk` 先报 `Plugin directory does not exist`，随后 `Target build_hooks failed`／`compileFlutterBuildDebug` 非零退出。只做两处可再生成文件的环境修复：在 `.pi/kanpilot/codex/f9e2e018-…/` 下建立指向既有 `~/.pub-cache` 的链接（该路径与被修复文件均在 `.gitignore` 内），并从同机既有主工作树复制 `.dart_tool/package_config.json`；复制前逐包核对 118 个依赖与本分支 `pubspec.lock` 的版本及缓存目录完全一致（0 处不符）。未执行 `pub get/upgrade`，未安装或升级 SDK/JDK，未修改 `pubspec`、锁文件、平台工程或签名配置；该过程前后 `git status --porcelain` 均为 `?? .pi/`。
- 代码复核：独立只读复核（`code-reviewer`，未修改任何文件）核对 `series_controller.dart` 的 `_byIndex` 排序与稳定补齐、`_episodeRequest` 请求序号与 401 全量作废、`player_page.dart` 先 `stop()` 再 `pop`、每集新建 engine/reporter、媒体库按 `item.type` 分流，结论为“未发现可明确复现的实质缺陷”（0 个）。另列两项非阻断项：`_leave` 在“网络通但服务器不响应”时无超时等待 Stopped；电影返回后媒体库重建缺少自动断言覆盖。两项均属既有行为或测试覆盖建议，本轮未改源码或测试。

### 本轮自动检查（本记录编辑前，五次独立终端调用）

| 冻结命令原文 | 实际退出码 | 结果 |
| --- | --- | --- |
| `./tool/check_layering.sh` | 0 | `layering ok`，无违规行 |
| `~/devsdk/flutter/bin/flutter analyze --no-pub` | 0 | `No issues found!`（`Analyzing branch...` 5.2s） |
| `~/devsdk/flutter/bin/flutter test --no-pub` | 0 | `+364: All tests passed!`，无失败，日志无跳过计数 |
| `LANG=en_US.UTF-8 ~/devsdk/flutter/bin/flutter build macos --debug --no-pub` | 0 | 生成本工作树 `build/macos/Build/Products/Debug/Media Player.app` |
| `~/devsdk/flutter/bin/flutter build apk --debug --no-pub` | 0 | 生成本工作树 `build/app/outputs/flutter-apk/app-debug.apk` |

- 环境：macOS 27.0.1 arm64，Flutter 3.47.7 stable / Dart 3.13.5，Xcode 27.0（27A5237l），沿用既有 JDK 与 Android 工具链。未安装或升级 SDK，未执行 `pub get/upgrade`，未修改依赖、平台工程、签名或质量门。macOS 构建仍有 media_kit 未采用 SPM 的 Swift 告警，Android 仍有既有 SDK XML 告警，两条命令实际均退出 0，未为消除告警改配置。
- 本节为本轮最后一次人工文件编辑；随后按冻结原文逐条、独立重跑五条，最终退出码为封版来源，之后不再修改源码、测试、文档或记录。

### 产物与指纹（本轮首次构建后实测）

- Android：`build/app/outputs/flutter-apk/app-debug.apk`，219142728 字节，SHA-256 `2590904b54d345c9fc469b5c54e0c6fadf2c5c7f4b15caf58f412afc32e9980f`；设备 `pm path` 指向的 `base.apk` 实测 SHA-256 与之逐字一致。
- macOS：`build/macos/Build/Products/Debug/Media Player.app`，bundle ID `dev.mediaplayer.mediaPlayer`，主可执行文件 `Contents/MacOS/Media Player` SHA-256 `1ff620645cc613993d8a001f4e1944d6c7f6643fcbcc141914d16a4c514d782d`；按用户本轮决定未启动该应用。
- 两处产物均在 `.gitignore` 的 `**/build/` 内，不改变 `git status --porcelain`。产物存在、构建退出 0、测试通过或界面标签均不作为真实播放、无视频转码或会话已停止的证据。

### Android 真机原生实测（Mi 10 / Android 16 / SDK 36，序列号 `8085d06e`，系统用户 0，1080×2340 竖屏）

- 启动对象：包名 `dev.mediaplayer.media_player`，`versionName=0.2.3`、`versionCode=5`、Debug；前台 `topResumedActivity=dev.mediaplayer.media_player/.MainActivity`，进程 `u0_a347 10284`。实测 APK 与设备 `base.apk` SHA-256 同为 `2590904b…e9980f`；未卸载、未清数据、未读取应用私有 token/密码，沿用用户已确认的专用测试设备与已登录的授权 Emby 测试账号。
- T5-1（选季选集）：媒体库“国产剧”→“雍正王朝”，选集页读到剧名、三行简介、季 chip 与单列分集；该样本服务端只返回**一个季**（chip“雍正王朝”），滚动后第 44 集“雍正皇帝去世”末项可见可及（`[44,2076][1036,2274]`）。因此**多季切换、特别篇编号 0、超过 60 集本轮未取得真实通过**，仍只有既有模拟测试证据。
- T5-2（画面/暂停/继续/拖动）：第 43 集“雍正亲自审问弘时”真实画面，读到 `直连播放`、`已从 35:28 继续播放`；21:09:26 时间码 `37:49`，21:09:33 为 `37:57`（7 秒推进 8 秒），相邻两帧像素差异 24.16%。暂停后 21:09:56 与 21:10:02 均为 `38:17`，暂停两帧像素差异 0.21%。拖动进度条由 86%（`38:17`）到 51%（`22:51`）；继续后 21:10:55 为 `22:53`、21:11:02 为 `23:00`（像素差异 23.23%）。画面另见烧录字幕“为了祖宗江山社稷”“我还能走到哪儿去”“不是奴才斗胆敢说祖宗不是”。
- T5-3（续播与跨集）：应用内返回后回到原季、原滚动区域，第 43 集刷新为“时长 44:37 · 已观看 36:13”；重开该集读到 `已从 36:13 继续播放`、时间码 `36:16 / 44:37`。随后用 Android 系统返回（`input keyevent 4`）退出，仍回原季与原列表位置，状态刷新为“已观看 36:17”。另选第 44 集，标题“雍正皇帝去世”，从 `00:02 / 44:56` 起播并推进到 `00:07`，未沿用第 43 集的 36 分钟位置（两帧像素差异 25.25%）。
- T5-4（返回媒体库与电影）：选集页返回后仍选中“国产剧”，《雍正王朝》海报 bounds 与进入前一致（`[386,2217][694,2340]`）。切“动画电影”点击《超级马力欧兄弟大电影》沿电影原入口直接进入播放器，读到 `已从 54:50 继续播放`，`54:50`→`54:54`（21:26:07→21:26:13，像素差异 19.39%），退出前 21:29:17 为 `57:58 / 01:32:24`；应用内返回后回到原“动画电影”库与海报位置。
- 退出停止（两条路径各一次）：应用内返回与系统返回均在退出前后读 `dumpsys audio` 的 `state:started` 计数，播放中 1、退出后 0；电影退出同样 1→0。该读数仅为辅助证据，不替代听音或服务端结论。

### 声音（用户当场听音，用户参与项）

- 样本 A：Mi 10 上正在播放《雍正王朝》第 43 集“雍正亲自审问弘时”（播放中时间码 `37:49`–`38:17` 区间，应用内音量 100%，系统媒体音量 79/150），用户当日在约 21:24 前当场回复**听到正常声音**。
- 样本 B：同机正在播放电影《超级马力欧兄弟大电影》（自 `54:50` 续播，约 21:26–21:29 区间），用户当场回复**听到正常声音**。
- 辅助：`dumpsys audio` 存在 `OpenSL ES AudioPlayer ... usage=USAGE_MEDIA state:started`（44100Hz）与音量读数，仅作旁证，未替代听音结论。

### 服务端（只读会话观察，用户参与项）

- 同一活动内以 `DeviceId + NowPlayingItem.Id` 关联：只读 `GET /Sessions` 返回活动播放唯一 1 条，`NowPlayingItem.Id=1646`、`Type=Episode`、`Name=雍正亲自审问弘时`；`PlayState.PlayMethod=DirectPlay` 仅作辅证；**无 `TranscodingInfo` 字段**（`hasTranscodingInfo:false`，`transcodingInfoKeys:null`），据此按契约记为视频未转码。同一条目 `PositionTicks` 两次读取由 `21813196065` 增至 `21833199828`（约 36:21→36:23），证明该活动确在播放。
- 退出后两次查询（21:37:15、21:37:21）`active_count=0`，匹配活动播放已清零；`total_sessions` 仍为 8，登录设备会话继续存在，按契约不影响判定。
- 观察仅使用用户提供的只读 API Key 文件（进程内读取，未打印、未写入仓库）。服务端基地址、Key 与会话标识未写入本记录或证据文件，记录中只保留脱敏字段与 SHA-256 截断标识；证据目录已用 Key 明文与地址做全文扫描，0 命中。

### 证据位置与指纹

- 目录：`.pi/kanpilot/codex/8d4fb649-c83e-4f40-a203-24920b1db7d9/native-acceptance/`（本任务缓存），含 25 张本轮截图、`ocr-log.txt`（逐图 OCR 文本）、`ui-*.xml`（UIAutomator 语义节点）、`server-observation.jsonl`、`server-observation-after-exit.json`（脱敏服务端字段）与 `device-info.txt`。
- 关键指纹：`09-ep43-paused-p1.png` `42d482de7c4c29ab55ba654934ed3a262197653714e4fd28f3ca2aac48f5513e`；`11-ep43-after-seek.png` `e36f73debfcbb9ba1aebde8ec1d1528cfd7e2045d19a2d7f01d9769b79c209bd`；`15-series-after-inapp-back.png` `e9df19fa76dd3d5414c1bc166d429564b7aa1bef4fc6bc3dabe87e58f9525ecb`；`17-series-after-system-back.png` `e6d69c5fcf0f11bb456ec37eb48547fe276af1429de115e28641a9c8687a907d`；`18-ep44-playing.png` `ec7ff993ad07bf4759f47ad6617f805f3117a733e5990e3265d4de2459ace98e`；`20-library-return.png` `21aec92e3db5d394afe5c5beb3efaccaec01a80378ad124daa95bec07e5384ac`；`21-movie-playing-t1.png` `43a00463a5b6cf43f8e78fa6d31db8d81b9647870a1860b6120416000985e4f8`；`server-observation.jsonl` `0b5f3cd3264dfe3d55f00aa21723fec78f2dcbb90e8e735234652553efc63f4f`；`server-observation-after-exit.json` `5fdb6e731d108b56297496ffa60097a59ee519862a5cd7f786bfa323783b8ce3`；`ocr-log.txt` `2d0b71dd7fb6c29ea72ead8d07c69458c067698c405b914bc407dc7cc2241c59`。

### 结果分类（历史／模拟／本轮实测／未运行项）

- **本轮实测（Mi 10 / Android 16）**：五条冻结命令退出 0；选季选集与末集可达（单季 44 集）；单集画面、暂停、继续、拖动；服务端位置续播；应用内返回与系统返回两条退出路径；跨集独立；电影原入口播放与返回；两次当场听音确认；服务端无 `TranscodingInfo` 与退出后活动播放清零。
- **历史结果（不冒充本轮）**：前几节记录的 364 项测试、两端构建与 2026-11-07 的 Android、macOS 实测证据保留原适用范围；本轮为重新独立执行，未沿用其退出码或结论。
- **模拟结果**：多季切换、特别篇编号 0、超过 60 集仍只有 `test/features/series/series_controller_test.dart` 等 fake 用例证据，不作为真实服务端通过。
- **未运行项（本轮未验证）**：macOS 原生选季/选集/播放/返回与桌面窗口视觉（含长标题、错误态矩阵）；多季/特别篇 0/超 60 集的真实样本；Windows 构建与实测。以上均不写入通过结论。
- 文档：`docs/README.md` 更新入口说明的验证状态与阶段描述，逐字保留“入口与调用关系：媒体库 → `/series/:seriesId` → 季集查询 → `/player/:episodeId` → 返回原季。”，未写入未验证的通过声明。

### 封版补记：最终构建产物与主路径复核（执行 8d4fb649）

- 产物变化：本轮第一次 `flutter build apk --debug --no-pub` 产出 `2590904b…e9980f`（219142728 字节），而记录前最后一轮五条命令重建后变为 `a724cf61dcf497dbb26c87cff0b4cdaa590fb3e38993fc719a3007c84a47eb52`（219249363 字节），即全新编译与后续增量编译的 Debug APK 二进制不同。按冻结验收第 6 项，实测产物必须等于最后一次构建产物，因此在最终产物上重新安装并复核主路径。
- 可复现性探针：随后连续两次执行 `~/devsdk/flutter/bin/flutter build apk --debug --no-pub`，退出码均为 0，产物 SHA-256 与字节数稳定为 `a724cf61…47eb52` / 219249363，说明增量构建自第二次起可复现。
- 安装核对：`adb install -r -t` 退出 0（`Success`）；设备 `pm path` 指向的 `base.apk` SHA-256 为 `a724cf61…47eb52`，与本轮最终产物逐字一致；`versionName=0.2.3`、`versionCode=5`；`am force-stop` 后 `am start -W` 冷启动 `Status: ok`，前台 `topResumedActivity=dev.mediaplayer.media_player/.MainActivity`，进程 `u0_a347 5475`。未卸载、未清数据、未读取应用私有 token。
- 最终产物上的主路径复核（21:45–21:48）：媒体库切“国产剧”→《雍正王朝》选集页仍为单季 44 集、第 44 集末项可达；第 43 集读到 `已从 36:30 继续播放`，21:45:39 `36:32` → 21:45:45 `36:38`（像素差异 3.97%）；暂停后 21:45:48 与 21:45:54 均为 `36:40`（两帧文件 SHA-256 相同，像素差异 0.0000）；拖动至 `22:24`，继续后 `22:28`。应用内返回后回原季原位置、第 43 集刷新为“已观看 22:29”，`state:started` 1→0；重开读到 `已从 22:29 继续播放`、`22:33`，Android 系统返回后仍回原季、刷新为“已观看 22:35”，`state:started` 1→0；第 44 集从 `00:05 / 44:56` 独立起播；返回媒体库仍选“国产剧”且《雍正王朝》位置一致；电影《超级马力欧兄弟大电影》原入口读到 `已从 57:59 继续播放`、`58:03 / 01:32:24`，返回后回到原“动画电影”库。
- 与最终产物对应的服务端观察（21:48）：活动播放仍唯一 1 条，`DeviceId` SHA-256 截断仍为 `beb6faf632f6`、`NowPlayingItem.Id=1646`、**无 `TranscodingInfo`**（`hasTranscodingInfo:false`），`PositionTicks` 由 `13610817805` 增至 `13630821469`；退出后 `active_count=0`、`total_sessions=8`。
- macOS 产物：Debug 主可执行文件在多次构建间指纹不同（`1ff62064…4d782d`、`99e0ff4c…fbe12f`），Debug 构建不保证二进制可复现；按用户决定未启动该应用，最后一次构建的实测值在交付答复中给出。
- 证据新增：`26`–`39` 号截图（最终产物复核，共 39 张）；更新后的 `server-observation.jsonl` SHA-256 `323350945fbe0ecb95b0d5d8c4fca4982ac4c3bab3fffc56da897fa3241250c1`、`server-observation-after-exit.json` `089117e9321618e1308643ac0ecb90fb9a43840de70442fa9f3bf09f7bf7404d`、`ocr-log.txt` `5766072be70d67abcfd6dfb7e6190acf8c02a3a1bbb15e6ee09164cb5abc13ff`；前文较早给出的同名文件指纹对应其当时状态，以本节为准。
- 本节为最终一次人工文件编辑；随后按冻结原文逐条独立重跑五条命令，并要求最终 APK 仍为 `a724cf61…47eb52` 以保持“实测产物 = 最后一次构建产物”，之后不再修改任何源码、测试、文档或记录。
