# TimeCampus 时光航迹

TimeCampus 根仓库用于生产编排：门户前端打进 Caddy 镜像，后端构建 Spring Boot 镜像，Caddy 统一暴露 HTTPS。生产 Compose 同时包含 Qdrant、Ollama、Valkey、Cap，并默认用 Ollama `all-minilm` 为 MCP/RAG 提供 384 维 embedding。

## Quick Start

```bash
cd ~/TimeCampus
git submodule update --init --recursive
cp .env.example .env
mkdir -p data/storage

cd ~/TimeCampus
docker compose --env-file .env -f compose.yaml up -d --build
```

首次启动后需初始化 Cap，并把 `CAP_SITEVERIFY_URL`、`CAP_SECRET` 写回 `.env`，然后重启后端，详见 [docs/deploy.md](docs/deploy.md)。

