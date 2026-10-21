# Kiku 助手本机快捷工具与依赖管理

Status: ready-for-agent

## 授权与来源

用户已调用 implement-spec 授权实施 docs/design.md 中的快捷工具和命名／依赖补充设计，并最新明确：本次所有功能不考虑远程，后续统一实现远程。本规范按最新范围执行，不保留半成品远程实现。领域定义见 GLOSSARY.md；本地跟踪规则见 docs/agents/issue-tracker.md。

集成分支：`integration/kiku-assistant`。用户确认审查固定基线：`4f63305a76ebd4f0831a54837cd4a7b7ed620eef`。用户已有 config.json 改动必须原样保留，不暂存或覆盖它；本轮不推送、不建 PR、不实际重命名本地目录或远端仓库。

## 完整范围

1. 显示名为 Kiku 助手，英文名 Kiku Assistant，仓库名称 tern-kiku-assistant；稳定插件 ID kiku、现有 plugin.kiku.* 动作及数据归属保持。更新清单、命令分组和使用文档。
2. 所有操作仅支持本机 macOS/Linux。先确认来源属于本机；主机未知、远程上下文或来源目录未知时拒绝，不把远程路径当成本机路径。现有 worktree 创建／管理／安全移除语义保持。
3. Ctrl+B → Option+G 打开 lazygit，Ctrl+B → t 打开临时终端。使用 Tern 原生右下角小浮窗，不承诺 Herdr 的 90%/80% 居中大弹窗。启动 cwd 为来源窗格触发时目录，不强制切 Git 根目录；非 Git 目录可以开临时终端，插件不自动 git init。
4. 按来源窗格各保留最多一个 lazygit 和一个临时终端，重复触发聚焦／恢复现存实例，不重复启动。存活实例保留自己的 cwd；退出后新建才读取来源新 cwd。工具内触发另一工具仍归属原来源，不嵌套；同源一次只显示一个工具，切换时收起另一个但不结束程序。
5. Ctrl+B → q 收起当前插件工具，回到来源窗格，保持程序、目录和运行任务；Ctrl+B → Shift+Q 显式结束当前插件工具。空闲 shell 可直接结束，存在运行程序或状态未知必须确认，默认取消，取消不改状态；执行前重核身份与状态。不抢占裸 Esc/Ctrl+C，不结束普通窗格，不删除文件。
6. 程序正常退出关闭浮窗，失败保留可查看的错误，不一闪而过。来源窗格单独关闭后保留存活工具并收起，不绑定给其他来源；提供“恢复收起的工具”命令，列出主机与目录，选中后恢复为独立终端标签页，不自动打断用户焦点。用户对整个 tab/session/宿主的原生关闭仍按 Tern 规则，不承诺复活已结束进程。
7. 插件重载优先恢复可确认存活的实例，不仅凭旧 pane ID 关闭或接管程序；身份未知时提示并停止，不盲目重开，不自动重跑命令。来源关闭、命令退出和 pane 关闭是不同事件。保存的绑定必须能防止宿主重启／ID复用误认。程序文件后来消失不妨碍存活实例的聚焦、收起、恢复和结束。
8. 外部程序路径可配置：Git、lazygit、系统 realpath。显式路径存在且可执行则优先；未配置、失效或不可执行时允许回退本机 PATH；均不可用才停用对应功能。回退说明最终路径；错误说明本机、程序、配置位置及失败原因。路径是单个可执行文件，不是 shell 命令，空格和特殊字符不得注入额外命令。
9. 按功能依赖门控，不全局禁用插件：Git 支持现有 worktree 流程；realpath 只影响正常和危险移除；lazygit 缺失不影响 worktree／临时终端；lazygit 启动环境须能使用 Git。临时终端沿用 Tern 默认 shell，不另造第二套 shell 设置。命令面板隐藏不可用启动项，管理选择器隐藏缺依赖子动作；快捷键或直接调用仍保护、仅提示，不先创建终端再发现缺依赖。
10. 依赖检测与实际执行使用一致的已解析程序和环境，覆盖 runGit、runGitAt、removalRun、physicalPath 全部调用。available 回调只读取快速状态，不在 4ms 回调里做进程探测。重载后刷新，启动前重新验证；在异步探测期间来源变化时不能将动作错误重定向到新焦点。
11. 保持 worktree 安全不变量：关闭只操作所选安全环境；正常／危险移除仍检查本机身份、Git 登记、pending 操作、使用者（含 parked/floating）、fsmonitor 等既有保护。工具收起不能绕过工作树仍在使用的判断；不用改名或依赖抽取削弱原有保护。
12. 保留原 config.json 的 defaultPath、keybinding、manageKeybinding 语义与用户覆盖；新增快捷键可配置，默认键位如上。无自动安装、远程通路、全局键位改写或无关重构。

## 共享实现契约

- 配置由新 `lib/config.luau` 统一读取：保留原三字段，新增字符串 `lazygitKeybinding`、`terminalKeybinding`、`hideToolKeybinding`、`endToolKeybinding`，默认分别为 `ctrl+b>alt+g`、`ctrl+b>t`、`ctrl+b>q`、`ctrl+b>shift+q`；新增 `executables = { git = "", lazygit = "", realpath = "" }`。未提供字段采用默认，不要求改用户 config.json；未知字段和错误类型保持明确错误。
- 本机依赖解析模块 `lib/executables.luau` 提供小型 interface：`new(paths)` 得到实例；`ready(name)` 同步读取已知可用性；`check(cx, names, callback)` 异步验证并以 fresh cx 回调 `(cx, result, err)`，result 含 `paths`、`pathEnv` 和 `fallbacks`，不足的工具不得伪装成功；`refresh(cx)` 更新用于入口显示的状态。如真实 SDK 调查要求微调，先向集成负责人说明，不建立第二套解析器。
- 新工具在 `lib/tools.luau` 集中处理实例、布局和生命周期，通过 `register(config, executables)` 由 window.luau 接入；动作 ID 为 `open_terminal`、`open_lazygit`、`hide_tool`、`end_tool`、`restore_tools`。02先实现完整临时终端路径；03再接入真实 lazygit，不显示尚未实现的占位动作。
- 现有 Git helper 保留 flow、timeout、异步回调守卫和安全参数，不重新发明 worktree 流程。稳定 exported manager/removal/worktree 符号尽量不变；若必须变动先查引用。

## TDD 与验收接口

用户已确认：真实 Tern 命令／快捷键／原生界面为测试 seam；观察真实进程、cwd、pane 存活状态以及隔离 Git 仓库／文件／refs／登记。不 mock Tern/Git，不写文案、源码、argv转发或纯绑定接线测试。复用现有 Python + Luau 原生 harness；测试在隔离配置与仓库中运行，不操作用户日常会话。

每个实现 ticket 读取 tdd 技能，先写一个纵向失败场景并交主线程跑 red，再实现该行为，主线程跑 green；后续场景仍按纵向切片。子代理不跑测试、构建、lint 或 formatter，主线程负责每个完成切片的验证。命名文案无需永久测试，用实际插件加载和原生界面烟测，不做措辞锁定测试。

最终必须实际验证：路径优先／回退／均缺失与特殊字符；Git/realpath独立门控；临时终端不依赖Git；快捷键、同源复用／跨源隔离／工具间切换；收起运行任务及恢复同一实例；安全结束取消／确认；正常与失败退出；来源消失恢复；插件重载不重复；已运行程序文件消失后的恢复；以及已有完整 worktree 回归。观察实际原生界面截图；不运行浏览器自动化。Linux 运行证据若不可得必须明确，不能把 macOS 结果称为双平台实测。

## 任务图

- [01 本机程序解析与依赖门控](issues/01-local-dependencies.md)：无依赖。
- [02 临时终端与完整生命周期](issues/02-terminal-lifecycle.md)：依赖 01。
- [03 lazygit 与双工具切换](issues/03-lazygit.md)：依赖 02。
- [04 插件命名与使用文档](issues/04-branding-docs.md)：无依赖；文档按本规范明确配置和命令，最终集成校正。

01 和 04 文件边界独立，可在各自隔离 worktree 中并行；02、03有真实代码依赖，串行。每个实现分支须以集成分支为基线，报告前合并集成 tip；由专门合并代理串行集成。只有集成及相关验证通过后才 resolved，才领取依赖 ticket。

## 完成规则

所有 ticket 集成验收后，按基线执行 code-review 的 Standards 和 Spec 双轴并行审查，再做终止程序／路径风险安全审查；若有问题由单个实施代理集中修复，验证后关闭全部工作。所有 tickets resolved 后规范才能 resolved。记录提交和实际证据，清理本轮实施 worktree，保留用户工作区与配置，不推送。
