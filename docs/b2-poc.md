# B2 直连 PoC 记录

- 日期：2026-10-27
- 服务器：Emby **4.10.1.0**（局域网 HTTP，端口 9096）
- 账号：只读测试账号（凭据不写入仓库）
- 结论：**macOS、Android 真机（Mi 10）、Windows 11 x64 直连均通过（H.264 / HEVC 4K，含 MKV/MP4）；WAN、PGS/HDR 仍待验证。**

## 1. 方法

1. `GET /System/Info/Public` 确认可达与版本。
2. `POST /Users/AuthenticateByName` 获取 token（`X-Emby-Authorization`）。
3. `GET /Users/{userId}/Views`、`/Users/{userId}/Items` 扫描媒体库。
4. `POST /Items/{id}/PlaybackInfo`，携带契约 §3.2 的 DeviceProfile。
5. 用 media_kit 播放返回的 `DirectStreamUrl`，分别测试 **URL `api_key`** 与 **仅 `X-Emby-Token` header** 两种鉴权。

## 2. 服务器概况

- 媒体库：13 个（movies / tvshows）。
- 条目总数：9598。
- 样本：从最近条目与全库扫描中选取 H.264、HEVC Main、HEVC Main10、4K、MKV、MP4。

## 3. 结果

| 条目 | 容器 / 编码 | 码率 | 直连 | macOS | Android（Mi 10） | Windows 11 x64 |
|---|---|---|---|---|---|---|
| 69117 | MKV / H.264 High 1080p / AAC | 5.2 Mbps | `SupportsDirectPlay=true`，无 `TranscodingUrl` | 通过：23m42s，1920×1080 | 未测 | 通过：23m42s，1920×1080，position 13.4s |
| 37106 | MP4 / HEVC Main10 3840×1608 / AAC | 4.5 Mbps | 同上 | 通过：41m41s，3840×1608 | 未测 | 未测 |
| 53212 | MKV / HEVC Main 3840×2160 / AAC | 12.1 Mbps | 同上 | 通过：82m04s，3840×2160 | 通过：82m04s，3840×2160，position 12.3s（query）/13.2s（header） | 通过：82m04s，3840×2160，position 13.2s |
| 70250 | MP4 / H.264 High 1080p / AAC | 2.1 Mbps | 同上 | 仅验证 PlaybackInfo | 未测 | 未测 |

- **两种鉴权都通过**：带 `api_key` 的 URL、去掉 `api_key` 仅用 `X-Emby-Token` header，macOS 与 Android 真机均可播放，无 401/403；Windows 使用 header-only URL 通过。
- **未触发转码**：上述条目 PlaybackInfo 均返回 `DirectStreamUrl`，没有 `TranscodingUrl`。
- 契约 §3.2 的 DeviceProfile 对 H.264 与 HEVC 4K 足以拿到直连。
- Android 真机（Mi 10 / Android 16 / API 36）使用默认硬件加速，HEVC 4K MKV 正常推进时间轴，无 FATAL；日志中的 `GraphicBufferAllocator` 与 mediacodec SELinux 记录未影响播放。
- Windows 真机：Windows 11 家庭版 26200 x64，i7-14650HX，RTX 5060 Laptop，1920×1080；`windows-latest` CI 构建的 release 包运行，两个条目均直连，`errors=[]`，App exit code 0。日志含 460 次 position 更新，无 error/fail。
- **模拟器差异**：headless 模拟器上同一网络流 position 恒为 0；真机通过，说明该现象是模拟器特有，**模拟器结果不能作为 Android 验收依据**。

## 4. 真实响应与契约差异

1. `DirectStreamUrl` 是**相对路径**，形如 `/videos/{id}/stream.{container}?MediaSourceId=...&Static=true&UserId=...&api_key=...`（小写 `videos`，带扩展名）。
2. 直接请求会返回 **302**，播放器需跟随重定向；mpv/media_kit 可正常跟随。
3. `PlaySessionId` 在 PlaybackInfo **顶层**，`MediaSources[]` 内没有。
4. `.strm` 条目在列表里没有 `MediaSources`/编码信息；详情或 PlaybackInfo 阶段再解析。
5. 服务器版本 4.10.1.0，契约写的 4.8+ 下限成立；4.8/4.9 未回归。

## 5. 对实现的影响

- `PlaybackPlan` 生成时**优先原样使用** `DirectStreamUrl`（相对路径拼 base），不要自己重拼；仅在其缺失时用 §3.4 的 fallback。
- 媒体请求优先 header 鉴权，已验证可行；URL `api_key` 作为回退。
- 播放器必须允许 302 重定向。
- 进度上报使用顶层 `PlaySessionId`。

## 6. 仍未验证

1. **WAN（frp HTTPS）**：尚未提供公网地址。
2. **PGS 字幕**：扫描前 800 条未发现 `pgssub`；如库中存在，需单独验证。
3. **HDR10**：测试到 HEVC Main10 SDR，未验证 HDR tone mapping。
4. **会话 `PlayMethod`**：客户端尚未实现 `/Sessions/Playing` 上报，服务器端 `PlayMethod/TranscodingInfo` 需在 B5 后核对。
5. **转码路径**：未强制转码，`TranscodingUrl`/HLS 对真实 Emby 未测。
6. **外挂字幕**：扫描 1000 条未发现 `IsExternal=true`；`DeliveryUrl` 未验证（当前样本均为内嵌 subrip）。

## 7. 下一步

- 提供 WAN 地址后验证 frp HTTPS 与码率策略。
- 实现 B5 的上报后，用 `GET /Sessions` 核对 `PlayMethod=DirectPlay`。
- 若库内存在 PGS/HDR 样本，补测；否则在 T2 中标注"未覆盖"。
