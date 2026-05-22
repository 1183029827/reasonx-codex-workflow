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

## 3. 何时调用 Advisor（升级规则）

通过自问闸门后，只有在以下条件之一满足时，才调用 Advisor：

1. 需要在多个研究或工程方案之间做选择
2. 实验结果与预期明显冲突，需要解释
3. 同一个 bug 在两次有意义尝试后仍未解决
4. 改动涉及核心接口、训练流程、评测逻辑或系统架构
5. 需要对较大 diff 做设计层 review
6. 需要判断论文 claim、ablation、结论边界是否成立
7. 需要复杂根因分析，而不是表面修补

**不要因为以下事项调用 Advisor：**

- 常规实现
- 明确规格下的编码
- 小 bug 修复
- 常规 refactor
- 测试执行
- SSH 命令
- Git 日常操作
- 简单日志整理
- 机械性代码修改

### 3.1 代码 Review Gate（强制）

**任何代码修改完成后，必须交由 GLM review。** 规则：

- 用 `git diff` 获取完整变更，附上压缩后的上下文（修改目的、关键设计选择）
- Review 问题至少包含：逻辑正确性、隐藏耦合、初始化纪律、梯度流
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

### 5.1 信息选择

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

### 5.2 语言与编码

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

### 5.3 Agent 行为控制（重要）

> `opencode run` 和 `codex exec` **两者都启动 agent**（不是纯 LLM 补全），默认有 grep、read、bash 等工具权限。如果不加限制，Advisor 收到问题后会自行探索代码库，导致：
> - 响应时间不可预测（多轮 LLM + 工具调用）
> - 可能超时挂死（Crush #2854 确认 opencode 无 per-call 超时机制；codex 同理）
> - Token 消耗不可控（7.7K+ tokens 即使是最简单的 "1+1"）

**对策（已内建到 prompt 模板，两者共用）：**

- prompt 顶部有硬指令禁止使用任何工具（已验证：opencode ✓、codex ✓）
- 所有必要信息必须在 prompt 中提供完毕——**不能指望 advisor 自己去找**
- 把相关代码段、日志、diff 摘要直接粘贴进 prompt
- 压缩的原则：**advisor 需要什么就提供什么，不要让它自己探索**

---

## 6. 调用命令与超时

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "<压缩后的咨询问题>" 2>&1
```

> **注意：** 在 Reasonix 工具环境下需加 `2>&1` 以确保 stdout 完整输出。

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

### 6.1 超时设置

在 Reasonix `run_command` 中设置 `timeoutSec`：

| 问题规模 | 推荐 timeout | 说明 |
|---------|-------------|------|
| T1 常规查证 | 30s | 简单 yes/no |
| T2 局部分析 | 60s | 2-3 选项判断 |
| T3 架构决策 | 120s | 多文件设计 |
| T4 战略问题 | 300s | 复杂推理 |

> **注意：** 超时设置的前提是 §5.3 已正确执行（prompt 中已包含全部必要信息，advisor 不会自行探索）。如果 advisor 仍然自行探索代码库，再高的超时也可能不够。

---

## 7. 顾问输出格式

要求 Advisor 严格按以下结构返回：

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

Reasonix 接收 Advisor 的结构化输出后，必须按以下格式形成执行决策：

```markdown
## Advisor advice
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

### B.1 Advisor 响应超时 / 无返回

**症状：** `run_command` 超时，或 advisor 返回空响应。

**原因：** `opencode run` 是 agent 模式，如果 prompt 中缺少关键信息，advisor 可能自行使用 grep/read 等工具探索代码库，导致多轮 LLM 调用超时。Crush 官方 (#2854) 确认该架构无 per-call 超时机制，工具调用可能无限挂住。

**解决：**
1. 确认 prompt 模板顶部有 `CRITICAL: You are a READ-ONLY advisor...` 硬指令
2. 检查压缩后的上下文是否包含了 advisor 决策所需的全部信息
3. 如果问题涉及特定代码，把代码段直接粘贴进去，不要让 advisor 自己找
4. 提高 `run_command` 的 `timeoutSec` 到 300s 作为最后手段

### B.2 Advisor 自行探索了代码库

**症状：** 日志中看到 advisor 使用了 `grep`、`read`、`ls` 等工具调用。

**原因：** prompt 中禁止工具的指令不够强，或 advisor 判断给定的信息确实不够。

**解决：**
1. 检查 prompt 是否包含了所需的关键文件内容
2. 如果 advisor 频繁自发探索，考虑在 prompt 中更明确地给出代码段
3. 终极方案：创建一个 `advisor` agent（通过 `opencode agent create`），禁用全部工具权限

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
