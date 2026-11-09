# MoviePilot 求片（S1–S14）

分支 `feat/moviepilot-request`，基线 = `experiment/liquid-glass`（b14bb15）+ 合入 `origin/main`（v0.2.5 剧集播放与更新渠道）。

本文件记录实际执行结果与未完成的验证，冻结计划正文见任务描述。

## 已实现

数据层（`lib/data/moviepilot/`）：

- `api/moviepilot_http_client.dart` — 逐请求绝对 Uri、`X-API-KEY`、GET/POST/DELETE、`ResponseType.plain` 自解码、Dio 异常映射、redact 日志。401 与 403 都映射为 `unauthorized`（v3 对无管理员角色的 token 返回 403）。
- `api/mp_envelope.dart` — 三态解包：`{success,data}`、裸 list/对象、`{data:{list,total}}`；`success:false` 抛 `MoviePilotException` 并带服务端 message。
- `models/` — 配置、媒体身份/搜索结果、季、订阅（含 execution_status）、下载任务、整理队列、整理历史。数字字符串、`media_id` 数字或字符串、缺失 `media dict`、progress 0–1 与 0–100 均已容错。
- `moviepilot_repository.dart` — `/api/v1` 前缀、not-configured 守卫、按需拉取。v3 契约要点：`/mediaserver/exists` 参数名是 `mtype`；`/subscribe/search/{id}` 是 POST；历史 `mtype` 是路径段；创建返回 `data.id`（缺失即视为失败，否则订阅无法跟踪或取消）。
- `progress/` — `PollSnapshot`（可持久化）、`RequestMatcher`（分层匹配）、`RequestProgressEngine`（纯函数推导）。

存储与 DI：`MoviePilotConfigStore`（`mp.moviepilot.v1`）、`RequestStore`（`mp.requests.v1`，记录 + 上次快照同键）、`lib/app/moviepilot_providers.dart`。

功能层：`lib/features/request/`（state/controller/page + 三个 widget）、`lib/features/settings/moviepilot_config_dialog.dart`；设置页新增「求片」分区，媒体库工具栏新增求片入口，路由 `/request`。

Emby 联动：`LibraryService.findByTmdb` / `searchByTitle`，`MediaItem.productionYear`。

## 逐片提交

S1 `ad1bbe7` … S14 `32ce556`，每片单独本地提交，未推送。

## 验证

- `flutter analyze` 无问题；`./tool/check_layering.sh` 通过；`flutter test` 598 通过。工具链为 `~/devsdk/flutter`（3.47.7 / Dart 3.13.5），系统 PATH 上的 3.41.3 不满足 `sdk: ^3.13.5`。
- 推导引擎测试含 mutation-check：逐条翻转决定性输入（`submitted_count` 0→1、加入/移除下载、整理历史 status false→true、订阅移出活动列表、error 出现、state R→S、progress 到 100%、出现 Emby id），断言阶段随之变化。

测试过程中发现并修复的真实问题（先于 UI 存在）：

1. 轮询在飞行中时，用户刚取消的记录会被该轮重新写回。
2. 取消失败后 busy 标记未清除，卡片永久处于禁用态。
3. `showGlassDialog` 的路由不在 `Scaffold` 下，含 `TextField` 的玻璃对话框缺少 `Material` 祖先。
4. 设置列表增至四个分区后，600pt 测试窗口下反馈项落在懒加载 ListView 的构建范围外。
5. 季选择弹窗内 `ListTile` 在装饰过的玻璃表面里触发框架“ink 可能不可见”断言。

## 未完成 / 需在真实实例核实

对照真实 MoviePilot 与 Emby 的 7 项（计划已列，本轮无真实实例，故全部未验证）：

1. `/mediaserver/exists` 的真实响应形状（当前按 `{item:{id,server}}` 解析）。
2. `POST /subscribe/` 返回 id 的位置（当前按 `data.id`；缺失即报错）。
3. `GET /subscribe/history/{mtype}` 的列表形状与分页。
4. `execution_status.phase` 的完整枚举（当前未知 phase 一律按搜索中处理，`submitted_count` 为决定性信号）。
5. 下载器 `progress` 的真实口径（0–1 / 0–100 用启发式：>1 视为百分比）。
6. Emby `AnyProviderIdEquals=tmdbid.<id>` 是否被目标版本支持；不支持时服务端会忽略该参数并返回整库，因此客户端按类型与年份二次过滤，并以 `SearchTerm` 兜底。
7. 完成信号：订阅完成后是否确实从活动列表移入历史（若实例保留在活动态，回退到 Emby 命中 + `lack_episode == 0` 的路径尚未单独实现）。

此外未做：系统级通知（计划内明确不做）、手动选种下载（计划内后续增强）。

## 设备/实例取证状态

未开始。需要用户在设置页填入真实 `url + API_TOKEN` 后按计划“端到端验证”1–7 逐条走。公开仓库中不得提交真实地址与 token；测试全部使用 loopback fake server 与 dummy token。
