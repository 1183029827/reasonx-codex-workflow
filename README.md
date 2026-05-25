# Second Opinion — OpenCode 双模型协作 Skill

**second-opinion** 是一个 opencode 原生 skill，实现"总控 + 顾问"双模型协作工作流。

- **总控** (`opencode-go/deepseek-v4-pro`) — 日常编码、测试、状态维护
- **顾问** (`opencode-go/glm-5.1` 或其他不同家族模型) — 高价值决策、代码审查、根因分析

## 快速安装（推荐 — 全局，任意项目可用）

```powershell
# 1. 安装 skill 到全局
cp -Recurse .opencode/skills/second-opinion/ $env:USERPROFILE\.config\opencode\skills\second-opinion\

# 2. 安装 advisor system prompt
mkdir -Force $env:USERPROFILE\.config\opencode\prompts
cp .opencode/prompts/advisor.txt $env:USERPROFILE\.config\opencode\prompts\advisor.txt

# 3. 在全局 opencode.json 的 "agent" 块中添加 advisor 定义
#    模板见 .opencode/skills/second-opinion/references/agent-config.json
#    或直接复制下面这段到 ~/.config/opencode/opencode.json 的 "agent" 中:

# 4. 重启 opencode
```

**完成后**，在任意空白文件夹启动 opencode，当遇到方案选择、复杂 bug、架构决策时，agent 会自动识别并调用 Task(advisor) 获取第二意见。

## 项目级安装（可选，覆盖全局配置）

```powershell
# 项目根目录下执行，会覆盖全局同名 agent
cp -Recurse .opencode/ ./your-project/.opencode/
cp opencode.json ./your-project/opencode.json
cp AGENTS.md ./your-project/AGENTS.md
```

## 文件清单

| 文件 | 用途 |
|------|------|
| `.opencode/skills/second-opinion/SKILL.md` | 工作流规范（10 节 + 附录） |
| `.opencode/skills/second-opinion/references/agent-config.json` | advisor agent 全局配置模板 |
| `.opencode/prompts/advisor.txt` | 顾问 system prompt（角色 + 输出格式） |
| `opencode.json` | 项目配置示例（总控模型 + advisor agent） |
| `AGENTS.md` | 项目入口示例 |
| `PROJECT_STATE.md` | 状态板示例 |

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
