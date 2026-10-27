# MediaPlayer（Emby 客户端）文档索引

当前阶段：**M0 已签核；B1 工程与三平台 CI 完成；B2 直连在三平台通过；B3 登录/端点/持久化在真实 Emby 通过；WAN、PGS/HDR 待验证。**

## 文档

- [ADR 0001：技术栈](adr/0001-tech-stack.md) — Flutter 3.47.7 + media_kit/libmpv，三平台单代码库。
- [Emby 客户端契约 v1.1](contracts/emby-client-contract-v1.1.md) — 双端点、认证、媒体库、直连策略、进度上报、播放引擎接口、验收门。
- [M0 签核记录](m0-signoff.md) — 环境实测、未闭环项、M1 开工顺序。
- [B2 直连 PoC 记录](b2-poc.md) — 真实 Emby 4.10.1 的直连结果与契约差异。
- [开发环境与构建](dev-setup.md) — Flutter 3.47.7 路径、平台前置、构建与质量门命令。
- [B3 实现与实测](b3-notes.md) — 探测/登录/恢复/401 的真实服务器证据与未覆盖项。
- [F1 登录页与双地址](f1-notes.md) — 实机登录/重启恢复截图与 macOS 平台坑。

## 当前硬约束

1. LAN 下视频不得转码（允许音频单独转码）。
2. 所有 API/媒体 URL 必须来自同一个已解析端点（LAN 或 WAN，不得混用）。
3. 播放内核必须封装在 `PlaybackEngine` 后，可替换。
4. macOS 无 Developer ID：ad-hoc 签名、不公证。
5. Windows 构建/运行已验证（CI release 构建 + Win11 x64 真机冒烟），但仅覆盖一台独显机器，不能替代核显/HDR 环境。
6. macOS entitlements 必须含 `com.apple.security.network.client`；Android 必须允许 LAN 明文 HTTP。
7. Android 网络播放需真机复核（模拟器仅 asset 可播）。

## 进入 M1 / 完成 B2 前需要

- ~~Emby LAN 地址与只读账号~~（已提供，仅存于本地测试环境，不入库）。
- ~~Windows 测试机或 CI runner~~（已提供，冒烟通过）。
- Emby WAN（frp HTTPS）地址与 frp 上行带宽。
- PGS / HDR10 / 60–80 Mbps 样本（当前库内未发现 PGS）。
