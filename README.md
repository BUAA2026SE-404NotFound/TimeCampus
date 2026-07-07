# TimeCampus 时光航迹

TimeCampus 是面向校园历史影像浏览、点位共创和运营维护的系统，中文产品名为“时光航迹”。根仓库负责跨模块文档和生产依赖服务编排，三个子模块分别承载门户/管理端、后端 API/MCP 和 Agent CLI。

## 模块

| 模块 | 职责 | 文档 |
| --- | --- | --- |
| `TimeCampus-Portal` | React 门户首页、公开校园地图、Web 管理端 | [README](TimeCampus-Portal/README.md) |
| `TimeCampus-Backend` | Spring Boot REST API、数据访问、鉴权、MCP/RAG、第三方服务封装 | [README](TimeCampus-Backend/README.md) |
| `TimeCampus-Agent` | 纯 Python 运维与导览 CLI，调用 Backend API/MCP | [README](TimeCampus-Agent/README.md) |
| 根仓库 | Docker Compose 依赖服务、生产环境样例、跨模块规格文档 | [docs](docs/README.md) |

## 依赖服务

根 `compose.yaml` 只启动后端运行所需的外部依赖：

- `valkey`：Redis 兼容缓存和 Cap 限流存储。
- `cap`：管理端登录验证码服务。
- `qdrant`：RAG 向量检索。
- `ollama`：默认拉取 `embeddinggemma:300m`，提供 768 维 embedding。

生产 Web 入口使用服务器上的 Nginx；CI 测试通过后由服务器获取精确 Git SHA 并本地构建，Backend/Agent 由 systemd 管理，Portal 发布到 Nginx 静态目录。

## 快速启动

```bash
git submodule update --init --recursive
cp .env.example .env
docker compose --env-file .env -f compose.yaml up -d
```

首次启动后访问 Cap dashboard 创建 site，把 site endpoint 和 secret 写入服务器后端配置，再重启后端 systemd 服务。完整生产流程见 [docs/deploy.md](docs/deploy.md)。

## 常用命令

```bash
docker compose --env-file .env -f compose.yaml config
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs -f cap
docker compose --env-file .env -f compose.yaml logs -f qdrant
```

本地 Backend + MCP 联调：

```powershell
.\tools\start-backend-mcp.ps1
```

Agent/API 冒烟：

```bash
node tools/agent-smoke.mjs --dry-run
```

Agent 评估门禁：

```bash
cd TimeCampus-Agent
uv run timecampus-agent eval run --suite all --mode fixture --report-dir eval-reports --min-pass-rate 0.85 --min-overall 80
```

根编排回归测试：

```bash
uv run --with pyyaml python -m unittest discover -s tests
```

## 文档入口

- [文档索引](docs/README.md)
- [功能规格说明书](docs/functional-spec.md)
- [技术规格说明书](docs/technical-spec.md)
- [文档维护指南](docs/documentation-maintenance.md)
- [Agent Stack 联调说明](docs/agent-stack.md)
- [Agent 评估框架](docs/agent-evaluation.md)
- [AI 产品测试工程面试材料](docs/ai-test-interview-pack.md)

README 只作为入口；跨模块功能规则写入 [功能规格说明书](docs/functional-spec.md)，架构、接口、数据和部署规则写入 [技术规格说明书](docs/technical-spec.md)。
