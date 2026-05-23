---
description: Consult a senior advisor (config-driven: currently opencode-go/glm-5.1). Invoke when escalation rules in §3 are met.
---

# consult-codex — Reasonix 总控 + 顾问 工作流规范

> **当前顾问：** opencode-go/glm-5.1（由 `.reasonix/config.json` 中 `advisor.provider` 决定）
> **后备：** codex/gpt-5.5（`config.json` → `codex` 节）

## 1. 角色定义

| 角色 | 身份 | 职责 |
|------|------|------|
| **总控 (Reasonix)** | 常驻执行器 (DeepSeek V4 Pro) | 持有主上下文、改代码、跑测试、维护状态、识别升级条件、吸收建议后继续执行 |
| **顾问 (Advisor)** | config 指定的模型（当前: GLM 5.1 via opencode） | 按需调用，提供结构化建议（decision/rationale/risks/next_steps/checks） |
| **用户** | 最终裁决者 | 设定目标、发起任务、确认/拒绝计划、验收结果 |

默认原则：
- Reasonix 负责执行和推进，Advisor 负责高价值判断和审查
- **Advisor 模型必须与 Reasonix 不同模型家族**（Reasonix 是 DeepSeek V4 Pro，Advisor 应选 GLM / GPT / Qwen 等），**多样性 > 强度**
- Advisor 不默认拥有写仓库、跑项目命令、做 Git 操作的权限
- 不要把长会话原样发给 Advisor
- 调用 Advisor 前必须压缩上下文

---

## 2. 自问闸门：是否真正需要升级？

在检查升级规则前，Reasonix 必须先问自己：

> **这个问题我能否凭当前上下文自信回答？**

| 判断 | 行动 |
|------|------|
| 能 → 不调用 Advisor，直接执行 | 继续日常执行（§1 定义的任务） |
| 不能 → 继续检查是否满足升级条件 | 进入 §3 |

这个闸门防止低价值问题消耗顾问模型 tokens 和增加延迟。只有当 Reasonix 的判断力或信息量不足时，才将问题升级。

---

## 3. 何时调用 Advisor（升级规则与模式选择）

通过自问闸门后，只有在以下条件之一满足时，才调用 Advisor。**同时选择对应的 Mode。**

| # | 触发条件 | 使用 Mode | 原因 |
|---|---------|----------|------|
| 1 | 多个方案之间做选择 | **`decide`** | 需要权衡、决策输出 |
| 2 | 实验结果与预期冲突 | **`discuss`** | 需要分析、形成假设 |
| 3 | 同一 bug 两次尝试未解决 | **`discuss`** | 需要根因分析 |
| 4 | 核心接口/训练流程变更 | **`decide`** | 需要设计决策 |
| 5 | 较大 diff 设计层 review | **`review`** | 需要结构化代码审查 |
| 6 | 论文 claim/ablation 判断 | **`decide`** | 需要判断性结论 |
| 7 | 复杂根因分析 | **`discuss`** | 需要假设 + 诊断计划 |

**不要因为以下事项调用 Advisor：**

- 常规实现、小 bug 修复、常规 refactor
- 测试执行、SSH 命令、Git 日常操作
- 简单日志整理、机械性代码修改

### 3.1 代码 Review Gate（强制）

**任何代码修改完成后，必须交由 Advisor review。** 使用 **`review`** 模式。

- 调用：`-Mode review -Context "<DIFF> + PURPOSE + DESIGN_DECISIONS + FOCUS_AREAS>"`
- Review 必须覆盖：逻辑正确性、隐藏耦合、初始化纪律、梯度流
- Review 通过后才可以提交或启动训练
- 例外：纯文档修改、`.gitignore` 变更、commit message 修改等无代码逻辑变更的操作

### 3.2 模型选择：按领域分工

| 问题领域 | 推荐模型 | 原因 |
|---------|---------|------|
| 代码 review、实现细节、bug 分析 | **GLM 5.1**（默认） | 速度快、代码级建议准确 |
| 架构设计、模型优化、研究方向 | **GPT-5.5** | 架构/模型类问题需要 OpenAI 系的知识多样性 |
| 工作流规范、skill/config 设计 | **GLM 5.1** | 日常 T1-T3，默认选择 |

切换方式：修改 `.reasonix/config.json` → `advisor.provider`（`opencode` = GLM，`codex` = GPT-5.5）。

---

## 4. 问题难度评估与推理强度选择

确定需要调用 Advisor 后，Reasonix 必须先评估问题难度，选择对应的推理强度级别。**模型不随难度切换**（固定用一个，调的是 `variant`）。

> **推理强度映射：** `low` / `medium` / `high` / `xhigh`
> - opencode: 通过 `--variant` 传递（对应值: `low` / `medium` / `high` / `max`）
> - codex: 通过 `-c model_reasoning_effort=` 传递
> - 配置位置: `.reasonix/config.json` → `advisor.variant`（opencode）或 `codex.reasoning_effort`（codex）
> - 环境变量覆盖: `ADVISOR_VARIANT` / `CODEX_REASONING_EFFORT`

| 层级 | 边界判断 | 推荐 variant | 典型问题示例 |
|------|---------|------------|-------------|
| **T1 常规查证** | 单文件/单命令问题，无架构权衡，答案可立即验证 | `low` | "添加 multiply 后应该跑 pytest 吗？" "这个 stderr 行为是预期的吗？" |
| **T2 局部实现判断** | 需要在 2-3 个合理选项中选择，影响范围限于一个脚本/一个文件/一个工作流步骤 | `medium` | "ask_codex.ps1 的超时应从 config 读取还是仅用 CLI 参数？" "日志应该怎样分层？" |
| **T3 架构/工作流决策** | 影响多个文件、未来扩展、Reasonix 行为、测试策略或用户可见约定 | `high` | "Reasonix 应该怎样决定何时调用 Advisor？" "consult-codex 应该以 skill 还是 config 驱动？" |
| **T4 战略/模糊/高代价决策** | 改变项目方向、总控/顾问职责边界、信任模型、自动化策略或长期治理 | `xhigh` | "Reasonix 和 Advisor 的正确职责划分是什么？" "这个 POC 应该演进为通用编排框架吗？" |

**选择指引：**
- 不确定时默认 `medium`
- 如果决策难以撤销，升一级
- 如果问题涉及 `.reasonix/skills/`、`.reasonix/config.json` 或控制器行为变动，升一级
- 普通代码添加（如 `multiply`）不超过 `medium`，除非问题涉及 API 方向或工作流策略

---

## 5. 调用前准备（上下文压缩）

确定推理强度后，将上下文压缩为最小必要信息。

### 5.1 调用接口

```powershell
# 基本形式
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 `
  -Mode <decide|review|discuss> `
  -Question "<核心问题>" `
  -Context "<Reasonix 组装的结构化上下文>"

# review 模式不需要 -Question（diff 本身即审查对象）
powershell ... -Mode review -Context "<DIFF + 元信息>"
```

Reasonix 负责组装 `-Context`，按模式填充下面的清单。

### 5.2 上下文组装清单（按模式）

#### decide 模式 — 方案决策

`-Context` 必须包含以下块（每条用英文写）：

```
GOAL: <我们要达成什么目标？一句话>
OPTIONS:
  A: <方案A描述 + 优点/缺点>
  B: <方案B描述 + 优点/缺点>
  (C: 可选)
CONSTRAINTS: <不能改的东西 — 接口、性能要求、时间窗口>
AFFECTED_CODE: <关键代码段或文件路径，贴代码不要贴文件名>
REASONIX_LEANING: <Reasonix 目前倾向哪个方案？不确定什么？>
```

#### review 模式 — 代码审查

`-Context` 必须包含：

```
DIFF: <git diff 完整输出或关键片段>
PURPOSE: <这次修改要达成什么？>
DESIGN_DECISIONS: <做了哪些关键设计取舍？>
FOCUS_AREAS: <希望 advisor 重点关注什么？>
RELATED_FILES: <可能被波及的文件>
```

#### discuss 模式 — 讨论分析

`-Context` 必须包含：

```
PROBLEM: <问题全貌，越详细越好>
TRIED_SO_FAR:
  - <尝试1> → <结果>
  - <尝试2> → <结果>
KEY_LOGS: <错误信息、指标变化、关键数值>
WHY_STUCK: <为什么 Reasonix 卡住了？矛盾在哪里？>
ELIMINATED_HYPOTHESES: <已排除的假设及排除原因>
```

### 5.3 通用压缩规则

不要发送：

- 整段聊天记录
- 大量无关代码
- 与当前决策无关的旧尝试
- 冗长背景叙述

### 5.4 语言与编码

**使用英文与 Advisor 交流。** 原因：

- ……→ Windows-1252 乱码）
- Advisor 模型（GLM / GPT 等）英文能力同样优秀
- 结构化关键词（decision / rationale / risks / next_steps / checks）本身是英文

如果用户的问题或上下文包含中文，在压缩时**翻译成英文**再发送给 Advisor。

**PROJECT_STATE.md 硬性规则**：

- **PROJECT_STATE.md 必须全 ASCII 书写。禁止中文、全角标点、emoji。**
- 原因：`scripts/ask_codex.ps1` 在注入 prompt 前对内容做 ASCII sanitization，非 ASCII 字符全部替换为 `?`。如果关键信息（FID 值、epoch 数、路径）夹杂在中文描述中，sanitize 后 advisor 收到的 prompt 将不可读。
- 人名、数字、路径、指标、状态关键词（done/running/failed 等）必须使用 ASCII 字符
- 违反此规则 → advisor 调用时 PROJECT_STATE 信息被毁 → 顾问决策基于残缺上下文 → 风险自负

### 5.5 Agent 行为控制（重要）

> `opencode run` 和 `codex exec` **两者都启动 agent**（不是纯 LLM 补全），默认有 grep、read、bash 等工具权限。

**当前策略：鼓励只读探索**

- Advisor 可以自由使用 **grep、read、glob** 探索代码库，补充上下文
- **bash、edit、write 被 prompt 禁止**——advisor 是只读顾问
- 质量优先于速度：advisor 可以花时间深入探索，给出带文件引用的具体答案
- 超时风险通过 **后台执行**（§6）解决，不再通过限制工具来规避

**Reasonix 的职责：**

- 仍通过 `-Context` 提供初始简报（按 §5.2 清单）——好的起点降低探索成本
- 但不过度追求"一次性塞够"——允许 advisor 自行补全

### 5.6 探索指引（Project Map）

> Advisor 探索代码库时是"盲搜"——第一轮 grep 可能命中 50 个文件，浪费工具调用。提供文件地图可以引导 advisor 直接命中目标。

**Reasonix 在调用 advisor 前必须：**

1. 用 `directory_tree` 或 `glob` 获取与问题相关的目录结构
2. 在 `-Context` 中追加 `PROJECT_MAP` 块：

```
PROJECT_MAP (auto-generated by Reasonix — relevant files for this question):
  training loop: experiments/common/trainer.py (train function, line ~69)
  model:         experiments/spike_jit_snn_stv2/models.py (STV2Model, STV2FeatureBlock)
  loss:          experiments/spike_jit_snn_stv2/objectives.py (compute_v_loss)
  config:        experiments/common/config.py (TrainingConfig)
  runtime:       experiments/common/runtime.py (Accelerator wrapper, _SingleProcessAccelerator)
```

**规则：**
- 只列与当前问题相关的文件（不是全项目地图）
- 标注关键符号/行号作 hint
- 来源：PROJECT_STATE.md Repo map + 本次 `directory_tree` 实时扫描
- **动态生成，不手写**——每次调用前重新扫

---

## 6. 调用命令（后台执行）

> **核心原则：** Advisor 可以自由探索代码库（§5.5），响应时间不可预测。因此**禁止使用 `run_command`**（会被沙箱超时杀掉），必须使用 `run_background` + `wait_for_job`。

### Reasonix 调用模式

```
// Step 1: 启动后台 job
run_background(
  command: "powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Mode decide -Question '...' -Context '...'",
  waitSec: 0
)
→ 返回 job_id

// Step 2: 等待完成（或超时）
wait_for_job(job_id, timeoutMs: 600000)  // 10 分钟
→ 返回 { exited: true, exitCode: 0, latestOutput: "..." }

// Step 3: 解析 latestOutput 中的 advisor 响应

// Step 4: 如果 exitCode != 0，按 §B 排查
```

> **注意：** `run_background` 不支持 shell redirect（`2>&1`），也不需要——后台模式自动捕获 stdout + stderr。

脚本自动从 `.reasonix/config.json` 读取 `advisor.provider` 决定使用 opencode 还是 codex：

- **opencode** 模式：`opencode run --model <model> --variant <effort> --format json <prompt>`，解析 JSONL 提取响应
- **codex** 模式：`codex exec --model <model> --sandbox <sandbox> -c model_reasoning_effort=<effort> <prompt>`

推理强度通过 `.reasonix/config.json` 或环境变量控制：

脚本自动从 `.reasonix/config.json` 读取 `advisor.provider` 决定使用 opencode 还是 codex：

- **opencode** 模式：`opencode run --model <model> --variant <effort> --format json <prompt>`，解析 JSONL 提取响应
- **codex** 模式：`codex exec --model <model> --sandbox <sandbox> -c model_reasoning_effort=<effort> <prompt>`

推理强度通过 `.reasonix/config.json` 或环境变量控制：
- opencode: `config.json` → `advisor.variant` / env `ADVISOR_VARIANT`
- codex: `config.json` → `codex.reasoning_effort` / env `CODEX_REASONING_EFFORT`

### 6.1 wait_for_job 超时建议

| 问题规模 | 推荐 timeoutMs | 说明 |
|---------|---------------|------|
| T1 常规查证 | 120000 (2min) | 简单 yes/no，几乎不需要探索 |
| T2 局部分析 | 300000 (5min) | 2-3 选项判断，可能读 1-3 个文件 |
| T3 架构决策 | 600000 (10min) | 多文件设计，需要追踪依赖 |
| T4 战略问题 | 900000 (15min) | 复杂推理，大量文件探索 |

> **注意：** 超时后 `wait_for_job` 返回 `exited: false`。此时应检查日志文件（`latestOutput` 可能包含部分输出），判断是 advisor 仍在探索还是已卡死。如卡死，按 §B 排查。

---

## 7. 顾问输出格式（按模式）

### 7.1 decide 模式

```yaml
decision: <clear choice with brief justification>
rationale:
- <bullet points citing specific evidence from the context>
risks:
- <what could go wrong with this decision>
next_steps:
- <concrete actions if the decision is accepted>
checks:
- <how to verify the decision was correct later>
```

### 7.2 review 模式

```yaml
summary: <approve | changes-requested | comment>

findings:
- file: <path>
  line: <line or range>
  severity: <critical | major | minor | nit>
  category: <logic | coupling | init | gradient | perf | style>
  description: <concrete issue>
  suggestion: <specific fix>

overall_notes:
- <cross-cutting observations or praise>
```

### 7.3 discuss 模式

```yaml
analysis: <free-form analysis of the situation>
key_observations:
- <important facts or constraints from the context>
hypotheses:
- <possible explanations or approaches, ranked by likelihood or merit>
open_questions:
- <what additional information would help narrow this down>
recommendation: <your top suggestion for what to try next>
```

---

## 8. 吸收建议（Reasonix action plan）

Reasonix 接收 Advisor 的结构化输出后，按以下格式形成执行决策。**输出格式随 Mode 变化**（见 §7），解释时注意对应关系。

```markdown
## Advisor advice (<mode>)
（展示 Advisor 的原始输出）

## Reasonix action plan

**处置：** <accepted | partially_accepted | rejected | deferred>
**接受：** ✅ ...
**驳回/修改：** ❌ / 🔧 ...（说明理由）
**延期理由（如适用）：** ...
**下一步 concrete actions：**
1. ...
2. ...
**验证方式：** ...
```

### 处置状态定义

| 状态 | 含义 | 后续要求 |
|------|------|---------|
| `accepted` | 完全采纳 Advisor 建议 | 按 next_steps 执行，更新状态 |
| `partially_accepted` | 部分采纳，部分驳回或修改 | 在 action plan 中说明驳回哪些、为什么 |
| `rejected` | 驳回全部建议 | 说明理由，记录到 PROJECT_STATE.md Verified results |
| `deferred` | 当前不执行，延后评估 | 说明延期原因和重新评估条件 |

**无论采纳与否，均须记录到 PROJECT_STATE.md。**"已记录 Advisor 建议但未采纳"本身就是有价值的决策痕迹。

### 8.1 答案验证（防幻觉）

> Advisor 可能引用不存在的文件或行号（幻觉）。Reasonix 必须在吸收建议前做快速验证。

**验证步骤：**

1. 从 Advisor 回答中提取所有 `file:line` 引用（如 `trainer.py:69`、`models.py:142-158`）
2. 对每个引用用 `read_file(path, range="行号-行号")` 验证该行是否存在
3. 如果引用不存在 → 标记为 **疑似幻觉**，记录到 PROJECT_STATE.md：
   ```
   | 2026-05-23 | Advisor hallucination check | ⚠️ | trainer.py:420 cited but file has 380 lines |
   ```
4. 如果 ≥2 处引用不存在 → 考虑换模型或调整 prompt 重问

**注意：** 此验证是**可信度检查**，不是正确性验证。advisor 可能引用真实存在的行但给错误的建议——那需要人判断。

---

## 9. 状态与进度管理

### 9.1 更新时机（强制规则）

每次以下操作后，**必须**更新 `PROJECT_STATE.md` 的对应章节：

| 操作 | 必须更新的章节 |
|------|--------------|
| 改代码 / 加功能 | `Current behavior`、`Verified results`（新增行） |
| 跑测试 | `Verified results`（更新对应行状态） |
| 咨询 Advisor（无论是否采纳建议） | `Verified results`（新增行，含 reasoning_effort 和模型名）、`Current behavior`（如有采纳） |
| 修改配置 / 工作流文件 | `Current behavior`、`Repo map` |
| 方向性变化 | `Design (intended)`、`Next candidate actions` |

**不更新 = 下次启动时基于 stale 状态做决策，后果自负。**

### 9.2 剪枝规则

`Verified results` 表格超过 **10 行**时，将最早的已关闭条目归档：

```markdown
# 归档方式
将早期已验证项从 Verified results 中移除，追加到 .reasonix/archive/<date>-verified.md
保留最新 5 行 + 所有 Open problems 行。
```

### 9.3 咨询回写

咨询完成后，必须更新 `PROJECT_STATE.md`：

- 在 `Verified results` 中记录本次咨询的输出（含使用的 `reasoning_effort`、模型名和处置状态）
- 在 `Current behavior` 中反映采纳决策后的实际变化
- 如果咨询改变了方向，更新 `Next candidate actions`

### 9.4 配置/规范漂移检测

`.reasonix/config.json`、本文件（`consult-codex.md`）和 `scripts/ask_codex.ps1` 三者可能在长期维护中悄然不一致。每次工作流文件变更后，检查以下内容：

- `config.json` 中 `advisor.provider` 是否有效（`opencode` 或 `codex`）？
- `config.json` 中 `advisor.model` 是否为 `opencode models` 列表中的合法模型？
- `scripts/ask_codex.ps1` 是否正确读取 `config.json` → `advisor` 和 `codex` 两个节？
- `config.json` 的 `codex.log_dir` 是否与脚本日志路径一致？

---

## 10. 约束

Unless the user explicitly asks otherwise:

- 不让 Advisor 直接改仓库文件
- 不让 Advisor 直接执行项目命令
- 不让 Advisor 直接做 Git 操作

Reasonix 始终是主执行器。Advisor 只是顾问。

---

## B. 故障排查

### B.1 wait_for_job 超时（exited: false）

**症状：** `wait_for_job` 返回 `exited: false`，advisor 未在超时内完成。

**原因：** advisor 探索范围过大，或某个工具调用卡住（Crush #2854）。

**解决：**
1. 检查日志文件 `.reasonix/logs/advisor-*.jsonl`，查看已完成的 tool_use——判断 advisor 探索到了什么程度
2. 如果 tool_use 显示 advisor 在循环读同一个文件，可能是陷入了分析僵局 → 缩小问题范围，拆成更小的子问题
3. 如果没有任何 tool_use 输出，可能是 opencode/codex CLI 本身挂起 → 提高 timeoutMs 重试
4. 如果日志显示 `bash` 工具被调用（不应该发生），说明 prompt 限制没生效 → 检查 prompt 模板

### B.2 exitCode != 0

**症状：** `wait_for_job` 返回 `exitCode: 1` 等非零值。

**原因：** 脚本执行失败（config 错误、PROJECT_STATE.md 缺失、provider 不可用）。

**解决：**
1. `latestOutput` 中包含错误信息，直接阅读
2. 常见原因：`.reasonix/config.json` 格式错误、advisor.provider 值无效、API key 未设置
3. 确认 JSONL 日志文件存在且可读

### B.3 Advisor 未探索代码库就给出了答案

**症状：** JSONL 日志中没有 `tool_use` 事件，直接返回了 `text`。

**原因：** 不一定是问题。如果 prompt 中的 `-Context` 和 `PROJECT_STATE` 已经足够，advisor 可能不需要额外探索。

**判断：** 检查答案质量——如果答案是具体的、引用代码细节的，说明上下文已足够。如果答案是泛泛的、没有文件引用，说明 advisor 应该探索但没探索 → 检查 prompt 模板中的工具允许指令是否生效。

---

## 附录：选择顾问模型

### 核心原则

> Reasonix 本身就是 DeepSeek V4 Pro，所以顾问模型不要选 DeepSeek 系
> Advisor 的价值在于不同模型家族带来的知识多样性，不是更强的推理

### 推荐模型

| 模型 | 优势（对比 DS V4 Pro） | 适用场景 |
|------|----------------------|---------|
| **GLM 5.1**（当前默认） | GLM 系列，代码级建议准确、速度快 | 日常 T1-T3、代码 review、实现细节、bug 分析 |
| **GPT-5.5** (codex) | OpenAI 系，知识面差异最大 | 架构设计、模型优化、研究方向讨论 |
| **Qwen 3.6 Plus** | 阿里 Qwen 系 | 中文技术文档分析 |

### 不推荐的模型

- `deepseek-v4-pro` — 和 Reasonix 重复，没有多样性收益
- `deepseek-v4-flash` — 同家族更弱，也没有多样性收益

### 切换方式

修改 `.reasonix/config.json`：

```json
{
  "advisor": {
    "provider": "opencode",
    "model": "opencode-go/glm-5.1",
    "variant": "medium"
  }
}
```

可用模型列表：运行 `opencode models` 查看 `opencode-go/` 前缀的所有模型。
