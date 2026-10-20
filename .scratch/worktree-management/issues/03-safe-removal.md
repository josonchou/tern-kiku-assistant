# 03 正常移除与风险审查

Status: resolved
Type: task
Blocked by: 01
Spec: ../spec.md

## 目标

正常移除经过身份和安全确认的干净 linked worktree，保留分支，并建立供危险入口复用的风险审查。

## 修改范围

管理 module、必要的 Git 状态解析 module、真实集成场景和 `README.md`。复用 01 的候选与绑定；不得实现强制移除或自动关闭。

## 交付契约

- 读取最新 `git worktree list --porcelain -z`；确认所选对象仍登记、非主工作树、非 bare、非 locked/prunable，存在且实际 root/common-dir 与来源仓库一致。
- 检查全部可见本机使用者，包括绑定 tab、子目录 terminal/agent、原生工具路径、浮动和 parked pane。使用中或相关身份无法确认时拒绝，不自动关闭。
- 风险审查覆盖 tracked 修改、untracked 和 ignored 文件；Detached HEAD 检查是否被本地/远程分支或标签保护。无保护提交归入危险，不视为干净可删。
- 检查目标私有 Git 操作与恢复状态；未完成Git操作即使工作目录干净也拒绝，并保留其恢复引用。不能以公共仓库中其他工作树的操作状态误拒绝目标。
- 正常移除有风险时停止并显示原因。干净且无使用者时展示路径、保留分支提示和外部使用确认，默认取消。
- 最终确认后重读身份、安全状态、HEAD/分支及使用者，发生变化则停止。仅调用 `git worktree remove -- <path>`，不 rm/prune/删分支/自动 --force。
- Git 状态读取失败时不进入移除；实际移除命令失败可能已部分移除目录或登记，只保留剩余现场。提示用户查看当前状态，不把失败当成功、不声称事务回滚、不盲目重试。

## 验收

1. 干净、未使用 linked worktree 经确认移除，分支、主工作树和其他 worktree 保留。
2. 主工作树、锁定、路径失效、替换身份、可见使用者（含 parked/子目录）拒绝。
3. tracked、untracked、ignored 文件均阻止正常移除；拒绝后文件字节、refs 和登记不变。
4. 无保护的 Detached 提交阻止正常移除；有分支或标签保护且干净的 Detached 可移除。
5. 取消、最终确认期间新增文件/锁定/打开环境/HEAD变化均不会删除；Git 失败不触发补救性破坏。
6. 初审或最终确认期间出现未完成的 autostash 合并时拒绝，目标、登记和可恢复的未提交内容保留；其他工作树中的未完成操作不阻止安全目标的正常移除。

## 测试与实施

先增加一条真实 Git/Tern 正常移除失败场景交主线程运行 red，再实施与补齐风险回归。子代理不运行测试/build/lint/formatter；主线程负责实际 red/green。风险展示需与真实解析数据对应，不以源码文本或 mock 回声测试代替行为。

## Result

实现提交 `ecb5941c9ed84389f0bbee11397caedd1f7c20c9` 已通过 `42b7f6b82a1154a0bd31f99a610310d394e1fd10` 集成；共享 Git 操作恢复保护随04提交 `5462e3dd61a3a6e831aed2d88e405a5dc97474b9` 经 `53147a5f7c64616fb2e770f8e80c5573998a0c6c` 集成。普通移除、身份与使用者审查、文件／索引／Detached 保护和最终复查均已完成验收。

- 最终审查修复后的普通模块通过28组记录（含加载和helpers），证据目录 `tern-kiku-test-7u51xxao`，覆盖文件风险、引用保护、嵌套／失效／替换身份、确认期间变化、各类使用者和真实 Git 错误后的保留与重入。
- 两入口未完成 Git 操作的初审／末次保护及合法相对 metadata、普通同名分支兼容性通过9组，证据目录 `tern-kiku-test-5g0f82_n`。恢复提交及内容保留，其他工作树中的未完成操作不阻止安全目标移除。
- 最终验收代码 `964ec9c7e7b3af23eec691edead1e41fc9bf0f9c` 上，`PYTHONDONTWRITEBYTECODE=1 python3 tests/integration.py` 完整通过83组；报告 `tern-kiku-test-kqycomoe/report.json`，完整路径及截图记录见 `docs/verification.md`。
- Standards／Spec 审查问题已集中修复并复核，独立删除安全审查未发现达到报告门槛的问题。
- 历史运行 `tern-kiku-test-evmeqxnq` 曾触发 `process exceeded 50 ms`，用户因此授权先集成03并推进04。没有放大时限、自动重载或失败重试；现依据真实完整验收解决本任务，不宣称宿主时限问题已被修复。
