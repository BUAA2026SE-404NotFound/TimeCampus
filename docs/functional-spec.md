# TimeCampus 功能规格说明书

版本：`0.3.0-beta`
基线日期：2026-06-15
适用范围：根仓库、`TimeCampus-Portal`、`TimeCampus-Backend`、`TimeCampus-Agent`

本文档描述 TimeCampus 当前应交付和应维护的产品功能。接口、数据库和部署细节以 [技术规格说明书](technical-spec.md) 为准；模块启动方式以各模块 README 为准。

## 1. 项目目标

TimeCampus 是面向校园历史影像浏览、点位共创和运营维护的系统，中文产品名为“时光航迹”。系统通过门户网站展示项目与地图入口，通过后端 API 支撑微信小程序、公开地图和管理端，通过 Agent/MCP 提供面向维护人员的检索、草案和低风险编辑能力。

当前版本重点覆盖：

- 校园 POI、历史影像、年份切换和地图聚合浏览。
- 管理员登录、权限分配、POI 管理、官方内容上传和导入。
- UGC 与评论审核流程，其中评论功能在 Portal 管理端标记为因微信小程序服务策略而废弃，但后端接口仍保留。
- 审计日志、运营 Dashboard、运营地图和地图辅助工具。
- Backend MCP Server、RAG 检索、Agent CLI 和游客步行路线摘要。
- Seedream 时光合影工作室，受限于后端白名单历史模板、Cap 校验、用户须知同意和同 IP 每日生成限额。

## 2. 用户角色

| 角色 | 说明 | 主要入口 |
| --- | --- | --- |
| 游客 | 未登录访问者，浏览门户、项目介绍、小程序说明和公开校园地图 | Portal `/`、`/project-info`、`/mini-program`、`/campus-map` |
| 小程序用户 | 通过微信登录的用户，可浏览内容、收藏、上传 UGC、查看审核结果 | Backend `/api/v1/auth`、`/api/v1/me`、`/api/v1/ugc` 等用户端 API |
| 只读管理员 `read` | 可查看运营数据和内容，不执行写操作 | Portal 管理端、Backend `/api/v1/admin/**` 查询接口 |
| 普通管理员 `admin` | 可维护 POI、内容、审核和运营数据 | Portal 管理端、Backend 管理端写接口 |
| 超级管理员 `super` | 可管理普通管理员账号和权限，但不能直接授权另一个账号为 `super` | Portal `/admin/accounts` |
| 未授权管理员 `none` | 可登录但不能访问受保护运营数据，需要等待授权 | Portal 登录后空状态提示 |
| 运维/内容 Agent 操作员 | 使用 Agent CLI 或 MCP 工具进行检索、草案、路线和维护辅助 | `TimeCampus-Agent` CLI、Backend `/mcp`、`/api/v1/admin/agent/**` |
| 部署维护人员 | 维护 Nginx、systemd 后端、Compose 依赖服务、Cap、Qdrant、Ollama、数据库和密钥 | 根仓库 `compose.yaml`、`.env`、后端部署脚本、`docs/deploy.md` |

## 3. 功能范围

### 3.1 Portal 门户

门户首屏面向公开访问者，提供项目介绍、统计展示、历史影像视觉入口、小程序说明、校园地图入口和管理端入口。

功能要求：

- `/` 展示门户首页，并提供进入项目详情、小程序说明、校园地图和管理端的导航。
- `/project-info` 展示项目背景、价值和相关介绍。
- `/mini-program` 展示微信小程序说明与入口素材。
- 首页突出展示 `CAMPUS MAP` 智能导览入口；`/campus-map` 独立加载腾讯地图，支持景点查询、热门路线和 2-8 点步行规划。
- `/seedream-studio` 提供时光合影工作室，用户需同意“隐私与安全”和“用户内容规范”，通过 Cap 后才能上传并生成图片。
- `/privacy-security` 与 `/content-guidelines` 提供简短用户须知，页脚长期保留入口。
- `/admin`、`/admin/*`、`/login`、`/register` 作为 Web 管理端入口；生产主站应把这些入口跳转到 `admin.timecampus.asia`，其中 `/admin/*` 去掉 `/admin` 前缀。
- 管理端登录、注册路由在本地预览、管理端域名或关闭重定向时可直接渲染。

验收口径：

- 首页不初始化腾讯地图；地图页可独立加载 POI、媒体预览和年份数据。
- 公开地图使用无需管理员 token 的 `/api/v1/portal/map/home`。
- 时光合影工作室不接收自由提示词或用户自定义背景，只能使用后端白名单历史模板；生成前必须提交 Cap token，同一 IP 每天最多生成 5 次。
- 管理端入口在本地和生产域名策略下都能进入正确页面。

### 3.2 公开校园地图

公开校园地图用于让游客浏览校园点位和历史影像。

功能要求：

- 展示上架 POI 的位置、名称、描述、封面图和可用年份。
- 支持按年份筛选或展示点位影像。
- 支持点位点击弹窗、影像预览和媒体列表。
- 使用腾讯地图 JS Key；前端不得保存或暴露腾讯地图 SK。
- 数据来自后端公开接口，不依赖管理员登录态。

验收口径：

- 无管理员 token 时，公开地图仍能读取公开 POI。
- 地图 key 缺失时前端应有可理解的错误或空状态。
- 图片 URL 使用后端返回的 `previewUrl`、`thumbnailUrl`、`coverPreviewUrl` 或 `coverThumbnailUrl`，不要自行拼接受保护文件路径。

### 3.3 小程序用户端后端能力

当前仓库不包含小程序前端，但 Backend 提供小程序/用户端 API。

功能要求：

- 微信登录：用户通过 `POST /api/v1/auth/wechat/login` 使用 code2Session 登录。
- 用户资料：用户可读取本人信息、审核结果汇总、UGC 审核结果和评论审核结果。
- POI 浏览：用户可查询 POI 列表与详情。
- 内容浏览：用户可查询 POI 内容、官方内容、单条内容和年份切换结果。
- 收藏：用户可收藏或取消收藏 POI / media，并查询收藏列表。
- UGC：用户可上传历史影像或内容，上传后进入待审核状态。
- 评论：后端保留评论创建、列表和个人评论查询；Portal 管理端将评论审核标记为已废弃能力。
- 地图：用户可读取地图首页聚合、点位时间机器、逆地理编码、POI 搜索和步行路线摘要。
- 媒体访问：用户端媒体文件直出使用短期 accessToken URL，适配小程序图片组件无法稳定携带 `Authorization` 的场景。

验收口径：

- 用户行为接口需要用户 token。
- 返回媒体访问 URL 的用户端接口不得泄露服务器本地文件路径。
- 审核结果查询只能查询本人数据。

### 3.4 Web 管理端

管理端服务内容运营人员和管理员。

功能要求：

- 登录：`POST /api/v1/admin/login`；生产环境必须携带 Cap `capToken` 并由后端服务端校验。
- 注册：`POST /api/v1/admin/register`；新账户默认 `none` 权限。
- Dashboard：展示内容覆盖、增长趋势、审核状态、媒体分布、POI 热度和最近日志。
- POI 管理：新增、编辑、删除、查看点位，维护坐标、描述、冷知识和上下架状态。
- 内容上传：上传本地图片或导入已有 URL，并关联 POI、年份、类型和说明。
- UGC 审核：查看待审核 UGC，审核通过或驳回；驳回必须填写原因。
- 评论审核：后端能力保留，Portal 标记为已废弃；若重新启用，需要同步更新本规格和管理端文案。
- 地图工具：通过后端封装调用腾讯地图逆地理编码和 POI 搜索。
- 运营地图：查看 POI 内容覆盖、互动热度、收藏、评论和媒体概览。
- 管理员管理：`super` 可把管理员调整为 `admin`、`read` 或 `none`，不可直接授权另一个 `super`。
- 审计日志：查看关键后台操作，辅助排查和追责。

验收口径：

- 管理端 API 请求使用 `Authorization: Bearer <token>`。
- `none` 权限用户登录后不加载受保护媒体、运营地图或业务数据。
- 权限调整需要显式确认，避免误触提交。

### 3.5 内容与审核流程

官方内容流程：

1. 管理员创建或选择 POI。
2. 管理员上传官方影像或批量导入官方内容。
3. 系统保存媒体记录、年份、说明和文件路径。
4. 通过公开或用户端接口展示已允许展示的内容。
5. 写操作记录进入审计日志。

UGC 流程：

1. 用户登录后提交 UGC。
2. 系统保存媒体记录并设置 `review_status = pending`。
3. 管理员在 UGC 审核页查看待审核内容。
4. 审核通过后设置 `approved`，可进入展示范围。
5. 审核驳回时设置 `rejected`，必须保存驳回原因。
6. 用户可查看本人审核结果。

评论流程：

1. 用户创建评论后进入 `pending`。
2. 管理员可通过后端接口审核通过或驳回。
3. Portal 管理端当前保留页面入口，但明确标记评论审核已废弃。

### 3.6 Agent 与 MCP 辅助能力

Agent 能力服务内容维护、检索、草案生成和游客导览。

功能要求：

- `TimeCampus-Agent` CLI 提供 `rag-search`、`draft`、`ask`、`route`、`mcp-tools` 命令；`ask` 使用 LangGraph supervisor 自动分流运营智能体和游客导引智能体。
- Backend 暴露 `/mcp` Streamable HTTP MCP Server，提供 POI、影像、RAG 和文案维护相关 Tools、Resources、Prompts。
- Backend 管理端 Agent API 提供 RAG、草案、向量索引、运营执行审批和 Eval 代理。
- Portal 管理端提供运营智能体和 Agent Eval 页面；运营智能体支持创建、选择本地持久 session 并在同一上下文中多轮完成任务。
- 运营回答通过 SSE 流式显示并使用 Markdown 渲染；运营写工具仍必须经过质量门禁与逐项人工审批。
- 游客导览继续保持无聊天入口，只提供景点查询、热门路线与地图路线规划。
- 草案生成必须带有 grounding、actionSafety、completeness、citationDensity、overall 等质量评分。
- 管理写入执行线默认为 `overall >= 85` 且 `actionSafety >= 80`；低于执行线只生成草案，不自动写入。
- 游客导览通过 `POST /api/v1/map/walking-route` 生成步行路线总距离、总耗时、分段摘要和地图折线路径。

安全要求：

- Agent 写入前必须先检索上下文，再读取当前记录。
- 文案改动优先使用 copy-only 工具。
- 删除、版权不明、年份/地点/来源不明确的任务必须人工确认。
- 生产 MCP 必须开启 token 鉴权。

## 4. 权限矩阵

| 能力 | 游客 | 小程序用户 | read | admin | super | none | Agent/MCP |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 浏览门户首页 | 是 | 是 | 是 | 是 | 是 | 是 | 不适用 |
| 浏览公开校园地图 | 是 | 是 | 是 | 是 | 是 | 是 | 可读 |
| 微信登录 | 否 | 是 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 收藏、UGC、本人审核结果 | 否 | 是 | 否 | 否 | 否 | 否 | 仅通过授权 API |
| 管理端登录 | 否 | 否 | 是 | 是 | 是 | 是 | 可通过配置凭据 |
| Dashboard/日志/运营地图查看 | 否 | 否 | 是 | 是 | 是 | 否 | 可读，取决于 token |
| POI 和内容写操作 | 否 | UGC 上传 | 否 | 是 | 是 | 否 | 需安全门槛和授权 |
| 审核操作 | 否 | 否 | 否 | 是 | 是 | 否 | 需安全门槛和授权 |
| 管理员角色和状态调整 | 否 | 否 | 否 | 否 | 是 | 否 | 不建议自动化 |
| MCP/RAG 索引重建 | 否 | 否 | 否 | 是 | 是 | 否 | 是，需生产 token |

## 5. 业务规则

- API 统一响应格式为 `{"code":0,"message":"ok","data":...}`，文件流等资源响应除外。
- 用户端和管理端 token 都通过 `Authorization: Bearer <token>` 传递。
- 管理端生产登录必须开启 Cap 校验；前端只保存 Cap site endpoint，不保存 secret。
- 管理员角色为 `super`、`admin`、`read`、`none`。
- POI `status = 1` 表示上架，`status = 0` 表示下架。
- 媒体类型为 `official`、`ugc`，MCP 查询中还可能出现维护语境下的 `memo` 类型。
- 审核状态为 `pending`、`approved`、`rejected`。
- 驳回 UGC、评论或媒体时必须提供明确原因。
- 数据库初始化脚本默认不创建物理外键，关联完整性由应用层校验。
- 本地存储文件必须位于 `storage.local-root-dir` 下，后端读取文件时需要阻止路径穿越。
- 不得提交 `.env`、`application-dev.yaml`、`application-prod.yaml` 或任何真实密钥。

## 6. 接口范围摘要

用户端：

- Auth：`/api/v1/auth/wechat/login`
- User/Me：`/api/v1/me`、`/api/v1/users/{id}`、审核结果查询
- POI/Content：`/api/v1/pois`、`/api/v1/contents`、`/api/v1/timeline`
- Favorite/UGC/Comment：`/api/v1/favorites`、`/api/v1/ugc`、`/api/v1/comments`
- Map/Media：`/api/v1/map/**`、`/api/v1/media/{id}/file`

公开 Portal：

- `GET /api/v1/portal/map/home`

管理端：

- Auth/Accounts：`/api/v1/admin/login`、`/api/v1/admin/register`、`/api/v1/admin/accounts`
- Content：`/api/v1/admin/pois`、`/api/v1/admin/contents`、`/api/v1/admin/media`
- Review：`/api/v1/admin/ugc`、`/api/v1/admin/comments`
- Ops：`/api/v1/admin/dashboard/stats`、`/api/v1/admin/map/**`、`/api/v1/admin/logs`
- Agent：`/api/v1/admin/agent/**`

更详细的控制器分组、数据模型和集成说明见 [技术规格说明书](technical-spec.md)。

## 7. 非功能要求

- 可用性：生产公网入口只暴露 Nginx `80/443`，后端和 Compose 依赖服务默认只监听服务器本机或 Docker 内网。
- 性能：门户首页不加载地图 SDK；图片使用懒加载；公开地图按需加载数据。
- 安全：密钥只在服务端或构建环境注入；生产 MCP、Cap、数据库、Redis 均需真实强密钥。
- 可审计：关键写操作写入 `log` 表。
- 可测试：后端以 `mvn test` 覆盖核心服务、控制器、鉴权和回归；Portal 以 `pnpm typecheck`、`pnpm lint`、`pnpm build` 做质量门槛；Agent 以 `uv run pytest` 验证 CLI 和配置。
- 可维护：文档分层更新，不在 README 中堆叠完整业务规则。

## 8. 出口检查清单

功能改动合入前，至少确认：

- 新增或变更的角色、流程、权限、状态是否已更新本文档。
- 新增或变更的接口是否已更新 [技术规格说明书](technical-spec.md) 和后端 OpenAPI/ApiFox。
- 新增配置是否已同步 `.env.example` 或 `application-*-example.yaml`。
- 新增数据表或字段是否已同步 `schema.sql` 和数据库说明。
- Portal 管理端路由、后端控制器和 README 中的页面/接口名称一致。
- Agent/MCP 写入类能力是否保留“先检索、再读取、再建议/执行”的安全流程。
