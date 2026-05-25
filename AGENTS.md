# OpenCode 工作流入口

**OpenCode 总控 + 多模型顾问** 模式。
启用 `second-opinion` skill，详见 `.opencode/skills/second-opinion/SKILL.md`。

## 项目
- **名称**：`<repo-name>`
- **目标**：`<project-goal>`

## 环境与命令
- OS: `<your-os>`
- Python: `<python-version>`
- Test: `<test-command>`

## 总控模型
- 使用 `opencode-go/deepseek-v4-pro` 作为常驻执行器
- 推理 variant: `high` / `max`（按需调整）
- 顾问模型必须是不同模型家族（见 second-opinion 附录 A）

## 状态文件
`PROJECT_STATE.md` — 持续维护，规则见 second-opinion §9。
