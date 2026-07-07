# TimeCampus Agent Stack

本文记录 Backend MCP/RAG、Agent CLI、管理端 Agent HTTP API 和游客路线 API 的本地联调与验收要点。

## 组成

- Backend MCP Server：`/mcp`，通过 Spring AI 暴露 Tools、Resources、Prompts，给外部 Agent 维护 POI、影像、审核状态和展示文案。
- Backend RAG：从 MySQL 的 `poi`、`media`、`comment` 和内置维护规范构建语料；优先走 Qdrant，缺少向量配置时回退词法检索。
- 管理端 Agent HTTP API：`/api/v1/admin/agent/**`，提供 RAG、草案、运营执行审批和 Eval 代理。
- TimeCampus-Agent：独立纯 Python 工作区，提供 CLI 和仅供 Backend 调用的内部 FastAPI 服务。
- 运营会话：Agent 使用 `sessions/*.jsonl` 保存多轮消息，使用 `MEMORY.md` 注入人工维护的长期约束；Portal 通过 Backend SSE 选择 session 并续聊。
- 游客导览 API：`/api/v1/map/walking-route`，根据 2-8 个点位返回步行摘要与可绘制 `path`。

Portal `/campus-map` 提供无对话入口的游客导览；管理端 `/admin/agent-operations` 和 `/admin/agent-eval` 分别提供运营审批与评测页面。

## 本地启动

从根仓库启动 Backend API/MCP：

```powershell
.\tools\start-backend-mcp.ps1
```

Backend 和 Agent 设置相同的 `TIMECAMPUS_AGENT_API_TOKEN` 后启动内部服务：

```powershell
cd TimeCampus-Agent
uv run timecampus-agent serve
```

本地会话默认写入 `TimeCampus-Agent/data/agent-memory`。可通过 `TIMECAMPUS_AGENT_MEMORY_DIR` 修改，并用 `TIMECAMPUS_AGENT_SESSION_HISTORY_LIMIT` 控制每轮回放消息数。

运营会话代理：

```text
GET  /api/v1/admin/agent/operations/sessions
POST /api/v1/admin/agent/operations/sessions
GET  /api/v1/admin/agent/operations/sessions/{sessionId}
POST /api/v1/admin/agent/operations/sessions/{sessionId}/messages/stream
POST /api/v1/admin/agent/operations/runs/{threadId}/decisions/stream
```

默认不依赖 Docker、WSL 或 Qdrant，后端使用 `dev` profile，RAG 使用词法检索。开发私钥写入被忽略的 `TimeCampus-Backend/timecampus-server/src/main/resources/application-dev.yaml`。

如需 Qdrant 向量检索，先启动 Qdrant，再用脚本开启向量配置：

```powershell
docker compose up -d qdrant
.\tools\start-backend-mcp.ps1 -WithQdrant
```

## Backend 配置

常用配置：

```yaml
timecampus:
  ai:
    deepseek:
      chat:
        enabled: true
        model: deepseek-chat
    ollama:
      embedding:
        enabled: true
        model: embeddinggemma:300m
        dimensions: 384
spring:
  ai:
    vectorstore:
      type: qdrant
      qdrant:
        host: localhost
        port: 6334
        collection-name: timecampus_rag
timecampus:
  rag:
    vector-enabled: true
```

生产 MCP 应开启鉴权：

```env
TIMECAMPUS_MCP_ENABLED=true
TIMECAMPUS_MCP_AUTH_REQUIRED=true
TIMECAMPUS_MCP_TOKEN=replace-with-a-long-random-token
```

## 索引重建

管理端 HTTP API：

```http
POST /api/v1/admin/agent/rag/rebuild-index
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "types": ["poi", "media", "comment", "guideline"],
  "includePending": false,
  "deleteExisting": true
}
```

MCP 工具：

```text
timecampus_rag_rebuild_vector_index
```

## Agent CLI

准备：

```powershell
cd TimeCampus-Agent
uv sync
Copy-Item .env.example .env
```

常用命令：

```powershell
uv run timecampus-agent rag-search "主楼旧照"
uv run timecampus-agent draft "为主楼补充面向游客的简介"
uv run timecampus-agent ask "检索主楼资料并给出维护计划"
uv run timecampus-agent ask --agent guide "主楼到图书馆怎么走？"
uv run timecampus-agent mcp-tools
uv run timecampus-agent route "主楼,39.981,116.34;图书馆,39.982,116.341"
```

Agent 架构见 [TimeCampus-Agent/docs/python-agent.md](../TimeCampus-Agent/docs/python-agent.md)。

## API Smoke

管理端 RAG/草案：

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

游客步行路线：

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

根仓库脚本：

```powershell
node tools\agent-smoke.mjs --dry-run
$env:TIMECAMPUS_API_BASE_URL="http://localhost:8080/api/v1"
$env:TIMECAMPUS_ADMIN_TOKEN="<admin-token>"
node tools\agent-smoke.mjs
```

未设置 `TIMECAMPUS_ADMIN_TOKEN` 时会跳过管理端 draft，只检查公开 walking-route。

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
pnpm typecheck
pnpm lint
pnpm build
```

Agent：

```powershell
cd TimeCampus-Agent
uv run pytest
uv run ruff check .
uv run timecampus-agent eval run --suite all --mode fixture --report-dir eval-reports --min-pass-rate 0.85 --min-overall 80
```

## 维护约束

- Agent 写入前必须先检索 RAG，再读取具体 resource/tool 的当前值。
- POI/影像文案优先用 copy-only 工具。
- 删除、版权不明、年份地点不明的任务必须交给人工确认。
- 前端只暴露腾讯地图 JS key，不暴露 SK、DeepSeek key、GLM key、Cap secret。
