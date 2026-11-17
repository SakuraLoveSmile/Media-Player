# MediaPlayer 开发入口

<!-- development-workflow:begin v1 -->
Project-ID: personal-mediaplayer
Worktree-Root: /Users/sakurasep/Documents/Code/Project/Project Worktree/personal-mediaplayer
<!-- development-workflow:end -->

本项目遵守用户提供的全局工作约定与统一开发流程。现有任务记录优先维护；新任务放在 docs/tasks。

- Flutter + Riverpod + go_router；Emby 请求与凭据在 data，features 通过服务与 PlaybackEngine 访问。
- 实际架构/限制：docs/README.md、docs/contracts/emby-client-contract-v1.1.md；工具链与质量门：docs/dev-setup.md。
- 固定 SDK：`/Users/sakurasep/devsdk/flutter/bin/flutter`。先在 `services/watch_together` 执行 `dart pub get`，再依次运行 `bash tool/check_layering.sh`、`/Users/sakurasep/devsdk/flutter/bin/flutter analyze`、`/Users/sakurasep/devsdk/flutter/bin/flutter test`。
- LAN 不允许视频转码；同一会话 API/媒体 URL 来自相同解析端点；不可暴露凭据。离线下载索引不可保存授权 URL/token/header。
- 保留主工作区与其他任务已有改动；整合功能以保存基线和增量为依据，不整树覆盖。
- 提交、推送、合并与发布按当前会话授权执行；公网服务部署和生产账号/媒体操作需另行授权。
