# TimeCampus AI 产品测试工程面试材料

## 4-5 行 STAR

1. 围绕 AI Agent、RAG 与智能客服类产品的质量保障，在 TimeCampus 中建设 `Spring Boot + Spring AI MCP + LangGraph` 的端到端评测闭环。
2. 建设 31 条版本化 JSONL 数据集，其中 16 条独立 RAG Benchmark 覆盖 POI 精确/语义查询和人工标注的校史影像，并覆盖多轮上下文、Prompt Injection、空召回、路线降级与 HITL。
3. 实现 Fixture/真实 Live 双模式、1-5 次重复运行、Recall/MRR/Hit@1/Faithfulness/安全/一致性/P50/P95 指标，以及通过率、平均分、一致性和高风险用例四重门禁。
4. 建设 SSE 实时评测、最近 20 次版本历史、append-only Bad Case 库，并由 Java Backend 完成 RBAC 与流式代理，Portal 提供结果对比和工具轨迹工作台。
5. 生产实测检索 Benchmark 80/80、Recall@5/MRR/Hit@1 均 100%、P95 532 ms；真实 DeepSeek + LangGraph + MCP 端到端三轮 6/6 通过，平均分 99.51、Faithfulness 100。

## 核心代码讲解

1. 数据入口：`evaluation/cases.jsonl` 定义输入、期望工具、风险等级、指标与 Fixture Trace。
2. 执行入口：`EvalRunner` 根据 mode 调用 Fixture 或真实 Operations/Guide Agent，并对每个 case 重复 1-5 次。
3. 真实链路：Operations 使用 `ChatDeepSeek + MultiServerMCPClient + HumanInTheLoopMiddleware`；Guide 调用 POI 解析和 Backend 路线服务。
4. 评分与门禁：确定性 scorer 产出逐指标分数，summary 聚合通过率、平均分、一致性和 P50/P95，高风险失败直接阻断。
5. 质量闭环：FastAPI 发 SSE，Spring Boot 校验 ADMIN/SUPER 并转发，Portal 展示轨迹；失败结果可去重写入 Bad Case JSONL 并补处理结论。
6. 发布：CI 完成测试，服务器获取精确 Git SHA 并用 uv/Maven/pnpm 本地构建，随后执行健康检查和失败回滚，不使用 SCP 上传产物。

## 面试追问

### 为什么不直接引入 DeepEval 或 Promptfoo？

项目需要同时表达 LangGraph HITL、Spring AI MCP 参数、路线结构和现有管理员权限。完整平台会引入额外运行时和数据模型；这里借鉴指标与回归方法，用小型确定性 scorer 保持 CI 可复现。后续可导出统一 trace 接入外部平台。

### Fixture 和 Live 的边界是什么？

Fixture 验证数据集、评分器、报告和前端回归，不访问网络。Live 必须真实调用模型和工具；仅对超时等异常做显式故障注入。系统记录 mode、模型、Git SHA、Prompt/Dataset 版本，避免把 Fixture 结果当模型效果。

### 如何测试大模型的不确定性？

同一 case 重复 1-5 次，按通过状态与关键指标计算一致性；同时记录各次 trace 和 P50/P95。门禁要求一致性不低于 80%，Live 默认三轮。

### 如何判断工具调用正确？

分别检查工具集合、禁止工具、必需参数、调用顺序和结果结构。运营写工具必须先 RAG/读取并触发 HITL；删除工具根本不注入 Agent。导览先解析 POI，再调用路线工具。

### RAG 指标为什么同时有 Recall 和 MRR？

Recall 检查相关资料是否进入 Top-K，MRR 检查首条相关资料的排名，Hit@1 直接约束第一名。Benchmark 使用稳定 `timecampus://` 业务 URI 做人工标注，并用 source diversity 检查重复资料挤占结果。

### Bad Case 如何形成闭环？

失败结果由管理员确认后写入 append-only JSONL，按 run/case 去重；修复后追加 `resolved` 和处理结论，不覆盖历史。下一步是将确认后的 Bad Case 晋升为正式数据集用例。

### 系统目前的限制是什么？

文件存储适合单实例和面试项目，不支持多 Agent 实例并发共享；HITL checkpoint 使用内存，重启后未完成审批失效；当前确定性指标不能完全替代人工语义评审。

## PPT 提示词

请生成 8 页中文技术面试 PPT，风格为数据密集型工程评审，不使用营销式大标题：

1. 岗位需求与 TimeCampus 质量问题
2. Java Backend + Spring AI MCP + LangGraph 架构
3. 31 条版本化数据集、16 条 RAG Benchmark 与风险覆盖矩阵
4. Fixture/Live 执行链和 HITL 安全边界
5. Recall、MRR、上下文、安全、一致性、P95 指标与门禁
6. SSE 质量工作台、版本对比和 Bad Case 闭环
7. 基线/首次退化/最终候选对比与真实 Live 三轮结果
8. 当前限制和演进到数据库/分布式评测平台的方案

每页给出 3-5 个要点和建议图表；只使用本文记录的实测数字，不虚构提升比例。
