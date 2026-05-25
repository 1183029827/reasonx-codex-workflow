# Second Opinion — OpenCode 双模型协作 Skill

**second-opinion** 是一个 opencode 原生 skill，实现"总控 + 顾问"双模型协作工作流。

- **总控** (`opencode-go/deepseek-v4-pro`) — 日常编码、测试、状态维护
- **顾问** (`opencode-go/glm-5.1` 或其他不同家族模型) — 高价值决策、代码审查、根因分析

## 安装

```powershell
# 1. 将 .opencode/skills/second-opinion/ 复制到你的项目或全局 skills 目录

# 2. 在 opencode.json 中添加 advisor agent 配置
#    模板见 .opencode/skills/second-opinion/references/agent-config.json

# 3. 配置总控模型
#    "model": "opencode-go/deepseek-v4-pro"

# 4. 重启 opencode
```

## 文件清单

| 文件 | 用途 |
|------|------|
| `.opencode/skills/second-opinion/SKILL.md` | 工作流规范（10 节 + 附录） |
| `.opencode/skills/second-opinion/references/agent-config.json` | advisor agent 配置模板 |
| `AGENTS.md` | 项目入口，引用 second-opinion skill |
| `opencode.json` | 项目配置（总控模型 + advisor agent） |
| `PROJECT_STATE.md` | 状态板 |

## 三种模式

| Mode | 用途 | 输出 |
|------|------|------|
| `decide` | 方案决策 | decision · rationale · risks · next_steps |
| `review` | 代码审查 | summary · findings · overall_notes |
| `discuss` | 根因分析 | analysis · hypotheses · recommendation |

## 顾问模型选择

| 顾问 | 适用场景 |
|------|---------|
| **GLM 5.1**（默认） | 代码 review、bug 分析、日常 T1-T3 |
| **GPT-5.5** | 架构设计、模型优化、研究方向 |

**核心原则：** 顾问必须与总控不同模型家族。

## License

MIT
