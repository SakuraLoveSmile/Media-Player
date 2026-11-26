# MP-WT02：一起看上游归因、重试与诊断日志

- 项目：personal-mediaplayer；分支：`kaneo/woxb5p5ne8f0e1656fb0y9jq`；工作树：本任务 run 目录
- 范围：一起看服务的上游失败归因与超时预算、客户端文案与诊断日志、房间页错误条重试；不改协议数据结构，不改票据/房间语义

## 背景与症状

- 用户侧只看到「媒体服务器暂不可用」，无法区分是超时、连不上、上游 5xx、响应异常还是服务端 Emby 地址配错，只能靠猜。
- 失败后无法就地重试：要退出页面、重走创建/加入流程才知道问题是否已恢复。
- 反馈日志里没有一起看事件，收到「一起看失败」的反馈时无法判断失败发生在健康检查、创建、加入、票据、离开还是 socket 握手。

## 证据来源

- 服务端 `services/watch_together/lib/watch_server.dart` 的 `_request`：所有非 401/403/404 的上游失败统一映射为 `EMBY_UNAVAILABLE` 503「媒体服务器暂不可用」，异常类型与 HTTP 状态全部丢弃；同文件 4 处硬编码 5 秒超时（连接/请求/读响应/入站 body），无法按部署环境调整。
- 客户端 `lib/data/watch_together/watch_together_client.dart` 的 `_message`：除少数既有 code 外只有通用兜底文案，新原因无处显示。
- 房间页错误条只有文本，没有「重试」，也没有对应的关闭动作；失败后 `client.error` 会一直保留，下一次成功前仍显示旧原因。
- 反馈诊断通道存在但一起看没有上报点，事件里既没有事件名也没有耗时与 code。

## 决定

- **服务端错误码分流**：新增 `EMBY_TIMEOUT` 503「媒体服务器响应超时」（连接/请求/读响应 `TimeoutException`）、`EMBY_UNREACHABLE` 503「无法连接媒体服务器」（`TlsException`/`SocketException`/`HttpException`）、`EMBY_UPSTREAM_ERROR` 502「媒体服务器返回错误」（上游非 200，401/403/404 除外）、`EMBY_BAD_RESPONSE` 502「媒体服务器响应异常」（JSON 解析失败、顶层形状不符、响应超过 1MiB）、`EMBY_CONFIG` 503「服务端媒体服务器地址配置无效」（`/Users/Me` 返回 404）。条目路径 404 仍为 `ITEM_FORBIDDEN` 403，401/403 仍为 `AUTH_INVALID` 401，其它未知异常仍为 `EMBY_UNAVAILABLE` 503。为什么：诊断可操作性优先——把「等一会儿」「查网络」「查 Emby」「改配置」四种完全不同的人工动作分开，且不引入新依赖；错误体仍是 `code`/`message`，不含上游 URL、token 或异常正文，不扩大信息暴露面。
- **上游超时参数化**：`EmbyWatchVerifier` 新增 `Duration timeout`（默认 8 秒），用于 `HttpClient.connectionTimeout`、`openUrl(...)`、`request.close()`、`response.timeout(...)`，不再硬编码 5 秒。为什么：局域网 Emby 与跨网 Emby 的合理超时不同，8 秒覆盖常见慢响应又不会让客户端白等；默认值即可用，测试与小规模部署可用构造参数收紧或放宽，属实现细节不进协议。
- **条目详情带 `Fields=MediaSources` 并跳过默认 `PlaybackInfo`**：未指定版本且条目详情已含 `SupportsDirectPlay || SupportsDirectStream` 的源时直接采用该源并跳过 `PlaybackInfo`；指定版本或详情无可用源时仍走原协商（`EnableTranscoding=false`，版本与权限校验不变）。为什么：详情里的 `MediaSources` 已由 Emby 按该用户权限过滤，LAN 不转码时多一次往返只增加失败面与延迟；跳过依据仍是服务端校验，不信任客户端，且保留原协商路径作为兜底，不改 `itemId`/`mediaSourceId` 语义。
- **客户端超时预算分层**：health 8 秒、房间读写与票据 30 秒、WebSocket 握手 15 秒。为什么：健康检查是探活应快速失败，房间读写与票据背后要等上游鉴权，握手需要覆盖慢网络升级；预算是同一会话内稳定的常量，不改协议数据结构。
- **客户端文案与旧版兼容**：为 5 个新 code 各加中文文案（`EMBY_TIMEOUT`「媒体服务器响应超时，请稍后再试」、`EMBY_UNREACHABLE`「无法连接媒体服务器，请检查网络与服务器设置」、`EMBY_UPSTREAM_ERROR`「媒体服务器返回错误，请稍后再试」、`EMBY_BAD_RESPONSE`「媒体服务器响应异常，请稍后再试」、`EMBY_CONFIG`「服务端媒体服务器地址配置无效，请联系服务维护者」），`EMBY_UNAVAILABLE` 保持「媒体服务器暂不可用，请稍后再试」；旧客户端遇到新 code 走通用兜底「一起看操作失败，请稍后重试」，不崩溃。为什么：文案只在前端映射，服务端只发 code，新旧版本可各自演进，不需要协议版本协商。
- **诊断日志 `WatchLogSink`**：四字段（事件名、`status`、`durationMs`、`code`），事件名固定白名单 `watch.health`、`watch.room.create`、`watch.room.join`、`watch.room.ticket`、`watch.room.leave`、`watch.room.kick`、`watch.room.end`、`watch.socket`；由 `lib/app/providers.dart` 注入到 `feedbackDiagnostics.record`（有 code 记 `warn`，否则 `info`）。为什么：反馈附件需要「哪个动作、多久、什么结果」，白名单事件名保证不由 URL 或房间码拼接，天然不含服务地址、房间码、token、票据；不新增依赖，也不新增协议字段。
- **页面错误条可重试**：失败时显示具体原因 +「重试」+「关闭」，「重试」重跑最近一次动作；新动作开始时同时清页面错误与 `client.error`；客户端新增 `clearError()`，`restore()` 成功时清除旧错误。为什么：失败原因已经可区分，下一步就是让用户不用退出页面即可复测；清旧错误避免用过期原因误导判断。

## 改动清单

- `services/watch_together/lib/watch_server.dart`：`EmbyWatchVerifier` 新增 `timeout`（默认 8 秒，替换 4 处硬编码 5 秒）；`_request` 按异常类型与上游状态分流为上述 code；`media()` 详情请求带 `Fields=MediaSources` 并在未指定版本且详情含可直接播放源时跳过 `PlaybackInfo`。
- `lib/data/watch_together/watch_together_client.dart`：分层超时预算；5 个新 code 文案与 `EMBY_UNAVAILABLE` 文案；`WatchLogSink` 与白名单事件；`clearError()`、`restore()` 成功清错。
- `lib/app/providers.dart`：注入 `WatchLogSink` 到 `feedbackDiagnostics.record`。
- 房间页：错误条显示原因 +「重试」+「关闭」；「重试」重跑最近一次动作；新动作开始清理旧错误。
- 文档：本记录、`docs/contracts/watch-together-v1.md`（上游归因、超时预算、跳过协商、诊断日志）、`services/watch_together/README.md`（错误码排查表）。

## 验证

本轮按仓库固定顺序执行以下五条质量门，全部退出码 0（2026-11-26，本任务工作树）：

```sh
(cd services/watch_together && /Users/sakurasep/devsdk/flutter/bin/dart pub get)
```

```sh
bash tool/check_layering.sh
```

```sh
/Users/sakurasep/devsdk/flutter/bin/flutter analyze
```

```sh
/Users/sakurasep/devsdk/flutter/bin/flutter test --no-pub test/data/watch_together/server_test.dart test/data/watch_together/client_test.dart test/app/watch_together_page_test.dart
```

```sh
/Users/sakurasep/devsdk/flutter/bin/flutter test --no-pub
```

本轮结果：五条命令均通过（退出码 0）。`dart pub get` 成功；`tool/check_layering.sh` 输出 `layering ok`；`flutter analyze` 输出 `No issues found!`；三个目标测试文件 `60` 个用例全部通过；`flutter test --no-pub` 全量 `1678` 个用例全部通过。其中服务端文件 `28` 个、客户端文件 `21` 个、房间页 `11` 个。

## 测试覆盖点

- 上游超时：100ms `timeout` + 300ms 上游延迟 → `EMBY_TIMEOUT` 503。
- 上游 500 → `EMBY_UPSTREAM_ERROR` 502；`/Users/Me` 返回 404 → `EMBY_CONFIG` 503；条目路径 404 → `ITEM_FORBIDDEN` 403。
- 未指定版本且详情含可直接播放源时不请求 `PlaybackInfo`；指定版本时仍请求；`EnableTranscoding=false` 与版本/权限校验行为不变。
- 客户端 5 个新 code 的中文文案；`EMBY_UNAVAILABLE` 文案保持原文；未知 code 走通用兜底。
- 日志 sink 只产生白名单事件名与四字段，且内容不含服务地址、房间码、token、票据。
- 上游响应超过 1MiB 或非法 JSON → `EMBY_BAD_RESPONSE` 502；上游连接被拒 → `EMBY_UNREACHABLE` 503；错误体只有 `code`/`message`，不含上游 URL 与 token。
- 房间页首次创建失败显示具体原因与「重试」，点击「重试」后成功进入房间。
- 新动作开始时清除旧 `client.error`，不再显示上一次失败原因。

## 发布状态

- 生产一起看镜像仍是 `v0.4.8-pilot`，容器 `pull_policy: never`。
- 本轮没有部署、没有构建或替换镜像、没有发版；部署需另行授权。

## 待人工验收

- 真实账号创建房间，故意制造失败后点「重试」确认可恢复。
- 双账号加入同一房间并各自暂停一次，确认控制与状态一致。
- 触发一次上游失败，检查反馈附件的 `watch.*` 事件是否出现且不含服务地址、房间码、token。

## 边界

- 只在本任务工作树改动；未提交、未推送。
- 不改协议数据结构与票据/房间语义。
- 本记录与两份文档的改动不涉及任何 `.dart` 文件；不动生产部署与镜像。
