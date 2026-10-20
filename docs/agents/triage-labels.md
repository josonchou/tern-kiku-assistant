# Triage 标签

五个规范角色与本地任务跟踪器使用的字符串对应如下：

| 规范角色 | 跟踪器标签 | 含义 |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | 等待维护者评估 |
| `needs-info` | `needs-info` | 等待补充信息 |
| `ready-for-agent` | `ready-for-agent` | 需求明确，可交给代理执行 |
| `ready-for-human` | `ready-for-human` | 需要人工实施 |
| `wontfix` | `wontfix` | 不予实施 |

技能提及某个 triage 角色时，使用表中对应的跟踪器标签。
本地 tickets 通过顶部的 `Status:` 行记录 triage 状态；领取和完成状态遵循 `issue-tracker.md`。
需要调整词汇时，修改“跟踪器标签”列。
