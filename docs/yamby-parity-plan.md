# Yamby 功能对齐（移植）计划

状态：**草案 v1（2026-11-11）**，待用户裁决优先级后冻结为执行计划。
性质：**功能复刻 / 对齐**，不是代码移植。Yamby 为闭源应用，无源码可搬；本计划在现有
Flutter 架构内实现等价能力。
范围：以 Android 手机 / 平板为主对齐目标，Windows / macOS 顺带收益；不引入 Android TV / iOS / Linux。

---

## 0. 结论摘要

- Yamby（`com.hush.yamby`，开发者 hush）是闭源、免费 + Pro 的安卓 Emby 客户端，
  **Compose Multiplatform** 构建（`MainCmpActivity` / `PlayerCmpActivity`），Material Design 3 + Monet，
  **默认 ExoPlayer、MPV 为可选 / 长按切换**，仅 Emby、不支持 TV / iOS，已从 Play 下架。
- 设备实证（17 屏）确认其完成度集中在：**首页 dashboard、库内多维浏览、富详情页、
  播放器交互（手势 / 倍速 / 截图 / 锁定 / PIP / 投屏）、字幕深度（外挂 / 字体 / 缩放 / 偏移 / ASS / PGS）、
  DandanPlay 中文弹幕、MPV 高级（Anime4K / gpu-next / deband）、MD3 + Monet 主题**。
- 本项目（v0.3.0）播放内核与直连 / 上报已扎实，但**首页 / 详情 / 搜索 / 收藏 / 手势 / 倍速 / 字幕渲染 /
  弹幕 / 主题**几乎全缺；差距主要在 UI 与播放周边，而非播放内核。
- 修正三处早期臆断：**不支持离线下载**；**HDR10 / 音频直通无独立开关（仍待确认）**；
  **主内核是 ExoPlayer 而非 MPV**。
- 建议从 **P0（播放器交互 + 字幕 + 发现核心）** 起步；多数 P0 项已在本项目既有待办（B6 / F3 tail）内。

## 1. 背景与目标

把 Yamby 的已确认能力对齐进 MediaPlayer，补齐"媒体库 → 详情 → 播放 → 周边"的体验闭环，
同时不破坏既有硬约束（LAN 不转码、同端点、`PlaybackEngine` 封装、分层守卫）。
Yamby 的 Pro 付费项（主题 / Monet / 多服务器 / 跳过启动画面）在本项目**不设付费墙**，但工作量计入。

## 2. 调研方法与证据边界

- **Web 交叉核实**：Play 商店描述、开发者发布帖（V2EX）、更新日志（CSDN / Telegram）、评测站。
- **设备实证**：用户 Mi 10（Android 16）已装 Yamby 并**明确授权仅对 Yamby 前台截屏**。
  共 17 屏（服务器 / 首页 / 搜索 / 收藏 / 库网格 / 详情 / 播放器 / 播放器菜单 / 设置 / MPV / 弹幕）。
  - 守卫：每次截屏 / 操作前确认 `mFocusedApp` 为 `com.hush.yamby`（弹出菜单窗口名为"弹出式窗口"，
    须用 app 级焦点而非窗口级焦点判定）。
  - 边界：不碰锁屏 / 通知栏、不用 `uiautomator dump`、不接触账号密码；试播约 2:53（<5%）即退出，
    服务端按 <5% 规则清零，不留续播点。
  - **原始截图含服务器标签与账号名，仅本地留存、不入库**；本文以文字转述证据。
- **证据分级**：`实证` = 设备截图确认；`web` = 公开资料；`待确认` =  neither，需实测或抓 API。

## 3. 功能全景与差距

| 类别 | Yamby 功能（证据级） | 本项目现状 | 缺口 |
|---|---|---|---|
| 连接 | 多服务器连接 / 切换（web，Pro 无限） | 单服务器双地址 LAN/WAN | 缺 |
| | 隐藏指定媒体库（web） | 无 | 缺 |
| | Emby 管理员功能（web） | 无 | 缺 |
| | STRM 直连（web） | 直连已验，STRM 未实测 | 部分 |
| | Live TV 直播（实证·设置项） | 无 | 缺 |
| 首页 | 推荐横幅轮播（实证） | 无 | 缺 |
| | 媒体库卡片行（实证） | 视图 chips | 部分 |
| | 继续观看行：剩余时长 / 进度条 / 已看勾（实证） | 仅播放器内续播 | 缺 |
| | 按库海报行 + 评分角标 + 更多（实证） | 单网格 | 部分 |
| | 悬浮胶囊导航 首页/搜索/收藏（实证） | 无 | 缺 |
| 浏览 | 网格 / 分页 / 已看标记（实证） | ✅ 已有 | — |
| | 搜索：类型 chips 电影/剧集/合集/演员/专辑 + 历史网格（实证） | API 有、UI 未暴露 | 部分 |
| | 库内子 tabs 全部/继续/合集/类型/标签/收藏（实证） | 无 | 缺 |
| | 筛选 / 排序 / 视图切换 / 随机播放（实证·全局列表） | 无 | 缺 |
| | 收藏 tab：类型 tabs + 计数/筛选/排序（实证） | 只读、无 tab | 缺 |
| 详情 | 背景 hero + 标语/简介/导演 + 演员行（实证） | 剧集页有、电影详情缺 | 部分 |
| | 评分 + 分级 + 年份 + 时长 + 类型 chips（实证） | 无 | 缺 |
| | 已看 / 收藏 / 投屏 Cast / 更多（实证） | 已看/收藏✅、DLNA 投屏✅（S19） | 部分（Chromecast 省略） |
| | 预告片按钮 + 播放/版本下拉（实证） | 无 | 缺 |
| 内核 | 默认 ExoPlayer + MPV 可选 / 长按切换（实证） | 单 media_kit/libmpv | 部分 |
| | 硬解 / 软解（解码 Auto）（实证） | 硬解已验、软解 UI 缺 | 部分 |
| | 直连 / 转码协商（实证） | ✅ 四级回退 | — |
| | 缓存 / 缓冲大小可调（web） | 无 | 缺 |
| | HDR10 / 音频直通（**待确认**，无独立开关） | 待验 | 双方待验 |
| 交互 | 手势 亮度/音量/进度（web） | 仅滑块 | 缺 |
| | 倍速 inline ±（实证） | 无 | 缺 |
| | 截图 / 锁定 / 旋转 / 画面比例（实证） | 无 | 缺 |
| | PIP 画中画（实证） | 无 | 缺 |
| | 上/下一集 + 连续播放保持版本轨道（实证+web） | 无 | 缺 |
| | rewind/ffwd + seek + 时间（实证） | seek 有 | 部分 |
| | 定时关闭 / 媒体信息 / 音量增益（实证） | 无 | 缺 |
| | 缩略图预览 / 跳过片头片尾（web，需服务端） | 跳过片头片尾✅（S12 章节） | 部分（Trickplay 缩略图省略） |
| 字幕 | 内嵌 + 外挂选择（实证） | 内嵌✅、外挂下载缺(B6) | 部分 |
| | 添加本地字幕（实证） | 接口预留 externalPath | 部分 |
| | 字体 / 缩放 / 偏移 / 描边 / 阴影（实证） | 无 | 缺 |
| | ASS / PGS 渲染（实证·PGS 拉伸/ASS 黑边开关） | PGS 待验 | 部分 |
| | 字幕/音轨语言偏好 + 播放中切换（实证+web） | 音轨✅、偏好/面板缺 | 部分 |
| 弹幕 | DandanPlay API 仅中文（实证） | 无 | 缺 |
| | 热力图/手动匹配记忆/简繁/合并/行数上限/字体/倍速同步（实证） | 无 | 缺 |
| 外观 | MD3 + Monet（Android12+，Pro）（实证） | 基础 Material | 缺 |
| | 多主题（Pro）/ 夜间模式 / 语言（实证） | 无 | 缺 |
| | 手机 / 平板自适应（web） | 网格自适应、无平板布局 | 部分 |
| 其他 | 备份 / 还原、同步（实验）（实证） | 无 | 缺 |
| | 图片缓存 / 忽略 SSL / 跳过启动(Pro)（实证） | 部分 | 部分 |
| | 基础音乐（专辑/演员）（实证） | 视频客户端、范围外 | 范围外 |
| | 离线下载（**实证·设置无下载区 → 不支持**） | 无 | 不对齐 |

> **收口对照（2026-11-12）**：上表为调研阶段快照，多数「缺/部分」行已在 §12 执行记录中落地
> （手势 S1、倍速 S2、字幕样式 S4、轨道偏好 S5、搜索 S6、详情 S7、收藏写 S8、库子 tabs S10、
> 缓存/硬解 S13、Monet/多主题/夜间 S14、平板 S15、播放器杂项 S16、弹幕 S17、PIP S18、DLNA 投屏 S19、
> 多服务器 S20、LiveTV S21、备份 S22、mpv 高级 S23、管理员 S24、竖屏 S26、章节跳过 S12，及 P1
> 首页/胶囊导航/连续播放/库增强/主题模式）。**仍为有界省略**：Chromecast（需 Google Cast SDK）、
> Trickplay 缩略图（需服务端文件）、隐藏媒体库、PGS 拉伸、Anime4K（需 GLSL）、弹幕热力图/简繁/手动
> 匹配记忆、i18n、合集子路由、HDR10/音频直通（双方待验）、ExoPlayer 第二引擎（决策单 MPV）、
> 基础音乐（范围外）、离线下载（Yamby 不支持）。以 §12 为准。

## 4. 实证修正记录（相对 web 调研）

1. **离线下载**：设置无下载区 → 判定不支持，移出对齐清单。
2. **HDR10 / 音频直通**：MPV 设置仅"解码 Auto / 强制立体声"，无独立 HDR / 直通开关 → 维持待确认，不臆断。
3. **主内核**：默认 ExoPlayer，MPV 为可选 / 长按切换 → 本项目"单 MPV"决策不受影响，双内核降级为可选。
4. **新增确认**：首页 dashboard、胶囊导航、投屏 Cast、预告片、版本下拉、截图 / 锁定 / 旋转、
   定时关闭 / 媒体信息 / 音量增益、备份还原 / 同步、Anime4K / gpu-next / deband / YUV420、
   PGS 拉伸 / ASS 黑边、弹幕来源 = DandanPlay。

## 5. 架构约束与决策

沿用 [契约 v1.1](contracts/emby-client-contract-v1.1.md) 与 README 硬约束：

1. 播放内核一律封装在 `PlaybackEngine`（`lib/data/playback/playback_engine.dart`）后；
   features 不得 import media_kit / dio（`tool/check_layering.sh` 强制）。
2. 所有 API / 媒体 URL 来自同一 `ResolvedEndpoint`；LAN 视频不转码（允许音频单独转码）。
3. **单 MPV 决策**：不引入 ExoPlayer 第二引擎；Yamby 的"双内核 / 长按切换"降级为可选项，默认不对齐。
4. 新增能力（手势 / 倍速 / 字幕渲染 / 弹幕 / 主题 / 缓存）需补 **契约 v1.2 增补**，至少覆盖：
   `PlaybackEngine` 新增 `setRate` / 截图 / mpv 选项透传；字幕 DeliveryUrl 与缓存；弹幕数据源与匹配；
   收藏 / 观看写接口；首页 / 搜索 / 筛选查询参数。
5. 平台特定能力（亮度 / PIP / Monet / Cast）仅 Android 生效，Windows / macOS 降级或隐藏入口。

## 6. 移植计划（切片 ≈1h，自带 unit/widget 测试 + analyzer + 分层守卫）

### P0 播放器交互 + 字幕 + 发现核心

- **S1 手势层**：左竖滑亮度、右竖滑音量、横滑进度预览。
  落点 `lib/features/player/` 手势覆盖层；亮度平台通道放 `lib/core/`（需 `screen_brightness` 插件）；
  音量复用 `engine.setVolume`、进度复用 `controller.seekTo`。验收：三手势跟手、贴边留余量。
- **S2 倍速**：`PlaybackEngine.setRate` + media_kit `setRate` + 控制条 inline ± 菜单。
- **S3 字幕 B6 外挂**：DeliveryUrl 下载 + 缓存，经 `selectSubtitleTrack(externalPath:)` 挂载。
- **S4 字幕渲染**：mpv `sub-font/sub-scale/sub-delay/sub-border/sub-shadow` 透传 + 设置项；ASS/PGS 实测。
- **S5 轨道偏好 + 面板**：语言偏好存储 + 播放中音轨 / 字幕选择面板 + 自动匹配。
- **S6 搜索页**：新 `lib/features/search/`，复用 `searchByTitle`；类型 chips + 历史网格。
- **S7 电影详情页**：新 `lib/features/detail/`；补 People/Overview/Tagline/评分/分级字段；
  hero + 演员行 + 预告片 + 版本下拉 + 已看 / 收藏（依赖 S8）。
- **S8 收藏 / 观看写**：`FavoriteItems` / `PlayedItems` 写 + 收藏 tab（类型 tabs + 筛选排序）。

### P1 首页 dashboard + 库增强 + 连续播放 + 外观

- **S9 首页 dashboard**：横幅轮播 + 库卡片 + 继续观看行（`Filters=IsResumable`）+ 按库行 + 胶囊导航。
- **S10 库内子 tabs**：继续/合集/类型/标签/收藏 + 筛选/排序/视图/随机；补 genres/tags/collections 查询。
- **S11 连续播放**：上/下一集 + 保持上一集版本 / 轨道选择（controller 播放列表）。
- **S12 缩略图预览 + 跳过片头片尾**：Chapter/Trickplay 图 + intro/credits 标记（需服务端）。
- **S13 缓存配置 + 媒体信息**：demuxer cache 参数 + 设置项；MediaStreams 信息面板。
- **S14 主题**：MD3 + Monet（`dynamic_color`）+ 多主题预设 + 夜间模式。
- **S15 平板自适应**：响应式网格 / master-detail。
- **S16 播放器杂项**：截图 / 锁定 / 旋转 / 画面比例 / 定时关闭 / 音量增益。

### P1+ 竖屏观看优化（新增，2026-11-11 用户提出）

- **S26 竖屏播放布局**：当前播放页为全屏 Stack + 视频 contain，竖屏时视频 letterbox 居中、
  控制条/字幕带按**屏幕**高度计算会错位。优化为：竖屏时视频置顶 + 下方信息/控制区（标题、进度、
  轨道、简介），字幕带改按**视频**高度定位（mpv `sub-pos` 百分比而非屏幕像素 `sub-margin-y`），
  竖屏手势/弹幕/缩略图适配；横屏保持现有全屏 + 字幕带。参照 Yamby 竖屏详情/播放形态。

### P2 服务端 / 平台 / 大未知（先裁决再排）

- **S17 弹幕**：DandanPlay 匹配 + 拉取 + 渲染 overlay + 热力图 / 简繁 / 行数 / 字体 / 倍速同步。
- **S18 PIP**：Android 画中画平台通道。
- **S19 投屏 Cast**：DLNA / Chromecast。
- **S20 多服务器**：多会话存储 + 切换器。
- **S21 Live TV**：直播 API + 播放。
- **S22 备份 / 还原 + 同步**。
- **S23 MPV 高级**：Anime4K / gpu-next / deband / YUV420（mpv setOption，可选）。
- **S24 管理员 + STRM 验证**。
- **S25 HDR / 直通 / PGS 实测**：并入 M2-W / M3，不重复立项。M3 自编译 libmpv 需补
  `truehd` / `hdmv_pgs_subtitle` 解码器（S27 实证自带白名单缺失，STRM 无法服务端回退）。

## 7. 依赖与风险

- **新插件 / 库**：`screen_brightness`、`dynamic_color`；Cast 需 DLNA/Chromecast；弹幕需 DandanPlay 匹配算法。
- **服务端依赖**：缩略图 / 跳过片头 / LiveTV / STRM / 快速跳转（管理员）需服务端开启，先探测再排期。
- **平台**：PIP / 亮度 / Monet 仅 Android；Cast 跨平台难。
- **架构红线**：内核改动只落 `lib/data/playback/`；features 不 import media_kit / dio。
- **最大未知**：弹幕匹配准确率与倍速同步；Anime4K 在移动端的性能开销。
- **Pro 项**工作量计入但不设付费墙。

## 8. 与现有路线图映射

- S3/S4/S5 ⊂ 既有 **B6 字幕**；S7 ⊂ **F3 tail 详情页**；S6/S8 ⊂ 既有搜索 / 收藏待办。
- S25 ⊂ **M2-W / M3**（Windows / WAN / PGS / HDR）。
- S9/S10 与 **F2 媒体库页** 演进衔接；S11 与 **剧集选季** 衔接。
- 不重复立项：凡已在本项目待办内的，直接扩展而非新建。

## 9. 验收与测试策略

- 每切片：unit + widget 测试、`flutter analyze`、`tool/check_layering.sh` 全绿方可交付。
- 规模 / 性能以普通 unit/widget 测试承载，不建专用 benchmark _bin_ / 设备腿。
- 必须真机的（亮度手势 / PIP / HDR / 弹幕观感）按隐私规则交用户手动走，agent 抓服务端 / 本包证据。
- 视觉对齐以 Yamby 参考帧判定"像不像"，不以测试绿灯代替。

## 10. 未决项（需用户裁决）

1. 弹幕是否优先（头号卖点但工作量 / 未知最大）？默认 P2。
2. 双内核是否对齐？默认**否**（单 MPV）。
3. 首页 dashboard 是否纳入 P1 首位（视觉差距最大）？
4. Pro 项（主题 / Monet / 多服务器）对齐范围与顺序。
5. 音乐 / 专辑 / 演员是否纳入（当前为视频客户端，默认范围外）。

## 11. 参考来源

- Play 商店描述（`com.hush.yamby`）、V2EX 开发者发布帖、CSDN / Telegram 更新日志、评测站（软鉴 / 小众 / catcat）。
- 设备实证：用户 Mi 10（Android 16），17 屏，仅 Yamby 前台；原始截图本地留存、不入库。

## 12. S1 执行记录（2026-11-11）

- 交付：手势层（左亮度 / 右音量 / 横进度预览，跟手、贴边 16dp、松手单次 seek）+ application 级亮度服务
  （`screen_brightness` 2.1.11）+ 接入播放页；时间格式化抽至 `playback_time.dart`。
- 质量门：analyze 干净、`check_layering.sh` ok、全量 689 测试通过。
- 真机证据（Mi 10，本包 logcat 脱敏上报）：`/Sessions/Playing` DirectPlay；多次横滑各产生一次即时
  `/Sessions/Playing/Progress`（位置 3357.7–3438.6s 跳变）；退出 `Stopped` 干净；无崩溃 / 无 MissingPlugin。
- 真机发现并修复的两个缺陷（S1-fix）：
  1. **浅色模式下亮度 / 进度 / 音量条看不清** → 播放页覆盖层强制深色玻璃
     （`buildGlassTheme(Brightness.dark)`），手势指示器 `GlassSurface(brightness: dark)`。
  2. **播放时字幕被常驻控制条遮挡** → 控制条闲置 3s 自动隐藏、点按视频切换、交互续期
     （`IgnorePointer` + `AnimatedOpacity`），隐藏时露出字幕区（对齐 Yamby 自动隐藏）。
  3. **字幕位置不佳** → 参照 Yamby 实测（底部字幕行约在屏高 94–95%、控制条最低行停在其上方）：
     底部 ~8% 留作**字幕带**，字幕固定距底 ~5%（mpv `sub-margin-y`，引擎新增
     `setSubtitleBottomMargin` → `NativePlayer.setProperty`），控制条整体上移到字幕带之上；
     控制条显示/隐藏字幕都不被遮、不跳动。
- 修复测试：自动隐藏 / 点按复显、浅色下覆盖层为深色玻璃、tap 与 drag 区分、指示器深色、字幕带边距、
  竖屏布局；harness 在长 pump 后复显控制条以免误伤既有用例。
- **S26 竖屏布局已落地**：引擎快照带 `videoWidth/Height` → 竖屏按真实宽高比 `AspectRatio` 视频置顶 +
  控制条下移到视频下方 + 可滚动信息 sheet（标题/简介）；竖屏字幕边距改视频盒内小间距。
  修复了竖屏字幕脱离视频、落到屏幕底黑边的问题。
- 真机复验（用户授权两 App 对比截屏）：浅色可读 ✔；竖屏对照 Yamby `port01`——视频置顶、字幕在视频内
  底边（`our04`）、控制条在视频下、信息 sheet 在下 ✔；横屏字幕带 ✔。首轮调研漏拍竖屏播放，已补。
- **S2 倍速已落地**：`PlaybackEngine.setRate` + controller `rate` 状态 + 控制条 inline −/倍速/+ 步进与
  预设菜单（0.5–3.0x），横竖屏控制条均带；真机点 + 由 1.0x→1.25x 生效（`our05`），widget 测试覆盖
  步进与菜单。
- **S3 字幕 B6 外挂已落地**：`SubtitleRepository`（§3.7）优先 `DeliveryUrl`（相对→会话端点解析、绝对保留
  host），缺省回退 `/Videos/{item}/{source}/Subtitles/{index}/Stream.{ext}`，`api_key` 仅在缺失时补；
  按 `item_source_index.ext` 落盘缓存（ass/ssa→ass、subrip/srt→srt、pgssub→sup），命中缓存不再请求；
  空字节 / 传输错误 → `subtitleFailed`，`EmbyException` 原样透传，登出拒绝下载。controller
  `selectSubtitle`：关 / 内嵌（mpv 按服务器顺序）/ 外挂（下载后经 `selectSubtitleTrack(externalPath:)`
  挂载）；下载失败只出非致命提示 `subtitleNotice`、视频不中断。播放页新增字幕菜单（关闭 + 逐条
  displayTitle/language/序号）与提示横幅，横竖屏均带；`PopupMenuButton` 丢弃 null 结果，故"关闭"用 −1 哨兵。
  控制条两行布局断点 520→640 以容纳字幕按钮。质量门：analyze 干净、layering ok、全量 723 测试通过
  （新增 repository 18 / controller 8 / widget 5）。真机验证待用户播放含字幕条目复核。
- **S6 搜索页已落地**：`LibraryService.search`（`SearchTerm` + `IncludeItemTypes` + 列表字段，空词不发请求）；
  新 `lib/features/search/`（防抖 300ms、过期应答丢弃、类型 chips 全部/电影/剧集、最近搜索持久化
  `search.history.v1` 上限 8、错误映射 + 401 回登录）；海报卡片抽至 `lib/ui/poster_card.dart` 供媒体库与
  搜索共用（features 互不 import 的分层约束）；媒体库顶栏新增搜索入口，路由 `/search`。
  质量门：analyze 干净、layering ok、全量 746 测试通过（新增 repository 5 / controller 10 / widget 8）。
  真机链路：搜索"冰海战记"→ 第 2 季第 13 集「暗云」→ 外挂 ASS 选择，接 S3 复验。
  真机终验（`our13`）：输入防抖出结果、类型 chips、海报缓存生效、结果→剧集→分集→播放全链路通。
- **S4 字幕样式已落地**：`SubtitleStyle`（font/scale/delay/border/shadow/overrideAss）+ 引擎 mpv 透传
  （`sub-font/sub-scale/sub-delay/sub-border-size/sub-shadow-offset/sub-ass-override`）+ 控制器持久化
  `player.subtitleStyle.v1` + 字幕菜单"字幕样式…"sheet（字体 presets、四滑杆、ASS 覆盖开关、恢复默认）。
  ASS 默认 `sub-ass-override=scale`（保脚本样式、字号生效），覆盖开关切 `force`。
- **S4-fix 两个真机根因（日志实证）**：
  1. media_kit `PlayerConfiguration.libass` 默认 false → `sub-ass`/`sub-visibility` 全关，任何字幕都不渲染；
     此前 `our11` 的"双语字幕"实为片源硬字幕（误判已纠正）。改 `libass: true`。
  2. media_kit 轨道表头部含 `auto`/`no` 伪轨道 → 服务器序号映射整体错两位（选 0 得 auto）；
     字幕/音轨选择均过滤伪轨道。
- **S27 解码能力（真机根因三）**：流浪地球 TrueHD 无声、PGS 不渲染＝自带 ffmpeg 白名单缺
  `truehd`/`hdmv_pgs_subtitle` 解码器（.so configure 串实证）；且全库 STRM（IsRemote）Emby 不转码、
  强制直连，服务端回退不存在。落地：DeviceProfile 音频白名单对齐 + `isDecodableAudioCodec`；
  不可解码音频出 `audioNotice` 横幅、PGS 选择出"当前内核不支持 PGS 字幕"；DirectStream 分支
  （本地片源）优先服务器 TranscodingUrl 而非 Static=true。完整解码器归 M3 自编译 libmpv。
  质量门：analyze 干净、layering ok、全量 757 测试通过。S4 样式真机复验改在 AAC+ASS 条目（冰海战记）。
- **S3-fix STRM 流表过期缺陷（真机发现）**：首验外挂字幕报"字幕加载失败"。根因：STRM 片源 Emby 懒探测，
  播放前 detail 的外挂字幕索引为 0/1，起播探测后重建为 9/10（0/1 变视频/音频）；按旧索引请求
  `Subtitles/0/Stream.ass` 得 200 空体 → 空字节判失败。Mac 预检曾用 Range 得 206 有内容，掩盖了空体
  （预检仪器自身也要怀疑）。修复：`PlaybackPlan.subtitles` 携带 PlaybackInfo 协商流表（探测后权威），
  controller 菜单改从 plan 取流，不再信 detail；repository 回归测试锁定。修复后索引 9 实测 200 / 27,254
  bytes ASS。全量 747 测试通过。
- **S3 真机终验（Mi 10）**：搜索→冰海战记 S2E13「暗云」；菜单外挂条目带（外挂）后缀（修复内嵌/外挂
  同名标签缺陷）；首选下载落盘 `14938_mediasource_14938_9.ass` 27,254 bytes（与服务器实测一致）；
  ASS 双语字幕渲染于视频盒底边（`our11`）；关闭→复选 mtime 不变＝缓存命中无二次下载；播毕退出干净。
  失败路径首验已实证：仅非致命横幅、视频不中断。
- **S27-fix / M3 内核替换（真机终验，彻底解决无声）**：流浪地球 TrueHD 7.1 无声、PGS 不渲染的根因是
  自带 ffmpeg 解码器白名单缺 `truehd`/`mlp`/`hdmv_pgs_subtitle`。先试 mpv-android 官方预编译内核
  （共享 ffmpeg）→ 不兼容：新 NDK 触发 binder 线程 `fdsan` SIGABRT、缺 `libc++_shared.so`、TLS 严格
  校验 + ytdl 默认开，两次真机失败（黑屏/闪退）后回退。改用 **media-kit 自家 `libmpv-android-video-build`
  的 `full` flavor**（v1.1.11 `full-*.jar`，`--enable-decoders` 全解码器）：与稳定 default 内核同
  NDK(android21)/静态 ffmpeg/仅系统依赖/`--disable-gpl --enable-version3`，故无 fdsan/libc++ 风险。
  三 ABI 以 `libmpv.so`+`libmediakitandroidhelper.so` 覆盖 `android/app/src/main/jniLibs/`。
  真机实证：`[engine] audio ao=opensles codec=truehd channels=7.1`、PGS `sid=1 vis=yes`，用户确认
  有声有字幕。内核既已全解码，S27 的 `audioNotice`/`isDecodableAudioCodec`/`kDecodableAudioCodecs`
  与 PGS 拦截提示整体移除（不再有误报），字幕下载失败等真实提示保留；macOS 侧 podspec 本就下载
  video-full。质量门：analyze 干净、layering ok、全量 755 测试通过。M3 自编译仍为可复现长期项。
- **S8 收藏/观看写 + 收藏 tab**：`EmbyHttpClient.deleteJson` + `ApiSession.authorizedDelete`
  （AuthRepository 同 401 登出/错误映射）；`UserItemData.isFavorite`；`LibraryService.favorites/
  setFavorite/setPlayed`。端点：`GET /Users/{id}/Items?Filters=IsFavorite`、`POST|DELETE
  /Users/{id}/FavoriteItems/{item}`、`POST|DELETE /Users/{id}/PlayedItems/{item}`。
  新 `lib/features/favorites/`（类型 tabs + 排序 + 分页 PosterCard 网格），library 页入口。
- **S5 轨道偏好 + 面板**：`TrackPrefs`（音/字幕语言，空=自动，ISO 别名归一 zho/zh→chi）持久化
  `player.trackPrefs.v1`；`PlaybackPlan.audios`；controller `selectAudio/setTrackPrefs` + 起播自动
  匹配（显式选择含"关"不被覆盖）；播放页 `player-track-menu` 强制暗色面板（音/字幕行 + 偏好 chips）。
- **S7 电影详情页**：`MediaItem` 增 tagline/communityRating/officialRating/genres/people/remoteTrailer
  （`Person` 值对象），detailFields 补齐；新 `lib/features/detail/`（hero + 评分/分级/年份/时长/类型
  chips + 简介 + 演员行 + 播放 + 收藏/已看乐观更新 + 版本下拉）；`/detail/:itemId`，电影海报改跳详情
  （剧集/单集不变）；版本经 `playerFor(id, source:)`→`preferredSourceId`→PlaybackInfo `MediaSourceId`；
  预告片仅 remoteTrailer 非空时显示（url_launcher 既有依赖）。
- **P0 收口**：S1–S8 全部落地。质量门：analyze 干净、layering ok、全量 **825 测试通过**。
  S5/S7/S8 为 unit/widget/repository 级验证（用户睡眠期不做真机交互/音量测试）；真机冒烟仅启动不播音。
  P1/P1+/P2（首页 dashboard、胶囊导航、库 tabs/筛选、连续播放、外观、弹幕、PIP/Cast 等）仍为路线图。
- **P1 首页 dashboard + 胶囊导航（2026-11-12）**：`LibraryService.resumable()`
  （`Filters=IsResumable`、`SortBy=DatePlayed` desc）+ `items()` 增 sortBy/sortOrder；新
  `lib/features/home/`（推荐横幅轮播 + 继续观看行[进度条/剩余时长] + 按库海报行/更多）；共享
  `lib/ui/capsule_nav.dart`（首页/搜索/收藏，features 互不 import）；登录后落地改 `/home`，
  search/favorites 挂胶囊。更多暂开未过滤库（LibraryPage 无 viewId 参数，留待库增强切片）。
  质量门：analyze 干净、layering ok、全量 **843 测试通过**。测试级验证 + 启动冒烟（不播音）。
- **P1 连续播放（2026-11-12）**：Episode 起播旁路拉季集表（失败不阻断播放），按 indexNumber 稳定排序
  算上/下一集；`PlayerState.hasPrevious/hasNext/previousEpisodeId/nextEpisodeId/completed`；完成判定
  （ready+曾播放+非暂停/缓冲+position≥duration−500ms）每_item_锁存一次；播放页 prev/next 按钮 +
  完成自动 `pushReplacement(playerFor(id, source:))` 保持版本；TrackPrefs 跨集自动匹配（显式选择按会话
  重置，已记录）。修复 go_router 同路由复用 State 需 `didUpdateWidget` 重建 controller 的关键缺陷。
- **P1 库增强（2026-11-12）**：子 tabs 全部/继续/收藏（`library-tab-*`，继续=resumable、收藏=favorites）；
  排序 GlassDialog（SortName/DateCreated/CommunityRating/ProductionYear + 升降序）；网格↔列表切换
  （`library-view-toggle`）；随机播放（`library-random`，取自当前页，Movie→detail/Series→series）。
  _generation_ 计数防过期响应。边界：继续无分页、随机取自当前页、视图模式不跨重启持久化。
  质量门：analyze 干净、layering ok、全量 **890 测试通过**。测试级验证（不播音/不真机交互）。
- **P1 外观·主题模式（2026-11-12）**：`app.themeMode.v1` 持久化（system/light/dark，默认 system，
  坏值回退）；`ThemeModeController`(AsyncNotifier) 接入根 `MaterialApp.router` 的 themeMode，
  theme/darkTheme 仍 `buildGlassTheme`，玻璃调色板全应用跟随；设置页「外观」ChoiceChips
  （`settings-theme-*`）即时生效、写失败 SnackBar 保留旧调色板；播放页强制暗色不变。
  Monet/MD3/多主题/i18n/平板自适应为 Pro/大型路线图，不在本切片。质量门：analyze 干净、
  layering ok、全量 **908 测试通过**。**P0 + P1 主体收口**；P1+（竖屏深化）/P2（多服务器/LiveTV/
  弹幕/PIP/Cast/备份/HDR 直通等，多需用户裁决或平台能力）仍为路线图。
- **播放详情调试面板（2026-11-12，用户提出）**：`PlaybackEngine.readStats()` → `PlaybackStats`
  （分辨率/视频音频编码/容器帧率/实时帧率 estimated-vf-fps/视频音频实时比特率/网络速度 cache-speed/
  缓存时长/解码与输出丢帧/硬解 hwdec-current/vo/ao/采样率/声道/倍速）；media_kit_engine 以
  `getProperty` 并行读取、缺项降级占位不抛错。播放页控制条新增 `player-stats-menu`（analytics 图标）
  开强制暗色 `_StatsSheet`，1s 轮询实时刷新。控制条单行阈值 640→820 以容纳新按钮（修 8px 溢出）。
  测试：controller 委托 + widget 面板数值/关闭。
- **S16+S13 播放器杂项+缓存/硬解（2026-11-12）**：引擎增 `setVideoRotation/setAspectMode/
  setHwdecEnabled/setVolumeMax/setCacheConfig/takeScreenshot`（mpv `video-rotate`/
  `video-aspect-override`/`keepaspect`/`hwdec`/`volume-max`/`cache-secs`/`demuxer-max-bytes`/
  `screenshot-to-file`）；`PlaybackSettings`（`player.playbackSettings.v1`：hwdec/增益/缓存）共享
  controller 与设置页；播放页 `player-options-menu`(tune) 开暗色选项 sheet（旋转/比例/硬解/增益/
  定时关闭/截图/锁定）；锁定抑制手势与控制条；定时关闭到点暂停。控制条单行阈值 820→880。
- **字幕增强（2026-11-12）**：`SubtitleStyle.useMargins`（ASS 黑边，`sub-use-margins`/
  `sub-ass-use-margins`，旧 JSON 兼容）+ 样式 sheet 开关 `subtitle-ass-margins`；添加本地字幕
  （菜单 -4，`file_picker 13.3.3` 经 `LocalSubtitlePicker` 注入抽象→直接挂载 externalPath，不走
  SubtitleRepository；-5 显示"文件名（本地）"）。PGS 拉伸语义待确认暂不做。
- **S10 剩余（2026-11-12）**：库子 tabs 补 合集(BoxSet)/类型(Movie/Series)/标签(Tags)；筛选
  （genre chips + year）经 `items(genreId/genre/year/tag/includeItemTypes)`；`collections()/
  genres()/tags()` 新查询（`/Genres`、`/Tags`、`IncludeItemTypes=BoxSet`）。BoxSet 暂跳详情
  （无合集子路由）；genres/tags 为服务端全局。质量门：analyze/layering 干净、全量 **991 测试通过**。
- **S26 竖屏深化（2026-11-12，P1+）**：竖屏视频置顶 AspectRatio 盒（snapshot 宽高，16:9 兜底，
  上限 60% 高保控制可达）+ 下方可滚信息/控制区（`player-portrait-info`）；字幕带改按**视频盒**高度
  5% 经 `setSubtitleBottomMargin`（横屏仍屏幕 5% 全屏 Stack）；重载重置缓存 margin 修续播/重试
  不重应用缺陷；竖屏手势仅限视频盒（信息区滚动不触发亮度/音量）；控制条增 <520 三行档。
- **S15 平板/宽屏自适应（2026-11-12）**：`lib/ui/responsive.dart`（列数 <600:3/<900:4/<1200:5/else6，
  isWide≥900）；库/搜索/收藏网格与首页行响应式；库 ≥900 master-detail（左网格右 360px 预览，
  点选不跳转，预览含播放/详情）；详情宽屏限宽双栏。播放器不动。
- **S23 mpv 高级（2026-11-12）**：`PlaybackSettings` 增 gpuNext/deband/yuv420（同 blob 向后兼容）；
  引擎 `setAdvancedVideo`（`vo=gpu-next/gpu`、`deband=yes/no`、`vf=format=yuv420p/''`）；起播应用 +
  选项 sheet「高级」三开关（`adv-*`）即时生效。Anime4K 需外部 GLSL shader 暂不做。
- **S22 备份/还原（2026-11-12）**：`BackupService` 导出/导入白名单偏好 JSON
  （subtitleStyle/trackPrefs/playbackSettings/themeMode/searchHistory；**不含凭据**，restore 校验
  version/未知键/类型后才写）；`BackupFilePicker` 注入抽象（file_picker saveFile/pickFile）；
  设置页「备份/还原」（`settings-backup-export/restore`）。质量门：全量 **1042 测试通过**。
- **S14 Monet+多主题（2026-11-12）**：`buildAppTheme(brightness,{accent})` 以 accent 替换品牌 seed；
  `app_accent.dart` 6 预设；`AccentController`（`app.accent.v1`={mode:default|preset|monet,preset}）；
  `dynamic_color ^1.9.0` 仅 Android 且 Monet 开时挂 DynamicColorBuilder 取系统强调色，否则回退
  预设/默认；设置外观 accent chips + Monet 开关。夜间模式沿用 S14 前已有 themeMode。
- **S18 Android PIP（2026-11-12）**：Manifest `supportsPictureInPicture`；MainActivity MethodChannel
  `media_player/pip`.enterPip（API≥26，16:9 Rational，IllegalStateException→false）；
  `core/device/pip.dart` PipController 注入（Android MethodChannel/其余 Noop）；播放选项 sheet
  Android-only `player-pip` 按钮 + 失败 SnackBar。Kotlin compileDebugKotlin 通过。
  质量门：全量 **1102 测试通过**。
- **S20 多服务器（2026-11-12）**：`ServerDirectory`（`servers.v1` 非密 name/lan/wan+activeId）+
  `ServerSessionService`（AuthRepository 实现，按 serverId 存取安全会话；`default` 复用原
  mp.token/session/profile 键，其余追加 `.<id>`，legacy 迁移不搬 token）；设置「服务器」切换/添加/
  删除，登录按目标 server 建表单；restore-first 启动恢复上次活跃服务器。单活跃会话不变。
- **S17 弹幕（2026-11-12）**：`DandanPlayClient`（search/episodes + comment/{id}，p 字段
  time,mode,color,size；超时/红acted 日志/失败→DandanPlayException）+ `DanmakuRepository`
  （电影按标题、单集按剧名+indexNumber 匹配；非致命边界、按 item 内存缓存）；`DanmakuOverlay`
  位置驱动前向 spawn、共享 Ticker 仅播放累时（暂停冻结/回seek清道）、scroll 8s/speed、mode4/5
  置顶/底（字幕带上）、密度/不透明度/上半/全屏、IgnorePointer 层级在视频上控制/字幕下；
  `player.danmaku.v1` + 选项 sheet 弹幕区。热力图/简繁暂不做。质量门：全量 **1185 测试通过**。
- **S21 Live TV（2026-11-12）**：`LiveTvRepository`（`/LiveTv/Channels?AddCurrentProgram=true`、
  `/LiveTv/Programs?ChannelIds`；404→"服务器未开启直播"）；直播页（频道 logo/号/当前节目+进度）
  点频道→playerFor(channelId)；PlaybackInfo 类型无关（AutoOpenLiveStream）直连/转码直播流已验；
  首页 `home-livetv` 入口。EPG 数据层有、独立屏暂不做。
- **S24 管理员（2026-11-12，只读）**：`AdminRepository`（`/System/Info`、`/Users`、`/Sessions`、
  `/Users/{id}` 取 Policy.IsAdministrator 门禁）；管理页（服务器信息/用户/活跃会话+无权限态），
  设置 admin-only 入口 `settings-admin`；不做破坏性操作（刷新库/重启等省略）。
- **S12 跳过片头片尾（2026-11-12，章节）**：`Chapter` 模型 + `MediaItem.chapters`；detailFields 增
  `Chapters`；纯函数 `resolveChapterSkip`（名称匹配 intro/opening/片头/OP、credits/ending/片尾/ED，
  短 token 整词匹配避免 operation/edited 误判；仅分集启用位置兜底：首章≤5s 为片头、末章≥80% 为片尾；
  电影仅名称匹配避免场景标记误跳；片头触及片长则拒绝）；控制器 `canSkipIntro/canSkipCredits` 随
  position 实时判定 + `skipIntro()`（seek 到片头末）/`skipCredits()`（seek 到片长触发完成→自动连播）；
  横竖屏悬浮跳过按钮（`player-skip-intro/credits`，锁定隐藏）。**缩略图预览（Trickplay）省略**：
  需服务端 trickplay 文件，非普遍可用。质量门：全量 **1259 测试通过**。
- **S19 投屏 Cast（2026-11-12，DLNA）**：`data/cast/`（`DlnaDevice` + `DlnaCastService` 抽象 +
  `DlnaCastServiceImpl`，注入 `DlnaTransport`：SSDP M-SEARCH 解析、设备描述 XML 取 friendlyName +
  AVTransport controlURL（相对路径解析、实体反转义）、SOAP SetAVTransportURI/Play/Stop/Pause（URL 与
  DIDL 标题 XML 转义）；`IoDlnaTransport` 用 RawDatagramSocket + HttpClient，M-SEARCH 响应为单播故
  无需 MulticastLock）；控制器 `discoverCastDevices/castTo/stopCast`（cast URL 保证带 api_key，
  投屏后暂停本地避免双声；失败为 picker 文案非播放错误）；选项 sheet `player-cast` → 设备 picker
  （`player-cast-sheet/device-*/stop/refresh/empty`，挂载后帧回调启动扫描避免 build 期通知）。
  **Chromecast 省略**（需 proprietary Google Cast SDK）；Android MulticastLock 加固列为后续。
  真机渲染器投屏验收待用户硬件。质量门：全量 **1279 测试通过**。
  质量门：全量 **1238 测试通过**。
- **S28 首页/库卡复刻（2026-11-12）**：数据层 `LibraryView.imageTag/itemCount`、`MediaItem` 增
  `backdropTags/parentBackdrop*/status/endDate/studios/externalUrls/remoteTrailers/dateCreated`、
  `UserData.unplayedItemCount`、`MediaSource.size`、`MediaStream` 详情字段；`imageUrl` 支持
  `type/index`（Backdrop）且缓存键带 variant；`library.serverName()`（`System/Info/Public`）、
  `library.similar()`（`/Items/{id}/Similar`）；列表字段补 `CommunityRating,Genres,Status,EndDate`。
  首页改为 Yamby 版式：顶栏（头像服务器快切/服务器名/设置/服务器页）、横幅评分·类型·年份胶囊、
  「媒体库」横条（库图+最新海报+数量角标）、继续观看 16:9 卡（剩余时长胶囊+进度条+年份）、
  库行评分/未看角标、悬浮胶囊导航；`/library?view=` 直达库、新增 `/servers` 页、设置「媒体」分组。
  质量门：analyze 干净、layering ok、全量 **1295 测试通过**。真机首页已复核（与 Yamby 同屏对照）。
- **S29 详情页复刻（2026-11-12）**：详情页改为 Yamby 版式：全宽剧照 hero（返回/标题/已看/收藏/更多
  浮层）、评分+分级+年份+时长行、类型 chips、「当前轨道」视频/音频/字幕行（PlaybackInfo 首版本流）、
  带续播进度填充的「继续 (剩余: …)」播放按钮 + 版本下拉、标语/简介/导演、演职人员（角色+类型）、
  艺术图横排（Backdrop 列表）、工作室、外部链接（IMDb/TMDb/Trakt，经 url_launcher）、推荐（Similar）、
  媒体信息（容器/体积/添加时间 + 每路流字段卡）。质量门：analyze 干净、layering ok、全量 **1295** 测试通过。
- **S30 播放器横屏复刻（2026-11-13）**：按 Yamby 实测重排横屏控制层：顶部渐变条（圆形返回 + 标题/直连状态 +
  画面比例快捷菜单 / 投屏 / 更多）、左侧竖栏（截图 / 锁定）、右侧竖栏（− / 倍速 / +）、中央大号
  上一集/播放暂停/下一集、底部渐变条（`(年份) 标题` + 音轨/字幕/播放详情入口、全宽进度条、时间 + 音量）。
  续播提示与字幕提示移入顶部区域；`PlayerState.productionYear` 供底部标题使用。
  质量门：analyze 干净、layering ok、全量 **1295** 测试通过；真机横屏截图与 Yamby 对照（控制条区域一致）。
- **S31 媒体库页复刻（2026-11-13）**：AppBar 标题改为当前库名（全部/类型/标签 tab 显示所选库），操作收敛为
  搜索/收藏/刷新/求片/设置；标签页顺序对齐 Yamby（全部/继续播放/合集/类型/标签/收藏）；新增工具行
  `N 项` + 全屏浏览 + 筛选 + 网格↔列表 + 随机 + `排序 字段 ↑/↓`（排序入口从 AppBar 移入工具行）；
  海报卡补评分角标、未看集数角标与年份范围（`2004 - 现在`）；全屏模式隐藏 AppBar 并保留浮动退出按钮。
  默认排序也对齐 Yamby 的「创建日期 ↓」（`LibrarySort.dateAdded` 默认、标签改为「创建日期」）；
  质量门：analyze 干净、layering ok、全量 **1298** 测试通过（新增 3 个库页测试）；真机库页截图对照通过。
- **S32 设置·通用（2026-11-13）**：设置新增「通用」分组（放在备份/还原之后以不改动既有测试布局）：
  「图片缓存」→ 独立页（显示磁盘占用 `PosterCache.sizeBytes()`、确认后 `clear()`）；
  「媒体库」→ 独立页（每个库一个可见性开关，写 `app.hiddenLibraries.v1`）；
  「忽略 SSL 证书错误」开关（写 `app.ignoreSsl.v1`，bootstrap 读取后给 Dio 配 `badCertificateCallback`，
  重启生效并在提示中说明）。隐藏库同时从首页条/行与库页 chips 过滤；若全部隐藏则回退全量避免死路。
  `HomeController`/`LibraryController` 均先 await 隐藏列表再加载，冷启动不闪出隐藏库。
  质量门：analyze 干净、layering ok、全量 **1301** 测试通过（新增 2 个设置测试 + 1 个库页过滤测试）；
  真机验证：通用分组、图片缓存页（显示 145.8 MB）、媒体库可见性页；关闭「儿童动画」后首页横条即时隐藏，
  重新打开后恢复（截图 docs/screenshots/s32-*.png）。
- **S33 播放器设置 + MPV 设置（2026-11-13）**：`PlaybackSettings` 增 `seekOnDrag`（拖拽进度条快速跳转，
  拖动时每 ~200ms 跳一次）与 `autoPlayNext`（自动连播，默认开，关后播完停留本集）；新增「播放器」页
  （交互开关 + 音轨/字幕语言偏好，写 `player.trackPrefs.v1`，下次播放自动匹配）与「MPV 播放器」页
  （GPU-Next/去色带/强制 YUV420P，写同一 `PlaybackSettings` blob）；`TrackPrefs` 提取共享 `storageKey`，
  设置页与播放器控制器共用。设置页新增「播放器」分组两个入口（追加在末尾，不打乱既有布局）。
  质量门：analyze 干净、layering ok、全量 **1306** 测试通过（新增 3 个设置页测试 + 2 个播放器行为测试）。
- **S34 搜索类型扩展（2026-11-13）**：`SearchFilter` 增 合集/演员，类型 chips 变为 全部/电影/剧集/合集/演员；
  全部 = `Movie,Series,BoxSet,Person`。新增 `LibraryService.collectionItems(ParentId)` 与
  `itemsByPerson(PersonIds)`；新 `lib/features/browse/browse_pages.dart`：合集详情页与演员作品页（复用海报网格、
  评分/年份/已看角标）；搜索命中的 BoxSet/Person 分别跳转各自页面。专辑/音乐仍为范围外。
  质量门：analyze 干净、layering ok、全量 **1311** 测试通过（新增 3 个搜索页测试 + 1 个控制器 + 1 个仓库测试）。
- **S35 收藏页复刻（2026-11-13）**：类型 tabs 扩为 全部/电影/剧集/合集/演员（带类型图标）；新增工具行
  `N 项` + 网格↔列表 + `创建日期 ↓`（排序从 AppBar 移入，支持升/降序对话框）；默认排序改为创建日期降序；
  海报卡补评分/未看/年份角标；列表视图新增紧凑行；空态加心形图标；合集/演员条目分别跳合集页/演员页。
  质量门：analyze 干净、layering ok、全量 **1314** 测试通过（新增 3 个收藏页测试）。
- **S36 弹幕默认设置页（2026-11-13）**：`DanmakuSettingsController`（读写 `player.danmaku.v1`，与播放器共用）；
  设置 → 播放器 → 弹幕：启用开关、密度、不透明度、速度、全屏显示四项，滑块/开关即写即存；
  下次播放生效。路由 `/settings/danmaku`。
  质量门：analyze 干净、layering ok、全量 **1317** 测试通过（新增 2 个弹幕设置页测试 + 1 个设置入口测试）。
- **S37 详情页轨道选择（2026-11-13）**：详情页「当前轨道」的音频/字幕行变为可点选（sheet：默认/各流/关闭）；
  选择写入 `DetailState.selectedAudioIndex/selectedSubtitleIndex`（服务器流序号，字幕 -1 = 关闭），随播放路由
  `?audio=&subtitle=` 传入播放器；播放器在协商完成后把服务器流序号翻译为轨道列表位置再调用
  `selectAudio/selectSubtitle`（避免序号与列表位置混用），显式选择覆盖语言自动匹配。
  质量门：analyze 干净、layering ok、全量 **1318** 测试通过（新增端到端详情→播放器轨道用例）。
- **S38 详情页投屏（2026-11-13）**：`PlaybackPlan.castUrl` 抽出「URL 必带 api_key」逻辑（播放器与详情共用）；
  详情 hero 新增 Cast 按钮 → `DetailCastSheet`（DLNA 发现、按需协商当前条目的流、投屏/停止/失败文案），
  未注入 cast 服务时不显示入口；测试用 FakeDlnaCastService 覆盖协商 + 投屏 + 停止。
  质量门：analyze 干净、layering ok、全量 **1319** 测试通过。
- **S39 收藏筛选/全屏（2026-11-13）**：`favorites()` 增 `genre`/`year` 查询参数（`Genres`/`Years`）；收藏页工具行
  新增 全屏浏览（隐藏 AppBar + 浮动退出）与 筛选（类型 chips 来自 `/Genres` + 年份输入，应用/清除），
  已选条件以可删除 chip 展示；`FavoritesController` 增 `applyFilters/loadGenres` 与缓存。
  质量门：analyze 干净、layering ok、全量 **1322** 测试通过（新增筛选/全屏用例 + 控制器筛选用例）。
- **S40 播放器横屏细节 + 详情已播放态（2026-11-13）**：按 Yamby 横屏实测把中央传输区改为「−10s / 播放暂停 /
  +10s」，上/下一集移到左下（标题左侧）；时间移到进度条左侧；详情页播完的条目按钮显示「已播放」
  （点击仍从头播放）。质量门：analyze 干净、layering ok、全量 **1323** 测试通过（新增 ±10s 跳转用例）。
- **S41 MPV 设置补充（2026-11-13）**：按 Yamby「MPV 播放器」页补充：强制输出立体声（`PlaybackSettings.forceStereo`，
  引擎写 mpv `audio-channels=stereo/auto`，默认开）；字幕描边 / 字幕阴影偏移两条全局滑块
  （`SubtitleStyleSettingsController` 读写 `player.subtitleStyle.v1`，与播放页字幕样式面板共用），下次播放生效。
  质量门：analyze 干净、layering ok、全量 **1325** 测试通过（新增 MPV 设置页与引擎应用用例）。
- **S42 截图设置（2026-11-13）**：新增「播放器 → 截图」页：截图时暂停视频（`player.screenshot.v1`，控制器在
  `takeScreenshot` 内pause→截图→resume，失败也会恢复播放）；保存位置展示（应用文档目录/screenshots，
  `AppServices.screenshotDirectory` 由 bootstrap 解析，测试里为空时回退临时目录）。分享/去黑边/水印暂未支持
  （需要 share/图像处理依赖，未擅自引入）。
  质量门：analyze 干净、layering ok、全量 **1327** 测试通过（新增截图设置页与暂停截图行为用例）。
- **S43 弹幕手动匹配记忆（2026-11-13）**：`DanmakuService` 增 `search/applyManual/clearManual/isManual`；
  `DanmakuRepository` 记住「条目 → 手动选的弹幕集数」（`danmaku.manualMatches.v1`，JSON），下次打开优先用记忆、
  自动匹配不再覆盖；播放页「更多 → 弹幕」新增「手动匹配」按钮 → 弹幕匹配面板（搜索番剧、按集选择、清除记忆）。
  质量门：analyze 干净、layering ok、全量 **1329** 测试通过（仓库记忆复用 + 播放页面板端到端用例）。
- **S44 弹幕热力图（2026-11-13）**：新增 `DanmakuHeatmap`（120 桶，按弹幕密度着色/高度）叠在进度条上方，
  仅在弹幕开启且有评论时出现；横屏/竖屏共用 `_progressSlider` 自动生效。另外把 `store` 接入手动匹配仓库，
  记忆可跨重启保留。DandanPlay 在本机网络返回 403（代理出口被拦），真机弹幕加载失败属环境限制，
  热力图渲染由 widget 测试覆盖。
  质量门：analyze 干净、layering ok、全量 **1330** 测试通过（新增热力图出现用例）。
- **S45 即将上映（2026-11-13）**：媒体库新增「即将上映」tab（排在收藏之后）。列表请求带上 `PremiereDate` 字段，
  按 `PremiereDate` 降序取一页后在客户端过滤「首播时间晚于现在」的条目并按时间升序展示；该 tab 排序固定，
  工具栏显示静态「上映日期 ↑」。Emby 没有「未来首播」服务端过滤，故用客户端过滤实现。
  质量门：analyze 干净、layering ok、全量 **1332** 测试通过（控制器过滤 + 页面 tab 用例）。
- **S46 详情页跳转（2026-11-13）**：类型 chip 可点，跳转 `/library?genre=<类型>`（`LibraryController.preferredGenre`
  初始化筛选、库页显示活动 chip）；演职人员卡片可点，跳转演员页（`/person/:id?name=`）。
  质量门：analyze 干净、layering ok、全量 **1335** 测试通过（新增类型跳转 + 演员跳转 + preferredGenre 用例）。
- **S47 剧集页分集缩略图（2026-11-13）**：`MediaItem` 增 `parentThumbItemId/parentThumbTag`；
  `SeriesController.episodeImage` 优先用剧集级 Thumb（Episodes 的 `ParentThumbItemId`），否则回退自身 Primary；
  分集行改为左侧 16:9 剧照 + 标题/时长/进度条（保留 `ListTile` 以不破坏键盘聚焦）。
  质量门：analyze 干净、layering ok、全量 **1336** 测试通过（新增剧照/进度条用例）。
- **S48 播放器顶栏补齐（2026-11-13）**：横屏顶栏按 Yamby 补上「截图」与「字幕列表」两个入口（字幕菜单复用底部同一
  组件，仅换 key），顶栏现为：截图 / 画面比例 / 投屏 / 字幕 / 更多。
  质量门：analyze 干净、layering ok、全量 **1338** 测试通过（新增顶栏截图与字幕菜单用例）。
- **S49 剧集页 Hero（2026-11-13）**：剧集页顶部新增 190 高的剧照 Hero（系列 backdrop + 黑色渐变），
  叠加标题/评分/年份/类型胶囊；`SeriesController.backdropImage` 复用海报缓存（`series-hero` variant）。
  质量门：analyze 干净、layering ok、全量 **1339** 测试通过（新增 hero 评分/年份/类型用例）。
- **S50 搜索类型多选（2026-11-13）**：搜索页类型由单选 ChoiceChip 改为多选 FilterChip（Yamby 是可勾选多选），
  `SearchState.filters` 集合 + `toggleFilter`：勾选累加、再点取消、全部清空回「全部」；请求 `IncludeItemTypes` 按选中类型拼接。
  质量门：analyze 干净、layering ok、全量 **1339** 测试通过（控制器组合/取消类型 + 页面叠加请求用例）。
- **S51 剧集页播放/续看按钮（2026-11-13）**：Hero 下方新增主按钮，自动选中「有进度且未看完」的分集
  显示 `继续观看 第 N 集`，否则选第一部未看分集显示 `播放 第 N 集`（全部看完回落第 1 集）。
  质量门：analyze 干净、layering ok、全量 **1341** 测试通过（续看目标 + 全看完回落用例）。
- **S52 搜索历史两列卡片（2026-11-13）**：搜索历史改成两列圆角卡片（历史图标 + 词条 + 单条移除 ×），
  右上角「清除全部」；控制器增 `removeHistory`/`clearHistory` 并持久化。顺带修正缺口表详情页若干过时行
  （Hero/简介/艺术图/工作室/外链/推荐/媒体信息均已实现）。
  质量门：analyze 干净、layering ok、全量 **1342** 测试通过（新增历史移除/清空用例）。
- **S53 竖屏播放器选集条（2026-11-13）**：竖屏信息区在控制条下方新增横向「选集」，播放分集时自动拉取该季分集，
  当前集高亮、已看集带 ✓，点选直接在当前播放器内切换（`pushReplacement`，先上报进度）。电影不显示；
  拉取失败只隐藏该条，不影响播放。
  质量门：analyze 干净、layering ok、全量 **1343** 测试通过（新增竖屏选集条用例）。
- **S54 导演链接 + 设备自检脚本（2026-11-13）**：详情页「导演:」一行拆成可点的姓名（有 id 时跳演员页，S54）；
  新增 `tool/device_check.sh`（无设备时明确报错退出 2，设备在线则安装 APK、启动并截首页图），
  缺口文档补「设备核对清单」8 条，覆盖 S42~S53 的待验项。
  质量门：analyze 干净、layering ok、全量 **1344** 测试通过（新增导演链接用例）。
- **S55 服务器页补用户名与添加按钮（2026-11-13）**：`/servers` 页的激活服务器卡片副标题追加当前用户名
  （`地址 · 当前 · 用户名`），并在页面上加悬浮「添加服务器」按钮（`AppPage` 新增 FAB 槽位）。
  质量门：analyze 干净、layering ok、全量 **1345** 测试通过（新增服务器页用户名/FAB 用例）。
- **S56 排序补「上映日期」+ 范围决定落档（2026-11-13）**：库页与收藏页排序菜单各加「上映日期 ↓」
  （`PremiereDate`）；按用户口径记录范围决定：基础音乐不做、不引入新依赖（简繁/Chromecast/i18n 暂缓，
  现有 DLNA 投屏保留）。
  质量门：analyze 干净、layering ok、全量 **1346** 测试通过（新增库页排序上新选项用例）。
- **S57 真机逐屏核对（2026-11-13，设备恢复后）**：安装 S56 APK 后按清单核对——
  - 即将上映：tab 选中、`0 项`、静态「上映日期 ↑」、空态「暂无即将上映的内容」；
  - 类型跳转：详情点「家庭」→ 媒体库出现 `家庭 ×` 活动筛选、`5 项`；
  - 剧集页：Hero（★6.6/2004/动画/儿童）、「播放 第 1 集」、「第 1 季」、带剧照的分集行；
  - 播放器顶栏：截图/画面/投屏/字幕/更多 五入口；中央 ±10s、左下上下集；
  - 搜索：类型多选叠加（电影+剧集同时高亮）、两列历史卡片（单条 × 与「清除全部」）；
  - 竖屏播放分集：控制条下「选集」条、当前集高亮；
  - 服务器页：`地址 · 当前 · test`、悬浮 + 按钮；
  - 排序弹窗：名称/创建日期/评分/年份/上映日期。
  发现待排查：个别片源（超时空辉夜姬）竖屏播放画面呈窄条彩色条纹，Mario 正常；疑似个例片源解码/旋转问题，记为缺陷待查（非 Yamby 对照项）。
  质量门：analyze 干净、layering ok、全量 **1346** 测试通过（本轮仅验证与文档，无代码改动）。
- **S58 真机补充证据 + 渲染异常排查（2026-11-13）**：
  - 剧集页带真实进度：第 2 集有 `已观看 00:27` 与进度条，主按钮变为「继续观看 第 2 集」（S47/S51 实测）；
  - 详情页媒体信息卡真机核对：`超时空辉夜姬！(2026) · 1080p H264`，分辨率 1920x1080、h264 Main、SDR、
    位深 8、色域 bt709、像素格式 yuv420p；音频 eac3 6 声道 5.1、日语（S29 媒体信息）；
  - 个别片源竖屏首帧画面呈窄条条纹的问题：重开同一影片后恢复正常（Netflix 片头正常 16:9），
    判断为「横屏播放结束→竖屏开新播放」时视频纹理尺寸未及时刷新的偶发问题，暂未复现到 100%，记为待排查。
  质量门：analyze 干净、layering ok、全量 **1346** 测试通过（本轮无代码改动）。
- **S58 续（真机补充）**：加载页揭晓两处：
  - 详情页导演行显示为三个可点姓名（山下清吾/木南凉太/山本幸治，S54 实测）；
  - 播放器「更多」弹层里的弹幕区：开关可切换、状态行显示「弹幕加载失败，不影响播放」、
    「手动匹配」按钮存在（DandanPlay 403 仍在，无法进一步验证匹配结果）；
  - 竖屏播放器字幕（ASS 双语）渲染正常，切换片源后画面尺寸恢复正常。
  质量门：analyze 干净、layering ok、全量 **1346** 测试通过（本轮无代码改动）。
- **S59 首帧纹理异常复现与定性（2026-11-13）**：连续复现到「竖屏首帧画面被挤成窄条」——同一时刻视频盒
  仍是全宽（加载中 16:9 占位可见），说明**布局没问题，是 media_kit 纹理在头几秒按错误尺寸呈现**；
  约 30 秒后（或下一帧尺寸同步）自动恢复为正确 16:9。截图 `s59-texture-glitch.png` / `s59-texture-recovered.png`。
  结论：第三方渲染层（media_kit/libmpv 纹理）的首帧尺寸同步问题，属已知类问题；不做侵入式 hack，记为已知限制，
  后续若升级 media_kit 再复测。
  质量门：analyze 干净、layering ok、全量 **1346** 测试通过（本轮无代码改动）。
- **S60 工作室跳转（2026-11-13）**：详情页「工作室」名字改为可点（下划线），跳转 `/library?studio=<id>&studioName=<名称>`；
  `LibraryController` 增 `studioFilterId/studioFilterName` + `clearStudioFilter`，库页显示 `工作室: <名称> ×` 活动 chip；
  Emby 详情载荷不总带工作室 Id，因此请求同时支持 `StudioIds` 与 `Studios`（名称回退）。
  真机验证：点 Studio Colorido → 媒体库 `1 项` + 活动 chip，点 × 恢复 `58 项`。
  质量门：analyze 干净、layering ok、全量 **1348** 测试通过（详情页工作室跳转 + 控制器 studio 种子用例）。

- **S61 搜索结果按类型分区（2026-11-13）**：搜索结果为多类型时按「电影 / 剧集 / 合集 / 演员 / 其他」分区渲染（每区标题 + 区网格），单类型仍是一体网格；结果点击路由抽成 `_openItem`。真机单一类型结果（SPY）确认不会出现多余分区标题。
  质量门：analyze 干净、layering ok、全量 **1349** 测试通过（新增分区与顺序用例）。

- **S62 外观设置页（2026-11-13）**：真机对照 Yamby「设置 → 外观」页（应用图标/自定义加载动画/导航栏替换为悬浮导航栏/自动隐藏/预测性返回动画/启用列表动画）后，落地其中可做的一项：新增「设置 → 外观」页，切换**悬浮胶囊**与**标准底栏**两种导航样式，持久化 `app.appearance.v1`；`AppBottomNav` 改为按设置渲染（标准底栏用 Material `NavigationBar`，三个目的地与图标一致）。
  真机：切换到标准底栏 → 首页底栏变长条并高亮「首页」；切回悬浮胶囊恢复原样。
  质量门：analyze 干净、layering ok、全量 **1350** 测试通过（新增外观页持久化用例）。

- **S63 自动隐藏悬浮导航栏（2026-11-14）**：新增 `app.appearance.v1.autoHideNav`（默认开）与外观页开关；`NavScrollReporter` 监听页面自身（depth 0）竖向滚动，向下滚把胶囊滑出、向上滚或回到顶部时滑回，`AppBottomNav` 用 `AnimatedSlide` + `IgnorePointer` 实现；首页与 `AppPage` 页面都接入了上报。
  真机：首页下滚胶囊滑出（截图为无胶囊状态），上滚恢复。
  质量门：analyze 干净、layering ok、全量 **1352** 测试通过（外观页开关持久化 + 首页滚动隐藏/恢复用例）。

- **S64 服务器在线状态点（2026-11-14）**：`AppServices.endpointProbe` 复用启动时的 `HttpEndpointProbe`；新增 `ServersController.probeOnline()`（逐个 `System/Info/Public` 探测，失败即离线，3s 超时，不影响切换），`ServersState` 增 `online` 映射；服务器列表在每个服务器的图标旁显示绿/灰圆点，进入 `/servers` 页时自动探测一次。
  真机：服务器页显示 `✓ + 绿点`，地址与用户名一行正常。
  质量门：analyze 干净、layering ok、全量 **1353** 测试通过（新增 `FakeEndpointProbe` 与在线点用例）。

- **S65 预测性返回动画（2026-11-14）**：`AndroidManifest.xml` 的 `<application>` 开启 `android:enableOnBackInvokedCallback="true"`，让 Android 14+ 在返回手势中预览上一页；Flutter 侧 `PopScope` 逻辑不变。
  真机：安装后应用正常启动，搜索页按返回键仍正确回到首页（无回归）。
  质量门：analyze 干净、layering ok、全量 **1353** 测试通过（本轮只改 manifest）。

- **S66 自定义加载动画（2026-11-14）**：新增 `lib/ui/app_loader.dart`（`AppLoader` + 4 种纯代码动画：气泡/三点/柱状/圆环），外观页新增「加载动画」选择区（实时预览、选中高亮），偏好存 `app.appearance.v1.loaderStyle`；库页/搜索/首页/详情/剧集/收藏的主加载态改为 `AppLoader`。
  真机：外观页四种样式预览各不相同，切换后列表加载态随样式变化。
  质量门：analyze 干净、layering ok、全量 **1354** 测试通过（加载样式持久化 + 剧集加载态断言更新）。

- **S67 启用列表动画（2026-11-14）**：新增 `lib/ui/list_entrance.dart`（前 12 个格子按索引错峰淡入 + 上移，超出的直接渲染），外观页新增「启用列表动画」开关（`app.appearance.v1.listAnimation`，默认开）；媒体库网格与搜索网格接入。
  真机：外观页开关存在且默认开；关闭后列表直接显示。
  质量门：analyze 干净、layering ok、全量 **1355** 测试通过（新增开关持久化用例；外观页测试补滚动到控件）。

- **S68 首页继续观看分集卡（2026-11-14）**：整屏对照 Yamby 首页后发现差异——它的分集卡主标题是**剧集名**、副标题是 `S1E2：分集名`；我们原来主标题是分集名、副标题是年份。为此 `MediaItem` 增 `parentIndexNumber`/`seriesName`（列表字段补 `ParentIndexNumber,SeriesName`），卡片改为「剧集名 + S1E2：分集名」，电影仍显示年份。
  真机：小猪佩奇卡显示「小猪佩奇 / S1E2：恐龙先生弄丢了」，飞驰人生 3 仍显示年份。
  质量门：analyze 干净、layering ok、全量 **1356** 测试通过（新增分集卡标题/副标题用例）。

- **S69 库页标签顺序 + 每个库记住排序（2026-11-14）**：真机对照发现 Yamby 的「即将上映」紧跟「继续播放」，我们排在收藏后——已按 Yamby 顺序重排；另外 Yamby 每个库各自记住排序（动画电影=创建日期、儿童动画=更新日期），`LibraryController` 新增 `_sortByView` + `_rememberSort/_restoreSort`，切换库时保留各自的排序，未记录过的库默认创建日期 ↓。
  质量门：analyze 干净、layering ok、全量 **1357** 测试通过（新增「每个库保留自己的排序」用例）。
- **S70 排序字段对齐 Yamby（2026-11-14）**：Yamby 的排序弹层有 10 个字段，我们只有 5 个且措辞不同。现统一为：更新日期/最新上线/创建日期/公众评分/标题/首映日期/官方分级/出品年份/影评人评分/播放日期（`DateLastSaved`/`DateLastContentAdded`/`DateCreated`/`CommunityRating`/`SortName`/`PremiereDate`/`OfficialRating`/`ProductionYear`/`CriticRating`/`DatePlayed`），库页与收藏页一致；弹层改为可滚动列表 + 固定升/降序行。
  真机：弹层显示前十项、滚动可见后四项，升/降序固定可见。
  质量门：analyze 干净、layering ok、全量 **1357** 测试通过（排序用例改为先滚动到目标字段）。

- **S71 收藏页工具行对齐（2026-11-14）**：真机对照 Yamby 收藏页——它的工具行是 计数 + 随机播放 + 视图切换 + 筛选 + 排序。我们缺少随机播放，且顺序不同。现补齐：`FavoritesController.randomItem()`（从已加载页随机选一条，注入可测的 `Random`）、工具行按 Yamby 重排并把全屏放末位、空列表时随机按钮禁用。
  真机：收藏页工具行为 0 项 → 随机(禁用) → 视图 → 筛选 → 排序 → 全屏。
  质量门：analyze 干净、layering ok、全量 **1358** 测试通过（新增随机按钮用例）。

- **S72 搜索页对齐（2026-11-14）**：对照 Yamby 搜索页后修两处视觉差异——(1) 类型 chips 选中时显示 ✓ 且未选项为描边样式（原来只有填充变化）；(2) 历史条目的前导图标由「时钟」改为「放大镜」，与 Yamby 一致。
  真机：搜索页「✓ 全部 / 电影 / 剧集 …」与历史条目的放大镜图标均正确。
  质量门：analyze 干净、layering ok、全量 **1358** 测试通过。

- **S73 设置页分组顺序（2026-11-14）**：对照 Yamby 设置页发现「关于」在最底部（我们从最上面开始）。已把「关于 / 更新渠道 / 检查更新」整组移到列表末尾，其余分组顺序保持（服务器 → 外观 → … → 播放器 → 关于）。
  真机：进入设置首屏为「服务器 → 外观」，滚到底部才是「关于」。
  质量门：analyze 干净、layering ok、全量 **1358** 测试通过（设置/装配用例改为先滚动到「关于」再断言）。

- **S74 剧集页 Hero 元数据行（2026-11-14）**：真机对照 Yamby 剧集页——它的 Hero 是两行：`★6.6  TV-G  2004 - 现在  共 1 季` 一行，类型 chips（动画/儿童）单独一行。我们原来把年份和类型混在一行、缺分级与季数。现补齐：元数据行含 ★评分 / 官方分级 / 年份范围 / 共 N 季，类型 chips 移到下一行。
  真机：小猪佩奇 Hero 显示 `★6.6 TV-G 2004 - 现在 共 1 季` + 第二行 `动画 儿童`。
  质量门：analyze 干净、layering ok、全量 **1358** 测试通过（hero 用例补「共 1 季」断言）。

- **S74 剧集页「继续观看」横条（2026-11-14）**：Yamby 在剧集页 Hero 与简介之间有一排横向分集卡（剧照 + `剩余: …` 胶囊 + 进度条 + `S1E2：标题`）。已补齐：`SeriesController` 状态派生未看完且有进度的分集，页面渲染横排卡片，点卡片直接续播；同时 Hero 元数据行改为两行（`★/分级/年份范围/共 N 季` 与类型 chips）。
  真机：小猪佩奇剧集页显示 Hero 元数据两行 + 「继续观看」横向卡片。
  质量门：analyze 干净、layering ok、全量 **1359** 测试通过（新增继续观看横条用例；剧集页/库页用例因新增横条改用了更高的测试视口）。

- **S75 竖屏播放器标题规则（2026-11-14）**：竖屏播放器原来只显示分集名；Yamby 的播放页标题是「剧集名 + `S1E2：分集名`」，与首页卡片（S68）、剧集页（S74）一致。现改为同规则：分集显示剧集名（主）与 `S1E2：标题`（副），电影仍只显示片名。
  真机：小猪佩奇竖屏播放器显示「小猪佩奇 / S1E3：最好的朋友」；横屏顶栏同规则（标题=剧集名、副标题=S1E4：鹦鹉波莉），底部进度条上方也改为 `S1E4：标题`（电影仍是 `(年份) 标题`）。
  质量门：analyze 干净、layering ok、全量 **1359** 测试通过（竖屏选集用例补标题/副标题断言）。

- **S76 服务器页底部导航（2026-11-14）**：Yamby 的服务器页底部保留胶囊导航（首页/搜索/收藏）。已给 `/servers` 加上同一 `AppBottomNav`，当前页高亮「首页」；悬浮添加按钮与列表底部留白同时保留。
  真机：服务器页显示服务器卡（✓ + 绿点 + 用户名 test）、右下 + 与底部胶囊导航。
  质量门：analyze 干净、layering ok、全量 **1359** 测试通过。

- **S77 播放器竖屏/横屏切换（2026-11-14）**：播放器原来完全跟随设备方向（`MediaQuery.orientationOf`），现改为**默认横屏播放**：进入播放页即锁定横屏；横屏顶栏新增圆形「竖屏播放」按钮，竖屏视频盒右上角新增「横屏播放」按钮，切换时同步锁定对应方向，离开播放页恢复系统默认方向（空偏好列表），不影响其他页面。布局由播放模式决定而非设备方向，系统旋转锁定、桌面窗口或分屏下按钮同样生效；界面锁定时按钮与其余控制一起隐藏。新增 `core/device/screen_orientation.dart`（接口 + SystemChrome 实现，桌面/测试端降级为无操作）与 `playerOrientationServiceProvider`（测试注入 fake）。
  质量门：analyze 干净、layering ok、全量 **1365** 测试通过（player_page_test 新增 5 条：默认横屏并锁定、竖屏设备仍默认横屏、切换往返、锁定后隐藏按钮、退出恢复方向；6 条既有竖屏用例改为先点「竖屏播放」）。
  真机（Mi 10 / Android 16 / SDK 36，序列号 8085d06e）：已构建 release 包覆盖安装（0.3.0+7，版本号不变，登录态与数据保留）。继续观看开播即 2340×1080（ROTATION_90）横屏；点横屏顶栏「竖屏播放」→ 1080×2340（ROTATION_0）竖屏；点竖屏视频右上角「横屏播放」→ 回到 2340×1080；系统返回退出播放后恢复 1080×2340 竖屏、media session 结束。截图 docs/screenshots/s77-player-landscape.png、docs/screenshots/s77-player-portrait.png。


- **S78 竖屏播放器复刻 Yamby（2026-11-14）**：竖屏播放器按真机实测 Yamby 竖屏形态重做（参考 screenshots/s78-yamby-player-*.png）：视频盒顶部固定（真实宽高比、16:9 兜底、60% 高度上限），控制层整体覆盖视频（圆形返回 + 剧集 logo/标题 + 截图/画面/投屏/字幕/更多/横屏 6 个圆钮；左列截图/锁定；右列 −/倍速/+；中央 ±10s/播放暂停），视频下 dock 两行（第 1 行半浮视频底边：上一集/下一集/可点标题；第 2 行：时间 + 波浪进度条 + 音轨 + 字幕）。新增自定义波浪进度条（蓝波已看段/灰线/白色滑块，可拖可点，保留 seekOnDrag 节流）、点标题的信息面板（剧照/剧集名/`S1E2：标题`/日期 + 评分[回退剧集]/简介/「集」48% 屏宽横条[当前集波浪线]/「演员」行）与「接下来」浮卡（剩余 <30s 且 hasNext 时右下显示，含剧照、`S1E2：标题`、进度，点击切集）。暂停/简介/选集条/音量滑杆自常驻布局移入面板与「更多」；音量由手势与音量增益承担，媒体信息仍在「更多」。方向随切集保持：`AppRoutes.playerFor` 新增 `portrait` 参数，播放器内切集/自动连播把当前方向传给新路由（真机确认自动连播后仍是竖屏）。
  另补两项对齐：竖屏顶栏用服务端透传 Logo 图替代纯文字标题（`MediaItem.logoTag/parentLogoItemId/parentLogoTag`，无图回退文字，真机小猪佩奇显示剧集 logo）；竖屏字幕带按视频盒高度上移（15%，下限 44dp）并强制 mpv 字幕边距（`PlaybackEngine.setSubtitleMarginsEnabled`），文本字幕可让开 dock 标题行。
  真机（Mi 10 / 1080×2340）：竖屏 layout、logo、dock、波浪进度、信息面板（评分/集/演员）、接下来浮卡、切集保持竖屏、返回剧集页播放按钮不卡死均逐项核对；截图 docs/screenshots/s78-our-player-*.png（与 s78-yamby-player-*.png 对照）。
  质量门：analyze 干净、layering ok、全量 **1428** 测试通过（player_page_test 竖屏组 22 条 + 新增 logo/边距断言）。
  已知差异：ASS 字幕若带显式定位，仍可能压在 dock 标题行上（仅控制层可见的 3 秒内，mpv 边距对其无效）；顶栏比 Yamby 多一个「横屏播放」钮（S77 的项目内入口）。

- **S78 剧集详情页 + 季页复刻 Yamby（2026-11-14）**：剧集页按真机实测 Yamby 版式重写（参考 screenshots/s78-yamby-series-*.png）：全宽 backdrop hero（1.05×屏宽，顶到状态栏下）+ 浮动顶栏（透明→滚动后黑底显示剧集名；无圆底的白色返回/已看/收藏[心形+加号]/更多）；hero 底部渐变上混合元数据胶囊（★浅蓝 + 评分、浅蓝描边官方分级与季数、纯文字年份）+ 深藏青类型 chips（点击进筛选库）；播放行改为 58% 屏宽深灰按钮（浅蓝按观看比例填充、白字）+ 56dp 浅蓝方形选集 chevron，按钮下当前分集 `S1E2：标题`；简介 4 行；「继续观看」横条（从最早有进度分集起最多 4 条，有进度显「剩余: X分X秒」、下一条显时长，卡片 46% 屏宽；标题行 ‹ # › 分页/# 进季页）；「季」横条（季海报 + ChildCount 徽标 + 第 N 季→季页）；「演员」矩形照片卡→演员页；「艺术图」「工作室」（下划线→筛选库）「外部链接」（描边胶囊）「推荐」（similar + 海报卡角标/评分/年份）；底部胶囊导航（进入页面时复位可见）。新增 `/season/:seasonId?series=…` 季页（season_page + season_controller）：同款 hero/浮动栏/年份元数据/播放行 + 「第 N 季」+ 分集卡（16:9 剧照、`1.标题`、时长、2 行简介、已看勾、进度）。数据层：`MediaItem.childCount`（seasons 请求 `Fields=ChildCount`）；`SeriesController` 增 similar/seasonCounts/continueWatchingEpisodes/playTarget/收藏已看忙态与回滚；播放忙态在播放器 pushReplacement 后 1s 兜底解锁并在路由重新可见时刷新，避免返回后按钮卡灰。
  真机（Mi 10 / 1080×2340）：剧集页首屏/季/演员/艺术图/外链/推荐、季页首屏与分集列表、`#` 进季页、季页底部导航均核对；截图 docs/screenshots/s78-our-series-*.png、s78-our-season-top.png。
  质量门：analyze 干净、layering ok、全量 **1428** 测试通过（series_page_test 31 条、season_page_test 18 条、series/season 控制器 47 条）。
  已知差异：Yamby 的「更多」含下载（本项目无下载），我们保留刷新/标记已看；外部链接比 Yamby 多一个 Trakt（服务端数据）。

- **S78 补充：竖屏视频下方信息区（2026-11-14，用户反馈「竖屏播放视频下面的信息全没了」）**：Yamby 把标题/简介/选集收进点标题弹出的信息面板，导致竖屏常驻区域只剩视频与进度坞。按用户要求把信息重新放回视频下方：新增 `player-portrait-info` 常驻区（剧集名 + `S1E2：标题` + 简介 + 「选集」横条，选集自动定位到当前集并高亮、带观看波浪线），不随控制层自动隐藏；dock 第一行原来的标题文字改为「播放详情」圆钮（`player-dock-title` 键保留，点开同一信息面板），既消除 ASS 字幕与标题行的重叠，也避免与下方信息区重复。信息面板（评分/集/演员）保持不变，简介右侧另有 ⓘ 入口。
  真机（Mi 10 / 1080×2340）：竖屏视频下方显示「小猪佩奇 / S1E14：放风筝 / 简介 / 选集（当前集高亮、条带定位到 S1E14）」；控制层隐藏后信息区仍在；ASS 字幕与控制层不再压字。截图 docs/screenshots/s78-our-player-portrait.png、s78-our-player-portrait-idle.png。
  质量门：analyze 干净、layering ok、全量 **1432** 测试通过（新增「视频下方保留标题/简介/选集」「选集条带定位当前集」「信息面板入口」用例）。

- **S79 页面转场淡入淡出 + 加载态补齐（2026-11-14）**：页面切换观感生硬（主题里虽声明了各平台
  `ZoomPageTransitionsBuilder`，但路由层从未用上，见下方真机复核）。改为 `AppFadePageTransitionsBuilder`
  （新 `lib/ui/theme/app_page_transitions.dart`，
  挂到 `pageTransitionsTheme` 的全部平台）：只改透明度，不缩放不位移，推入 320ms / 返回 260ms
  （真机反馈「太短」后从 240/200 上调；纯淡入淡出没有位移，主观时长短于同长的缩放转场）
  （`AppMotion.pageIn/pageOut` + `easeOutCubic` / `easeInOutCubic`）；过渡期间旧页仍在绘制自身背景，
  因此没有空帧或黑闪；系统「移除动画」/「减弱动态效果」时完全不做淡入。
  加载态：新增 `AppLoadingView`（`lib/ui/app_loader.dart`）＝居中 `AppLoader` + 150ms 淡入 + `加载中` 语义，
  替换首页/媒体库/搜索/收藏/剧集/季/详情/管理/合集/演员/直播/求片/我的求片的主加载态（原来是裸
  `CircularProgressIndicator` 或直接 `AppLoader`），使外观 → 加载动画（S66）在全应用生效；服务器区块在
  目录尚未解析时显示「正在加载服务器…」，不再看起来像「没有服务器」。**播放器也纳入**（用户要求「播视频前
  加载这个动画」）：控制器就绪前整页 `AppLoadingView`，开播中 `AppLoader`(44dp)、缓冲中 `AppLoader`(32dp)，
  横竖屏一致——播放器原来这三处都是裸 `CircularProgressIndicator`。
  开播态另按用户要求收紧：**加载期间不显示播放控件**（顶栏/侧栏/传输区都淡出且不接收点击，和素材/字幕一起
  只留加载动画），点一下画面才把控件唤回；加载动画下方新增**实时网速**（600ms 轮询引擎 `cache-speed`，
  `2.00 MB/s` 形式，未取到样本时显示「正在连接…」），慢速起播不再看起来像卡住。
  真机反馈「打开视频仍显示控件」后把判定从 `state.loading` 收紧为 `!state.ready || state.buffering`——`ready`
  在引擎 open 返回时就置位（首帧还没出来），只用 loading 会漏掉 ready→首帧之间的缓冲窗口；控件初始也改为隐藏。
  **缓冲（中途卡顿）同样显示加载动画与网速**，缓冲期间控件一并淡出。
  再按真机第二轮反馈收紧：**开播期间（首帧出来之前 = `!state.ready || state.buffering`）控件一律不出现**，
  只留加载动画 + 网速；这段窗口里点画面可以把控件唤回来。首帧到达后按常规「显示 3 秒再自动隐藏」，
  开播完成后的中途缓冲不再隐藏控件、只在加载动画下方显示网速。
  质量门：analyze 干净、layering ok、全量 **1446** 测试通过（新增 14 条：六平台接线、推入/返回叠化、首路由
  被替换时的叠化、go_router 路由仍走同一转场、减弱动效跳过、加载态淡入/尺寸/语义、服务器区块加载行、
  播放器开播态的加载动画）。
  临时黄金帧像素采样复核过中段确实是两页混合（蓝页淡入 60ms 时采样为 (101,0,153)，结束帧纯蓝），不是硬切。

  **真机复核发现更根本的缺陷（同日修复）**：装上包后过渡仍像硬切。screenrecord 抽帧证实此前**所有页面切换
  根本没有转场**——go_router 18.1.1 的默认页面是 `NoTransitionPage`：它按 `material_ui` 包的 `MaterialApp`
  判定应用类型，而本应用用的是 `package:flutter/material.dart` 的 `MaterialApp`（Flutter 3.47 起两者是不同类），
  判定失败后静默降级，`pageTransitionsTheme` 从未生效。这也解释了最初"转场生硬"的观感。修复：新增
  `lib/core/router/app_page.dart` 的 `appPage()`（按 go_router 自己的 key/name/arguments/restorationId 构造
  `MaterialPage`），`lib/app/router.dart` 全部 24 条路由改用 `pageBuilder`；单元测试用 go_router + 真实
  `appPage` 锁住「页面必须是 `MaterialPage` 且中途有淡入」。
  修复后真机证据（Mi 10 / 1080×2340，screenrecord 逐帧）：点设置后 2.45s→2.70s 画面平均亮度 70.4 → 30.8 连续
  下滑（约 25 帧），六帧可见首页与设置页叠化（docs/screenshots/s79-page-fade.png）；修复前同操作是单帧硬切
  （72.7 → 30.8）。安装包：release 0.3.0+7，覆盖安装保留登录态与设置。

  **播放器加载态的第二处干扰（用户反馈「圆圈和加载动画重合」）**：`media_kit_video` 的 `Video` 组件默认挂
  `AdaptiveVideoControls`，在 Android 上即 `MaterialVideoControls`，其中有一个只由 `buffering` 驱动、与控件
  显隐无关的白色 `CircularProgressIndicator`，正好叠在我们的加载动画上。播放器本来就有自己的控制层
  （S30/S78），因此在 `MediaKitEngine.createSurface()` 显式传 `controls: NoVideoControls`，内置控件及其缓冲圈
  一并移除；字幕仍由 mpv 烧进视频纹理（S3/S4/S78），不受影响。
