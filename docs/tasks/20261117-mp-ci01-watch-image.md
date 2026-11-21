# MP-CI01：直接拉取一起看服务镜像

- 项目：personal-mediaplayer；创建日期：2026-11-17（Asia/Taipei）
- 状态：待体验
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
- 本机没有 Docker；已在 Actions 完成 amd64/arm64 构建及启动检查，并在生产主机完成 amd64 实际运行核验。
- 本次候选基于 `5996f63`，改动为本记录、release.yml、新增 watch-image.yml、Dockerfile、服务 README；已提交 `caa2d31` 并快进合入/推送 main。
- 本地已执行：actionlint（含 ShellCheck）零问题、`git diff --check`、service `dart pub get --enforce-lockfile`、`bash tool/check_layering.sh`、Flutter analyze 均通过；Flutter 3.47.7 全量 1621 项测试通过（63 秒）。
- 从工作流提取实际版本校验脚本，stable、pilot、旧版补建、PR、非法 tag、非法 SHA、空手动输入七场景均符合预期；确认 pilot/默认补建不会更新 latest。
- 独立 reviewer 未发现阻断问题；指出手动补建覆盖 latest 已修复。未降低或跳过项目门禁。
- 日志保全：`/Users/sakurasep/Documents/Code/Project/Project Worktree/_preserved-notes/20261117-mp-ci01-watch-image/` 中 analyze/test 日志。
- 工作树收尾：已确认任务提交在 main、工作树无未保存改动；已正常移除本任务 worktree 和已合入本地分支，主仓保留。

## 发布与 SSH 部署（2026-11-17）

- 用户明确确认首次 GHCR 发布及 SSH 线上部署；指定 `blog-prod`、`watch.上杉九月.cn` 和 Emby `media.上杉九月.cn`，并已添加 watch 的 A 记录。
- 功能提交：`caa2d31`；主分支镜像检查 [44050895542](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44050895542) 成功；测试版镜像发布 [44050897101](https://github.com/SakuraLoveSmile/Media-Player/actions/runs/44050897101) 成功。
- 已发布 `ghcr.io/sakuralovesmile/media-player-watch-together:v0.4.8-pilot.1794895367`，匿名访问 manifest 成功，包含 amd64/arm64 和 provenance；未更新 latest。镜像源码为客户端标签的 `4f84b4c0e613b0c8d62c4c641dccc65e4b7f2ee4`。
- Registry index digest：`sha256:53b48b78a726f340f174d78797c48445c68709c76c62aa210f4ac493e268db9b`；amd64 manifest：`sha256:c4653d7254e8b1f233b979ca5630bc8be59c0e8b83cab391c21c2718a75d7773`；arm64 manifest：`sha256:8eee11af657ac2ac846abcb9203349d01d3ebde90150b6b17e14a8d9b7e442be`。
- 线上原有 Docker daemon 代理指向未监听的 127.0.0.1:7890，直接 pull 失败；未修改全局 Docker/代理或其他容器。改为用临时 crane 匿名下载已发布 amd64 镜像，经 SSH 传输并核验 tar SHA256：`41d45665e16a7dfac16f8c8b955b45e8b06fd424c7543ffad33f0722f8c85460`。Docker containerd 导入产生本地 image Id `sha256:b0bd6b167acf2cf2fa19b1aa5af7e41558824d228beed3e9f7dc9b97fbebe475`；核对架构、源码标签及 rootfs 后赋对应版本 tag。
- 部署目录 `/opt/media-player-watch`，Compose project `media-player-watch`；容器 `media-player-watch-watch-1`，`restart: unless-stopped`、只读根文件系统、无额外 capabilities。仅监听 `127.0.0.1:18444`，Compose `pull_policy: never`（因上述现有代理故障，后续升级需先导入或修复代理后拉取，不能只更换版本字符串）。
- Emby 固定为 `https://media.xn--fhqths51enha.cn`，公开服务器 ID 已核对匹配；无需持久化用户会话或管理员 API Key。
- OpenResty 独立站点 `/opt/1panel/www/conf.d/watch.conf`；站点目录 `/opt/1panel/www/sites/watch/`。该站点通过 SSH 管理，非 1Panel 数据库创建；不要在面板中覆盖同名配置。HTTP 跳转 HTTPS，保留 ACME 验证路径；API 启用 WebSocket Upgrade。关闭访问日志，错误日志仅 crit，避免房间及会话信息落入请求日志。
- Let's Encrypt 证书有效至 2027-02-15，域名 `watch.xn--fhqths51enha.cn`。ACME 数据位于 `/opt/media-player-watch/letsencrypt`（root 保护）；`media-player-watch-cert-renew.timer` 每日两次检查并带随机延迟，续期后复制证书并检查/平滑重载 OpenResty。
- 本次线上实测：HTTPS 健康响应 200 且 protocol=1；WSS 升级成功且假票据以 4401 拒绝；缺失凭据 401 AUTH_REQUIRED、假凭据经实际 Emby 验证后 401 AUTH_INVALID、非允许 Origin 403；同网络容器访问 Emby HTTPS 并匹配 ID 成功。容器 running、RestartCount=0。证书 `renew --dry-run` 成功，实际 systemd oneshot Result=success/ExecMainStatus=0。
- 未使用真实账号、播放真实媒体或创建真实房间；真实多成员放映仍待用户体验。

## 体验、维护与回退

- 客户端「一起看」填写 `https://watch.上杉九月.cn` 并确认信任，成员登录绑定的同一台 Emby；各自仍须能直接播放 Emby 媒体。
- 公开健康入口：`https://watch.xn--fhqths51enha.cn/watch/v1/health`。
- 查看运行：`ssh blog-prod 'sudo docker compose -f /opt/media-player-watch/compose.yaml ps'`；查看续期：`sudo systemctl status media-player-watch-cert-renew.timer`。
- 原始镜像 tar、校验文件、初始 Compose 和 HTTP 站点备份在 `/opt/media-player-watch/backups/`；无业务数据库。停止服务会结束内存房间。
- 如需撤销本次新增服务：仅对本项目执行 `docker compose -f /opt/media-player-watch/compose.yaml down`，停用 `media-player-watch-cert-renew.timer`，移出独立 watch.conf（保留副本），`docker exec openresty nginx -t` 通过后平滑 reload；不要重启/清理其他容器或删除现有证书/站点。
- 本地持久证据目录：`/Users/sakurasep/Documents/Code/Project/Project Worktree/_preserved-notes/20261117-mp-ci01-watch-image/`；保留发布日志、运行摘要和部署配置副本（不含证书私钥/账号）。
