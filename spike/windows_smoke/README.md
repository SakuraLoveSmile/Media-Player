# Windows B2 冒烟包

用于在 Windows 11 x64 上验证 media_kit/libmpv 能否直连局域网 Emby 并播放 HEVC 4K MKV。

> 目录边界：从 B1 起，仓库根目录是正式 Flutter 工程；本目录是**独立的 M0 冒烟包**（自带 pubspec），
> 不参与根工程的分析与构建，只由 `.github/workflows/windows-smoke.yml` 单独构建。修改本目录不会触发 `app-ci`。

## 前置

- Windows 10/11 x64，和 Emby 在同一局域网。
- 不需要安装 Flutter、Visual Studio 或额外运行库（Release 包已带所需 DLL）。
- 未签名 exe：SmartScreen 提示时选"更多信息 → 仍要运行"。

## 使用

1. 从 GitHub Actions 下载 `windows-smoke-x64` artifact，解压到任意目录。
2. 在该目录打开 PowerShell，执行：

```powershell
.\run-smoke.ps1 -Server http://<emby-lan>:<port> -Username <test-user>
```

按提示输入密码（不会写入脚本或日志）。

如果被执行策略拦截：

```powershell
powershell -ExecutionPolicy Bypass -File .\run-smoke.ps1 -Server http://<emby-lan>:<port> -Username <test-user>
```

3. App 会自动登录、请求 PlaybackInfo、播放以下条目各 15 秒：
   - `53212` HEVC 4K MKV
   - `69117` H.264 1080p MKV
4. 结束后生成 `m0_windows_report.zip`，包含：
   - `m0_smoke.log`
   - `m0_result.json`
   - `system.txt`（OS / CPU / GPU / 显示）
   - `playback-info.txt`（每条目的 directPlay / transcodeUrl / directUrl 判定）

把这个 zip 回传即可。

## 说明

- 脚本现场用测试账号换 token，token 只写入本地 `emby_config.json`，运行结束注销并删除该文件。
- 默认条目 ID 可用 `-ItemIds` 覆盖，例如 `-ItemIds 53212`。
- 日志不记录密码；`emby_config.json` 已在 `.gitignore` 中。
