# Tern Kiku Plugin

通过 Tern 原生选择框创建与管理 Git worktree，并安全关闭对应的标签页工作环境。

默认创建快捷键：先按 **Ctrl+B**，松开后再按 **Shift+G**（大写 G）。也可以在命令面板搜索 **Kiku: 新建 Git worktree** 或 **Kiku: 管理 Git worktree**。

## 安装

需要 Git 和支持 `cx:pick` / `cx:prompt` 的 Tern；移除安全审查还需要系统 `realpath`。已在 Tern **0.9.5 (2863c37)**、macOS 上实测。

```bash
tern plugin link ~/Workspace/tern-kiku-plugin
```

链接后可在 Tern 命令面板运行 **Reload plugins**。使用 `tern plugin list` 查看插件状态。

## 使用

1. 在 Tern 中进入项目或任一已有 worktree，聚焦对应终端。
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

从本机仓库内的命令面板运行 **Kiku: 管理 Git worktree**，或配置独立的 `manageKeybinding` 快捷键。选择当前仓库中 Git 登记的 worktree 后，可选择 **打开／切换**、**关闭工作环境** 或 **正常移除 worktree**。列表包括 Git 或其他工具直接创建的 worktree；插件根据 Git 仓库身份和本机 pane cwd 发现有效标签页，优先复用，若有多个匹配项则让你选择，没有时才在打开操作中创建命名标签页；关闭时没有有效绑定则拒绝，不会新建标签页。

关闭只作用于选定的绑定标签页，并检查其中全部 tiled／floating pane。终端和 agent 必须明确空闲；锁定的会话、未保存文件、运行或排队的 Notebook、无法确认安全状态的工具都会被拒绝。Database 等没有充分可核验运行状态的原生面板需要手动关闭。

确认列表默认选取消，明确显示目标 session／tab ID，并逐项列出将关闭的 pane。选择“查看 pane”可检查完整位置信息；预览里的输入不会修改文件或关闭对象，回车返回原确认列表，Esc 取消整个关闭流程。最终确认后重新检查环境身份、pane 集合和安全状态；预览期间的变化不会被返回操作重新认可。

关闭不移除 worktree、目录或分支，不提供强制关闭。预期的安全拒绝直接显示原因及手动处理建议；部分关闭失败时报告已关闭的 pane 并停止，不继续扩大操作范围。

正常移除仅针对身份已确认、未锁定且干净的 linked worktree；主工作树通过最新 Git 登记中的主工作树项识别，与发起操作的来源 worktree 分开。界面检查 tracked、untracked、ignored 文件、隐藏索引标记、Detached HEAD 的本地／远程分支及标签保护，以及当前窗口内 tiled、floating、parked pane 的 cwd、原生 path 和本机 file URL。可见本机 pane 缺少可核实位置、host 归属不明、身份不符或安全状态不完整时拒绝；远程 pane 不按本机路径误判。确认列表默认选取消；“查看完整目标路径…”会显示完整路径，返回原确认列表时不会刷新审查基线。最终确认会重新审查 Git 登记、仓库身份、文件／索引／refs 和可见 pane；状态变化即停止。成功后只移除目标目录及 Git 登记，保留分支和其他工作树。

无法完整审查的嵌套仓库、子模块、嵌套 worktree、无效或锁定登记、身份未知状态均拒绝移除。安全状态读取和最终普通 Git 移除均以命令级 `core.fsmonitor=false` 绕过陈旧文件监视缓存，不改写 Git 配置；路径安全检查依赖系统 `realpath`（macOS/Linux），命令不可用或身份无法确认时拒绝移除。Git 错误保留现场，不自动关闭程序、解锁、删除分支、清理 Git 记录或强制重试。

检查范围限于当前窗口可见的本机会话。其他窗口、外部终端及其他工具是否仍在使用目标，需要操作者自行确认；插件不声称检测全部外部进程或提供跨窗口原子性。移除不会自动关闭这些环境，不能代替外部使用确认。

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

修改后在 Tern 命令面板执行 **Reload plugins**。Tern 用户 `keybinds` 可以绑定动作 `plugin.kiku.create_worktree`；用户设置优先于插件快捷键。如果插件快捷键与 Tern 内置键位冲突，Tern 会忽略该绑定，命令面板入口仍可使用。macOS 的 `cmd+alt+w` 已用于关闭标签页。

## 错误处理与边界

- 已存在的目录不会覆盖，即使它是空目录；可保留输入并改路径重试。
- 已存在的新分支名不会覆盖；可修改名称或改为“已有分支”方式。
- 执行前重新检查分支占用，Git 仍负责最终的并发冲突检查。
- Git 返回失败或超时后不自动删除目录、分支或 Git 留下的记录；必要时先运行 `git worktree list` 检查实际结果。
- worktree 创建成功但标签页打开失败时，保留 worktree 并通过提示显示路径。
- 创建过程中切换 Tern 会话，结果仍在原来的本机会话打开；若原会话已关闭，则保留 worktree 并报路径。
- 首版面向 macOS / Linux 本机仓库；Tern 管理的远程会话会被拒绝。Windows、iOS、web 不支持。普通终端里手动运行的 SSH 嵌套会话不在支持范围内。
- 没有首个提交的仓库没有可用 HEAD；插件会显示 Git 错误。先完成首次提交再使用。
- 终端需要正常报告当前目录（Tern 默认 shell integration）。

## 开发和验证

插件无需构建，也无需 Python、Node 或 lazygit 作为运行依赖。运行依赖 Tern/Luau 和 Git；移除安全审查额外依赖系统 `realpath`，创建和打开不需要它。Python 3 仅用于集成验证。

```bash
# 为编辑器生成与本机 Tern 匹配的声明文件（已 gitignore）
tern plugin types .

# 真实 Tern/Git 集成测试；测试工具额外需要 Python 3
python3 tests/integration.py
```

测试使用独立 Tern 配置、测试插件副本和临时 Git 仓库，不修改日常 Tern 配置。测试结束会关闭实例；报告、截图和日志保留在打印出的临时目录。Linux 测试需要可运行 Tern 的图形环境；当前实测平台为 macOS。

目录结构：

```text
plugin.toml          # 插件清单
window.luau          # 原生创建／管理流程、异步 Git 操作及工作树标签页绑定
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
