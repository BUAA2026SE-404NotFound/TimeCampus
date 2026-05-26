# TimeCampus 时光航迹

TimeCampus 根仓库用于生产编排：门户前端构建静态资源，后端构建 Spring Boot 镜像，Caddy 统一暴露 HTTPS。

## Quick Start

```bash
cd ~/TimeCampus
git submodule update --init --recursive
cp .env.example .env
mkdir -p data/storage

cd ~/TimeCampus/TimeCampus-Portal
pnpm install --frozen-lockfile
VITE_CAP_API_ENDPOINT=https://cap.timecampus.asia/<site-key>/ pnpm build

cd ~/TimeCampus
docker compose --env-file .env -f compose.yaml up -d --build
```

首次启动后需初始化 Cap，并把 `CAP_SITEVERIFY_URL`、`CAP_SECRET` 写回 `.env`，然后重启后端，详见 [docs/deploy.md](docs/deploy.md)。

