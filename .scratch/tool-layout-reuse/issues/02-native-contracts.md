# 原生回归契约同步

Status: resolved
Type: task
Blocked by: none

## Scope

只修改 tests/tools.py、tests/lazygit.py，必要时tests/integration.py，按../spec.md更新既有真实回归契约。稳定plugin.kiku动作ID保持；新语义为tab+启动目录+kind复用、lazygit tiled/scratch PiP、双工具共存、管理动作仅scratch、source关闭不park、原归属tab消失parked scratch恢复到当前tab。

不改运行代码、新代码级runner、README、配置或文档。保持原生测试独立隔离、真实PID/cwd/TUI/bridge证据及身份安全拒绝断言。禁止以删除安全测试或放松为只检查pane数量规避新行为。所有原生测试都不运行；同样不运行build/lint/formatter，由主代理做Python语法核验。

## Acceptance

旧浮窗/按source隔离/互斥可见/孤儿新tab预期不再与spec冲突；保留Restart/reload/历史标记不可认领与真实进程保护；新布局和归属有相应行为场景。报告精确调整清单和未运行限制。

## Comments

- 公共命令interface固定，可与01独立隔离实施；不依赖运行代码完成后才能写明的私有结构。

## Result

- 已串行整合 `tests/tools.py` 与 `tests/lazygit.py` 到当前工作分支的未提交工作区；`tests/integration.py` 无需修改，没有创建提交。
- 同 tab／启动目录复用、不同目录／tab 隔离、lazygit tiled／scratch PiP共存、跨 tab 找回、仅 scratch 管理动作、来源关闭不 park、停放终端原 tab 消失后的当前 tab 恢复等契约已同步，保留真实进程、cwd、bridge、reload 和 Restart 安全断言。
- `python3 -m py_compile tests/tools.py tests/lazygit.py` 通过。只读增量审查发现的缺少 json 导入、非 ASCII 路径转义及过期 pane 快照已修正，复查无新增项。
- 按用户决定未执行原生套件，未启动 Tern；不能将本任务的静态检查称为真机验收。
