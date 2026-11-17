# MediaPlayer 一起看服务

独立 Dart 标准库服务，只同步房间/时间线，不代理视频。一个实例绑定一个 Emby 服务器；房间仅内存保存，重启后结束。不依赖 Tigerest 服务或账号。协议见仓库 `docs/contracts/watch-together-v1.md`。

```sh
cd services/watch_together
dart pub get
EMBY_URL='http://your-emby:8096' EMBY_SERVER_ID='your-server-id' \
  HOST=127.0.0.1 PORT=18444 dart run bin/server.dart
```

`EMBY_URL` 必须是管理员配置且信任的 Emby 地址（支持 `/emby` 前缀），不能含账号、query 或 fragment。`EMBY_SERVER_ID` 必须匹配该 Emby 的 Id。服务使用成员自己的会话核实身份和媒体版本权限，不需要 Emby 管理员 API Key。不要把服务暴露为任意上游代理。

## 使用预构建镜像

MediaPlayer 发布流程额外构建一起看服务镜像，发布到 GHCR：

```text
ghcr.io/sakuralovesmile/media-player-watch-together:<MediaPlayer版本标签>
```

支持 `linux/amd64`、`linux/arm64`，Docker 自动选择宿主机架构。版本标签与客户端 Release 一致（例如 `v0.4.8-pilot.1794895367`）；测试版不会更新 `latest`，只有正式 `vX.Y.Z` 发布会更新。生产使用明确版本或工作流摘要中的 `@sha256:…`，便于回退。

```sh
# 将版本替换为已成功完成 watch-image 构建的 Release 标签。
WATCH_VERSION='v0.4.8-pilot.1794895367'
docker run -d --name media-player-watch --restart unless-stopped \
  -p 127.0.0.1:18444:18444 \
  -e EMBY_URL='http://your-emby:8096' \
  -e EMBY_SERVER_ID='your-server-id' \
  "ghcr.io/sakuralovesmile/media-player-watch-together:$WATCH_VERSION"
```

容器内的 `127.0.0.1` 指向容器自身；`EMBY_URL` 应填写容器可访问的 Emby 地址。无需挂载数据卷，也无需管理员 API Key。首次发布后，仓库维护者需在 GHCR 包设置中确认可见性为 Public，才支持匿名 `docker pull`；Private 包需要先登录 GHCR。

维护者可在 GitHub Actions 的 **watch-image → Run workflow** 填写已有版本标签，单独补建镜像，不重建三个客户端；补建旧版本时保持 `update_latest` 关闭（默认），避免覆盖当前正式版。正式发布与 Pilot 发布自动调用相同工作流，源代码固定到发布验证解析的 SHA。每次发布前先分别启动 amd64、arm64 镜像并检查健康接口；服务或镜像工作流的 PR/main 变更只构建检查，不推送镜像。工作流摘要提供版本地址和镜像 digest。

也可自行构建：

```sh
docker build -t media-player-watch .
docker run -d --name media-player-watch --restart unless-stopped \
  -p 127.0.0.1:18444:18444 \
  -e EMBY_URL='http://your-emby:8096' -e EMBY_SERVER_ID='your-server-id' \
  media-player-watch
```

供其他设备使用时，在自己管理的反向代理配置 HTTPS 与 WebSocket Upgrade，指向本地18444；客户端配置该 HTTPS 服务地址。HTTP只适合受信任局域网调试，公网不要明文发送会话。此仓库不自动部署、不修改防火墙。原生客户端不带 Origin；浏览器Origin默认拒绝。

检查 `GET /watch/v1/health` 应返回 `{"data":{"enabled":true,"protocol":1}}`。默认普通房间4人、Emby管理员创建20人、最多50房间；房间24小时到期，断线座位60秒，全员断线保留5分钟，ready等待15秒。服务端不记录会话/票据/房间码/媒体业务日志，不落盘保存成员身份。

本地测试从仓库根运行：

```sh
/Users/sakurasep/devsdk/flutter/bin/flutter test --no-pub test/data/watch_together/server_test.dart
```

测试使用回环HTTP/WebSocket和注入身份/媒体验证器，不访问真实 Emby。生产连通性、真实多账号权限和跨网络音视频同步需部署者另行验收。


## 客户端使用

1. 每位成员在 MediaPlayer 登录此服务绑定的同一个 Emby 服务器，各用自己的账号。
2. 从首页“一起看”或设置底部“一起看”进入，填写服务 HTTPS 地址并确认信任；地址可填写站点根路径（自动补 `/watch/v1`）或完整API前缀。
3. 选择电影/剧集单集及版本创建房间，或从详情/季页的“一起看”按钮带入选片；将六位房间码告诉朋友。
4. 成员加入后点“开始放映”，加载就绪后统一开始；任何成员可播放/暂停/拖动/换片。退出播放器保留房间，点“离开房间”才退房；房主可移出成员或解散。

Nginx HTTPS 站点的代理片段（放入已有、配置有效证书的 `server` 内，不自动修改证书/防火墙）：

```nginx
location /watch/v1/ {
    proxy_pass http://127.0.0.1:18444;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 90s;
    proxy_send_timeout 90s;
    client_max_body_size 16k;
}
```

同步服务需要能访问配置的 Emby；客户端还需能独立访问自己的 Emby 播放端点。房间服务不分发视频，因此不能代替 Emby 外网访问配置。服务不支持通用任意账号/任意Emby上游，也不包含聊天/语音。
