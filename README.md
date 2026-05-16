# Reasonix + Codex Workflow

**Reasonix 总控 + Codex 顾问** — 一个可复用的结构化 AI 协作工作流。

将本包的文件放入任意项目，即可启用双 AI 协作模式：
**Reasonix**（常驻执行器）负责日常编码、测试和状态维护；
**Codex**（GPT-5.5 顾问）按需提供高价值判断。

---

## 适用场景

- 你使用 AI 编码助手（如 Claude Code、Codex CLI）开发项目
- 你希望让一个 Agent 持有主上下文长期推进项目，另一个 Agent 做高价值判断
- 你需要在多个方案之间做选择，或分析复杂 bug，或 review 架构设计
- 你的项目有明确的状态管理需求（当前目标、已验证结果、待决策事项）

---

## 快速开始

```powershell
# 1. 将本包的文件复制到你的项目根目录

# 2. 安装 Codex CLI
npm install -g @openai/codex
codex login

# 3. 验证工作流
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "Smoke test, respond with OK." 2>&1
# 输出应为 "OK"（stderr 自动捕获到 .reasonix/logs/）

# 4. 检查配置
codex --version                    # 确认 CLI 版本
```

---

## 文件清单

| 文件 | 用途 | 是否需要修改 |
|------|------|-------------|
| `REASONIX.md` | 项目入口 — 告诉 Reasonix 它的角色和项目目标 | ✅ 编辑 `<placeholder>` |
| `PROJECT_STATE.md` | 状态板 — Reasonix 持续读写 | ✅ 随项目推进更新 |
| `.reasonix/config.json` | 工作流配置（模型、推理强度、日志目录） | ⬜ 可选修改 |
| `.reasonix/skills/consult-codex.md` | 完整工作流规范（10 节） | ❌ 无需修改，可复用 |
| `scripts/ask_codex.ps1` | Codex CLI 桥接脚本 | ❌ 无需修改 |

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
│ ③ 升级规则（满足任一即调用 Codex）                 │
│   方案选择 / 结果冲突 / 复杂 bug / 架构改动        │
│   设计 review / 论文判断 / 根因分析                │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ④ 难度评估 → 选择推理强度                          │
│   T1 low · T2 medium · T3 high · T4 xhigh        │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑤ 压缩上下文 → 调用 consult-codex skill           │
│   goal + state + files + logs + question          │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑥ Codex 返回结构化建议                             │
│   decision · rationale · risks · next_steps · checks
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑦ Reasonix action plan                           │
│   处置: accepted / partially_accepted / rejected  │
│   下一步 + 验证方式                                │
└──────────┬───────────────────────────────────────┘
           ▼
┌──────────────────────────────────────────────────┐
│ ⑧ 强制更新 PROJECT_STATE.md                       │
│   Verified results + Current behavior + 下一步    │
└──────────────────────────────────────────────────┘
```

---

## 调用示例

```powershell
# 简单查证（T1 → low）
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "这个错误日志是什么原因？" 2>&1

# 方案选择（T2 → medium）
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "应该用 YAML 还是 JSON 做配置文件？" 2>&1

# 架构决策（T3 → high 或 T4 → xhigh）
$env:CODEX_REASONING_EFFORT = "high"
powershell -ExecutionPolicy Bypass -File scripts/ask_codex.ps1 -Question "这个重构方案的风险有哪些？" 2>&1
```

> **注意：** 在 Reasonix 的 `run_command` 环境中调用时，必须加 `2>&1`。脚本内部已自动将 `codex exec` 的 stderr 捕获到 `.reasonix/logs/`。

---

## 推理强度选择

| 层级 | 边界判断 | 推荐 `effort` | 示例 |
|------|---------|-------------|------|
| **T1 常规查证** | 单文件问题，无架构权衡，可立即验证 | `low` | "这个错误是什么意思？" |
| **T2 局部实现判断** | 2-3 个选项中选择，影响范围有限 | `medium` | "应该用函数还是 class？" |
| **T3 架构/工作流决策** | 影响多个文件或未来扩展 | `high` | "如何设计模块接口？" |
| **T4 战略/高代价决策** | 改变项目方向或长期治理 | `xhigh` | "项目架构应该怎么拆分？" |

配置位置：`.reasonix/config.json` → `codex.reasoning_effort`

---

## 前置依赖

| 依赖 | 版本要求 | 用途 |
|------|---------|------|
| [OpenAI Codex CLI](https://github.com/openai/codex) | ≥ v0.125 | 连接 GPT-5.5 |
| PowerShell | Windows 自带 | 运行 ask_codex.ps1 |
| GitHub / OpenAI 账户 | — | `codex login` 认证 |

---

## License

MIT
