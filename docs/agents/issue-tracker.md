# 任务跟踪器：本地 Markdown

本仓库的规范和 tickets 以 `.scratch/` 下的 Markdown 文件为准，不依赖远端 issue 服务。

## 文件约定

- 每个功能一个目录：`.scratch/<feature-slug>/`。
- 规范：`.scratch/<feature-slug>/spec.md`。
- 每个 ticket 一个文件：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 编号；不使用合并所有 tickets 的单一文件。
- 文件顶部使用 `Status:` 记录状态；triage 角色字符串见 `docs/agents/triage-labels.md`。
- 评论和讨论追加到文件末尾的 `## Comments` 下，保留历史。

## 读写操作

- 技能要求“发布到任务跟踪器”时，在对应功能目录创建文件，按需创建目录。
- 技能要求“获取 ticket”时，读取给定路径；只有编号时，在当前功能的 `issues/` 中定位。
- 新任务使用 `Status: needs-triage`；需求和验收条件明确、适合代理执行后，使用 `Status: ready-for-agent`。

## 任务图与完成规则

- 依赖写在顶部的 `Blocked by: NN, NN` 中；无依赖使用 `Blocked by: none`。编号在当前功能目录内解析。
- 只有所有依赖均为 `Status: resolved`，任务才解除阻塞。
- 可领取任务必须为 `Status: ready-for-agent` 且无未解决依赖；同等条件按编号排序，独立任务可并行领取。
- 开始工作前写入 `Status: claimed`，表示已领取。
- 实现类 ticket 只有在变更集成到集成分支、验收和相关验证完成后，才能改为 `Status: resolved`；在 `## Result` 下记录结果、验证证据和相关提交。
- 规范关联的所有 tickets 均解决后，再将规范标记为 `Status: resolved`。
- `claimed` 和 `resolved` 是执行状态，不是 triage 标签角色。本地完成状态由文件更新表达，不依赖 PR 自动关闭。

## Wayfinder 操作

- 探索地图：`.scratch/<effort>/map.md`，保留 Notes、Decisions-so-far、Fog 内容。
- 每个子问题仍使用独立 ticket，并通过 `Type:` 标明 `research`、`prototype`、`grilling` 或 `task`。
- 领取和阻塞关系沿用上述规则。
- 解决探索 ticket 时，在 `## Answer` 下追加答案，设置 `Status: resolved`，并将结论摘要与 ticket 链接追加到地图的 Decisions-so-far。
