# 允许从 OMP、Git 等激活 block 打开快捷工具

Status: resolved
Type: task
Blocked by: 03

## 用户报告

2026-10-22，用户确认：激活 OMP 或 Git 等其他 block 时，lazygit 和临时终端均无法打开，截图提示“无法打开工具，无法确定本机终端来源及其工作目录”。该运行错误以用户观察为准，不再启动 Tern 确认。

## Scope

最小修复 `lib/tools.luau` 来源门禁：当前激活 block 只要有可靠绝对 `PaneInfo.cwd`、标签页及本机上下文，就可发起打开或恢复工具；不局限于普通 terminal。保持来源目录跟随当前 block，不强制切到 Git 根目录，不把 `path` 这个 file/root 字段猜作 cwd。

`liveTool`、`managedNow`、`tool_identity` 的 terminal-only 工具身份保护必须不变；固定 tab／启动目录／kind 单实例、source/target联合采样、single-flight和异步上下文核验不变。未知目录／非本机仍拒绝，不改用户配置或其他 worktree 行为。

## 验收与代码验证

- 在既有获准 seam 上增加回归：实际注册命令从 `agent`（OMP）和 `git` block 发起，创建正确 cwd／默认形态的两类工具；在相同 tab／cwd 的不同 block 来源间复用，不向 OMP 或 Git block 注入工具握手。
- 覆盖 native block 的空／缺失 cwd（即使有 path）仍不启动，非本机来源仍不启动；普通 block 不会因类型放宽获得受管工具身份。
- 先加入来源场景，记录代码级失败，再修复；执行完整隔离逻辑验证、Luau编译／静态分析及相关Python语法检查。保留已知原有告警，不用忽略清零。
- 延续用户明确选择的代码验证限制：不启动 Tern GUI／serve／daemon，不运行原生或浏览器测试。静态源码／SDK资料不能表述为真机通过。
- 更新来源说明、规范与验证记录；当前工作区已有上一轮未提交改动，全部保留，不提交或推送。

## Comments

- 只读核验已确认 `ownerFor` 是唯一来源类型门禁，布局 anchor 接受普通原生 block；SDK `PaneInfo.path` 可能是 file/root path，不提供通用的未知 cwd 回退契约。

## Result

- `ownerFor` 不再要求来源为 terminal，使用当前 block 的可靠绝对 cwd；工具自身的 terminal-only 身份校验和其他安全保护未变。
- 来源场景修复前真实失败 `0 != 1`，修复后通过。完整代码回归 30 场景、151 断言通过，包含从 Git 来源恢复同一停放终端及异步 cwd 变化后重新发起。
- 生产命令 SDK 边界烟测确认从 agent／Git 启动、复用和恢复，普通来源不受管理动作影响且未收到握手注入；Luau 编译、静态分析及 Python 语法检查通过，保留 1 条原有分析告警。
- 只读审查无可行动缺陷；README、设计与验证记录已同步。本轮不启动或重载用户 Tern，不将边界替身称为真机验证，未改用户配置、未提交、未推送。
- 证据：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-block-source-proof-ps4xv8yk/`。执行脚本已移除，保留结果与源码指纹。
