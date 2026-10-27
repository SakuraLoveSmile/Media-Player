# B4 媒体库查询层实现与实测

- 日期：2026-10-27
- 服务器：Emby 4.10.1.0，局域网 HTTP（地址与账号不入库）
- 结论：**视图 → 分页条目 → 详情 → 季/集 → 图片** 全链路在真实服务器通过；WAN、空库/权限受限库未覆盖。

## 1. 实测输出（脱敏）

```text
$ EMBY_LAN_URL=<lan> EMBY_USER=<user> EMBY_PASS=<pass> dart run tool/b4_smoke.dart
B4 smoke
PASS views: 13 (movies=3, tvshows=10)
PASS items: page0=58 page1=0 total=58 overlap=0
PASS detail: type=Movie sources=1
PASS seasons: 1 episodes(season1)=52
PASS image: 200 bytes=57842
RESULT pass
```

- 只输出数量与布尔值，不输出库名、条目名、URL 或 token。
- 首个电影库共 58 条（<60），因此第二页为空属预期；分页越过 60 条的边界由单测覆盖（130 条 → 60/60/10，无重复）。

## 2. 覆盖矩阵

| 能力 | 结论 | 证据 |
|---|---|---|
| `GET /Users/{id}/Views` | 通过 | 13 个库：movies 3 / tvshows 10 |
| `GET /Users/{id}/Items` 列表参数 | 通过 | 单测断言 `IncludeItemTypes=Movie,Series`、`SortBy`、`StartIndex`、`Limit`，且 `Fields` 不含 `MediaSources` / `MediaStreams` |
| 分页不重不漏 | 通过 | 单测 130 条三页；实测 58 条两页 |
| 详情含 `MediaSources` | 通过 | 实测 sources=1；单测校验 `DirectStreamUrl` |
| `Seasons` / `Episodes` | 通过 | 实测 1 季 52 集；单测校验按 `SeasonId` 过滤 |
| 图片 Primary + `api_key` | 通过 | 实测 200 / 57,842 bytes；单测校验 `maxWidth`/`tag`/`quality` 与编码 |
| 401 自动登出 | 通过 | 单测：token 被服务端作废后，一次请求即清会话 |
| 未登录调用 | 通过 | 单测：不发请求直接 `unauthorized` |
| WAN | 未验证 | 地址未提供 |
| 权限受限账号/空库 | 未验证 | 测试账号为全库只读 |

## 3. 实现要点

1. `ApiSession` 是 B4 新增的**数据层**接口：`endpoint` / `userId` / `accessToken` / `authorizedGet`。UI 仍只拿 `AuthService`，接触不到 token。
2. 所有 URL 由 `ResolvedEndpoint.resolve(path)` 派生，再 `replace(queryParameters:)` 追加参数，避免 LAN/WAN 混用与手工拼接转义错误。
3. 列表字段严格按契约 §2：`Overview,PrimaryImageAspectRatio,UserData,ProductionYear,RunTimeTicks`，详情才带 `MediaSources,MediaStreams,People,Genres,UserData`。
4. `ItemsPage` 以 `TotalRecordCount` + `StartIndex` 为准，`isLast`/`nextStartIndex` 供 F2 直接翻页；不做客户端排序或去重。
5. `MediaItem.mediaSources` 只在详情响应里有值；列表响应恒为空列表，避免误用。
6. 图片 URL 总是带 `quality=90` 与 `api_key`；`maxWidth`/`tag` 可选，`tag` 为空串时省略；登出后返回 `null`。

## 4. 测试

- 新增 `test/data/library/library_repository_test.dart` 10 项，覆盖视图、列表参数、分页、非法参数、详情、季/集、图片 URL、401 登出、未登录。
- 全量 `flutter test`：**102 项通过**；`flutter analyze` 无告警；分层守卫通过。
- FakeEmbyServer 增加库路由，B3 的既有用例未改动。

## 5. 未覆盖 / 后续

1. WAN 地址就绪后复跑同一冒烟。
2. 60 条以上的真实分页（当前首个电影库 58 条）；单测已覆盖边界。
3. 空库、无权限库的 UI 表现（F2）。
4. 多版本片源（`MediaSources[0]` 规则）需要多版本样本；当前库内多为单版本。
5. 图片缓存与内存占用（F2）。
