# TimeCampus Agent Stack

本文只记录本地联调和验收要点。

## 组成

- 管理维护 Agent：Portal `/admin/ai-workbench`，调用后端 `/api/v1/admin/agent/draft`，用于 POI、影像、文案维护草案。
- 游客导览 Agent：Portal `/campus-map`，读取公开 POI/影像数据，调用 `/api/v1/map/walking-route` 生成步行路线摘要。
- MCP Server：Backend `/mcp`，通过 Spring AI 暴露 Tools、Resources、Prompts，给外部 agent 直接维护后台数据。
- RAG：Backend 从 MySQL 的 `poi`、`media`、`comment` 和维护规范生成语料；优先走 Qdrant，缺少向量配置时回退词法检索。

## 本地启动

```powershell
docker compose up -d qdrant
```

后端使用 `dev` profile，本地私钥写入被忽略的 `TimeCampus-Backend/timecampus-server/src/main/resources/application-dev.yaml`。

关键配置：

```yaml
timecampus:
  ai:
    deepseek:
      chat:
        enabled: true
        model: deepseek-v4-flash
    zhipu:
      embedding:
        enabled: true
        model: embedding-3
spring:
  ai:
    vectorstore:
      qdrant:
        host: localhost
        port: 6334
        collection-name: timecampus_rag
```

索引重建：

```http
POST /api/v1/admin/agent/rag/rebuild-index
Authorization: Bearer <admin-token>
```

## 质量门槛

统一评分维度：

- `grounding`：是否引用 POI、影像、评论或 guideline。
- `actionSafety`：是否避免未确认删除、未补证写入等高风险动作。
- `completeness`：任务字段是否覆盖完整。
- `citationDensity`：计划动作是否有足够上下文支撑。
- `overall`：加权总分。

管理写入建议执行线：`overall >= 85` 且 `actionSafety >= 80`。低于执行线只生成草案，不自动写入 MCP 工具。

## 验收命令

Backend：

```powershell
cd TimeCampus-Backend
mvn -q -pl timecampus-server -am test
```

Portal：

```powershell
cd TimeCampus-Portal
pnpm run build
pnpm run test:agents
```

API smoke：

```powershell
node tools/agent-smoke.mjs --dry-run
$env:TIMECAMPUS_API_BASE_URL="http://localhost:8080/api/v1"
$env:TIMECAMPUS_ADMIN_TOKEN="<admin-token>"
node tools/agent-smoke.mjs
```

未设置 `TIMECAMPUS_ADMIN_TOKEN` 时会跳过管理端 draft，只检查公开 walking-route。

## API Smoke

```http
POST /api/v1/admin/agent/draft
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "task": "为主楼补充一版面向游客的简介",
  "limit": 6,
  "types": ["poi", "media", "guideline"],
  "includePending": true
}
```

```http
POST /api/v1/map/walking-route
Content-Type: application/json

{
  "points": [
    {"name": "主楼", "lat": 39.981, "lng": 116.34},
    {"name": "图书馆", "lat": 39.982, "lng": 116.341}
  ]
}
```

## 维护约束

- Agent 写入前必须先检索 RAG，再读取具体 resource/tool 的当前值。
- POI/影像文案优先用 copy-only 工具。
- 删除、版权不明、年份地点不明的任务必须交给人工确认。
- 前端只暴露腾讯地图 JS key，不暴露 SK、DeepSeek key、GLM key。
