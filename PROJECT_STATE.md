# PROJECT_STATE

## Goal
- `<当前项目目标>`

---

## Design (intended)
- OpenCode 总控 + Advisor 顾问模式推进项目。
- 工作流规范见 `.opencode/skills/second-opinion/SKILL.md`。

## Current behavior (actual)
- _(填写实际运行状态)_

## Verified results

| 验证项 | 结果 | 验证命令 | 备注 |
|--------|------|---------|------|
| Skill 基础就绪 | ✅ | — | second-opinion skill 已创建 |
| Task 调用 advisor 验证 | ✅ | Task(subagent_type:"advisor") | advisor subagent 成功响应，防幻觉验证 0 失误 |
| GLM review 后修复 | ✅ | — | 修复 3 项（T1 fast-track、格式去重、steps/specific param names） |

## Repo map
- `AGENTS.md` — 项目入口
- `PROJECT_STATE.md` — 本文件
- `opencode.json` — 项目配置（总控模型 + advisor agent）
- `.opencode/skills/second-opinion/SKILL.md` — 工作流规范
- `.opencode/skills/second-opinion/references/agent-config.json` — 配置模板

## Open problems
- _(待解决的问题)_

## Next candidate actions
- _(下一步操作)_
