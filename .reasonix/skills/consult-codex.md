---
description: Consult Codex GPT-5.5 as a senior advisor for high-value decisions. Invoke when escalation rules in §3 are met.
---

# consult-codex — Reasonix 总控 + Codex 顾问 工作流规范

## 1. 角色定义

| 角色 | 身份 | 职责 |
|------|------|------|
| **总控 (Reasonix)** | 常驻执行器 (DeepSeek v4) | 持有主上下文、改代码、跑测试、维护状态、识别升级条件、吸收建议后继续执行 |
| **顾问 (Codex)** | GPT-5.5 | 按需调用，提供结构化建议（decision/rationale/risks/next_steps/checks） |
| **用户** | 最终裁决者 | 设定目标、发起任务、确认/拒绝计划、验收结果 |

默认原则：
- Reasonix 负责执行和推进，Codex 负责高价值判断和审查
- Codex 不默认拥有写仓库、跑项目命令、做 Git 操作的权限
- 不要把长会话原样发给 Codex
- 调用 Codex 前必须压缩上下文

---

## 2. 自问闸门：是否真正需要升级？

在检查升级规则前，Reasonix 必须先问自己：

> **这个问题我能否凭当前上下文自信回答？**

| 判断 | 行动 |
|------|------|
| 能 → 不调用 Codex，直接执行 | 继续日常执行（§1 定义的任务） |
| 不能 → 继续检查是否满足升级条件 | 进入 §3 |

这个闸门防止低价值问题消耗 GPT-5.5 tokens 和增加延迟。只有当 Reasonix 的判断力或信息量不足时，才将问题升级。

---

## 3. 何时调用 Codex（升级规则）

通过自问闸门后，只有在以下条件之一满足时，才调用 Codex：

1. 需要在多个研究或工程方案之间做选择
2. 实验结果与预期明显冲突，需要解释
3. 同一个 bug 在两次有意义尝试后仍未解决
4. 改动涉及核心接口、训练流程、评测逻辑或系统架构
5. 需要对较大 diff 做设计层 review
6. 需要判断论文 claim、ablation、结论边界是否成立
7. 需要复杂根因分析，而不是表面修补

**不要因为以下事项调用 Codex：**

- 常规实现
- 明确规格下的编码
- 小 bug 修复
- 常规 refactor
- 测试执行
- SSH 命令
- Git 日常操作
- 简单日志整理
- 机械性代码修改

---

## 4. 问题难度评估与模型选择

确定需要调用 Codex 后，Reasonix 必须先评估问题难度，选择对应的 `reasoning_effort` 级别。级别通过环境变量 `CODEX_REASONING_EFFORT` 或 `.reasonix/config.json` 中的 `codex.reasoning_effort` 控制。

有效值：`low` / `medium` / `high` / `xhigh`

| 层级 | 边界判断 | 推荐 effort | 典型问题示例 |
|------|---------|------------|-------------|
| **T1 常规查证** | 单文件/单命令问题，无架构权衡，答案可立即验证 | `low` | "添加 multiply 后应该跑 pytest 吗？" "这个 stderr 行为是预期的吗？" |
| **T2 局部实现判断** | 需要在 2-3 个合理选项中选择，影响范围限于一个脚本/一个文件/一个工作流步骤 | `medium` | "ask_codex.ps1 的超时应从 config 读取还是仅用 CLI 参数？" "日志应该怎样分层？" |
| **T3 架构/工作流决策** | 影响多个文件、未来扩展、Reasonix 行为、测试策略或用户可见约定 | `high` | "Reasonix 应该怎样决定何时调用 Codex？" "consult-codex 应该以 skill 还是 config 驱动？" |
| **T4 战略/模糊/高代价决策** | 改变项目方向、总控/顾问职责边界、信任模型、自动化策略或长期治理 | `xhigh` | "Reasonix 和 Codex 的正确职责划分是什么？" "这个 POC 应该演进为通用编排框架吗？" |

**选择指引：**
- 不确定时默认 `medium`
- 如果决策难以撤销，升一级
- 如果问题涉及 `.reasonix/skills/`、`.reasonix/config.json` 或控制器行为变动，升一级
- 普通代码添加（如 `multiply`）不超过 `medium`，除非问题涉及 API 方向或工作流策略

---

## 5. 调用前准备（上下文压缩）

确定推理强度后，将上下文压缩为最小必要信息。

只发送以下内容：

- **current goal** — 当前目标
- **current state** — 当前状态
- **relevant files** — 相关文件
- **key logs / results / diff summary** — 关键日志/实验结果/diff 摘要
- **the specific advisory question** — 明确的咨询问题
- **reasoning_effort** — 本次使用的推理强度

不要发送：

- 整段聊天记录
- 大量无关代码
- 与当前决策无关的旧尝试
- 冗长背景叙述

---

## 6. 调用命令

从配置读取顾问入口脚本并执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "<压缩后的咨询问题>" 2>&1
```

> **注意：** 在 Reasonix 工具环境下需加 `2>&1` 以确保 stdout 完整输出。脚本内部已自动将 stderr 捕获到 `.reasonix/logs/`。

`reasoning_effort` 通过 `.reasonix/config.json` 或环境变量 `CODEX_REASONING_EFFORT` 控制。

脚本路径、模型、sandbox 等配置见 `.reasonix/config.json`。

---

## 7. Codex 输出格式

要求 Codex 严格按以下结构返回：

```yaml
decision:
- ...

rationale:
- ...

risks:
- ...

next_steps:
- ...

checks:
- ...
```

---

## 8. 吸收建议（Reasonix action plan）

Reasonix 接收 Codex 的结构化输出后，必须按以下格式形成执行决策：

```markdown
## Codex advice
（展示 Codex 的原始输出）

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
| `accepted` | 完全采纳 Codex 建议 | 按 next_steps 执行，更新状态 |
| `partially_accepted` | 部分采纳，部分驳回或修改 | 在 action plan 中说明驳回哪些、为什么 |
| `rejected` | 驳回全部建议 | 说明理由，记录到 PROJECT_STATE.md Verified results |
| `deferred` | 当前不执行，延后评估 | 说明延期原因和重新评估条件 |

**无论采纳与否，均须记录到 PROJECT_STATE.md。**"已记录 Codex 建议但未采纳"本身就是有价值的决策痕迹。

---

## 9. 状态与进度管理

### 9.1 更新时机（强制规则）

每次以下操作后，**必须**更新 `PROJECT_STATE.md` 的对应章节：

| 操作 | 必须更新的章节 |
|------|--------------|
| 改代码 / 加功能 | `Current behavior`、`Verified results`（新增行） |
| 跑测试 | `Verified results`（更新对应行状态） |
| 咨询 Codex（无论是否采纳建议） | `Verified results`（新增行，含 reasoning_effort）、`Current behavior`（如有采纳） |
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

- 在 `Verified results` 中记录本次咨询的输出（含使用的 `reasoning_effort` 和处置状态）
- 在 `Current behavior` 中反映采纳决策后的实际变化
- 如果咨询改变了方向，更新 `Next candidate actions`

### 9.4 配置/规范漂移检测

`.reasonix/config.json`、本文件（`consult-codex.md`）和 `scripts/ask_codex.ps1` 三者在长期维护中可能悄然不一致。每次工作流文件变更后，检查以下内容：

- `config.json` 中的 `model`、`reasoning_effort`、`sandbox` 是否与本文件 §6（调用命令）的描述一致？
- `ask_codex.ps1` 读取的字段名是否与 `config.json` 的键名匹配？
- `config.json` 的 `log_dir` 是否与本文件 §6 提到的 `.reasonix/logs/` 一致？

---

## 10. 约束

Unless the user explicitly asks otherwise:

- 不让 Codex 直接改仓库文件
- 不让 Codex 直接执行项目命令
- 不让 Codex 直接做 Git 操作

Reasonix 始终是主执行器。Codex 只是顾问。
