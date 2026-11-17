# MP-CI01：直接拉取一起看服务镜像

- 项目：personal-mediaplayer；创建日期：2026-11-17（Asia/Taipei）
- 状态：实现中
- 目标：MediaPlayer 发布时额外构建一起看服务 Docker 镜像，部署者无需克隆源码构建。
- 基线：main `5996f63`；分支：`codex/feat/20261117-mp-ci01-watch-image`；合入目标：main。
- 工作树：`/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer/20261117-feat-mp-ci01-watch-image`。
- 范围：镜像构建、发布工作流和部署说明；新增用户确认的 SSH 线上部署（主机别名 blog-prod）；不修改客户端协议，不操作真实账号/媒体。

## 决定与验收

- 镜像：`ghcr.io/sakuralovesmile/media-player-watch-together`；支持 amd64/arm64；版本标签沿用客户端，只有正式版更新 latest；手动补建默认不更新 latest，另提供完整源 SHA 标签和 OCI 来源信息。
- T1：共用 watch-image 工作流；发布验证输出不可变 SHA；客户端 Release 依赖镜像发布成功。手动入口按已有 tag 补建；PR/main 只构建不推送。
- T2：两个架构分别构建、启动并断言健康响应，再推送 multiarch manifest。夹具仅绑定回环且使用假 Emby 地址，不访问账号/媒体。
- T3：README 提供直接拉取启动、GHCR 可见性、版本选择和反向代理配置。
- 授权：用户已确认合入、推送、首次 GHCR 镜像发布，并要求通过 SSH 在线上部署（blog-prod）；域名及 Emby 绑定待核对。部署前检查原服务与端口，保留回退配置。

## 分工与验证

- 主 agent 唯一写入工作流、Dockerfile、README 和本记录；reviewer 只读独立审查工作流权限、源版本、架构和 Release 兼容，不派生。
- 本机没有 Docker，不能本地完成容器实测。Actions 两架构构建及启动检查是远端发布的必要验证；通过后才可称镜像可用。
- 本次候选基于 `5996f63`，改动为本记录、release.yml、新增 watch-image.yml、Dockerfile、服务 README；尚未提交/推送。
- 本地已执行：actionlint（含 ShellCheck）零问题、`git diff --check`、service `dart pub get --enforce-lockfile`、`bash tool/check_layering.sh`、Flutter analyze 均通过；Flutter 3.47.7 全量 1621 项测试通过（63 秒）。
- 从工作流提取实际版本校验脚本，stable、pilot、旧版补建、PR、非法 tag、非法 SHA、空手动输入七场景均符合预期；确认 pilot/默认补建不会更新 latest。
- 独立 reviewer 未发现阻断问题；指出手动补建覆盖 latest 已修复。未降低或跳过项目门禁。
- 日志保全：`/Users/sakurasep/Documents/Code/Project/Project Worktree/_preserved-notes/20261117-mp-ci01-watch-image/` 中 analyze/test 日志。
- 工作树收尾：尚未合入，保留用于继续提交/远端构建；完成合入验证后清理。
