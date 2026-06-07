# TimeCampus 根仓库部署

根仓库负责生产编排：`TimeCampus-Portal` 在 Caddy 镜像构建阶段产出静态前端，`TimeCampus-Backend` 构建 Spring Boot 镜像，Caddy 统一暴露 HTTPS。Compose 还会部署 Qdrant、Ollama 和 Valkey，后端 MCP/RAG 默认使用 Ollama 的 `all-minilm` embedding 模型写入 `timecampus_rag_minilm` 集合。

## 域名路由

```text
www.timecampus.asia          门户首页
www.timecampus.asia/admin/*  308 跳转到 admin.timecampus.asia/*
www.timecampus.asia/api/v1/* 兼容旧入口，反代到后端
admin.timecampus.asia/*      管理端 SPA
api.timecampus.asia/v1/*     API 新入口，Caddy 重写到后端 /api/v1/*
cap.timecampus.asia/*        自托管 Cap Standalone
```

生产只暴露 Caddy 的 `80/443`。`backend:8080`、`cap:3000`、`valkey:6379`、`ollama:11434` 都只在 Compose 内网访问；Qdrant 默认只绑定服务器本机 `127.0.0.1:6333/6334`，用于排查和备份。

## 首次准备

```bash
cd ~/TimeCampus
git submodule update --init --recursive
cp .env.example .env
mkdir -p data/storage
```

编辑 `.env`，填入数据库、微信、腾讯地图、Cap、DeepSeek、MCP token 等真实值。若 `REDIS_PASSWORD` 非空，`CAP_REDIS_URL` 也要带上同一个密码。`OLLAMA_EMBEDDING_MODEL=all-minilm` 对应 MiniLM 384 维 embedding，后端会以该维度初始化新的 Qdrant collection。

## 启动服务

```bash
cd ~/TimeCampus
docker compose --env-file .env -f compose.yaml config
docker compose --env-file .env -f compose.yaml up -d --build
```

也可以从本机直接上传并启动，脚本会读取 `TimeCampus-Portal/.env` 中的 `DEPLOY_HOST`、`DEPLOY_USER`、`DEPLOY_PASSWORD`：

```bash
uv run --with paramiko python tools/deploy-compose.py
```

Compose 首次启动会先拉起 Ollama，并执行一次 `ollama pull all-minilm`；后端会等待该一次性任务成功后启动。

## Cap 初始化

首次启动后访问：

```text
https://cap.timecampus.asia
```

用 `.env` 的 `CAP_ADMIN_KEY` 登录，创建站点，记录 `site key` 和 `site secret`，然后更新：

```env
CAP_SITEVERIFY_URL=https://cap.timecampus.asia/<site-key>/siteverify
CAP_SECRET=<site-secret>
```

重启后端：

```bash
docker compose --env-file .env -f compose.yaml up -d backend
```

## RAG 初始化

后端启动后，通过 MCP 工具 `timecampus_rag_rebuild_vector_index` 从 MySQL 抽取 POI、媒体、评论和内容切块，写入 Qdrant。也可以先用 `timecampus_rag_search` 做小范围查询验证。

当前部署默认使用：

```env
SPRING_AI_VECTORSTORE_TYPE=qdrant
TIMECAMPUS_RAG_VECTOR_ENABLED=true
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_EMBEDDING_MODEL=all-minilm
OLLAMA_EMBEDDING_DIMENSIONS=384
QDRANT_COLLECTION=timecampus_rag_minilm
```

## 常用检查

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs -f caddy
docker compose --env-file .env -f compose.yaml logs -f backend
curl -i https://api.timecampus.asia/v1/health
docker compose --env-file .env -f compose.yaml exec ollama ollama list
docker compose --env-file .env -f compose.yaml exec backend sh -lc 'wget -qO- http://127.0.0.1:8080/actuator/health'
```
