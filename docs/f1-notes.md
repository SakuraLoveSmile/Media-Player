# F1 登录页与双地址配置

- 日期：2026-10-27
- 范围：登录页 UI、地址校验与归一化、错误文案、地址预填、登录成功跳转
- 结论：**macOS 实机完成「输入局域网地址 → 登录 → 进入媒体库 → 退出重开直接进入媒体库」**；Android / Windows 的登录 UI 未实机点击。

## 1. 截图

| 文件 | 说明 |
|---|---|
| `docs/screenshots/f1-login.png` | 空表单（release 构建，窗口标题已是 Media Player） |
| `docs/screenshots/f1-library.png` | 真实 Emby 登录成功后进入媒体库占位页 |

## 2. 实测步骤（macOS 26/27，release）

1. 启动应用 → 登录页（无存档时）。
2. 填局域网地址、用户名 `test`、密码 → 回车提交。
3. 进入「媒体库」占位页。
4. 退出应用重新打开 → **直接进入媒体库**，不再停留登录页（会话恢复 + 地址持久化）。
5. 存储文件 `~/Library/Application Support/dev.mediaplayer.mediaPlayer/mp_storage_v1.json`：
   - 权限 `600`；
   - 键：`mp.token.v1`、`mp.session.v1`、`mp.profile.v1`、`mp.deviceId.v1`。

## 3. macOS 关键发现（必须保留）

1. **App Sandbox 下所有局域网请求失败。** 带沙箱的 release 包即使地址/账号正确，也报「无法连接服务器」，`lsof` 看不到任何 TCP 连接；关闭沙箱后同一份代码立即登录成功。
   M0 决策原文就是「ad-hoc 签名、不公证、内测期关闭 Sandbox」，但 B1 只补了 `network.client`，没有关掉沙箱。**B2 的 macOS 直连是在未沙箱化的临时 debug 工程里完成的，不能代表 release 沙箱包。**
2. **Local Network 隐私。** macOS 15+ 访问局域网需要 `NSLocalNetworkUsageDescription`，已写入 `macos/Runner/Info.plist`；沙箱关闭后不再被拦截。
3. **ad-hoc Keychain 授权弹窗。** 重新签名后读取上一版写入的钥匙串项会弹出「Media Player 想要使用你储存在钥匙串的…」，且阻塞启动（实测卡在启动页）。按契约 §7 改为 macOS 默认使用 0600 文件；有 Developer ID 时用 `--dart-define=USE_KEYCHAIN_MACOS=true` 切回 Keychain。
4. **应用名。** `PRODUCT_NAME` 从 `media_player` 改为 `Media Player`，窗口标题、Finder 名称同步修正；产物路径变为 `Media Player.app`。

## 4. 测试

- `flutter test`：92 项全部通过。
- 新增：`test/features/login/login_form_test.dart` 7 项（必填、地址格式、归一化、WAN-only、错误文案）；
  `test/app/login_flow_test.dart` 5 项（成功跳转并校验下发的归一化数据、拒绝后停留、端点原因展示、空表单不发请求、地址预填）。
- UI 与真实服务器的组合由 macOS 实机截图覆盖；HTTP 细节由 B3 的真实服务器冒烟覆盖。

## 5. 未覆盖

1. Android / Windows 的登录 UI 实机点击（CI 只证明构建）。
2. WAN 地址登录（地址未提供）。
3. 业务请求 401 → 回登录页：当前没有业务请求，F4 接入媒体库时补。
4. 「添加第二地址」入口：`adoptAddress` 后端已实现并有单测，UI 留到 F4 设置页。
5. 有 Developer ID 的 Keychain 路径。
