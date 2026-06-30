# TimeCampus 文档索引

本文档是 TimeCampus 根仓库的文档入口。根仓库负责把 Portal、Backend、Agent 三个子模块和生产编排连接在一起；模块内部细节优先从对应 README 进入，跨模块规则优先从项目级规格进入。

## 项目级文档

| 文档 | 用途 | 主要维护场景 |
| --- | --- | --- |
| [功能规格说明书](functional-spec.md) | 定义角色、功能范围、业务流程、权限规则与验收口径 | 新增页面、接口、业务流程、权限规则、审核状态 |
| [技术规格说明书](technical-spec.md) | 定义架构、技术栈、模块边界、数据模型、接口分组、部署与质量要求 | 调整架构、依赖、数据结构、部署拓扑、集成服务 |
| [文档维护指南](documentation-maintenance.md) | 定义文档分层、更新清单、真源关系和评审要求 | 任何会改变开发、部署、接口、数据或运营流程的改动 |
| [生产部署说明](deploy.md) | 说明 Nginx、systemd 后端、Compose 依赖服务、Cap、Qdrant、Ollama 等生产流程 | 域名、容器、环境变量、生产启动和健康检查变化 |
| [Agent Stack 联调说明](agent-stack.md) | 说明 Backend MCP/RAG、Agent CLI 和游客路线 API 的本地联调 | Agent、MCP、RAG、草案生成或路线规划变更 |
| [Agent 评估框架](agent-evaluation.md) | 说明 TimeCampus-Agent Eval Harness、指标、报告和 CI 门禁 | Agent 评测、Bad Case、质量回归和面试材料 |
| [AI 产品测试面试材料](ai-test-interview-pack.md) | STAR 简历、核心代码讲解、真实追问和 PPT 提示词 | 投递 AI 产品测试、测试开发或 Agent 质量岗位 |

## 子模块文档

| 模块 | README | 职责 |
| --- | --- | --- |
| Portal | [TimeCampus-Portal/README.md](../TimeCampus-Portal/README.md) | React 门户首页、公开校园地图、Web 管理端 |
| Backend | [TimeCampus-Backend/README.md](../TimeCampus-Backend/README.md) | Spring Boot API、数据访问、鉴权、MCP/RAG、第三方服务封装 |
| Agent | [TimeCampus-Agent/README.md](../TimeCampus-Agent/README.md) | LangChain 运维与导览 CLI、Backend API/MCP 调用 |

## Backend 专项文档

| 文档 | 用途 |
| --- | --- |
| [Backend 数据库设计](../TimeCampus-Backend/docs/database.md) | 数据表字段、索引和建模说明 |
| [Backend MCP Server](../TimeCampus-Backend/docs/mcp-server.md) | MCP Tools、Resources、Prompts、RAG 和 Agent HTTP API |
| [Seedream Image Agent](../TimeCampus-Backend/docs/seedream-agent.md) | 时光合影工作室的职责边界、系统提示词、白名单背景和风控约束 |
| [Alpha Release Notes](../TimeCampus-Backend/docs/alpha-release-notes.md) | Alpha 交付范围、限制和检查清单 |
| [Alpha Test Report](../TimeCampus-Backend/docs/alpha-test-report.md) | 测试计划、测试矩阵、压测和出口条件 |

## 常用入口

- 根仓库快速启动：见 [../README.md](../README.md)。
- 生产部署：见 [deploy.md](deploy.md)。
- 本地后端和 MCP 联调：见 [agent-stack.md](agent-stack.md)。
- Agent 评估与 Bad Case 闭环：见 [agent-evaluation.md](agent-evaluation.md)。
- API 调试：后端本地启动后访问 `http://localhost:8080/swagger-ui/index.html`。

## 维护原则

- README 只放模块定位、快速启动、常用命令、目录结构和权威链接。
- 功能规则写入 [功能规格说明书](functional-spec.md)，技术规则写入 [技术规格说明书](technical-spec.md)。
- 配置样例以 `.env.example`、`application-*-example.yaml` 和各模块 `.env.example` 为真源，文档只解释用途与风险。
- 数据结构以 `TimeCampus-Backend/timecampus-server/src/main/resources/sql/schema.sql` 为初始化真源，文档需要同步说明偏差。
- 发现代码和文档不一致时，先确认代码事实，再更新对应文档和索引。
