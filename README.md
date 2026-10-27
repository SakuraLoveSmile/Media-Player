# Media Player

跨 Android / Windows / macOS 的 Emby 媒体库客户端。当前处于方案验证阶段（M0 已完成，B2 直连验证进行中）。

- 技术栈：Flutter 3.47.7 + media_kit/libmpv
- 目标：局域网 HTTP 直连 Emby；公网经 frp HTTPS；LAN 下视频不转码
- 当前进度：
  - macOS：直连 H.264 1080p、HEVC Main10 4K、HEVC 4K MKV 通过
  - Android 真机（Mi 10）：HEVC 4K MKV 直连通过
  - Windows 11 x64：release 构建直连 HEVC 4K MKV、H.264 1080p MKV 通过（`directPlay=True`，无转码）
  - 工程：B1 三平台 CI 绿；B3 探测/登录/持久化/重启恢复在真实 Emby 通过（见 `docs/b3-notes.md`）
  - F1：双地址登录页在 macOS 实机登录成功并重启恢复（见 `docs/f1-notes.md`）
  - B4：视图/分页/详情/季集/图片在真实 Emby 通过（见 `docs/b4-notes.md`）
  - WAN、PGS、HDR：待验证

## 文档

- [技术栈决策](docs/adr/0001-tech-stack.md)
- [Emby 客户端契约](docs/contracts/emby-client-contract-v1.1.md)
- [M0 签核](docs/m0-signoff.md)
- [B2 直连 PoC](docs/b2-poc.md)
- [开发环境与构建](docs/dev-setup.md)

## 构建

```bash
export LANG=en_US.UTF-8
~/devsdk/flutter/bin/flutter pub get
~/devsdk/flutter/bin/flutter build macos --release
~/devsdk/flutter/bin/flutter build apk --release --split-per-abi
~/devsdk/flutter/bin/flutter build windows --release
```

必须使用 `~/devsdk/flutter`（3.47.7）；PATH 中的 3.41.3 不可复现。详见 `docs/dev-setup.md`。

## Windows 冒烟

- 工程：`spike/windows_smoke/`
- CI：`.github/workflows/windows-smoke.yml`（`windows-latest` 构建并上传 artifact）
- 使用说明见 `spike/windows_smoke/README.md`

## 约束

- 不提交任何服务器地址、账号、密码或 token。
- 播放层必须封装在 `PlaybackEngine` 后，可替换。
