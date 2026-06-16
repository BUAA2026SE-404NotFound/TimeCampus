# TimeCampus Agent Evaluation

本文说明 `TimeCampus-Agent` 的轻量 Agent Eval Harness。目标是把后台运营维护 Agent 和游客导览 Agent 的质量从人工试跑变成可复现、可回归、可进入 CI 的评测流程。

## 设计参考

本框架采用自研核心，不绑定 SaaS 或单一评测库。设计上参考：

- LangSmith：dataset -> evaluators -> experiment 的生命周期。
- DeepEval：面向 LLM apps / agents / RAG 的 pytest-like 评测体验。
- Ragas 与 TruLens：RAG 评估里的 context relevance、groundedness、answer relevance。
- Promptfoo：CLI、报告、CI/CD 和安全测试思路。
- Giskard：prompt injection、越权、敏感信息等 Bad Case/安全扫描思路。
- Anthropic Agent Evals：评测 harness 要记录工具、步骤、输出和最终环境状态。

## 架构

核心对象：

- `EvalCase`：评测数据集条目，包含 `id`、`suite`、`target`、`input`、`expected`、`checks`、`tags`、`riskLevel`。
- `AgentTrace`：Agent 或工具执行轨迹，包含 `output`、`toolCalls`、`retrievedDocs`、`routePlan`、`latencyMs`、`error`。
- `EvalResult`：单 case 评分，包含 `metrics`、`overall`、`passed`、`failureReasons`、`badCaseTags`。

评测模式：

- `fixture`：默认 CI 模式，使用固定 trace，不访问网络、不依赖后端、不依赖真实模型 key。
- `live`：本地或服务器联调模式，正常路径真实调用 Backend MCP RAG 和公开 route API；校验型 Bad Case 使用 deterministic trace，避免外部地图服务随机性影响门禁。

## 指标

通用指标：

- `taskCompletion`：是否完成用户意图。
- `schemaValidity`：输出结构和必要字段是否存在。
- `toolCorrectness`：工具选择是否符合 expected，禁止工具是否未被调用。
- `errorFree`：非预期异常是否为零。
- `latencyMs`：记录耗时，不作为默认阻断项。

后台维护 Agent：

- `ragGrounding`：是否先检索并引用 POI、media、comment 或 guideline。
- `citationCoverage`：是否包含 `timecampus://...`、media id 或 poi id。
- `toolOrderSafety`：写工具前是否已有 RAG/读工具。
- `actionSafety`：删除、版权不明、年份/坐标不明时是否停止并要求人工确认。
- `hallucinationRisk`：是否出现上下文不支持的年份、地点、人物或来源。

游客导览 Agent：

- `routeValidity`：路线是否包含 legs、总距离和总耗时。
- `waypointOrder`：路线点顺序是否与输入一致。
- `poiGrounding`：导览文案是否覆盖用户给定 POI。
- `visitorHelpfulness`：是否给出面向游客可读的路线摘要。
- `safetyBoundary`：是否拒绝非法坐标、过多点位或不可用路线结果。

可选 LLM-as-judge 通过 `TIMECAMPUS_EVAL_LLM_ENABLED=true` 开启，只增强开放式指标，不作为默认 CI 阻断项。

## 命令

```powershell
cd TimeCampus-Agent
uv run timecampus-agent eval list
uv run timecampus-agent eval run --suite all --mode fixture --report-dir eval-reports --min-pass-rate 0.85 --min-overall 80
uv run timecampus-agent eval run --suite maintenance --mode live
uv run timecampus-agent eval run --suite guide --mode live
```

报告产物：

- `eval-reports/eval-report.json`：CI 与机器解析。
- `eval-reports/eval-report.md`：面试展示、人工复盘和 Bad Case 沉淀。

## CI 门禁

默认 CI 只跑 fixture 模式：

```bash
uv run pytest
uv run ruff check .
uv run timecampus-agent eval run --suite all --mode fixture --report-dir eval-reports --min-pass-rate 0.85 --min-overall 80
```

门槛：

- pass rate >= 85%。
- average overall >= 80。

失败 case 不直接写入 tracked dataset。先由人工判断是否代表真实产品风险；确认后再把它沉淀为固定回归用例。
