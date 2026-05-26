# TimeCampus 根仓库部署

根仓库负责生产编排：`TimeCampus-Portal` 构建静态前端，`TimeCampus-Backend` 构建 Spring Boot 镜像，Caddy 统一暴露 HTTPS。

## 域名路由

```text
www.timecampus.asia          门户首页
www.timecampus.asia/admin/*  308 跳转到 admin.timecampus.asia/*
www.timecampus.asia/api/v1/* 兼容旧入口，反代到后端
admin.timecampus.asia/*      管理端 SPA
api.timecampus.asia/v1/*     API 新入口，Caddy 重写到后端 /api/v1/*
cap.timecampus.asia/*        自托管 Cap Standalone
```

生产只暴露 Caddy 的 `80/443`，`backend:8080`、`cap:3000`、`valkey:6379` 都只在 Compose 内网访问。

## 首次准备

```bash
cd ~/TimeCampus
git submodule update --init --recursive
cp .env.example .env
mkdir -p data/storage
```

编辑 `.env`，填入数据库、微信、腾讯地图、Cap 等真实值。

## 构建前端

```bash
cd ~/TimeCampus/TimeCampus-Portal
pnpm install --frozen-lockfile
VITE_CAP_API_ENDPOINT=https://cap.timecampus.asia/<site-key>/ pnpm build
```

构建产物在 `TimeCampus-Portal/dist`。当前 Compose 将该目录只读挂载到 Caddy 的 `/srv/portal`。

## 启动服务

```bash
cd ~/TimeCampus
docker compose --env-file .env -f compose.yaml config
docker compose --env-file .env -f compose.yaml up -d --build
```

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

## 常用检查

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs -f caddy
docker compose --env-file .env -f compose.yaml logs -f backend
curl -i https://api.timecampus.asia/v1/health
```
