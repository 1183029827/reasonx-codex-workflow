---
name: second-opinion
description: Use when facing design decisions, code review, bug analysis with 2+ failed attempts, architecture changes, or conflicting results. Triggered by uncertainty: "which approach", "should I", "review this", "why is this failing", "design decision". Enables consulting a read-only advisor from a different model family for structured second opinions.
---

# second-opinion — 总控 + 顾问 工作流规范

> 多样性 > 强度。主控模型解决不了的判断，交给不同家族的顾问模型。

## 1. 角色定义

| 角色 | 身份 | 职责 |
|------|------|------|
| **总控** | 当前 agent | 持有主上下文、改代码、跑测试、维护状态、识别升级条件、吸收建议后继续执行 |
| **顾问 (Advisor)** | 另一个 agent (不同模型家族) | 按需调用，提供结构化建议 |
| **用户** | 最终裁决者 | 设定目标、发起任务、确认/拒绝计划、验收结果 |

核心原则：
- 总控负责执行和推进，顾问负责高价值判断和审查
- **顾问模型必须与总控不同模型家族**（多样性 > 强度）
- 顾问不拥有写仓库、跑命令、做 Git 操作的权限
- 不要把长会话原样发给顾问
- 调用顾问前必须压缩上下文

---

## 2. 自问闸门

调用顾问前，先问自己：

> **这个问题我能否凭当前上下文自信回答？**

| 判断 | 行动 |
|------|------|
| 能 → 不调用顾问，直接执行 | 继续日常任务 |
| 不能 → 检查是否满足升级条件 | 进入 §3 |

---

## 3. 升级规则

只有以下条件之一满足时，才调用顾问：

| # | 触发条件 | Mode | 原因 |
|---|---------|------|------|
| 1 | 多个方案之间做选择 | `decide` | 需要权衡、决策输出 |
| 2 | 实验结果与预期冲突 | `discuss` | 需要分析、形成假设 |
| 3 | 同一 bug 两次尝试未解决 | `discuss` | 需要根因分析 |
| 4 | 核心接口/流程变更 | `decide` | 需要设计决策 |
| 5 | 较大 diff 设计层 review | `review` | 需要结构化代码审查 |
| 6 | 复杂根因分析 | `discuss` | 需要假设 + 诊断计划 |

**不要因以下事项调用顾问：**
- 常规实现、小 bug 修复、常规 refactor
- 测试执行、Git 日常操作
- 简单日志整理、机械性代码修改

### 3.1 代码 Review Gate

任何代码修改完成后，必须交由顾问 review（`review` 模式）：
- Review 覆盖：逻辑正确性、隐藏耦合、初始化纪律
- Review 通过后才可提交
- 例外：纯文档、`.gitignore`、commit message 等无逻辑变更
- T1 级修改（单文件、无架构影响、无隐藏耦合风险）可由总控自审，记录到 PROJECT_STATE.md 即可，无需调顾问

---

## 4. 难度评估

评估问题难度，选择推理强度。模型不随难度切换（固定用一个），调的是 variant/options。

| 层级 | 边界判断 | variant | 示例 |
|------|---------|--------|------|
| **T1** | 单文件问题，无架构权衡 | `low` | "这个错误是什么意思？" |
| **T2** | 2-3 选项中选择，影响≤1文件 | `medium` | "应该用函数还是 class？" |
| **T3** | 影响多个文件或未来扩展 | `high` | "如何设计模块接口？" |
| **T4** | 改变项目方向或长期策略 | `max` / `xhigh` | "架构应该怎么拆分？" |

选择指引：不确定时默认 `medium`；决策难以撤销升一级。

---

## 5. 调用前准备（上下文压缩）

### 5.1 decide 模式 — 方案决策

必须包含（英文）：

```
MODE: decide
GOAL: <一句话目标>
OPTIONS:
  A: <方案A + 优点/缺点>
  B: <方案B + 优点/缺点>
CONSTRAINTS: <不能改的东西>
AFFECTED_CODE: <关键代码段>
CONTROLLER_LEANING: <当前倾向哪个方案？不确定什么？>
EXPECTED_FORMAT: decision, rationale, risks, next_steps, checks（见 §7.1）
```

### 5.2 review 模式 — 代码审查

必须包含：

```
MODE: review
DIFF: <git diff 完整输出或关键片段>
PURPOSE: <这次修改要达成什么？>
DESIGN_DECISIONS: <关键设计取舍>
FOCUS_AREAS: <希望顾问重点关注什么？>
RELATED_FILES: <可能被波及的文件>
EXPECTED_FORMAT: summary, findings (severity, category, file, line), overall_notes（见 §7.2）
```

### 5.3 discuss 模式 — 讨论分析

必须包含：

```
MODE: discuss
PROBLEM: <问题全貌>
TRIED_SO_FAR:
  - <尝试1> → <结果>
  - <尝试2> → <结果>
KEY_LOGS: <错误信息、关键数值>
WHY_STUCK: <为什么卡住了？矛盾在哪里？>
ELIMINATED_HYPOTHESES: <已排除的假设及原因>
EXPECTED_FORMAT: analysis, key_observations, hypotheses, open_questions, recommendation（见 §7.3）
```

### 5.4 通用规则

不要发送：整段聊天记录、大量无关代码、旧尝试、冗长背景。

### 5.5 语言与编码

- 与顾问交流使用英文（避免编码管道问题）
- 结构化关键词（decision/rationale/risks/next_steps）本身是英文
- 在 opencode 同一实例内通过 Task 通信时无编码管道问题，可放宽编码限制；跨进程调用时建议 ASCII

### 5.6 Project Map

调用顾问前，用 `glob` 生成相关文件地图，追加到 Context：

```
PROJECT_MAP (auto-generated):
  training: src/trainer.py (train fn, line ~69)
  model:    src/model.py (ModelClass, FeatureBlock)
  config:   src/config.py (TrainingConfig)
```

规则：只列相关文件，标注关键符号/行号，动态生成每次重新扫。Project Map 是总控对项目结构的理解快照——顾问仍可自行 glob 补充探索。

---

## 6. 调用方式（Task 工具）

使用 opencode 原生 Task 工具调用顾问 subagent：

```
// Step 1: 构造 prompt（按 §5 清单 + PROJECT_STATE + PROJECT_MAP）

// Step 2: 调用 Task 工具，参数 subagent_type 为 "advisor"
Task(
  subagent_type: "advisor",
  description: "Advisor <mode> - <简短描述>",
  prompt: "<压缩后的上下文 + 问题>"
)
→ 返回顾问的文本响应

// Step 3: 解析响应中的结构化输出（见 §7）

// Step 4: 按 §8 做防幻觉验证
```

顾问最大迭代数由 agent 配置中的 `steps` 字段控制（推荐默认值 20）。

---

## 7. 顾问输出格式

### 7.1 decide

```yaml
decision: <choice with brief justification>
rationale:
- <bullet points citing evidence>
risks:
- <what could go wrong>
next_steps:
- <concrete actions if accepted>
checks:
- <how to verify correctness later>
```

### 7.2 review

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
- <cross-cutting observations>
```

### 7.3 discuss

```yaml
analysis: <free-form analysis>
key_observations:
- <important facts or constraints>
hypotheses:
- <possible explanations, ranked by likelihood>
open_questions:
- <what additional info would help>
recommendation: <top suggestion for what to try next>
```

---

## 8. 吸收建议

收到顾问输出后形成 action plan：

```markdown
## Advisor advice (<mode>)

## Controller action plan
**处置：** <accepted | partially_accepted | rejected | deferred>
**接受：** ...
**驳回/修改：** ...
**下一步：**
1. ...
2. ...
**验证方式：** ...
```

| 状态 | 含义 | 后续要求 |
|------|------|---------|
| `accepted` | 完全采纳 | 按 next_steps 执行，更新状态 |
| `partially_accepted` | 部分采纳 | 说明驳回哪些、为什么 |
| `rejected` | 驳回全部 | 说明理由，记录到 PROJECT_STATE.md |
| `deferred` | 延后评估 | 说明延期原因和重新评估条件 |

无论采纳与否，均须记录到 PROJECT_STATE.md。

### 8.1 防幻觉验证

1. 从顾问回答中提取所有 `file:line` 引用
2. 用 `read` 工具验证该行是否存在
3. 引用不存在 → 标记为疑似幻觉
4. ≥2 处不存在 → 换模型或调整 prompt 重问

---

## 9. 状态管理

### 9.1 PROJECT_STATE.md 规则

每次以下操作后必须更新对应章节：

| 操作 | 更新章节 |
|------|---------|
| 改代码 | `Current behavior`、`Verified results` |
| 跑测试 | `Verified results` |
| 咨询顾问 | `Verified results`（含 variant 和模型名）、`Current behavior` |
| 改配置 | `Current behavior`、`Repo map` |
| 方向变化 | `Design (intended)`、`Next candidate actions` |

### 9.2 剪枝规则

`Verified results` 超过 10 行时，将最早条目移入 `.opencode/archive/<date>-verified.md`，保留最新 5 行 + 所有 Open problems。

### 9.3 漂移检测

`SKILL.md`、`opencode.json`（agent.advisor）和 `PROJECT_STATE.md` 三者保持一致性。每次变更后检查：
- `agent.advisor` 的模型和 variant 是否与推荐一致？
- 顾问的 permission 是否保持只读？

---

## 10. 约束

- 不让顾问改仓库文件
- 不让顾问执行项目命令
- 不让顾问做 Git 操作

总控始终是主执行器。顾问只是建议者。

---

## 附录 A：配置顾问

### 核心原则

> 总控本身使用一个模型家族 → 顾问必须选不同家族

### 推荐组合

| 总控模型 | 推荐顾问 |
|---------|---------|
| DeepSeek 系列 | GLM / GPT / Qwen / Doubao |
| GLM 系列 | DeepSeek / GPT / Doubao |
| GPT 系列 | DeepSeek / GLM / Doubao |

### opencode.json 配置

```jsonc
{
  "model": "opencode-go/deepseek-v4-pro",  // 总控
  "agent": {
    "advisor": {
      "description": "Second-opinion advisor for high-value judgment calls. Read-only: grep/read/glob only.",
      "model": "opencode-go/glm-5.1",       // 顾问（不同家族）
      "prompt": "{file:./.opencode/prompts/advisor.txt}",
      "mode": "subagent",
      "hidden": true,
      "permission": {
        "edit": "deny",
        "bash": "deny",
        "task": "deny",
        "webfetch": "deny",
        "websearch": "deny"
      }
    }
  }
}
```

如需不同推理强度，定义多个 agent 并通过 `reasoningEffort`（或其他 provider 支持的 passthrough 参数）区分：`low` / `medium` / `high` / `max`。具体参数名确认你的 provider 文档。

完整配置模板见 `references/agent-config.json`。
