# TimeCampus 生产部署说明

根仓库只负责生产依赖服务编排：Valkey、Cap、Qdrant、Ollama 和一次性 embedding 模型拉取任务。Web 入口使用服务器 Nginx；Backend 使用 jar + systemd；Portal 构建产物发布到 `~/app/dist`，Nginx 直接以该目录作为 SPA root。

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

Compose 首次启动会拉起 Ollama，并执行一次 `ollama pull all-minilm`。

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

常态修改后，在 Backend 仓库使用部署脚本发布 jar。脚本在本地构建，然后通过 SSH 替换服务器 jar 并重启 systemd 服务，不依赖服务器代理下载 Maven 依赖。

```bash
cd TimeCampus-Backend
bash deploy/scripts/deploy-backend.sh
```

Backend 配置继续从服务器 `~/app/config` 读取，避免把生产密钥写入仓库。

## Agent 部署

Agent 作为独立 systemd 服务运行，只监听 `127.0.0.1:8090`。服务器创建仅 Agent 用户可读的 `/etc/timecampus/agent.env`：

```env
TIMECAMPUS_AGENT_API_TOKEN=<与 Backend 相同的长随机 Token>
TIMECAMPUS_AGENT_API_HOST=127.0.0.1
TIMECAMPUS_AGENT_API_PORT=8090
TIMECAMPUS_AGENT_MEMORY_DIR=/var/lib/timecampus-agent/memory
TIMECAMPUS_AGENT_SESSION_HISTORY_LIMIT=40
TIMECAMPUS_CHAT_BASE_URL=https://api.deepseek.com/v1
TIMECAMPUS_CHAT_MODEL=deepseek-chat
TIMECAMPUS_CHAT_API_KEY=<DeepSeek API key>
TIMECAMPUS_MCP_URL=http://127.0.0.1:8080/mcp
TIMECAMPUS_MCP_TOKEN=<与 Backend MCP 相同的 Token>
```

创建持久目录并安装依赖：

```bash
sudo install -d -o timecampus -g timecampus /var/lib/timecampus-agent/memory
cd ~/TimeCampus/TimeCampus-Agent
uv sync --frozen
```

`timecampus-agent.service` 的 `WorkingDirectory` 指向 Agent 仓库，`EnvironmentFile` 指向 `/etc/timecampus/agent.env`，`ExecStart` 使用 `uv run timecampus-agent serve`。部署后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now timecampus-agent
curl http://127.0.0.1:8090/health
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

Portal 常态部署由 Portal 仓库 CI 或部署脚本完成：CI 只通过 SSH 登录服务器，在服务器已有 Portal 仓库拉取对应分支并本地执行 `pnpm install --frozen-lockfile`、`pnpm run lint`、`pnpm run typecheck` 和 `pnpm run build`；若服务器 Portal 仓库存在未提交改动，先用 `git stash push -u` 备份再切换分支。构建通过后备份旧 `~/app/dist`，再把新的 `dist` 发布到 `~/app/dist`。Nginx 的 `www.timecampus.asia` 与 `admin.timecampus.asia` SPA root 都指向该目录；主站 `/admin`、`/admin/*`、`/login` 与 `/register` 只做 308 跳转到管理域名。Portal 只保存前端可公开配置，例如腾讯地图 JS key 和 Cap site endpoint；不得保存 Cap secret。

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
        model: all-minilm
        dimensions: 384
```

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
