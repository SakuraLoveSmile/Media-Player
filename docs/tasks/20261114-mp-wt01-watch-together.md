# MP-WT01：一起看功能复刻

状态：待体验。用户明确要求接入“一起看”，在MP-TT01已交付分支上继续，保留离线/画质及全部已有用户改动。复用工作树 `/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer/20261114-feat-mp-tt01-theater-features`，分支 `codex/feat/20261114-mp-tt01-theater-features`，HEAD2f765b7。不修改原main工作目录，不提交/推送/合并/部署生产。

本次可观察目标：每人登录自己的同一Emby服务器账号，连接自建同步服务，创建/加入房间，选相同版本，统一开始/暂停/拖动/换片；断线/后台/退出播放器和房主管理均有明确行为。视频仍各自直连Emby，不使用作者专属服务。聊天/语音不是参考功能，未纳入。

## 关键决定与唯一契约

[watch-together-v1.md](../contracts/watch-together-v1.md)为前后端唯一规格，包含认证、限额、数据/消息、等待、时间/版本及客户端安全规则。独立Dart标准库房间服务，无数据库/新框架，部署文档与容器入口随代码交付；实际公网部署尚未授权，先本机隔离Emby夹具验证。

UI继承当前设置/离线页AppPage、AppSection；房间页按配置→创建/加入(未在房)或房间码/影片/放映/成员/离开(在房)顺序。沿现有颜色/字号/间距token和ListTile/Wrap；只添加必要入口，不改旧页面布局风格。

## 分工与步骤

T1 主agent：当前状态核对、协议冻结、配置provider与服务图/路由/详情/季页/首页接入、房间页面与选片、原生联合验收与最终组合态门禁，维护本记录。旧MP-TT01记录保留历史，不重写其已验证成果。
T2 server worker(Sol/high)：独占services/watch_together/**及test/data/watch_together/server_test.dart，实现协议服务、认证适配、可注入clock/auth夹具、部署说明与真实loopback HTTP/WS测试，不写Flutter客户端。
T3 sync worker(Sol/high)：独占lib/data/watch_together/**、lib/features/player/player_controller.dart与watch_playback_coordinator.dart、test/data/watch_together/client_test.dart、test/features/player/watch_*，实现客户端/恢复/状态模型+播放器命令与协调器；不写app providers/routes/player_page或房间UI。冻结Dart接口由主agent协调。
只读analyst先核对参考行为，T2/T3按冻结协议并行，无下级派生。主agent做实际集成，reviewer只读审查实际安全/并发/回声与关闭缺口，不用自报代验收。

验收：两独立客户端加入同房，权限/同版本/容量/踢出与解散；统一ready后播放，暂停、拖动、并发旧revision拒绝、换片全员验权；网络断线/重连、后台away与退出不影响别人、时钟偏差对齐；无凭据落盘/日志/URL、伪造用户与不同服务器拒绝；真实native界面展示与双端合成视频联合验证（非真实Emby账号）。适用flutter全量、analyze、分层守卫及服务测试与构建；无法实测环境明确保留，不冒充公网/真实设备结果。


## 最终交付（2026-11-14）

T1–T3实现完成，保留MP-TT01离线/画质和复制基线的全部用户工作；未提交、推送、合并、安装覆盖或部署。工作树尚未合入目标，继续保留供体验，未满足清理条件。HEAD仍为2f765b7，实际代码为此工作树的未提交组合态；本轮起点为`.task-baseline-mp-wt01.json`，最终文件指纹见`.task-verification-mp-wt01.json`。

入口：设置底部“一起看”、首页群组图标、电影详情播放按钮旁群组图标、季页单集群组图标。房间页配置可信服务、选片/版本或选择续播、创建/六位码加入、复制房间码、统一开始/暂停/拖动/换片、成员/房主管理。季列表缺少SeriesId时保留上级series上下文。新增入口采用紧凑按钮，不增加原详情/每集高度，设置新入口放在原节序列之后。

服务交付：`services/watch_together`标准库HTTP/WS、固定Emby身份/版本核验、一次性短票据、等待/缓冲屏障、revision冲突、断线/房主转移/限流/到期/权限复核；README含本地运行、Docker和Nginx HTTPS/WS反代及客户端步骤。仅内存房间与凭据，无数据库和额外Flutter依赖。

播放交付：独立客户端与协调器，远端应用无回声；暂停方式打开避免提前出声；所有成员可控制，房主额外管理；后台/睡眠/退出播放器只暂停本机，回前台重新对齐；断线自动重连，跨账号/服务切换取消旧操作；同影片换版本也重建播放器，旧实例不能误报新版本ready。正常Emby进度上报保留。

## 本次验证与修正

- 固定Flutter3.47.7：`flutter analyze --no-pub`无问题、`bash tool/check_layering.sh`通过、`flutter test --no-pub` **1493项全部通过**（日志`/tmp/mp-wt01-full-tests-final.log`）。`git diff --check`通过；服务独立`dart analyze`和native exe编译通过。
- 新增52项：服务18、客户端12、播放协调11、真实服务+双客户端组合6、房间页面/选片5；总计新增52项（1441→1493）。全部纳入最终全量，不能只拼各worker通过记录。服务测试含本机假Emby HTTP对真正EmbyWatchVerifier的身份、版本、禁止重定向核验。
- `flutter build macos --debug --no-pub`及`flutter build apk --debug --no-pub`正常入口通过；macOS产物`build/macos/Build/Products/Debug/Media Player.app`，Android产物`build/app/outputs/flutter-apk/app-debug.apk`。构建沿用既有media_kit插件Swift Package Manager提醒，无构建错误。
- 原生隔离`tool/watch_together_smoke.dart`使用本机12秒合成视频、两真实MediaKitEngine/PlayerController/协调器、两真实客户端与loopback服务、内存身份存储。实际检查暂停加载/未来锚点、双端播放、B全暂停、暂停拖动6s、B后台A继续、返回对齐、最终暂停。首次完整运行最终偏差83ms；最终组合代码再次原生运行全部通过，最终暂停位置均7238ms（此轮偏差0ms）；CUA截图看见双端视频和成功日志，不能外推为公网误差保证。
- `WATCH_ROOM_UI=true`模式用真实WatchTogetherPage/PlayerPage和隔离服务图；CUA确认配置、六位码、影片版本、成员与房主按钮，实际点“开始放映”进入合成视频播放。Flutter原生AX树在导航后有框架更新错误，截图可检查页面；此证据不包含无障碍兼容性验收。
- 独立review修复并复查：准备完成后再buffering重新入屏障且不延长原15s期限；后台加载不覆盖away；seek后重新读取buffering；loading/error去重节流；source绑定与旧片close不污染新片；未来锚点末端校验；服务变更作废旧REST响应/时钟；IPv4真实分段校验；REST/WS均禁止重定向以防凭据/票据发送至别处。复核无剩余实质发现。
- 首轮全量在测试文件仍并行编写时暴露UI测试异步挂起及原页面新增行挤动内容；修复生产入口布局与新测试正确等待真实微任务，保留原测试预期和门禁，受影响39项及最终全量通过。没有删测/跳过/放宽预期。

## 体验边界与下一步

真实Emby多账号权限、独立设备/手机、跨网络时延、真实断网恢复、Docker镜像运行、Windows原生和公网HTTPS部署尚未实测；当前本机夹具不能替代这些证据。未操作真实用户账号/媒体/原应用数据。下一步按服务README部署到用户选择的受信任环境，将地址配置到两台已登录同一Emby的设备进行体验。聊天、语音和作者专属服务不是本次范围。状态保留“待体验”，用户确认后才为“已验收”。


## 2026-11-17 提交整合与测试版发布

状态：待体验。用户已明确授权整合、提交、推送、合入 main、云构建并发布测试版；不含公网同步服务部署或生产账号/媒体操作。本节更新旧记录中的授权与未发布状态，历史验证只保留为历史证据。

整合基线 main/origin main `45f92d47dd429fba2f26b85ac833ee43101af882`，主目录干净。旧任务工作树含早期 Yamby 未提交基线，保留只读；为防覆盖其独有成果，新增同任务 integration 工作树 `/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer/20261117-feat-mp-tt01-integration`，分支 `codex/feat/20261117-mp-tt01-integration`。以增量合并到当前 main，保留其后续公网地址、播放器及反馈修复；不重做 UI。

分工：主 agent 负责任务记录、发布版本/说明、最终组合态门禁、原生隔离界面/播放验证、Git 合入和产物核验；worker(Sol/high) 独占功能源码/测试/契约增量整合及 analyze 修正；researcher(Sol/medium) 只读核对发布输入、签名与现有 CI。无共享文件并发写入；原生夹具使用 loopback 随机端口与临时目录，不读用户账号。Android SDK/ADB/模拟器不重装，Android 和 Windows 由现有云构建验证。本机 Flutter/原生 Mac 检查会重新生成必要缓存。

发现现 main 同 SHA 历史 CI 有更新下载目录异步删除测试抖动：dismiss 为 fire-and-forget，测试只 pumpEventQueue 不能等待文件系统 I/O。保持状态立即清空，返回可等待的清理 Future，测试 await 后保留原目录删除断言；不跳过或放宽检查。

发布走现有 release.yml pilot workflow_dispatch，预发布版本 v0.4.8-pilot.1794895367，固定三平台资产名与 provenance。完成后记录本次新证据，并对旧工作树独有/忽略文件归档核验后清理。

本轮组合态门禁（2026-11-17，基于 main45f92d4 的 integration 未提交增量）：分层守卫通过，flutter analyze --no-pub 无问题，flutter test --no-pub 全量1618项通过（日志 `/tmp/mp-tt01-integration-tests.log`），同步服务 dart analyze 及 exe 编译通过。独立复查确认 end() generation/roomId 防护与迟到响应回归有效；最终原生与远端构建待继续。原有 main 异步删除时序测试保留断言，现等待真实清理 Future。

旧源工作树完整保全归档：`/Users/sakurasep/Documents/Code/Project/Project Worktree/_preserved-notes/20261117-mp-tt01-release/source-worktree.tar`，SHA256 `02d88831e739e15a5800d01a9ac00fa4f63e175c01439163629d4478c7188ee1`。含全部未跟踪源码、截图、忽略的历史构建产物和配置，仅排除 `.git` 指针；1038普通文件内容及242符号链接目标已逐项比对，附hash清单、原status与binary diff。因源树混有独有旧基线，后续不能简单依“干净”判断删除，须以此可恢复保全和本次功能实际合入为条件。


原生补充验收与发布拦截：代码 `a31e91339b6d5a7683121bedb335a787bef8d30c` 已经快进合入 main；整合分支 app-ci [44029380025](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44029380025) 四门全绿。macOS 正常入口 Debug 构建通过；原生双端隔离 smoke 完成统一起播/暂停/6s seek/后台返回对齐，最终暂停偏差0ms（`/tmp/mp-tt01-integration-native-watch.log`）。原生离线夹具完成1.2MB下载、关闭HTTP服务器后实际播放彩条；MPV页选择影视、拒绝vo=gpu并禁保存、brightness=5/scale=lanczos校验2项并保存。

额外真实 WatchTogetherPage→PlayerPage 原生检查暴露旧门禁未覆盖的实际卡死：ready且buffering时后台/断线分支applyWatchState通知controller，_playerChanged把_lastStatus当缓冲边沿又请求sync，_again使微任务do循环不退。CPU100%，VM service stack暂停在coordinator._sync，原生sample/stack保存在 `/tmp/mp-tt01-room-sample.txt`、`/tmp/mp-tt01-room-dart-stack.json`。两端直接controller的smoke和widget/全量通过不能替代此真实页面入口。独立analyst复核同一根因。已取消尚未发布的release [44030497871](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44030497871)，不会将该版本冒充完成。接下来按真实buffering边沿去重并补ready+buffering后台/失效房间回归，重跑门禁与原生房间入口后发布修订提交。


修复结果：独立记录真实buffering状态边沿，仅活跃前台/连接有效且room/item/source匹配时立即同步，保留seek后重读buffering及既有周期对齐。新增后台/断线/房间结束三项ready+buffering回归；旧coordinator下三项均因21次重复apply失败（有限测试护栏避免挂死），修复后三项及定向14项通过。最终全量 `flutter test --no-pub` **1621项全部通过**（`/tmp/mp-tt01-final-tests.log`），analyze无问题，分层守卫/diff检查通过。原生真实WatchTogetherPage→PlayerPage复测可绘制合成视频与响应控件，不再微任务卡死；VM确认ready=true、buffering=false、syncing=false，当前自动化保持app后台，因此按规则paused，不能称作前台放映实测。原生AX树仍有Flutter桥错误，采用截图核对。最终双端自动同步再测与修订版本云门禁继续进行。

最终修复组合态双端原生自动核验全部通过（`/tmp/mp-tt01-final-native-watch.log`）：统一开始、B暂停同步A、暂停seek6s、B后台A继续、B前台重新对齐、最终两端7208ms/paused，偏差0ms。此为本机合成媒体与显式模拟前后台的原生播放器验证，不是跨设备/公网保证。


修订提交与收尾：`4f84b4c0e613b0c8d62c4c641dccc65e4b7f2ee4` 已快进合入并推送 main；该SHA的 [app-ci 44032410826](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44032410826) 分析/测试及 Android/Windows/macOS 构建全部通过。最终发布运行 [44033261315](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44033261315) 冻结此SHA和版本 `0.4.8+1794895367`，首轮取消构建未生成Release。

已确认停止本轮所有Flutter/原生夹具进程，源归档与文件指纹/原git状态再次一致；旧源工作树和integration工作树均已通过git worktree remove移除，两个已整合本地任务分支删除。只保留主工作区与共享根目录，未删除远端任务分支。integration仅有本轮生成的依赖/构建缓存，验证日志已复制到上述保全目录的evidence；旧源全部历史产物保存在完整tar中。git worktree list及两个实际路径均已核对。

最终门禁计数补充：macOS本机全量1621项通过；Linux CI全量1619项通过、2项既有macOS专属安装器用例跳过（ditto/桌面启动仅适用于macOS），这两项已在本机全量执行。本轮未新增跳过、删测或放宽门禁。本机确认Android SDK目录仍不存在，未重装SDK/ADB/模拟器；macOS验证重新生成的临时构建缓存随integration工作树移除。


### 本轮发布完成（2026-11-17）

状态：待体验。离线下载/播放、MPV画质、自建服务一起看均已合入main并发布测试版 [v0.4.8-pilot.1794895367](https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.4.8-pilot.1794895367)。构建目标/标签为 `4f84b4c0e613b0c8d62c4c641dccc65e4b7f2ee4`；[发布44033261315](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44033261315) 所有校验、三平台构建与发布job成功。Android固定keystore解码与签名构建步骤成功，macOS沿既有内测方式分发；没有安装覆盖用户应用。

已实际下载全部资产，文件大小和SHA256均与GitHub digest及来源清单一致；ZIP/APK完整性检查通过。Release的kaneopilot-release.json与Actions provenance artifact逐字节一致，内含目标SHA/版本/批次/构建运行和三平台摘要；远端tag实际指向目标SHA。macOS包内Info.plist核对0.4.8+1794895367，Release正文与手写更新说明一致。

| 可下载资产 | 字节 | SHA256 |
|---|---:|---|
| [kaneopilot-release.json](https://github.com/SakuraLoveSmile/Media-Player/releases/download/v0.4.8-pilot.1794895367/kaneopilot-release.json) | 1103 | `e3b5cb1d706a8ce47fd3663595181ffb48d5fc38c9eab9739ed64b1c8dbd1bcd` |
| [MediaPlayer-android.apk](https://github.com/SakuraLoveSmile/Media-Player/releases/download/v0.4.8-pilot.1794895367/MediaPlayer-android.apk) | 117527059 | `0cf22b298229050e1cb9e2e97c7d4e292ae872d9fbe490247612fb8f099e30b6` |
| [MediaPlayer-macos.zip](https://github.com/SakuraLoveSmile/Media-Player/releases/download/v0.4.8-pilot.1794895367/MediaPlayer-macos.zip) | 43352082 | `ca1e44f215df573f71444019ff63dc3334676603b8d0b11b082103b31197b401` |
| [MediaPlayer-windows-x64.zip](https://github.com/SakuraLoveSmile/Media-Player/releases/download/v0.4.8-pilot.1794895367/MediaPlayer-windows-x64.zip) | 35373762 | `e3aa59f5b74a9ed268197e67269327c94e2a33427d3f8617827d087673d24eb2` |

本地安装包保留在上述保全目录的 `release-assets/`；下载与来源校验记录见 `evidence/published-verification.json`，云端测试日志及本轮原生日志也保留在evidence。两临时worktree及本地任务分支已清理，主目录只追加本发布记录；本记录的文档提交不改变上述已构建代码。

体验入口：设置→下载与离线媒体、设置→MPV播放器；首页/详情/季页→一起看。默认正式版渠道不会提示此预发布，需要切到设置中的预览版渠道或直接从上述链接下载安装。一起看仍需配置用户自己的可信同步服务，运行说明见 `services/watch_together/README.md`。本次未部署公网服务，未操作生产账号/媒体数据。真实Emby权限/多账号、跨设备/公网、Android/Windows原生运行、Docker和前台房间页面完整放映仍需实际环境体验；Mac隔离夹具、构建和单测不替代这些证据。只有用户确认后才转已验收。
