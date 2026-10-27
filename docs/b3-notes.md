# B3 实现与实测记录

- 日期：2026-10-27
- 服务器：Emby 4.10.1.0，局域网 HTTP（地址与账号不入库）
- 结论：**探测 → 登录 → 持久化 → 重启恢复 → 登出** 链路在真实服务器通过；WAN、第二服务器、macOS Keychain 实际路径未覆盖。

## 1. 实测输出（已脱敏）

```text
$ EMBY_LAN_URL=<lan> EMBY_USER=<user> EMBY_PASS=<pass> dart run tool/b3_smoke.dart
B3 smoke
- lan address: provided
- wan address: skipped (not configured)
PASS wrong password rejected, no token stored
PASS probe+login: endpoint=lan server=97eb93bf device=22ce4ea6 user=test
PASS restart restore: endpoint=lan user=test
PASS views: 13 via token header
PASS logout: token cleared, profile kept
SKIP serverMismatch: needs a second Emby instance (unit-tested)
RESULT pass
```

- server / device 仅打印前 8 位；token、密码、完整 URL 均不输出。
- `views: 13` 与 B2 阶段扫描到的库数量一致，说明授权头对真实 API 生效。

## 2. 覆盖矩阵

| 能力 | 结论 | 证据 |
|---|---|---|
| `GET /System/Info/Public` 探测 + 采纳 serverId | 通过 | 第 2 行 |
| `POST /Users/AuthenticateByName` + `X-Emby-Authorization` | 通过 | 第 2 行 |
| token / session 分离持久化 | 通过 | 第 3 行（新对象读同一存储） |
| 重启恢复且不额外请求校验 | 通过 | 第 3 行 |
| 授权 GET（`X-Emby-Token`） | 通过 | 第 4 行 |
| 错误密码 → `unauthorized` 且不落盘 | 通过 | 第 1 行 |
| 登出只清 token/session、保留 profile | 通过 | 第 5 行 |
| `serverMismatch` 拒绝第二地址 | 单测通过；真实第二服务器未提供 | 第 6 行 |
| 业务请求 401 → 自动登出、不重试 | fake server 单测；真实环境尚无业务请求 | `test/data/auth` |
| WAN frp HTTPS | 未验证 | 地址未提供 |
| macOS Keychain 启动探针 | 通过（login keychain，见 §5） | 无回退目录、无 WARN |

## 3. 复现方式

```bash
read -r -p "LAN URL: " EMBY_LAN_URL
read -r -p "user: " EMBY_USER
read -r -s -p "password: " EMBY_PASS; echo
export EMBY_LAN_URL EMBY_USER EMBY_PASS
~/devsdk/flutter/bin/dart run tool/b3_smoke.dart
unset EMBY_PASS
```

- 工具使用临时目录里的文件存储（`0600`），退出时删除；不会写入平台 Keychain。
- 应用运行时走 `createKeyValueStore()`：优先 Keychain/Keystore/DPAPI，失败才降级到同一套文件格式。
- 单测总量：`flutter test` 80 项，覆盖 URL 规范化、错误映射、302、超时、缓存/单飞、存储降级、登录/恢复/401。

## 4. 未覆盖与后续

1. WAN 地址就绪后，用同一工具把 `EMBY_LAN_URL` 指向 frp HTTPS 地址复跑，并补 `EMBY_WAN_URL` 版本。
2. 真实 token 的跨进程重启：F1 首次登录后杀进程重开验证（探针已通过，但探针不等于 token 持久化）。
3. 第二台 Emby 或临时改端口伪造 serverId 的实测：当前只有单测覆盖。
4. `PlayMethod` 核对仍等 B5 上报。

## 5. macOS ad-hoc 签名下的 Keychain（实测）

默认的 data protection keychain 需要 team identifier，ad-hoc 签名没有，实测表现：

1. 首版 release（`MacOsOptions` 默认 `usesDataProtectionKeychain: true`）启动后，
   沙箱容器内出现 `<bundle>/Data/Library/Application Support/dev.mediaplayer.mediaPlayer/`
   —— 说明探针抛错、工厂降级到了文件实现。
2. 改为 `usesDataProtectionKeychain: false`（login keychain）后重新构建并清理该目录再启动：
   进程存活 6s、无 `[storage]` WARN、目录未重建 —— 探针的 write/read/delete 全部走通 Keychain。

因此 `storage_factory.dart` 在 macOS 上先试 login keychain，失败才落 0600 文件。
仍未验证的是真实 token 跨重启读取（依赖 F1 的真实登录）。

