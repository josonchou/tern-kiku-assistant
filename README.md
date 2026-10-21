# Kiku 助手（Kiku Assistant）

仓库名称：`tern-kiku-assistant`。稳定插件 ID 为 `kiku`；本地目录和远端仓库名称不因本说明而变更。本插件目前只支持 macOS/Linux 本机操作，不支持远程环境；远程功能留待后续统一实现。

Kiku 助手在 Tern 中创建、发现和管理 Git 工作树，并安全关闭对应的标签页工作环境；快捷工具随来源窗格提供 lazygit 与临时终端工具浮窗。

## 安装

需要支持 `cx:pick` / `cx:prompt` 的 Tern。工作树创建、打开和管理需要本机 Git；正常及危险移除另需本机 `realpath`。lazygit 仅供 lazygit 工具使用，缺失时不影响工作树操作或临时终端；lazygit 启动环境还须能使用 Git。依赖按功能独立门控，不自动安装程序。Git、lazygit 和 realpath 均可在插件配置中指定单个可执行文件路径；配置路径不可用时会回退本机 `PATH`，两者均不可用才停用相应功能。临时终端使用 Tern 默认 shell，不另设 shell 配置。

```bash
tern plugin link ~/Workspace/tern-kiku-assistant
```

这是本地开发目录示例，请替换为实际插件目录；它不代表已发布的下载地址。链接后可在 Tern 命令面板运行 **Reload plugins**。使用 `tern plugin list` 查看插件状态。

## 快捷工具

快捷键均可配置，默认值如下：

| 操作 | 快捷键 |
| --- | --- |
| 打开 lazygit | **Ctrl+B → Option+G** |
| 打开临时终端 | **Ctrl+B → t** |
| 收起当前工具 | **Ctrl+B → q** |
| 结束当前工具 | **Ctrl+B → Shift+Q** |

从来源窗格触发时，工具在 Tern 原生右下角小浮窗中启动，初始目录为触发时的当前目录；不强制切换到 Git 根目录。该浮窗不同于 Herdr 的居中大弹窗。临时终端可从非 Git 目录启动，插件不会自动执行 `git init`。

同一来源窗格最多保留一个 lazygit 和一个临时终端实例。重复打开会聚焦或恢复本次插件运行期内身份已确认的现存实例，保留工具自己的当前目录；退出后再打开才使用来源窗格的新目录。工具内触发另一工具仍归属原来源，不会嵌套。切换工具会收起另一个工具但不结束其程序；同一来源一次只显示一个工具。

**收起当前工具**会隐藏视图并回到来源窗格，程序、目录和运行任务继续保留；再次打开可恢复。来源窗格关闭后，身份已确认的存活工具会收起但不会转交给其他来源。本次插件运行期内使用“恢复收起的工具”命令可查看主机和目录并恢复为独立终端标签页，不自动抢占焦点。整个标签页、会话或宿主被关闭时仍遵循 Tern 自身规则；插件不承诺复活已结束的进程。

**结束当前工具**会结束程序并关闭视图，但不会删除其中创建的文件。空闲 shell 可直接结束；存在运行程序或状态无法确定时会要求确认，默认取消。按 **Esc** 或 **Ctrl+C** 不会结束插件工具，也不会关闭普通窗格。

**安全模式**：插件重载后，不重新接管旧终端，不自动收起、移动、结束或重跑已有程序；旧实例交由 Tern 原生管理。失败卡片仍保留供查看，但无法确认进程代次时仅由原生关闭。历史标记、旧窗格 ID 或仍存活的 PID 不能单独证明归属；身份未知时，插件即使收到结束请求也只提示并停止。

重载前已收起的旧工具，可在 Tern 原生 **Parked panes**（默认 **Ctrl+Shift+↑**）中选择卡片恢复。这是原生视图恢复，不会重新执行工具启动命令。

插件仅在确认来源属于本机且目录可知时执行本机操作；远程上下文、主机或来源目录未知时拒绝，不把远程路径当成本机路径。配置的可执行程序路径应指向单个可执行文件，而不是 shell 命令；显式路径存在且可执行时优先，未配置、失效或不可执行时回退到本机 `PATH`，并说明实际使用路径；两者均不可用时停用相应功能并说明本机、程序、配置位置及原因。独立的 `realpath` 缺失只影响正常与危险移除，不影响创建、打开或快捷工具。命令面板会按依赖隐藏不可用的启动项；快捷键或直接调用仍会检查依赖并提示，不会先创建终端再报告缺失。

快捷键动作 ID：`plugin.kiku.open_lazygit`、`plugin.kiku.open_terminal`、`plugin.kiku.hide_tool`、`plugin.kiku.end_tool`、`plugin.kiku.restore_tools`。程序路径配置的键为 `executables.git`、`executables.lazygit`、`executables.realpath`。原有 `defaultPath`、`keybinding`、`manageKeybinding` 语义及用户覆盖保持不变；以下配置示例仅展示新增项，不要求覆盖现有用户配置：

```json
{
  "defaultPath": "../app-worktrees",
  "keybinding": "ctrl+b>shift+g",
  "manageKeybinding": "",
  "lazygitKeybinding": "ctrl+b>alt+g",
  "terminalKeybinding": "ctrl+b>t",
  "hideToolKeybinding": "ctrl+b>q",
  "endToolKeybinding": "ctrl+b>shift+q",
  "executables": {
    "git": "",
    "lazygit": "",
    "realpath": ""
  }
}
```

路径留空时使用本机 `PATH`。`defaultPath`、`keybinding` 和 `manageKeybinding` 的说明见下方“配置”。

## 工作树使用与安全

默认创建快捷键：先按 **Ctrl+B**，松开后再按 **Shift+G**（大写 G）。也可以在命令面板搜索 **Kiku 助手: 新建 Git worktree** 或 **Kiku 助手: 管理 Git worktree**。

1. 在本机 Tern 中进入项目或任一已有 worktree，聚焦对应终端。
2. 依次按 **Ctrl+B → Shift+G**，选择创建方式：
   - **新分支 + worktree**：先选择创建基准，再输入新分支名。
   - **已有分支 + worktree**：筛选本地分支或已获取的远程跟踪分支；已检出的本地分支不显示。远程分支会先让你确认本地跟踪分支名。
   - **Detached worktree**：先选择创建基准，再输入工作树名称，不增加分支。
3. 选择完整目标路径，或选 **其他目录…** 自行输入；新分支与 Detached 的目录选择框会显示所选基准及提交短哈希。
4. 回车开始创建；完成后自动打开并聚焦新标签页。

创建基准默认是**发起操作时的当前 HEAD**，也可筛选本地分支或已获取的远程跟踪分支。已在其他 worktree 检出的分支仍可作为基准。选择分支后会固定其当时的提交，后续分支移动或路径重试不会改变创建起点；这不会切换来源分支，也不会为新分支建立 upstream。需要跟踪远程分支时，请使用“已有分支 + worktree”。

选择框支持输入筛选、上下键选择、回车确认。选择框或输入框中按 **Esc** 取消整个创建流程。最后一次路径确认才会执行 `git worktree add`；Git 执行中请等待完成。

分支名中的 ASCII 空格会转为 `-`，`/` 保留。例如 `feature/login page` 变成 `feature/login-page`，对应嵌套目录。名称会先通过 Git 校验。

原目录的未提交修改留在原处；新目录使用已提交内容。插件不自动 fetch，不复制 `.env`，不安装依赖，也不执行额外初始化脚本。Git 自身配置的 hooks、过滤器仍按 Git 正常行为运行。

### 管理已有 worktree

从本机仓库内的命令面板运行 **Kiku 助手: 管理 Git worktree**，或配置独立的 `manageKeybinding` 快捷键。选择当前仓库中 Git 登记的 worktree 后，可选择 **打开／切换**、**关闭工作环境**、**正常移除 worktree** 或独立的 **危险移除 worktree**。列表包括 Git 或其他工具直接创建的 worktree；插件根据 Git 仓库身份和本机 pane cwd 发现有效标签页，优先复用，若有多个匹配项则让你选择，没有时才在打开操作中创建命名标签页；关闭时没有有效绑定则拒绝，不会新建标签页。

打开／关闭前会核对实际 Git root 与所选登记路径；目标 `.git` 失效而回退到父仓库时拒绝，不误用父工作环境。新建结果也会检查目标本身仍是 Git 根，打开失败时保留已创建的 worktree。合法符号链接父目录仍受支持，按 Git 登记的规范路径打开。

关闭只作用于选定的绑定标签页，并检查其中全部 tiled／floating pane。终端和 agent 必须明确空闲；锁定的会话、未保存文件、运行或排队的 Notebook、无法确认安全状态的工具都会被拒绝。Database 等没有充分可核验运行状态的原生面板需要手动关闭。

确认列表默认选取消，明确显示目标 session／tab ID，并逐项列出将关闭的 pane。选择“查看 pane”可检查完整位置信息；预览里的输入不会修改文件或关闭对象，回车返回原确认列表，Esc 取消整个关闭流程。最终确认后重新检查环境身份、pane 集合和安全状态；预览期间的变化不会被返回操作重新认可。

关闭不移除 worktree、目录或分支，不提供强制关闭。预期的安全拒绝直接显示原因及手动处理建议；部分关闭失败时报告已关闭的 pane 并停止，不继续扩大操作范围。

正常移除仅针对身份已确认、未锁定且干净的 linked worktree；主工作树通过最新 Git 登记中的主工作树项识别，与发起操作的来源 worktree 分开。界面检查 tracked、untracked、ignored 文件、隐藏索引标记、Detached HEAD 的本地／远程分支及标签保护、未完成 Git 操作及其恢复状态，以及当前窗口内 tiled、floating、parked pane 的 cwd、原生 path 和本机 file URL。可见本机 pane 缺少可核实位置、host 归属不明、身份不符或安全状态不完整时拒绝；远程 pane 不按本机路径误判。确认列表默认选取消；“查看完整目标路径…”会显示完整路径，返回原确认列表时不会刷新审查基线。最终确认会重新审查 Git 登记、仓库身份、文件／索引／refs、未完成 Git 操作和可见 pane；状态变化即停止。成功后只移除目标目录及 Git 登记，保留分支和其他工作树。

危险移除用于明确放弃目标工作树中的本地修改、未跟踪文件、忽略文件，或无分支／标签保护的 Detached 提交。先查看风险预览；**查看完整目标路径…** 只是只读预览，不构成授权。选择 **继续：输入完整目标路径** 后，输入框初始为空，必须重新输入与目标完全一致的完整路径，再明确确认**无外部使用**。任一级按 Esc 或选择取消都不执行移除；路径不符可重新输入或取消。最终确认前插件会重新检查 Git 登记、仓库身份、HEAD／分支、风险清单、refs、未完成 Git 操作与当前窗口可见 pane；相关状态变化会取消本次操作并要求重新审阅。超长风险列表会在风险项前明确说明未展示项也会被丢弃；选择风险行可打开完整内容预览，编辑后回车仅返回原风险基线，不构成授权。

危险入口只在上述复查一致时执行一次 `git worktree remove --force -- <path>`，保留对应分支；它不会自动关闭程序，也不会越过主工作树、锁定或失效登记、仍被可见环境使用、嵌套 worktree／子模块、路径身份不符或状态无法确认等硬保护。不自动 unlock、删除分支、清理登记或重试。Git 移除失败或超时可能已部分删除目标内容或登记；提示不代表事务回滚。不要据此认定目录／登记完整保留，也不要自动补救或重试，请先检查目录与 `git worktree list` 的实际状态。

插件仅能检查当前窗口可见的本机会话；其他窗口、外部终端及其他工具的使用情况仍须由操作者确认。它不保证检测所有外部进程或跨窗口原子性，也不会自动关闭这些外部环境。完整真实验证记录见 [`docs/verification.md`](docs/verification.md)。

无法完整审查的嵌套仓库、子模块、嵌套 worktree、无效或锁定登记、身份未知状态均拒绝移除。正常与危险移除都拒绝目标 worktree 中未完成的 merge／autostash、cherry-pick、revert、rebase、sequencer 或 bisect 状态；请先保存需要保留的内容，再在 Git 中手动结束或中止操作。审查需要 Git 支持 `for-each-ref --include-root-refs`，且能读取目标 worktree 的 private Git 状态；不支持或无法确认时拒绝移除，不作隐式降级。安全状态读取以及普通／危险移除前的最终 Git 检查，均以命令级 `core.fsmonitor=false` 绕过陈旧文件监视缓存，不改写 Git 配置；路径安全检查依赖系统 `realpath`（macOS/Linux），命令不可用或身份无法确认时拒绝移除。

## 与 lazygit 对齐的目录规则

对齐版本：lazygit **0.65.1**，源码固定在 commit `17cb09fa7b08bc96d9f0e81b91f4720fc1a36700`。

1. 列出已有 linked worktree 的父目录；从 linked worktree 发起时优先其父目录。
2. 加入 `config.json` 中的 `defaultPath`，去重。
3. 如果前两步都没有候选，使用主仓库的上一级目录。
4. 在各父目录后拼接分支名或工作树名称，最后提供“其他目录…”。

例如主仓库为 `/Users/you/Workspace/app`，还没有其他 worktree：

```text
/Users/you/Workspace/
├── app/                 # 原仓库
└── feature/
    └── login/           # 新分支 feature/login
```

`defaultPath` 的相对路径以主仓库目录解析；“其他目录”输入的相对路径以来源工作树的根目录解析。两者均支持绝对路径及 `~/`。

## 配置

编辑插件目录的 `config.json`：

```json
{
  "defaultPath": "../app-worktrees",
  "keybinding": "ctrl+b>shift+g",
  "manageKeybinding": ""
}
```

- `defaultPath`：额外的默认父目录。空字符串表示只参考已有工作树，没有时回退到主仓库上一级目录。
- `keybinding`：创建 worktree 的快捷键。`>` 分隔先后按下的组合键，`+` 表示同时按下；空字符串回退到 `ctrl+b>shift+g`。
- `manageKeybinding`：管理 worktree 的独立快捷键，格式相同；空字符串表示不绑定，仍可从命令面板运行。
- `lazygitKeybinding`、`terminalKeybinding`、`hideToolKeybinding`、`endToolKeybinding`：对应快捷工具的可配置快捷键；默认分别为 `ctrl+b>alt+g`、`ctrl+b>t`、`ctrl+b>q`、`ctrl+b>shift+q`。
- `executables.git`、`executables.lazygit`、`executables.realpath`：对应程序的本机可执行文件路径；留空或路径不可用时从本机 `PATH` 回退查找。Git、lazygit、realpath 各按依赖门控对应功能，不会自动安装程序。
- 原有配置字段仍按原语义读取，新增字段采用默认值；不必将示例完整复制到已有配置中。

修改后在 Tern 命令面板执行 **Reload plugins**。Tern 用户 `keybinds` 可以绑定动作 `plugin.kiku.create_worktree`；用户设置优先于插件快捷键。如果插件快捷键与 Tern 内置键位冲突，Tern 会忽略该绑定，命令面板入口仍可使用。macOS 的 `cmd+alt+w` 已用于关闭标签页。

## 错误处理与边界

- 已存在的目录不会覆盖，即使它是空目录；可保留输入并改路径重试。
- 已存在的新分支名不会覆盖；可修改名称或改为“已有分支”方式。
- 执行前重新检查分支占用，Git 仍负责最终的并发冲突检查。
- Git 返回失败或超时后不自动删除目录、分支或 Git 留下的记录；必要时先运行 `git worktree list` 检查实际结果。
- worktree 创建成功但标签页打开失败时，保留 worktree 并通过提示显示路径。
- 创建过程中切换 Tern 会话，结果仍在原来的本机会话打开；若原会话已关闭，则保留 worktree 并报路径。
- 仅支持 macOS / Linux 本机仓库；Tern 管理的远程会话会被拒绝。Windows、iOS、web 不支持。普通终端里手动运行的 SSH 嵌套会话不在支持范围内；远程功能留待后续统一实现。
- 没有首个提交的仓库没有可用 HEAD；插件会显示 Git 错误。先完成首次提交再使用。
- 终端需要正常报告当前目录（Tern 默认 shell integration）。

## 开发和验证

插件无需构建；Python、Node 不是运行依赖。运行时需要 Tern/Luau，各功能独立检查程序：工作树操作需要 Git，正常／危险移除另需系统 `realpath`，lazygit 浮窗需要 lazygit 和 Git；临时终端只沿用 Tern 默认 shell。Python 3 仅用于集成验证。

```bash
# 为编辑器生成与本机 Tern 匹配的声明文件（已 gitignore）
tern plugin types .

# 真实 Tern/Git 工作树完整回归
python3 tests/integration.py

# 依赖隔离与快捷工具（工具组包含独立 serve Restart 回归）
python3 tests/integration.py --dependencies-only
python3 tests/integration.py --tools-only
python3 tests/integration.py --lazygit-only
python3 tests/integration.py --lazygit-missing-git-only
python3 tests/integration.py --lazygit-missing-lazygit-only
```

测试使用独立 Tern 配置、测试插件副本和临时 Git 仓库，不修改日常 Tern 配置。快捷工具使用正常 GUI 与私有 daemon；macOS 验收期间需保持本机桌面解锁。lazygit 的真实 wrapper 显式使用私有配置目录，不能只依赖宿主环境变量隔离其配置。测试结束会关闭实例；报告、截图和日志保留在打印出的临时目录。Linux 需要可运行 Tern 的图形环境，尚未实测。

目录结构：

```text
plugin.toml          # 插件清单
window.luau          # 原生创建／管理流程、异步 Git 操作及工作树标签页绑定
lib/config.luau      # 配置字段与默认值
lib/executables.luau # 本机外部程序解析、探测和功能门控
lib/tools.luau       # 来源工具实例、浮窗与生命周期
lib/tool_identity.luau # 本次运行期的进程启动身份验证
lib/lazygit_launch.luau # 私有 Git 执行桥与 lazygit 启动环境
lib/worktree.luau    # Git porcelain 解析、路径和创建参数
lib/manager.luau     # 本机跨会话 pane 与工作树身份匹配
lib/removal.luau     # 共用的安全移除审查与路径边界检查
config.json          # 用户可编辑配置
tests/               # Luau 断言及真实 Tern/Git 集成测试
GLOSSARY.md          # 已确认的领域术语
docs/design.md       # 已确认的设计
docs/verification.md # 验证记录
```

卸载链接，不删除项目文件：

```bash
tern plugin unlink kiku
```

## 参考

- [Tern Window API](https://docs.stencil.so/tern/reference/api-window.html)
- [Tern Shared API](https://docs.stencil.so/tern/reference/api-shared.html)
- [Tern 插件包与清单](https://docs.stencil.so/tern/concepts/packages.html)
- [lazygit 0.65.1 worktree 创建流程](https://github.com/jesseduffield/lazygit/blob/17cb09fa7b08bc96d9f0e81b91f4720fc1a36700/pkg/gui/controllers/helpers/worktree_helper.go)
