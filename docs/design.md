# Tern Kiku 插件设计访谈

状态：创建流程及基准分支选择已实现、隔离集成测试通过；Herdr worktree 管理行为迁移设计已确认，本轮暂不实现。
日期：2026-10-20。

## 已确认的产品行为

1. 使用 Tern 原生选择框和输入框，对齐 lazygit 的工作树创建步骤。
2. 提供「新分支 + worktree」「已有分支 + worktree」「Detached worktree」三种方式，默认选中新分支方式。
3. 使用当前聚焦终端目录所属的 Git 工作树作为来源；新分支与游离工作树默认基于发起时的 HEAD，也可选择本地分支或已获取的远程跟踪分支作为基准。
4. 未提交修改保留在来源工作树，目标工作树从已提交内容开始。
5. 首版支持本机 Git 项目；远程会话暂不支持。
6. 创建成功后打开并聚焦新 Tern 标签页，终端进入目标工作树目录，分支模式使用分支名命名标签页。
7. 首版不自动复制 .env、不安装依赖、不执行项目初始化脚本。
8. 选择框支持键盘筛选、回车确认；Esc 取消当前创建流程。

用户在第一轮回答「全按推荐」。

## 第二轮确认

用户在第二轮同样回答「全按推荐」，确认快捷键、目录规则、已有分支范围与失败处理。具体决定见下文。

## 已核实的环境与接口

- 本机 Tern：0.9.5（2863c37）；本机 lazygit：0.65.1。
- Tern 原生 cx:pick 与 cx:prompt 返回 awaitable，取消时返回 nil。
- Git 进程可通过 tern.process.run 异步执行，窗口回调获得新的 cx。
- 插件可通过 cx.layout 创建指定 cwd 的标签页。

## 参考

- https://docs.stencil.so/tern/reference/api-window.html
- https://docs.stencil.so/tern/reference/api-shared.html
- https://docs.stencil.so/tern/concepts/packages.html
- https://github.com/jesseduffield/lazygit/blob/master/pkg/gui/controllers/helpers/worktree_helper.go

## 第二轮已确认决定

1. 默认快捷键 Ctrl+B → Shift+G（`ctrl+b>shift+g`）；通过插件 config.json 的 keybinding 配置，也允许通过 Tern keybinds 覆盖，并提供命令面板入口。用户于 2026-10-20 将此前确认的快捷键调整为此序列。
2. 目录候选对齐 lazygit 0.65.1：已有 linked worktree 的父目录、插件配置的默认父目录，去重；无候选时使用主仓库上一级目录。每项显示完整目标路径，最后提供「其他目录」。分支名中的 / 保留为目录层级，ASCII 空格转为 -。
3. 已有分支支持本地分支及已获取的远程跟踪分支，不自动 fetch；已被工作树占用的分支不可再次检出。
4. 路径或分支冲突时保留输入并允许修改重试，不覆盖或强制删除。Git 创建成功但标签页打开失败时保留工作树并显示完整路径。

## 分支基准选择

用户于 2026-10-20 要求支持选择基于某个分支创建 worktree。实现沿用原生选择框：

- 新分支与 Detached 模式先选创建基准，再输入名称；第一项为发起操作时的当前 HEAD。
- 本地分支和已获取的远程跟踪分支按组列出，支持输入筛选；已被工作树占用的本地分支仍可作为起点。已有分支检出模式继续排除被占用分支。
- 使用完整 ref 解析所选分支，避免同名 tag 歧义；将解析出的 commit OID 固定为创建基点，路径或名称重试仍使用此 OID。
- 目录选择框显示基准名称和提交短哈希；重新选择创建方式时清除旧基准信息。
- 不 fetch、不切换来源分支，也不因选择远程基准建立 upstream；需要本地跟踪分支仍使用“已有分支 + worktree”。
- 在基准选择框按 Esc 取消，不创建分支或工作树。

## 本机键位与版本核验

在隔离的 Tern 0.9.5 headless 实例中读取 cx.actions:keys()：
- cmd+alt+w 已绑定 close_tab。
- cmd+alt+shift+w 未绑定。
- ctrl+alt+w 未绑定。

lazygit v0.65.1 精确源码：
https://github.com/jesseduffield/lazygit/blob/17cb09fa7b08bc96d9f0e81b91f4720fc1a36700/pkg/gui/controllers/helpers/worktree_helper.go

该版本目录策略与第二轮建议一致；feature/login 会作为嵌套目录名，名称清理只将 ASCII 空格替换为连字符。

## Herdr worktree 管理行为迁移（设计已确认）

用户要求根据现有 Tern SDK 评估迁移 Herdr 的 worktree 管理功能。

- 已确认：以创建、列出、打开／切换、安全移除的管理行为对齐为目标，界面和工作区组织使用 Tern 原生能力，不要求一比一复制 Herdr workspace 界面。
- 已确认：管理当前仓库的全部 worktree，包括 Git、lazygit、Herdr 等外部工具创建的；以 Git 实际状态为准。主工作树可打开，但不能从插件移除。
- 已确认：沿用一棵 worktree 对应一个命名标签页，标签页内可拆分 pane，不改为每棵 worktree 一个独立 session。
- 已确认：本轮仅覆盖本机 macOS/Linux，继续拒绝远程会话操作。
- 已确认：保留当前 lazygit 对齐目录策略、`defaultPath` 和自定义路径，不采用 Herdr 集中目录规则，不搬迁已有工作树。
- 已确认：打开时优先复用当前窗口可见会话中的有效绑定标签页；有多个候选时让用户选择，没有候选才新建，不自动合并或关闭。
- 已确认：关闭只针对选定的绑定标签页；检测到运行中命令、未保存内容或安全状态无法判断时拒绝自动关闭，通过检查后仍需确认。不提供插件内强制关闭。
- 已确认：移除前先关闭当前窗口可见会话中仍在使用该工作树的环境；关闭与移除分为两步。外部终端和其他工具的使用情况仍由用户确认。
- 已确认：提供独立的危险移除入口，展示将丢弃的内容并要求再次输入目标路径。正常移除保持保守，不删除分支，也不自动 merge 或 push。
- 已确认：危险入口可舍弃本地已修改、未跟踪和忽略文件，但不能移除主工作树、锁定工作树、仍被可见环境使用的工作树或身份／状态未知的路径；不自动 unlock，不使用双重 `--force`。
- 已确认：没有分支或标签保护的 Detached 提交属于危险移除情形；正常移除停止并提示先保留提交，危险入口可在展示提交风险和再次确认后允许放弃，不自动创建或删除分支。
- 已确认：保留 `Ctrl+B → Shift+G` 的新建行为，另加「Kiku: 管理 Git worktree」命令，允许单独配置管理快捷键，默认不新增绑定。
- 用户已最终确认整体设计；本轮止于可行性评估和文档记录，暂不实施新增管理功能。

### SDK 可行性核验

本机实际版本：Herdr 0.9.5；Tern 0.9.5（2863c37）。已运行 Herdr 只读 CLI 帮助，并通过 `tern plugin types <临时目录>` 导出本机 SDK 声明，未修改日常配置。

- Herdr 的 `worktree create/list/open/remove` 对应创建、发现、打开和移除；`workspace close` 只关闭界面状态，`worktree remove` 使用 Git 移除 checkout 且不删除分支。创建的 worktree workspace 与父仓库 workspace 分组。来源：[Herdr v0.9.5 CLI reference / Worktrees](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.5/docs/next/website/src/content/docs/cli-reference.mdx)。
- Tern 提供 `cx.session:tabs/panes`、`cx.sessions:list/create/switch/close`、`cx.layout:tab/focus/close`，可组合实现工作树发现、打开复用及环境关闭。worktree 的 Git 操作仍由插件通过 `tern.process.run` 执行；SDK 没有专用 worktree 管理接口。来源：本机 `tern.d.luau` 的 `SessionCx`、`SessionsCx`、`LayoutCx`、`GitCx` 声明及 [Window API](https://docs.stencil.so/tern/reference/api-window.html)。
- `cx.layout:close` 和 `cx.sessions:close` 不带交互确认或锁保护；不能将“Git 工作区干净”等同于“可安全结束程序”。安全确认、操作范围以及 Git 失败时的处理必须由插件实现。来源：本机类型声明及 [Sessions and hosts cx](https://docs.stencil.so/tern/reference/api-window.html#sessions-and-hosts-cx)。
- `snapshot/restore` 保存现存布局而非程序；pane 已增删或 session 消失后可能拒绝恢复。不可用它承诺重启后恢复任意运行中的命令。来源：[Layout cx](https://docs.stencil.so/tern/reference/api-window.html#layout-cx)。
- 进程和文件操作在对应 VM 所在机器执行，窗口插件的 `tern.process.run` 不因当前焦点在远程会话就自动成为远程执行；远程 worktree 管理需要单独设计执行通路。来源：[Shared API](https://docs.stencil.so/tern/reference/api-shared.html)。
- 多窗口共用 `tern.kv`，但并发写入为最后一次重命名获胜，不能用它代替跨窗口互斥锁；SDK 未提供原子的“查找或创建工作树环境”操作。来源：[Storage](https://docs.stencil.so/tern/reference/api-shared.html#storage)。

隔离 Tern 实例实际通过五项探针：跨会话枚举 tab/pane/cwd 与关联 ID、切换并聚焦已有 tab、恢复现存 tab 布局元数据、关闭指定 tab 的最后一个 pane、关闭指定 session 且保留另一个 session。探针仅操作临时实例中的自建环境，没有操作用户会话或真实工作树。

报告：`/private/tmp/tks-l5staddh/report.json`。探针准备期间修正了控制命令的 Lua 字符串传参、macOS Unix socket 路径长度和 `PaneInfo.pane` 字段使用；最终五项全部通过。尚未验证远程执行、多窗口并发及完整 worktree 移除流程。
