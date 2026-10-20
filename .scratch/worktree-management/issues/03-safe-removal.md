# 03 正常移除与风险审查

Status: claimed
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
- 正常移除有风险时停止并显示原因。干净且无使用者时展示路径、保留分支提示和外部使用确认，默认取消。
- 最终确认后重读身份、安全状态、HEAD/分支及使用者，发生变化则停止。仅调用 `git worktree remove -- <path>`，不 rm/prune/删分支/自动 --force。
- Git 错误保留现场，提示用户查看当前状态，不把失败当成功，不盲目重试。

## 验收

1. 干净、未使用 linked worktree 经确认移除，分支、主工作树和其他 worktree 保留。
2. 主工作树、锁定、路径失效、替换身份、可见使用者（含 parked/子目录）拒绝。
3. tracked、untracked、ignored 文件均阻止正常移除；拒绝后文件字节、refs 和登记不变。
4. 无保护的 Detached 提交阻止正常移除；有分支或标签保护且干净的 Detached 可移除。
5. 取消、最终确认期间新增文件/锁定/打开环境/HEAD变化均不会删除；Git 失败不触发补救性破坏。

## 测试与实施

先增加一条真实 Git/Tern 正常移除失败场景交主线程运行 red，再实施与补齐风险回归。子代理不运行测试/build/lint/formatter；主线程负责实际 red/green。风险展示需与真实解析数据对应，不以源码文本或 mock 回声测试代替行为。

## Result

实现已写入 `ticket/worktree-management-03`，提供普通移除、共享身份与使用者审查、完整文件风险与索引保护、Detached 引用保护和确认后复查。当前状态保持 claimed，不宣称完成验收。

- 已观测通过：普通移除成功与默认取消、主工作树/锁定/三类内容风险拒绝、隐藏索引和gitlink拒绝、无保护Detached拒绝；三类引用独立保护、linked来源发起及后续嵌套保护的专门原生运行通过5组记录（含加载和helpers），证据目录 `tern-kiku-test-7xuidxe6`。
- 只读安全预检未发现达到报告门槛的新数据丢失缺陷，不替代最终审查或全部验收。
- 完整回归仍受阻：`tern-kiku-test-evmeqxnq` 通过12组旧创建/基础检查后，在旧创建流程触发 `process exceeded 50 ms`，尚未进入新增移除场景；其 `logs/tern-serve.log:10-11` 保存宿主错误。
- 不加载业务模块的真实Tern进程探针也复现同类50ms上限；没有提高预算、自动重载或失败重试。
- 用户批准先集成本实现并推进04；本任务仍待其余原生场景及完整回归验收，未设置 resolved。
