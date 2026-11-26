# MediaPlayer 一起看协议 v1（MP-WT01 唯一共享契约）

本协议为自建服务独立实现，参考Tigerest用户行为，不对接其专属服务器、不复制源码。一个服务绑定一个管理员配置的Emby服务器，成员各自登录并有相同媒体/版本的访问权限，视频不经过房间服务。所有位置/时间单位毫秒。

## 传输与认证

API前缀 `/watch/v1`；HTTPS（loopback/LAN调试允许HTTP）。服务端配置 EMBY_URL、EMBY_SERVER_ID，绝不接受客户端指定上游URL；REST头 `X-Emby-Token`、`X-Emby-User-Id`、`X-Emby-Server-Id`。服务端用固定Emby `/Users/Me`核验真实用户身份且Id匹配，读取Policy判管理员；`/Users/{userId}/Items/{itemId}`检查CanPlay!==false、PlayAccess!==None、Movie/Episode及选中MediaSources归属。需要更严格播放访问时调用PlaybackInfo，不能信客户端title/时长。拒绝重定向，不记录token/房间码/票据。

服务仅内存保存房间与成员token，离开/到期清理；最多50房间、普通4人/管理员20人、24h到期。房间码6位无歧义大写字母数字，不公开列房。匿名只有health；不返回原userId/token/endpoint。

REST返回成功HTTP200 `{ "data": {...} }`；错误相应4xx/5xx `{ "error": {"code":"...","message":"..."} }`。未授权401、权限403、房间失效404、满房/版本冲突409、参数400、限流429、上游不可用503。message固定安全文案，不带URL或异常正文。REST只接受JSON有界body(16KiB)。所有变更异步鉴权结束后复核房间、成员、revision，目标加入失败不离开旧房。
上游失败归因（错误体仍只有`code`/`message`，不含上游URL、token或异常正文）：连接/请求/读响应超时 `EMBY_TIMEOUT` 503「媒体服务器响应超时」；`TlsException`/`SocketException`/`HttpException` `EMBY_UNREACHABLE` 503「无法连接媒体服务器」；上游非200（401/403/404除外）`EMBY_UPSTREAM_ERROR` 502「媒体服务器返回错误」；JSON解析失败、顶层形状不符或响应超过1MiB `EMBY_BAD_RESPONSE` 502「媒体服务器响应异常」；`/Users/Me` 返回404 `EMBY_CONFIG` 503「服务端媒体服务器地址配置无效」。条目路径404仍为`ITEM_FORBIDDEN` 403，401/403仍为`AUTH_INVALID` 401，其它未知异常仍为`EMBY_UNAVAILABLE` 503「媒体服务器暂不可用」。新增code只细分上游失败原因，不改变原有code的含义与语义。

超时预算为同一会话内稳定的预算，不改变任何协议数据结构：服务端上游连接、请求与读响应默认8秒，可由构造参数调整；客户端health 8秒、房间读写与票据30秒、WebSocket握手15秒。

## 数据

Room：`roomId, code, capacity, ownerMemberId, media, playback, members`。
Media：`itemId, mediaSourceId`(可为null表示服务器默认；返回服务端选择的明确sourceId), `title, type, runTimeMs`。标题/时长来自Emby。
Playback：`revision:int, state:paused|waiting|playing, positionMs:int, serverTime:int, waitingMemberIds:List<String>`。serverTime为进程epoch基准+Stopwatch单调时间，不受校时影响；playing时目标=max(0,positionMs+max(0,estimatedServerNow-serverTime))，直到未来serverTime前保持暂停，目标不超runtime。
Member：`memberId, name, role:owner|member, connected:bool, status:away|loading|ready|playing|paused|buffering|ended|error, lagging:bool`。memberId为房内opaque身份，name来自各自Emby用户；只给昵称，不给原userId。

## REST

GET `/health` -> data `{enabled:true,protocol:1}`，不暴露Emby配置。
POST `/rooms` body `{clientId,itemId,mediaSourceId?,positionMs:0}` 创建；已在房间409 ALREADY_IN_ROOM（客户端先确认leave，不静默换房）。
POST `/rooms/join` `{clientId,code}`；已有同房成员允许重连；其他房409。
上述成功data `{room:Room, memberId, ticket}`；ticket随机256bit、30秒一次性、绑定clientId/用户/房间。
POST `/rooms/{roomId}/ticket` `{clientId}` ->同上；仅已有成员，重连/重启恢复使用。
GET `/rooms/{roomId}` -> data `{room:Room,memberId}`，仅成员。
POST `/rooms/{roomId}/leave` `{}` -> data `{left:true}`；最后成员离开删除房间，房主转给在线成员优先。
POST `/rooms/{roomId}/kick` `{memberId}` ->data `{removed:true}`；仅owner，不能踢自己，被踢用户在该房间结束前禁入。
POST `/rooms/{roomId}/end` `{}` ->data `{ended:true}`；仅owner，发closed事件。

## WebSocket

连接 `/socket` 无URL凭据；5秒内发 `{type:"hello",ticket,clientId}`；成功发 `{type:"snapshot",room:Room,memberId}`；新连接替换同成员旧连接(close4409)，旧票据作废。失败close4401；房间结束/被踢用closed事件与close4410。
每5秒ping `{type:"ping",clientTime:int}` -> `{type:"pong",clientTime,serverTime}`；客户端用RTT中点估时，持续30秒无消息断开；60秒座位保留，全员断线保留300秒，房主断线60秒后转移在线成员。客户端自动重连有界退避1/2/4/8秒，4409/4410停止重连，断线本机暂停不改变房间。
客户端命令 `{type:"command",requestId,revision,action:"play"|"pause"|"seek"|"changeItem",positionMs?,itemId?,mediaSourceId?}`。
成功 `{type:"ack",requestId}` 且向全员broadcast snapshot；失败 `{type:"error",requestId,code,message}`，STALE_REVISION另发最新snapshot，不自动重发旧控制。
所有成员均可控制，revision不等拒绝。pause冻结当前位置（可传本机positionMs，校验0..runtime）；play进入waiting；seek在暂停时保持paused，否则进入waiting；changeItem逐成员验权/同版本，核验中锁定change且提交前再查房间成员和revision；任何拒绝旧媒体继续。成功新媒体position=0进入waiting。
状态 `{type:"status",revision,status,positionMs}`，仅当前revision参与ready与buffer；away/error可随时取消等待。加载完成且buffering=false发ready；等待名单为当前connected且status非away/error的成员，15秒超时标lagging并开始；全ready后playing锚点serverTime=now+500ms，revision+1；同版本等待名单缩减可broadcast且不递增revision。
持续buffering>=1500ms进入等待并回退到不超过当前房间目标的该成员position；同成员30秒内最多触发一次，其余标lagging。playing期间定期status与server心跳快照校正。
服务端定期10分钟复核token，明确401/403移除，网络错误保留且30秒重试。限制消息32KiB、命令10/s、其他消息20/s，票据和房间受全局上限。Origin非空默认拒绝（原生无Origin），如部署需Web可显式白名单。

## 客户端与播放器集成

服务URL由用户设置，文案明确这是自己部署/信任的同步服务并会核验当前Emby会话；仅持久化服务URL、clientId、恢复roomId及server/user身份，不保存额外token/ticket。服务地址变更/登出/切服务器立即断开/清除恢复状态，不用新账号重放旧凭据；服务token不在URL或日志。
房间页展示房间码/复制、影片/版本、成员/状态、开始放映/进入播放、换片、离开与房主kick/end。create选择电影/剧集单集及版本；支持从详情与季页单集带选片进入。新页沿AppPage/AppSection +现有ListTile/按钮，窄屏Wrap与列表换行，不更换theme。
播放器由roomId绑定；加载就暂停并ready，服务器锚点开始。用户按钮/手势/章节跳过统一走远程command，应用远端状态调用本地无回声入口并保持正常Emby进度上报。小偏差250ms内不处理，250..2000ms用0.95/1.05调速，大于2000ms seek；暂停/等待强制定位且pause；用户倍速固定1，仅协调器内部可微调。后台/退出播放器发away+本地pause，不能暂停别人；回来对齐。房间结束/被踢/会话失效暂停并清晰提示，停止同步；不会悄悄变成个人继续播放。
换片统一先服务端changeItem，收到新media后当前一起看播放器重建并关闭旧会话；自动下一集通过room changeItem一次提交，不能各端独立导航。局域网视频不转码、每人原有进度上报均保留。

服务端获取媒体信息：条目详情请求带上游参数`Fields=MediaSources`；未指定版本且详情已含`SupportsDirectPlay || SupportsDirectStream`的源时直接采用该源并跳过`PlaybackInfo`，因为该`MediaSources`已由Emby按当前用户权限过滤，局域网不转码时多一次往返只增加失败面与延迟。指定版本、或详情没有可用源时仍走原`PlaybackInfo`协商（`EnableTranscoding=false`，版本与权限校验不变）。跳过与否不改变Media的`itemId`/`mediaSourceId`语义，客户端无需区分。

客户端失败界面：错误条显示具体原因（新code各自的中文文案，见「传输与认证」）并提供「重试」与「关闭」；「重试」重跑最近一次动作，新动作开始同时清除页面错误与客户端`error`，恢复成功也清除旧错误。旧客户端遇到新增code走通用兜底文案「一起看操作失败，请稍后重试」，不崩溃、不改变流程。

客户端诊断日志：客户端`WatchLogSink`只接收四字段（事件名、`status`、`durationMs`、`code`），事件名限定白名单`watch.health`、`watch.room.create`、`watch.room.join`、`watch.room.ticket`、`watch.room.leave`、`watch.room.kick`、`watch.room.end`、`watch.socket`。事件名不由URL或房间码生成，不包含服务地址、房间码、token或票据；协议本身不新增日志字段或接口。
