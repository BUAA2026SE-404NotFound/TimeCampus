# TimeCampus 生产部署说明

根仓库只负责生产依赖服务编排：Valkey、Cap、Qdrant、Ollama 和一次性 embedding 模型拉取任务。Web 入口使用服务器 Nginx；Backend 使用 jar + systemd；Agent 使用 wheel + systemd；Portal 使用静态 `dist`。三个应用均由 CI runner 构建产物，服务器不依赖私有仓库 `git fetch`。

## 域名路由

```text
www.timecampus.asia          门户首页静态资源
www.timecampus.asia/admin/*  308 跳转到 admin.timecampus.asia/*（去掉 /admin 前缀）
www.timecampus.asia/login    308 跳转到 admin.timecampus.asia/login
www.timecampus.asia/register 308 跳转到 admin.timecampus.asia/register
www.timecampus.asia/api/v1/* 兼容旧入口，Nginx 反代到后端
admin.timecampus.asia/*      管理端 SPA 静态资源
api.timecampus.asia/v1/*     API 新入口，Nginx 反代到后端 /api/v1/*
cap.timecampus.asia/*        Nginx 反代到 127.0.0.1:3000
```

生产公网入口只开放 Nginx `80/443`。Compose 服务默认只绑定服务器本机端口或 Docker 内网；后端 systemd 服务监听 `127.0.0.1:8080`。

## 首次准备

```bash
cd ~/TimeCampus
git submodule update --init --recursive
cp .env.example .env
```

根 `.env` 只填写 compose 依赖服务变量，例如 Valkey 密码、Qdrant/Ollama 本机端口和 Cap 管理密钥。后端数据库、MCP、DeepSeek、腾讯地图、微信、存储和 Cap secret 配置位于服务器 `~/app/config/application.yaml` 与 `~/app/config/application-prod.yaml`。

## 启动依赖服务

```bash
cd ~/TimeCampus
docker compose --env-file .env -f compose.yaml config
docker compose --env-file .env -f compose.yaml up -d
```

也可以从本机同步根 compose 栈并启动：

```bash
uv run --with paramiko python tools/deploy-compose.py
```

Compose 首次启动会拉起 Ollama，并执行一次 `ollama pull embeddinggemma:300m`。

## Cap 初始化

首次启动后访问：

```text
https://cap.timecampus.asia
```

用 `.env` 的 `CAP_ADMIN_KEY` 登录，创建站点，记录 `site key` 和 `site secret`，然后更新后端生产配置：

```yaml
timecampus:
  security:
    cap:
      enabled: true
      site-verify-url: https://cap.timecampus.asia/<site-key>/siteverify
      secret: <site-secret>
```

重启后端：

```bash
sudo systemctl restart timecampus-backend
```

## Backend 部署

Backend CI 在 runner 执行 Maven 测试与打包，上传 `timecampus-server.jar`，服务器调用 `deploy-backend-artifact.sh` 替换 `~/app/app.jar`。发布前备份到 `~/app/backups`，健康检查失败自动恢复旧 jar。`~/app/config` 与远端仓库均不修改。

## Agent 部署

Agent 作为独立 systemd 服务运行，只监听 `127.0.0.1:8090`。生产环境变量统一由 `/home/ubuntu/TimeCampus/.env` 提供，文件权限应为 `600`：

```env
TIMECAMPUS_AGENT_API_TOKEN=<与 Backend 相同的长随机 Token>
TIMECAMPUS_AGENT_API_HOST=127.0.0.1
TIMECAMPUS_AGENT_API_PORT=8090
TIMECAMPUS_AGENT_MEMORY_DIR=/home/ubuntu/timecampus-agent/shared/memory
TIMECAMPUS_AGENT_SESSION_HISTORY_LIMIT=40
TIMECAMPUS_EVAL_REPORT_DIR=/home/ubuntu/timecampus-agent/shared/eval-reports
TIMECAMPUS_CHAT_BASE_URL=https://api.deepseek.com/v1
TIMECAMPUS_CHAT_MODEL=deepseek-chat
TIMECAMPUS_CHAT_API_KEY=<DeepSeek API key>
TIMECAMPUS_MCP_URL=http://127.0.0.1:8080/mcp
TIMECAMPUS_MCP_TOKEN=<与 Backend MCP 相同的 Token>
```

CI 上传 wheel 后调用 `deploy/deploy-agent-artifact.sh`。每个版本安装到 `~/timecampus-agent/releases/<git-sha>`，`current` 软链接切换到新版本，内存与评测历史保存在 `shared`。健康检查失败自动恢复旧软链接，最多保留 5 个 release。部署后执行：

```bash
curl http://127.0.0.1:8090/health
readlink -f ~/timecampus-agent/current
```

Backend 的 `application-prod.yaml` 必须配置：

```yaml
timecampus:
  agent:
    base-url: http://127.0.0.1:8090
    token: ${TIMECAMPUS_AGENT_API_TOKEN}
```

Backend systemd 同样需要读取包含 `TIMECAMPUS_AGENT_API_TOKEN` 的环境文件；两个服务的值必须完全一致。

## Portal 部署

Portal CI 在 runner 执行 lint、typecheck、build 和桌面/移动端 Playwright。通过后上传 `dist`，服务器将旧 `~/app/dist` 移入 `~/app/backups`，再通过同文件系统重命名发布新目录。Nginx 校验失败时恢复旧目录。远端 Portal 仓库不会被修改。Portal 只保存可公开配置，例如腾讯地图 JS key 和 Cap site endpoint；不得保存 Cap secret。

`/campus-map` 优先从公开接口 `GET /api/v1/portal/map/config` 运行时读取腾讯地图 JS Key，`VITE_TENCENT_MAP_KEY` 只作为构建期回退值。该接口不得返回腾讯地图 SK。

运营智能体使用 SSE。Nginx 的 API 反向代理需配置：

```nginx
proxy_buffering off;
proxy_read_timeout 300s;
```

## RAG 初始化

后端启动后，通过 MCP 工具或管理端 Agent API 从 MySQL 抽取 POI、媒体、评论和内容规范，写入 Qdrant。

```text
timecampus_rag_rebuild_vector_index
```

## 环境变量白名单

从本地同步到服务器前必须先备份远端 `.env`，且仅同步缺失项。至少检查：

```text
TIMECAMPUS_AGENT_API_TOKEN
TIMECAMPUS_AGENT_API_HOST
TIMECAMPUS_AGENT_API_PORT
TIMECAMPUS_AGENT_MEMORY_DIR
TIMECAMPUS_AGENT_SESSION_HISTORY_LIMIT
TIMECAMPUS_EVAL_REPORT_DIR
TIMECAMPUS_CHAT_BASE_URL
TIMECAMPUS_CHAT_MODEL
TIMECAMPUS_CHAT_API_KEY
TIMECAMPUS_MCP_URL
TIMECAMPUS_MCP_TOKEN
QDRANT_*
OLLAMA_*
```

共享 Agent Token 必须同时被 Agent systemd 与 Backend systemd 读取。凭据不得写入 Git、CI artifact、测试报告或命令日志。

当前生产默认使用：

```yaml
spring:
  ai:
    vectorstore:
      type: qdrant
timecampus:
  rag:
    vector-enabled: true
  ai:
    ollama:
      embedding:
        enabled: true
        model: embeddinggemma:300m
        dimensions: 768
```

embedding 模型维度发生变化时不得复用旧 collection。生产使用
`QDRANT_COLLECTION=timecampus_rag_embeddinggemma`，切换后执行
`timecampus_rag_rebuild_vector_index`，确认新 collection 状态为 green 后再保留或清理旧索引。

## 常用检查

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs -f cap
docker compose --env-file .env -f compose.yaml exec ollama ollama list
curl -i https://api.timecampus.asia/v1/health
sudo systemctl status timecampus-backend --no-pager
sudo systemctl status timecampus-agent --no-pager
sudo journalctl -u timecampus-backend -n 100 --no-pager
sudo journalctl -u timecampus-agent -n 100 --no-pager
```

根编排回归测试：

```bash
uv run --with pyyaml python -m unittest discover -s tests
```
