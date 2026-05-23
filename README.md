# Reasonix + Advisor Workflow

**Reasonix 总控 + 多模型顾问** — 一个可复用的结构化 AI 协作工作流。

将本包的文件放入任意项目，即可启用双 AI 协作模式：
**Reasonix**（DeepSeek V4 Pro 常驻执行器）负责日常编码、测试和状态维护；
**Advisor**（默认 GLM 5.1 via opencode，后备 GPT-5.5 via codex）按需提供高价值判断。

---

## 适用场景

- 你使用 AI 编码助手开发项目
- 你希望让一个 Agent 持有主上下文长期推进项目，另一个 Agent 做高价值判断
- 你需要在多个方案之间做选择，或分析复杂 bug，或 review 架构设计
- 你的项目有明确的状态管理需求（当前目标、已验证结果、待决策事项）

---

## 快速开始

```powershell
# 1. 将本包的文件复制到你的项目根目录

# 2. 安装依赖
npm install -g @openai/codex    # Codex CLI（后备顾问）
# opencode CLI 另需按 Crush 官方指引安装

# 3. 编辑 REASONIX.md 和 PROJECT_STATE.md，填入项目信息

# 4. 验证工作流
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Mode decide -Question "Smoke test, respond with OK." 2>&1
```

---

## 文件清单

| 文件 | 用途 | 是否需要修改 |
|------|------|-------------|
| `REASONIX.md` | 项目入口 — 告诉 Reasonix 它的角色和项目目标 | ✅ 编辑 `<placeholder>` |
| `PROJECT_STATE.md` | 状态板 — Reasonix 持续读写 | ✅ 随项目推进更新 |
| `.reasonix/config.json` | 工作流配置（顾问 provider、模型、推理强度、日志目录） | ⬜ 可选修改 |
| `.reasonix/skills/consult-codex.md` | 完整工作流规范（10 节 + 附录） | ❌ 无需修改，可复用 |
| `scripts/ask_codex.ps1` | 顾问桥接脚本（opencode / codex 双 provider，三模式 + Dual + Session） | ❌ 无需修改 |

---

## 工作流

```
┌──────────────────────────────────────────────────┐
│ ① Reasonix 日常执行                              │
│   改代码 · 跑测试 · 维护 PROJECT_STATE.md         │
└──────────┬───────────────────────────────────────┘
           │ 遇到需要判断的场景
           ▼
┌──────────────────────────────────────────────────┐
│ ② 自问闸门："我能否凭当前上下文自信回答？"          │
│   ├─ 能 → 直接执行，不升级                        │
│   └─ 不能 → 检查升级规则                          │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ③ 升级规则 → 选择 Mode + 模型                      │
│   方案选择 → decide   结果冲突 → discuss            │
│   代码 review → review  架构改动 → decide           │
│   GLM 5.1: 代码/bug/workflow                      │
│   GPT-5.5: 架构/模型优化/研究方向                   │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ④ 难度评估 → 推理强度                              │
│   T1 low · T2 medium · T3 high · T4 xhigh        │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑤ 按模式组装上下文 + PROJECT_MAP                    │
│   -Mode decide|review|discuss                    │
│   -Context "GOAL/DIFF/PROBLEM + 结构化块"         │
│   附自动生成的文件地图，引导 Advisor 探索            │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑥ run_background + wait_for_job 调用 Advisor      │
│   Advisor 可使用 grep/read/glob 探索代码库          │
│   禁止 bash/edit/write（只读顾问）                  │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑦ Advisor 返回模式特定的结构化输出                  │
│   decide: decision · rationale · risks · steps    │
│   review: summary · findings · overall_notes      │
│   discuss: analysis · hypotheses · recommendation │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑧ 防幻觉验证：逐条核对 Advisor 引用的 file:line     │
│   ≥2 处不存在 → 换模型或重新提问                    │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑨ Reasonix action plan                           │
│   处置: accepted / partially_accepted / rejected  │
│   下一步 + 验证方式                                │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑩ 强制更新 PROJECT_STATE.md                       │
│   Verified results + Current behavior + 下一步    │
└──────────────────────────────────────────────────┘
```

---

## 三种调用模式

### decide — 方案决策

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 `
  -Mode decide `
  -Question "应该用方案 A 还是方案 B？" `
  -Context "GOAL: ...; OPTIONS: A: ... B: ...; CONSTRAINTS: ..." `
  2>&1
```

### review — 代码审查

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 `
  -Mode review `
  -Context "DIFF: ...; PURPOSE: ...; DESIGN_DECISIONS: ..." `
  2>&1
```

### discuss — 讨论分析

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 `
  -Mode discuss `
  -Question "为什么训练在第 50 epoch 开始发散？" `
  -Context "PROBLEM: ...; TRIED_SO_FAR: ...; KEY_LOGS: ..." `
  2>&1
```

> **注意：** 由于 Advisor 可以自由探索代码库，Reasonix 内部必须使用 `run_background` + `wait_for_job`（而非 `run_command`），超时建议 2-15 分钟按 T 级递增。`-Context` 的组装清单详见 `consult-codex.md` §5.2。

---

## 高级功能

### Dual 模式 — GLM + GPT-5.5 双模型并行

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 `
  -Mode decide `
  -Question "这个架构重构方案是否可行？" `
  -Context "GOAL: ..." `
  -Dual
```

同时咨询 GLM 5.1 和 GPT-5.5，输出两个模型的独立建议，方便交叉验证。

### Session 续接

```powershell
# 首次调用
powershell ... -Mode discuss -Question "分析这个 bug" -Context "..."

# 从输出中提取 session ID，后续追加信息继续讨论
powershell ... -Mode discuss -Question "基于上次分析，我补充了日志" -Session ses_abc123
```

---

## 顾问模型

| 模型 | Provider | 适用场景 |
|------|----------|---------|
| **GLM 5.1**（默认） | opencode | 代码 review、bug 分析、工作流规范、日常 T1-T3 |
| **GPT-5.5** | codex | 架构设计、模型优化、研究方向讨论 |

切换方式：修改 `.reasonix/config.json` → `advisor.provider`（`opencode` / `codex`），或设置环境变量 `ADVISOR_PROVIDER`。

---

## 推理强度

| 层级 | 边界判断 | variant | 示例 |
|------|---------|--------|------|
| **T1 常规查证** | 单文件问题，无架构权衡 | `low` | "这个错误是什么意思？" |
| **T2 局部实现判断** | 2-3 个选项中选择 | `medium` | "应该用函数还是 class？" |
| **T3 架构/工作流决策** | 影响多个文件或未来扩展 | `high` | "如何设计模块接口？" |
| **T4 战略/高代价决策** | 改变项目方向或长期治理 | `xhigh` / `max` | "项目架构应该怎么拆分？" |

配置位置：`.reasonix/config.json` → `advisor.variant`（opencode）或 `codex.reasoning_effort`（codex）。

---

## 前置依赖

| 依赖 | 用途 |
|------|------|
| opencode CLI (Crush) | 连接 GLM 5.1（默认顾问） |
| [OpenAI Codex CLI](https://github.com/openai/codex) | 连接 GPT-5.5（后备顾问） |
| PowerShell | Windows 自带，运行 ask_codex.ps1 |

---

## Changelog

### [1.0.0] — 2026-05-23

- **Advisor exploration mode**: Advisor can now explore the codebase freely using `grep`, `read`, and `glob`. Prompt changed from "MUST NOT use ANY tools" to "use grep, read, and glob freely". `bash`, `edit`, and `write` remain forbidden.
- **Background execution**: Reasonix now uses `run_background` + `wait_for_job` instead of synchronous `run_command`, with tiered timeouts (2 min – 15 min) to accommodate exploration latency.
- **Dual-model mode** (`-Dual`): Query both GLM 5.1 and GPT-5.5 in a single call for cross-validation on high-stakes decisions.
- **Session resume** (`-Session`): Continue a previous advisor conversation by passing a session ID, enabling multi-turn dialogue without losing context.
- **Hallucination check** (§8.1): Reasonix verifies every `file:line` reference in advisor responses before absorbing advice. Two or more invalid references trigger a model switch.
- **PROJECT_MAP** (§5.6): Reasonix auto-generates a relevant-file map appended to `-Context`, guiding the advisor to high-value files instead of blind grep.
- **Reasoning effort** bumped to `xhigh` by default for both opencode and codex.
- **Dispatch refactor**: `_Run-OpenCode`, `_Parse-OpenCodeJsonl`, `_Run-Codex` helpers extracted; stdout/stderr captured via temp files to avoid PowerShell encoding issues.

### [0.3.0] — 2026-05-22

- **Three-mode system**: `-Mode decide|review|discuss` replaces the flat `-Question`-only interface. Each mode has a dedicated prompt template and structured output format.
- **Context assembly checklists** (§5.2): Mode-specific required fields (`GOAL`/`OPTIONS`/`CONSTRAINTS` for decide, `DIFF`/`PURPOSE`/`DESIGN_DECISIONS` for review, `PROBLEM`/`TRIED_SO_FAR`/`KEY_LOGS` for discuss).
- **Mode-specific output formats** (§7): `decide` outputs `decision`/`rationale`/`risks`/`next_steps`/`checks`; `review` outputs `summary`/`findings`/`overall_notes`; `discuss` outputs `analysis`/`hypotheses`/`recommendation`.

### [0.2.0] — 2026-05-22

- **Dual provider**: Advisor now supports `opencode` (GLM 5.1) as primary and `codex` (GPT-5.5) as fallback, driven by `.reasonix/config.json` → `advisor.provider`.
- **Code Review Gate** (§3.1): Mandatory advisor review for all code changes before commit or training launch.
- **Model routing by domain** (§3.2): GLM 5.1 for code review / bugs / workflows; GPT-5.5 for architecture / model design / research.
- **ASCII-only enforcement** for `PROJECT_STATE.md` to prevent encoding corruption in CLI pipelines.
- **Agent behavior control** (§5.3): Prompt-level tool restriction to prevent advisor self-exploration.
- **Timeout recommendations** (§6.1): Tiered `run_command` timeouts (30s – 300s).

### [0.1.0] — 2026-05-21

- Initial release: Reasonix + Codex (GPT-5.5) dual-AI collaboration workflow.
- Single `-Question` parameter interface via `scripts/ask_codex.ps1`.
- Structured advisor output format (`decision`/`rationale`/`risks`/`next_steps`/`checks`).
- `PROJECT_STATE.md` state tracking with `Verified results` table.
- `REASONIX.md` project entry point with placeholder-based project configuration.

## License

MIT
