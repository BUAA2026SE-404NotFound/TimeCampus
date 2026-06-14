# TimeCampus 文档维护指南

版本：`0.3.0-beta`
基线日期：2026-06-15

本文档定义 TimeCampus 文档的分层、真源、更新清单和评审要求。目标是让文档随着代码自然维护，而不是在版本后期集中补账。

## 1. 文档分层

| 层级 | 文档 | 应包含 | 不应包含 |
| --- | --- | --- | --- |
| 项目入口 | 根 [README](../README.md) | 项目定位、模块入口、快速启动、关键文档链接 | 完整接口表、完整业务规则、长篇部署细节 |
| 项目规格 | [功能规格](functional-spec.md)、[技术规格](technical-spec.md) | 跨模块功能、架构、接口分组、数据模型、质量门槛 | 单个模块的逐行实现说明 |
| 模块入口 | 三个子模块 README | 模块职责、快速启动、目录结构、命令、模块级约定 | 与项目规格重复的大段业务规则 |
| 运维联调 | [deploy.md](deploy.md)、[agent-stack.md](agent-stack.md) | 可执行步骤、环境变量、健康检查、冒烟命令 | 产品背景和长期路线图 |
| 专项文档 | Backend `docs/*` | 数据库、MCP、测试报告、发布说明 | 根仓库 Compose 或 Portal 路由细节 |

## 2. 真源关系

| 主题 | 真源 | 文档同步点 |
| --- | --- | --- |
| 子模块列表 | `.gitmodules` | 根 README、`docs/README.md` |
| 根依赖服务 | `compose.yaml`、`.env.example` | `docs/deploy.md`、技术规格 |
| 根环境变量 | `.env.example` | 根 README、部署说明、技术规格配置表 |
| Portal 路由 | `TimeCampus-Portal/src/App.tsx`、`src/components/admin/types.ts` | Portal README、功能规格 |
| Portal API 调用 | `TimeCampus-Portal/src/api/*` | Portal README、技术规格 API 分组 |
| Portal 质量命令 | `TimeCampus-Portal/package.json` | Portal README、技术规格测试表 |
| Backend API | Backend Controller | Backend README、功能规格、技术规格、OpenAPI/ApiFox |
| Backend 数据表 | `schema.sql` | 技术规格、Backend `docs/database.md` |
| Backend 配置 | `application-*-example.yaml`、配置类 | Backend README、技术规格、部署说明 |
| Backend MCP/RAG | `timecampus-server/src/main/java/.../mcp` | `TimeCampus-Backend/docs/mcp-server.md`、`docs/agent-stack.md` |
| Agent 命令 | `TimeCampus-Agent/src/timecampus_agent/cli.py` | Agent README、`docs/agent-stack.md` |
| Agent 配置 | `TimeCampus-Agent/.env.example`、`config.py` | Agent README、技术规格 |

## 3. 改动清单

### 新增或修改页面

- 更新 Portal README 的路由或目录说明。
- 如果影响用户流程，更新功能规格。
- 如果新增 API 调用，确保调用封装在 `src/api` 并更新技术规格 API 分组。
- 如果新增环境变量，更新 `.env.example` 和技术规格配置表。

### 新增或修改后端接口

- 更新控制器测试或回归测试。
- 更新 OpenAPI/ApiFox。
- 更新 Backend README 的接口分组摘要。
- 如果影响业务流程或权限，更新功能规格。
- 如果影响接口分组、鉴权或集成，更新技术规格。

### 新增或修改数据表/字段

- 先更新 `schema.sql`。
- 同步 Entity/DTO/VO 和字段契约测试。
- 更新 Backend `docs/database.md`。
- 更新技术规格的数据模型摘要。
- 如影响业务规则，更新功能规格。

### 新增或修改配置

- 更新对应 example 文件，不提交真实密钥。
- 更新模块 README 的环境变量说明。
- 生产配置变化更新 `docs/deploy.md`。
- 根编排变量变化更新技术规格配置表。

### 新增或修改 Agent/MCP 能力

- 更新 `TimeCampus-Backend/docs/mcp-server.md` 的 Tools、Resources、Prompts 或 Agent HTTP API。
- 更新 `docs/agent-stack.md` 的联调命令。
- 更新 Agent README 的 CLI 示例。
- 若新增写工具，说明确认参数、安全门槛和人工确认条件。

### 新增或修改部署拓扑

- 更新 `compose.yaml`、Nginx 配置或 systemd 部署方式后，同步 `docs/deploy.md`。
- 更新根 README 的快速启动或服务说明。
- 更新技术规格的部署架构和集成服务表。

## 4. 写作约定

- 用相对链接连接仓库内文档，便于 GitHub 和本地阅读。
- README 保持可扫读，优先表格、命令块和链接。
- 规格文档记录稳定事实，不把临时调试过程写成长期规则。
- 命令应明确工作目录。
- 环境变量说明只写变量名、用途和风险，不写真实值。
- 标注版本和基线日期；重大版本变更时同步更新。
- 中文文档保持术语一致：Portal、Backend、Agent、POI、UGC、MCP、RAG、Cap、Valkey。

## 5. 评审要求

文档相关 PR 或改动至少检查：

- 链接是否存在，尤其是跨子模块链接。
- 命令是否与 `package.json`、`pyproject.toml`、`pom.xml` 和脚本文件一致。
- 接口路径是否与 Controller 注解一致。
- 权限描述是否与后端拦截、Service 校验和前端空状态一致。
- 配置变量是否在 example 文件中存在或有明确默认值。
- 是否有重复大段内容可以改成链接。

## 6. 当前需要关注的漂移点

- `schema.sql` 尚未覆盖 `MeController` 中 notes/memos 相关接口的数据表。下一次处理该功能时，应补表和数据库文档，或移除/隐藏未交付接口。
- Portal 管理端当前没有独立 AI Workbench 页面。Agent 草案能力以 Backend `/api/v1/admin/agent/**`、MCP 和 Agent CLI 为准。
- Portal 当前没有 `test:agents` 脚本。Agent 相关冒烟以根目录 `tools/agent-smoke.mjs` 和 Backend/Agent 测试命令为准。
- Seedream 图片生成由 Backend 白名单、Cap 校验、Redis/Valkey 每日 IP 限流和 Portal 用户须知共同约束；修改时需同步 `seedream-agent.md`、Portal README 和功能/技术规格。

## 7. 文档更新最小模板

新增文档时建议包含：

```markdown
# 标题

版本：
基线日期：
适用范围：

## 目的

## 操作或规则

## 验证方式

## 相关链接
```

如果文档只记录一次性排查过程，不应放入长期 `docs/`；可以改为 issue、PR 描述或发布说明。
