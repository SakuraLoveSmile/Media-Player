# Emby 客户端契约 v1.1

- 状态：Frozen（M0，2026-10-27）
- 适用：B1–B7、F1–F4、T1–T3
- 变更规则：任何端点、字段、策略变更必须先改本文件，再改代码；前后端不得各自复制一份契约。

## 0. 范围

首阶段只做：双端点（LAN HTTP / WAN frp HTTPS）配置与选路 → 登录 → 媒体库（电影/剧集）浏览 → 播放（LAN 视频直连，WAN 按码率上限）→ 进度上报与续播。

不做：自建服务端、下载、投屏、直播、音乐/照片、搜索、多服务器、Android TV、iOS/Linux、播放中无缝切换网络。

## 1. 服务器与端点

### 1.1 ServerProfile

```dart
enum EndpointKind { lan, wan }
enum EndpointPreference { auto, lan, wan }

class ServerProfile {
  final String serverId;          // 来自登录响应 / System/Info/Public 的 Id
  final String name;              // ServerName
  final String? lanUrl;           // 例：http://192.168.1.10:8096
  final String? wanUrl;           // 例：https://emby.example.com
  final EndpointPreference preference; // 默认 auto
  final int wanBitrateCapMbps;    // 默认 30
  final bool forceDirectOnWan;    // 默认 false
  final EndpointKind? lastGoodEndpoint;
}
```

### 1.2 URL 规范化

- 去首尾空白；无 scheme 时补 `http://`；去掉末尾 `/`。
- 候选 base：输入值本身、输入值 + `/emby`（兼容反代子路径）。
- 只接受 `http` / `https`。

### 1.3 EndpointResolver

```dart
class ResolvedEndpoint {
  final String baseUrl;
  final EndpointKind kind;
  final String serverId;
  final DateTime resolvedAt;
}
```

探测：`GET {base}/System/Info/Public`，要求 `Id == profile.serverId`。

顺序：

- `auto`：LAN（超时 1.5s）→ WAN（超时 3s）。
- `lan`：仅 LAN。
- `wan`：仅 WAN。

缓存与重解析：

- 解析结果缓存 5 分钟。
- 重解析触发：应用启动、回前台、手动"重新连接"、`NetworkUnreachable`/超时、播放前缓存过期。
- 两端都失败时返回 `NetworkUnreachable`，并携带每个端点的失败原因。
- **一次播放会话内所有 URL（PlaybackInfo、媒体流、字幕、进度上报）必须使用同一个 `ResolvedEndpoint.baseUrl`。**

### 1.4 认证

```http
POST {base}/Users/AuthenticateByName
X-Emby-Authorization: MediaBrowser Client="MediaPlayer", Device="<deviceName>", DeviceId="<deviceId>", Version="<appVersion>"
Content-Type: application/json

{"Username":"...","Pw":"..."}
```

成功响应关键字段：`User.Id`、`User.Name`、`AccessToken`、`ServerId`。

- 首次登录必须把 `ServerId` 写入 `ServerProfile.serverId`。
- 添加第二个地址时探测其 `System/Info/Public.Id`，必须与已存 `serverId` 一致，否则拒绝（`serverMismatch`）。
- `DeviceId` 首次生成 UUID 后持久化；`DeviceName` 使用平台 + 主机名。
- 除登录请求外，所有 API 请求带：

```http
X-Emby-Token: <AccessToken>
X-Emby-Device-Id: <deviceId>
```

- 401：清除会话并回到登录页；403：提示权限不足，不自动重试。
- 自签证书：默认拒绝；用户显式"信任此服务器证书"后放行，并记录证书指纹（待实测：frp 使用 Let's Encrypt 时无需此开关）。

## 2. 媒体库

| 用途 | 请求 |
|---|---|
| 视图 | `GET /Users/{userId}/Views` |
| 库内条目 | `GET /Users/{userId}/Items?ParentId={viewId}&Recursive=true&IncludeItemTypes=Movie,Series&Fields=Overview,PrimaryImageAspectRatio,UserData,ProductionYear,RunTimeTicks&SortBy=SortName&SortOrder=Ascending&StartIndex={n}&Limit=60` |
| 条目详情 | `GET /Users/{userId}/Items/{itemId}?Fields=Overview,MediaSources,MediaStreams,People,Genres,UserData` |
| 季 | `GET /Shows/{seriesId}/Seasons?UserId={userId}` |
| 集 | `GET /Shows/{seriesId}/Episodes?UserId={userId}&SeasonId={seasonId}&Fields=Overview,MediaSources,UserData` |
| 图片 | `GET /Items/{itemId}/Images/Primary?maxWidth={w}&tag={ImageTags.Primary}&quality=90&api_key={token}` |

约定：

- 库页只列 `Movie` / `Series`，不列 `Episode`。
- 列表接口不请求 `MediaSources` / `MediaStreams`（避免大库首屏过慢）；详情页与 PlaybackInfo 再取。
- 分页以 `TotalRecordCount` 为准；加载页不得重复/漏项（以 `StartIndex` 游标）。
- 所有请求必须使用 `ResolvedEndpoint.baseUrl`；图片与媒体 URL 同样。
- 多版本片源首阶段取 `MediaSources[0]`；版本选择留到后续。

## 3. 播放

### 3.1 PlaybackInfo

```http
POST {base}/Items/{itemId}/PlaybackInfo?UserId={userId}
Content-Type: application/json
```

```json
{
  "UserId": "<userId>",
  "StartTimeTicks": 0,
  "IsPlayback": true,
  "AutoOpenLiveStream": true,
  "MaxStreamingBitrate": 1000000000,
  "EnableDirectPlay": true,
  "EnableDirectStream": true,
  "EnableTranscoding": true,
  "DeviceProfile": { "...": "见 3.2" }
}
```

响应取 `MediaSources[]`，关键字段：`Id`、`Container`、`Bitrate`、`SupportsDirectPlay`、`SupportsDirectStream`、`DirectStreamUrl`、`TranscodingUrl`、`MediaStreams[]`。`PlaySessionId` 在响应顶层（Emby 4.10.1 实测），`MediaSources[]` 内可能没有。

### 3.2 DeviceProfile（初版，B5 用真实服务器校准）

```json
{
  "Name": "MediaPlayer-mpv",
  "DirectPlayProfiles": [
    {
      "Container": "mkv,mp4,m4v,mov,ts,webm",
      "Type": "Video",
      "VideoCodec": "h264,hevc,av1,vp9,mpeg2video",
      "AudioCodec": "aac,ac3,eac3,dts,truehd,flac,opus,vorbis,mp3"
    }
  ],
  "SubtitleProfiles": [
    { "Format": "srt", "Method": "External" },
    { "Format": "ass", "Method": "External" },
    { "Format": "pgssub", "Method": "Embed" },
    { "Format": "dvdsub", "Method": "Embed" }
  ]
}
```

- 登录后额外调用一次 `POST /Sessions/Capabilities/Full` 上报同一份能力；请求体为 `ClientCapabilities`，含 `PlayableMediaTypes`、`SupportedCommands`、`DeviceProfile`（已由官方文档确认）。它与 PlaybackInfo 内 DeviceProfile 哪个最终生效、是否被服务端缓存，仍需实测。
- 直连片源不得因 DeviceProfile 缺项被服务端转码；T2 以真实片源验证。

### 3.3 码率与直连策略

```
LAN: MaxStreamingBitrate >= 1_000_000_000；要求视频直连
WAN: MaxStreamingBitrate = wanBitrateCapMbps × 1_000_000
     源 Bitrate <= cap → 期望直连
     源 Bitrate >  cap → 允许转码
     forceDirectOnWan=true → MaxStreamingBitrate 抬高、EnableTranscoding=false
```

- LAN 下若服务端仍返回转码：重试一次（高码率 + `EnableDirectPlay/DirectStream=true`）；仍失败则标记 `directDenied`，UI 明示，按阻断缺陷处理。
- WAN + forceDirect 失败时回退到转码，并提示用户"已回退转码"。
- 允许"音频转码、视频复制"：`videoDirect=true`、`audioTranscoded=true`。

### 3.4 PlaybackPlan

```dart
enum PlaybackMode { direct, transcode }

class PlaybackPlan {
  final PlaybackMode mode;
  final EndpointKind endpointKind;
  final String url;
  final Map<String, String> headers;
  final String mediaSourceId;
  final String playSessionId;
  final Duration startAt;
  final bool? videoDirect;       // 直连=true；会话核对后确定；未知为 null
  final bool audioTranscoded;
  final List<String> transcodingReasons; // 服务端返回则记录，字段名待实测
}
```

URL 生成顺序：

1. `SupportsDirectPlay == true && DirectStreamUrl != null` → 用 `DirectStreamUrl`（绝对化）。
2. 否则 `{base}/Videos/{itemId}/stream?Static=true&MediaSourceId={id}&DeviceId={deviceId}&api_key={token}`。
3. 否则 `{base}{TranscodingUrl}`（相对路径拼接；缺 token 时补 `api_key`）。
4. 都不可用 → `PlaybackUnsupported`。

实测（Emby 4.10.1）：`DirectStreamUrl` 为相对路径 `/videos/{id}/stream.{container}?MediaSourceId=...&Static=true&UserId=...&api_key=...`，请求会返回 302；播放器必须跟随重定向。优先原样使用，不要重拼。

媒体服务器需支持 HTTP Range（Emby 支持）；不支持时 MP4 可能无法 seek 或起播，客户端应给出可读错误，不得静默停在 0。

鉴权优先级：媒体请求优先通过播放器 header 传 `X-Emby-Token`；播放器不支持或失败时回退 URL `api_key`。不得同时把 token 打进日志。

### 3.5 直连判定（验收用）

不以 URL 形态判断，以下列为准：

- `GET /Sessions`（带 token）找到本机 `DeviceId` 的会话；官方文档确认返回 `SessionInfo`，含 `PlayState`、`PlayMethod`、`TranscodingInfo`、`DeviceId`、`NowPlayingItem`；
- 读 `PlayState.PlayMethod` 与 `TranscodingInfo`；
- `PlayMethod = DirectPlay` → 视频直连；
- `PlayMethod = DirectStream` → 容器重封装，视频复制，计为视频直连；
- `PlayMethod = Transcode` 且 `TranscodingInfo.IsVideoDirect == true` → 视频直连、音频转码；
- `IsVideoDirect == false` → 视频转码（LAN 下为阻断缺陷）。

字段名与取值以真实 Emby 响应为准（待实测）；debug 构建在起播 3s 后轮询一次并记日志。

### 3.6 会话上报

| 时机 | 请求 |
|---|---|
| 起播 | `POST /Sessions/Playing` |
| 每 10s / 暂停 / 拖动 / 退后台 | `POST /Sessions/Playing/Progress` |
| 退出 / 切条 | `POST /Sessions/Playing/Stopped` |

Body 关键字段：

```json
{
  "ItemId": "...",
  "MediaSourceId": "...",
  "PlaySessionId": "...",
  "PositionTicks": 0,
  "IsPaused": false,
  "PlayMethod": "DirectPlay",
  "CanSeek": true
}
```

失败重试 1 次（2s 退避），不得阻塞播放。退出播放页必须发 Stopped。

### 3.7 字幕

- 优先 `MediaStreams[]` 中字幕流的 `DeliveryUrl`；相对路径拼 `base`；缺 `api_key` 时补。
- 回退：`/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{format}?api_key=`（路径待实测）。
- 统一由客户端下载到临时文件后交给播放内核挂载（避免播放器鉴权差异）；按 item + streamIndex 缓存。
- 内嵌 PGS/ASS 由 mpv 直接渲染；外挂 SRT/ASS 走文件挂载。
- 字幕下载失败只提示，不中断视频。

## 4. 内部模型

```dart
class AuthSession { userId, userName, accessToken, deviceId }
class LibraryView { id, name, collectionType }
class MediaItem {
  id, name, type, seriesId?, seasonId?, indexNumber?,
  runTimeTicks, imageTag, overview?,
  userData { played, positionTicks }
}
class MediaSource {
  id, container, bitrate,
  supportsDirectPlay, supportsDirectStream,
  directStreamUrl?, transcodingUrl?, playSessionId,
  streams[]
}
class MediaStream {
  type, index, codec, language, displayTitle,
  isDefault, isExternal, deliveryUrl?
}
```

所有 DTO 字段可空，解析失败不得导致整页崩溃；未知字段忽略。

## 5. 播放引擎接口

```dart
abstract class PlaybackEngine {
  Future<void> open(PlaybackPlan plan, {Duration startAt, Map<String, String> headers});
  Stream<PlaybackSnapshot> get state;
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> selectAudioTrack(int index);
  Future<void> selectSubtitleTrack(int? index, {String? externalPath});
  Future<void> dispose();
}

class PlaybackSnapshot {
  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;
  final Object? error;
}
```

- UI 只依赖该接口与 snapshot。
- media_kit 实现不得把 `Player`/`VideoController` 类型暴露到 `features/`。
- 引擎内部负责 hwdec、缓存、tone mapping 等调优（B7）。

## 6. 错误模型

```dart
enum AppErrorCode {
  networkUnreachable,
  tlsUntrusted,
  unauthorized,
  forbidden,
  notFound,
  serverError,
  serverMismatch,
  directPlayDenied,
  playbackUnsupported,
  transcodeFailed,
  subtitleFailed,
}
```

- `serverMismatch`（B3 新增）：用户添加的第二个地址探测到的 `System/Info/Public.Id` 与已存 `ServerProfile.serverId` 不一致，见 §1.4。

- 每个错误必须可映射到用户文案 + 是否可重试。
- 网络类错误附带 `endpointKind` 与各端点失败原因。
- UI 不得显示裸异常/堆栈；日志不得包含 token、密码。

## 7. Token 存储

- 接口 `TokenStore { read/write/delete }`。
- 首选 `flutter_secure_storage`（Android Keystore / Windows DPAPI / macOS Keychain）。
- macOS 无 Developer ID、ad-hoc 构建下若 Keychain 不可用或反复授权：回退到 Application Support 下 0600 文件，仅内测；有证书后切回 Keychain。
- F4 必须验证 macOS 回退路径在重启后可恢复会话。

## 8. 验收门

| 门 | 条件 |
|---|---|
| 平台前置 | macOS Debug/Release entitlements 含 `com.apple.security.network.client`；Android 允许 LAN 明文 HTTP；缺失时网络播放不可用（已实测） |
| M1 | 双端点探测/登录/浏览可用；B2 在三平台直连 HEVC（MKV/MP4）成功；库内存在 PGS 时 PGS 也必须过 |
| M2 | LAN 下三平台 `videoDirect=true`；续播误差 ≤5s；控制项完整 |
| M3 | T2 LAN 矩阵 ≥11/12；库内存在 PGS 时 PGS 全过；T3 WAN 全项通过；三平台包可安装 |

## 9. 实测状态（Emby 4.10.1.0，2026-10-27）

已确认：

- 服务器 4.10.1.0 可登录；13 个库、9598 条目。
- 契约 §3.2 的 DeviceProfile 对 H.264 1080p、HEVC Main 4K、HEVC Main10 4K 均返回直连（`SupportsDirectPlay=true`，无 `TranscodingUrl`）。
- `DirectStreamUrl` 为相对路径、带 `api_key`，请求 302；media_kit 跟随重定向可播。
- header 鉴权（`X-Emby-Token`）与 URL `api_key` 两种方式均可播放真实直连流。
- macOS media_kit 播放 MKV/H.264 1080p、MP4/HEVC Main10 4K、MKV/HEVC 4K 成功。
- Windows 11 x64（release，media_kit/libmpv）：MKV/HEVC 4K 与 MKV/H.264 1080p 直连成功，PlaybackInfo 返回 `SupportsDirectPlay=true`、无 `TranscodingUrl`，播放位置递增、错误列表为空。

待实测：

1. Emby 4.8 / 4.9 回归（当前只验证 4.10.1）。
2. `/Sessions/Capabilities/Full` 与 PlaybackInfo 内 DeviceProfile 的优先级/缓存。
3. `PlayState.PlayMethod` 与 `TranscodingInfo.IsVideoDirect/IsAudioDirect` 的实际取值（需 B5 上报后）。
4. 字幕 `DeliveryUrl` / 回退路径（当前样本为内嵌 subrip，未测外挂）。
5. 强制转码、`TranscodingUrl`、HLS 对真实 Emby（当前均未触发转码）。
6. 同一 token 在 LAN 与 WAN 两个 base 上是否通用（WAN 未提供）。
7. 缺失 `DirectStreamUrl` 时手动拼接是否可用（当前均有 `DirectStreamUrl`）。
8. 服务端转码原因字段名（未触发转码）。
9. Android 真机（Mi 10）已验证 HEVC 4K MKV 直连；headless 模拟器 position=0 为模拟器特有，不作为验收依据。
10. PGS、HDR10、60–80 Mbps（扫描前 800 条未发现 PGS；HDR 未验证）。

## 10. 实现附录（B3，2026-10-27）

本附录只记录实现级细节，不改变 §1–§7 的字段与语义。改动此节不需要重新冻结契约，但必须与代码同批提交。

### 10.1 持久化

| 存储键 | 内容 |
|---|---|
| `mp.token.v1` | `AccessToken` 原文字符串 |
| `mp.session.v1` | `{userId, userName, deviceId}`，**不含** token |
| `mp.profile.v1` | `{schemaVersion: 1, profile: ServerProfile}` |
| `mp.deviceId.v1` | UUID v4 字符串 |

- 首选 `flutter_secure_storage`；任一次读/写/删除自检失败即整体降级到文件实现，并记录一次 WARN（不含值）。
- 文件实现：`<Application Support>/<bundleId>/mp_storage_v1.json`，权限 `0600`，写入走临时文件 + rename。
- 读取失败（JSON 损坏、字段缺失、`schemaVersion` 未知）一律返回 `null`，不抛异常。
- 登出删除 `mp.token.v1`、`mp.session.v1`，保留 `mp.profile.v1` 供重登。
- DeviceId 丢失后重新生成：服务端会视为新设备，可接受。

### 10.2 超时

| 请求 | 连接 | 读取 |
|---|---|---|
| `System/Info/Public` 探测（LAN） | 1.5s | 1.5s |
| `System/Info/Public` 探测（WAN） | 3s | 3s |
| 登录与业务 API | 5s | 10s |

- 探测超时以 `Future.timeout` 兜底，不依赖 dio 的超时语义。

### 10.3 端点

- 候选 base 顺序：规范化值 → 规范化值 + `/emby`；已以 `/emby` 结尾则不重复追加。
- `profile.serverId` 为空（首次登录）时跳过 Id 校验，采用探测到的 Id，由登录响应回写。
- 单飞：同一 profile 的并发 `resolve` 共享一个 Future；结果缓存 5 分钟（`Clock` 可注入）。
- resolver 不写盘；`lastGoodEndpoint` 由 `AuthRepository` 持久化。
- 一次播放会话内所有 URL 使用同一个 `ResolvedEndpoint.baseUrl`（B5 执行）。

### 10.4 错误映射

| 条件 | 错误码 | 可重试 |
|---|---|---|
| 连接/读取超时、`SocketException`、连接被拒绝 | `networkUnreachable` | 是 |
| `HandshakeException` / `badCertificate` | `tlsUntrusted` | 否 |
| HTTP 401 | `unauthorized`（清会话） | 否 |
| HTTP 403 | `forbidden` | 否 |
| HTTP 404 | `notFound` | 否 |
| HTTP 5xx、非 JSON、JSON 解析失败 | `serverError` | 是 |
| 探测到的 Id 与 `profile.serverId` 不一致 | `serverMismatch` | 否 |

- 端点全部失败时顶层为 `networkUnreachable`，`failures[]` 内保留每个候选的真实原因。

### 10.5 认证与会话

- 登录成功后必须用响应的 `ServerId` 回写 `profile.serverId`。
- `restore()` 不额外请求校验 token；首次业务请求 401 再登出。
- 401 → 清 token/session + 清端点缓存 + 回登录页；不自动重试。
- `logout()` 只清本地，不调用服务端。
- 地址格式在 UI 边界用 `UrlNormalizer` 校验；非法地址不进入数据层。

### 10.6 日志

- 只记录 `method + host + path`，query 整体丢弃。
- token、密码、`api_key` 永不写入日志、永不进入仓库。

### 10.7 DeviceId / DeviceName

- `DeviceId`：UUID v4，首次生成后持久化（§10.1）。
- `DeviceName`：`<os> <hostname>`，例如 `macos MacBook-Pro`。
- `X-Emby-Authorization` 中的 `Device` 字段需转义引号。
