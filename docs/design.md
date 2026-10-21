# Kiku 助手设计访谈

状态：创建流程及基准分支选择已实现、隔离集成测试通过；Herdr worktree 管理行为迁移已获实施授权，规范及任务图见 [worktree 管理规范](../.scratch/worktree-management/spec.md)。
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
- 用户在设计访谈时确认先记录、暂不实施；随后调用 `implement-spec` 授权按已确认设计实施。后续范围、验收和进度以关联规范及 tickets 为准。

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

## Herdr 快捷工具迁移（已实现，本轮仅本机）

用户于 2026-10-21 通过 `grill-with-docs` 确认设计，随后调用 `implement-spec` 授权实施。实施前进一步明确：本次所有功能暂不考虑远程，后续统一实现远程；本节按该最新决定更新，规范及任务图见 [Kiku 助手规范](../.scratch/kiku-assistant/spec.md)。

### 已确认的边界

- 仅迁移 `Ctrl+B → Option+G` 打开 lazygit、`Ctrl+B → t` 打开临时终端，优先保留原使用习惯，不调整已有 worktree 流程或其他快捷键。
- 接受 Tern 原生浮窗，不改用临时标签页；接受默认小尺寸与四角定位，不要求复制 Herdr 的居中、百分比尺寸。
- 本轮所有功能仅支持本机 macOS/Linux；远程能力由用户明确延后到后续统一实现。新工具必须确认来源属于本机，远程或主机身份不明时明确拒绝，不在本机执行远程路径，不识别本地 shell 内手动建立的 SSH 子会话，不预建半成品远程通路。
- 两项工具均从触发时来源窗格的当前目录启动，不强制切到 Git 工作树根目录；lazygit 自行识别仓库。无法可靠取得目录时提示错误，不猜路径。
- 每个来源窗格最多各有一个 lazygit 和一个临时终端；重复触发聚焦已有实例，不重复创建或结束程序。不同来源窗格不串用；实例存活时保留其自身目录，退出后重建才读取来源的新目录。
- 第三方程序优先使用本机手动路径，未配置或显式路径无效时允许回退本机 `PATH`；均不可用时不启用对应启动功能，具体规则见下文“命名与第三方程序依赖”。临时终端使用 Tern 默认 shell，不自动安装程序。
- 采用“收起保活 + 显式结束”，不照搬 Herdr 必须退出程序才能返回的体验：`Ctrl+B → q` 收起当前插件工具并返回来源窗格，原打开快捷键恢复／聚焦；`Ctrl+B → Shift+Q` 明确结束当前插件工具。结束运行中或状态不明的工具前确认，不全局抢占裸 `Esc`、`Ctrl+C`，不删除工具中创建的文件。
- 工具正常退出后关闭浮窗；失败需保留可查看的错误，不一闪而过。无法确认进程代次的失败卡片交由 Tern 原生查看／关闭，插件不凭历史标记继续管理。
- 同一来源一次只显示一个工具浮窗，默认右下角；打开另一工具时收起前者但保留程序。浮窗内触发另一工具仍使用原来源，不形成嵌套工具归属。
- 来源窗格单独关闭后不自动杀掉仍存活的工具，也不把它绑定到其他来源；本次插件运行期内，身份已确认的工具可通过“恢复收起的工具”命令找回，列表显示主机与目录，选中后恢复成独立终端标签页，不突然自动跳出新标签页。
- 原生回归与 SDK 身份能力审查后，用户明确选择安全模式：本轮取消跨插件重载自动接管。重载后旧终端与任务保持原状，不自动收起、移动、结束或重跑，改由 Tern 原生管理。历史标记、旧 pane ID 和一个仍存活的 PID 不构成候选窗格的归属证明；Restart 或进程代次无法确认时停止插件管理。远程断线与重连留待未来统一支持远程时实现。
- 保活不是阻止用户结束进程：不替代 Tern 对整个标签页、会话或宿主的原生关闭规则，不承诺在这些操作终止程序后复活任务。
- 沿用现有快捷键配置与命令面板入口惯例，尊重用户 Tern keybinds 覆盖，不修改已有 worktree 创建／管理绑定。收起和结束仅作用于插件工具，不把普通窗格当作工具关闭。

### 已核实的来源与平台差异

- 用户 Herdr 配置中，`prefix+alt+g` 执行 `/opt/homebrew/bin/lazygit`，popup 尺寸为 `90% × 90%`；`prefix+t` 执行 `exec "${SHELL:-sh}"`，popup 尺寸为 `80% × 80%`；前缀为 `ctrl+b`。
- [Herdr 配置文档](https://herdr.dev/docs/configuration/#custom-command-keybindings) 说明 popup 不改变 tab 布局，包含 Esc 在内的终端输入交给命令，命令退出后结束；退出临时 shell 后恢复原终端视图。自定义命令从可检测到的聚焦 pane 工作目录启动。文档未承诺同一快捷键重复触发时的复用策略。
- 本机导出的 Tern 0.9.5 SDK 中，`cx.layout:float(pane, over, corner, reveal)` 只暴露四角定位，无居中或百分比尺寸参数；`park` 隐藏 pane 并保持程序运行，`unpark` 可恢复。接口说明见 [Window API](https://docs.stencil.so/tern/reference/api-window.html#layout-cx)。
- 隔离 Tern 实例已实际验证终端创建、转为浮窗、停放、恢复为浮窗和关闭；截图显示原生四角小浮窗。此核验不代表两个新操作、快捷键或远程执行已经实现或通过验收。
- 本轮核验文件位于 `/tmp/tkp-Nq5MZO/`，截图为 `shots/serve/floating-terminal.png`；隔离实例及自建窗格已关闭。
- [Tern Layout／Launch 契约](https://docs.stencil.so/tern/reference/api-window.html#layout-cx) 明确 `split` 在目标 pane 所属主机创建终端，`Launch.command` 由该 pane 的 login shell 执行；普通插件的 launch 不能据此推断继承本地 shell 内手动建立的 SSH 会话。远程实机执行尚未验证。
- 补充隔离探针确认：收起的终端在来源窗格关闭后仍存在，可通过 `move_to_new_tab` 恢复为独立终端；可见浮窗在其唯一 tiled 来源关闭后仍存活，但被 Tern 转为普通 pane，插件仍需按已确认策略处理归属。
- 一次带命令的 `split` 探针报告 `lua exceeded hard slice budget of 50 ms`；随后读取实际状态发现该 pane 已创建，且保留了 `exited = 7` 的失败终端。不能将调用报错视为“未创建”，也不能据此宣称正常退出、错误输出呈现或远程完整生命周期已通过验证。
- 补充原生证据：`tern-kiku-test-z6g4pw39` 中，普通窗格仅展示旧工具 prefix 文本，恢复扫描便错误认领该窗格。Tern 0.9.5 的 `PaneInfo` 不提供 shell PID／进程代次，进程列表也不提供 pane 绑定；因此不能把旧进程仍存活当作当前候选窗格的身份。用户据此批准上述安全模式，而非降低身份检查以保留启发式恢复。

### 实施验收契约

以下为本轮实现遵循的验收要求；macOS 实际结果与验证限制见 [验证记录](verification.md)，不代表 Linux 已实测：

1. 两个打开快捷键在来源目录、来源主机上创建正确工具，且不改变既有 worktree 操作。
2. 同源重复打开复用同一实例；从工具内切换不形成嵌套，另一工具自动收起；不同来源不串用。
3. 收起前后的程序身份、当前目录与运行任务保持，恢复不重新执行启动命令；裸 Esc、Ctrl+C 仍交给程序。
4. 显式结束身份已确认的工具时，空闲 shell 可直接关闭；存在运行中程序或安全状态无法确认时必须确认，取消不改变工具状态。正常退出关闭视图，失败原因可查看；身份代次未知时即使确认也不得由插件关闭。
5. 非 Git 目录可打开临时终端；lazygit 的仓库交互交给程序，插件不自动初始化仓库。目录未知、程序缺失、启动或浮动失败时明确显示主机、目录和原因，不误报成功，不自动杀掉已经启动的任务。
6. 来源单独关闭后，本次运行期内身份已确认的存活工具可从恢复入口找回；重载后旧实例保持原样，不重新接管、重复启动或串到另一来源，普通窗格展示旧工具文本也不获得工具归属。
7. 本机执行、cwd、shell、收起与恢复使用真实 Tern 验证；远程上下文必须安全拒绝。远程实机验收不属于本轮范围，后续统一实现远程时再验收。
8. 保留用户已有配置改动，不覆盖冲突快捷键；收起／结束不误操作普通窗格，隐藏工具不绕过既有 worktree 使用中与安全关闭保护。

用户已通过 `implement-spec` 授权按完整本机规范实施，并确认真实 Tern／Git／进程结果的 TDD 接口。最终审查固定基线为 `4f63305a76ebd4f0831a54837cd4a7b7ed620eef`。

## 命名与第三方程序依赖（已实现，本轮仅本机）

用户于 2026-10-21 补充插件名称、依赖缺失时停用功能和手动程序路径要求，并确认下述入口呈现与路径回退规则。

本节的本机实现已完成，macOS 实机验收见 [验证记录](verification.md)；插件清单、运行代码、快捷键和使用说明已同步，用户已有配置保持原样。本地目录及远端仓库的实际重命名不在本轮执行范围内。

### 命名

- 中文显示名：**Kiku 助手**；英文项目名：**Kiku Assistant**；英文仓库名称：`tern-kiku-assistant`。
- 保留稳定插件 ID `kiku`，不因显示名变更而改写 `plugin.kiku.*` 动作、安装标识或现有数据归属；本地目录与远端仓库的实际更名不在本轮执行范围内。
- `plugin.toml` 已应用 `name = "Kiku 助手"`；稳定 ID 仍为 `kiku`，命令分组和使用说明同步采用新名称。

### 按功能判断依赖

依赖是否可用按实际执行主机分别判断，不是插件的全局开关。未确认可用时不启用依赖它的新建／启动动作，不创建终端后才发现缺少程序；其他功能保持可用。

| 功能 | 外部程序依赖 | 缺失时的范围 |
| --- | --- | --- |
| Git worktree 创建、管理、打开与关闭 | Git | 停用依赖 Git 的对应动作，不影响独立临时终端 |
| 普通／危险 worktree 移除 | Git、系统 `realpath` | 缺少 `realpath` 仅停用移除子动作，不连带停用创建、打开或整个管理入口 |
| lazygit 工具浮窗 | lazygit 及其运行环境中可用的 Git | 停用 lazygit 的启动，不因 lazygit 缺失而停用插件自身的 Git/worktree 功能 |
| 临时终端 | Tern 在对应主机配置的 shell | 不依赖 Git、lazygit 或 `realpath`；shell 配置继续由 Tern 管理 |

现有 worktree 调用使用 `window.luau` 的 Git／realpath helper；lazygit 通过 `lib/lazygit_launch.luau` 的私有 Git 执行桥使用已解析的 Git，真实进程验收见 [验证记录](verification.md)。系统 `realpath` 也纳入可手动指定路径的外部程序，不遗漏系统工具。

- 命令面板隐藏不可用的启动项；选择器中的依赖子动作遵循同样规则。快捷键或直接动作调用仍需保护，只说明缺少哪个程序、对应主机及配置方式，不执行被停用功能。
- 停用启动能力不等于终止现有实例：本次运行期内身份仍已确认的工具，其聚焦、收起、结束与恢复不因可执行文件后来消失而被禁用，也不重新启动程序。重载后或身份代次未知的旧实例遵循上述安全模式。
- 不自动下载或安装依赖，不把远程缺失误判为本机可用，不将未知或断线状态当作依赖存在。

### 手动程序路径与回退

1. 本轮为本机 Git、lazygit、`realpath` 分别配置程序路径，不预建远程配置或执行通路；未来所有功能统一支持远程时再扩展主机维度。
2. 有手动路径且对应程序可执行时优先使用它；未配置、路径不存在或不可执行时，允许按标准程序名回退到本机 `PATH`。
3. 两处都不可用才停用依赖该程序的功能；错误说明包含主机、程序、显式路径的问题及 `PATH` 查找结果。回退成功时应说明发生了回退及最终程序路径，不能让用户误以为仍在执行手动指定的版本。
4. 配置值是程序文件路径，不是包含参数或重定向的 shell 命令。包含空格或特殊字符的路径按单个可执行文件处理，避免被解释成额外命令。
5. 检测与实际调用必须使用同一解析结果及执行环境，覆盖普通 Git 调用、移除安全专用 Git 调用和 `realpath`。检查到插件可调用某个 Git，不等于已经证明 lazygit 的自身运行环境能调用它。
6. 配置修改后按现有插件重载方式重新检测。启动前仍检查有效性，不把旧的可用结果当作永久保证。

### 依赖验收补充

- 缺少 lazygit 时不展示其启动项，快捷键仅提示原因；Git/worktree 和临时终端不被连带停用。
- 缺少 `realpath` 时正常／危险移除均不可执行，但创建、打开和不依赖它的管理动作仍可用。
- 显式路径有效时不被 `PATH` 中的其他版本覆盖；显式路径失效但 `PATH` 有程序时允许回退并显示实际路径；两处均失效时停用对应功能。
- 只处理本机来源，远程上下文明确拒绝；缺少依赖时不留下新终端、分支或工作树。
- 程序文件被移除后，本次运行期内身份已确认的存活工具仍可收起、恢复及结束，不出现“停用入口后无法退出”的状态。
- 程序路径包含空格或 shell 特殊字符时不发生额外命令执行；所有外部程序调用遵守配置结果，不遗漏移除安全检查中的调用。
- 新显示名与英文项目名一致，插件 ID 与既有动作引用保持有效；不覆盖用户已有配置改动。
