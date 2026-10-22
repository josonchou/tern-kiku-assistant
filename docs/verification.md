# 验证记录

日期：2026-10-21。

## 环境

- macOS arm64
- Tern 0.9.5 (2863c37)
- 系统 Git
- Python 3 仅用于驱动集成测试

## 当前管理功能验收

**完整验收已通过，01–04及 spec 均已解决。** 最终验收代码提交为 `964ec9c7e7b3af23eec691edead1e41fc9bf0f9c`，集成分支为 `integration/worktree-management`。

2026-10-21，在上述环境执行 `PYTHONDONTWRITEBYTECODE=1 python3 tests/integration.py`，完整83组通过，覆盖已有创建／基准分支、发现与复用、安全关闭、普通与危险移除、身份退化、Git 操作恢复保护及错误后重入。报告：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-kqycomoe/report.json`。

已查看该次 `shots/serve/` 中的 `base-picker.png`、`management-close-confirm.png`、`normal-removal-confirm.png`、`dangerous-removal-risk-preview.png` 和 `dangerous-removal-truncated-risk-preview.png`。本次通过不表示历史宿主50ms限制的根因已被解决；没有提高时限、自动重载或失败重试。

### 最终审查修复验证

- **Standards**：原1项P2已修复并经原审查者复核；拒绝等待改为可见错误 alert，不依赖完整提示文案，文件、refs、登记、tab／pane、安全状态及流程重入断言未削弱。
- **Spec**：原1项P2及其遗漏的创建入口已修复并经原审查者复核；管理时核对实际 root 与登记路径，创建后先确认目标本身仍是 Git 根，再发现或复用环境。合法嵌套目标和符号链接父目录仍可正常打开。
- **删除安全**：独立安全审查未发现达到报告门槛的缺陷。这不替代原生验证。

修复后的局部原生验证全部通过，报告均位于 `/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/` 下：

| 验证范围 | 通过组数 | 报告 |
| --- | ---: | --- |
| 创建后身份丢失与合法符号链接父目录 | 4 | `tern-kiku-test-gj86r63n/report.json` |
| 来源会话关闭后的完整路径披露及非 Git 错误恢复 | 4 | `tern-kiku-test-vymxs916/report.json` |
| 完整管理模块，含打开／复用／关闭及身份边界 | 15 | `tern-kiku-test-mr9jal09/report.json` |
| 完整普通移除模块 | 28 | `tern-kiku-test-7u51xxao/report.json` |
| 完整危险移除模块 | 19 | `tern-kiku-test-k_8libot/report.json` |
| 未完成 Git 操作及恢复状态保护 | 9 | `tern-kiku-test-5g0f82_n/report.json` |
| 真实 Git 部分删除失败及剩余现场保留 | 3 | `tern-kiku-test-rtgbxx9g/report.json` |

每次局部启动均包含2组初始化检查，不能相加为独立用例总数，也不替代完整回归。管理身份先在 `tern-kiku-test-1godi9a9` 取得真实 red：目标 `.git` 丢失后错误列出父环境；创建身份先在 `tern-kiku-test-dwo7d1gj` 取得真实 red：post-checkout hook 移除指针后错误聚焦父环境。两次日志均无50ms超限或插件错误。修正后，目标内容、登记、refs、环境身份及焦点保持断言通过，流程可以重新发起。

原生截图检查先发现 `tern-kiku-test-rkv7_60f` 的创建失败通知把长路径置前，原因和处理建议被截断。原因前置后，`tern-kiku-test-stv7g8p2` 的身份提示已可见，但集成到 `af57bce` 后的完整回归 `tern-kiku-test-hxn721cx` 通过16组即在既有完整路径断言失败：Tern 实际通知树没有保留换行后的路径；该次日志无50ms超限。

最终将原因中的 CR/LF 合并为空格，把原因与完整目标路径放在同一消息行，不依赖第二行展示；保留原有完整路径、HEAD 和流程重入断言，来源会话关闭及非 Git 目录也改用语义错误状态等待。`tern-kiku-test-vymxs916` 恢复了原路径披露契约，`tern-kiku-test-gj86r63n` 同时验证身份拒绝及合法符号链接创建。已查看两次截图：原因／处理建议可见，完整路径通过原生通知树断言；长路径仍可能视觉省略，不宣称截图首屏完整显示任意路径。Standards 与 Spec 原审查者均已只读复核此限定修复，无残余问题；没有新增交互或自动修复。

### 集成过程验证

- 02集成时，创建、发现/复用打开及安全关闭的完整原生回归通过30组。记录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-ytvddzqn/report.json`。已查看关闭确认和pane预览截图。
- 共享Git操作保护加入后，普通移除模块全部原生场景通过28组记录（含加载及原生helpers）：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-y0btow2_/report.json`。包括普通成功/取消、全部文件及索引风险、独立引用保护、确认期间变化、嵌套/失效/替换身份、fsmonitor、floating/parked/native path 使用者和真实Git读取错误后的数据保留与重入。这是模块整组通过，不替代创建/管理全流程回归。
- 此前一次完整运行 `PYTHONDONTWRITEBYTECODE=1 python3 tests/integration.py` 在旧创建流程通过12组后，被 `process exceeded 50 ms` 中断，尚未进入新增移除流程。证据：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-evmeqxnq/logs/tern-serve.log:10-11`。
- 04首个真实 red 精确命中尚缺的危险入口：筛选 `危险移除 worktree` 后picker为0行；该次日志没有宿主超限。证据目录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-0vgaryo2`。它不是功能通过记录。
- 共享Git操作保护加入后，04危险移除模块通过19组记录（含加载及原生helpers）：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-td1_dmuo/report.json`。覆盖tracked、独立ignored-only、独立无保护Detached、主动路径与外部确认、只读预览不授权、各级取消和错路径改正；200项纯untracked清单下，完整风险项可查看，未展示的新文件使旧授权失效；main/bare/locked/prunable、隐藏索引和最终pane/HEAD/symbolic-ref/路径替换/新增锁定保护均已实际执行。真实staged rename/copy的两条NUL路径都能完整预览，其他checkout与refs保持。长风险预览先在`tern-kiku-test-nriquast`获得真实red，再修正；已查看首屏截断声明截图。此前R/C夹具遍历不存在prunable路径的问题已修正，仍保留全部登记和路径状态断言。
- 真实Git部分失败烟测先失败再通过，并在当前实现上复验通过3组：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-9hdq8969/report.json`。不可变文件令单次 `--force` 失败，但其他文件及worktree登记已被删除；已查看原生截图，“目录或登记可能已部分移除，请手动核查”完整可见，refs、残留 `.git` 与保护文件均未被进一步清理。最初修正前后证据为`tern-kiku-test-vcpyl6wg`、`tern-kiku-test-o1mahflw`。此烟测使用自建临时文件并在finally清除不可变标志，没有把Git删除顺序或提示文案固化为永久测试。

普通回归过程中修正了测试驱动的确认项漏选和对提示空格的依赖。另一次等待误把 `ctl tree` 中的常驻 `Git  ⌥⌘G` 工具栏 tooltip 当成 Git 错误，导致夹具过早恢复索引；证据为 `tern-kiku-test-tnrhqphq`。最终审查后改为匹配 `role="alert"`、`toast`／`err` 类及非零可见矩形，同时要求 picker 已关闭；新操作先清除旧通知，等待新错误期间不执行会清掉通知的 Lua 查询。不再钉完整文案，仍验证索引字节、refs、登记与流程重入；没有修改生产保护来迎合测试。

另外用真实 `git merge --autostash --no-commit --no-ff` 构造已开始但尚未结束的同树合并：工作目录、索引、HEAD和普通refs均保持原审查值，未提交内容只存在于`MERGE_AUTOSTASH`。修正前原生流程仍删除了目标与恢复指针，证据目录 `tern-kiku-test-zwnbo0zh`。共享审查现验证目标private Git目录/backpointer，同时检查目录标记及目标自己的root refs；files/reftable后端的真实Git实验确认二者不能互相替代。新增原生回归通过9组记录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-wu2fp1g8/report.json`，覆盖两入口初审与末次拒绝、恢复内容保留、其他pending worktree不误阻止安全目标、合法relative backpointer以及普通`MERGE_HEAD`同名分支。相对metadata先在`tern-kiku-test-wsbchvj0`获得真实red；现按private Git目录解析相对路径，并用目录名/root-ref精确识别操作状态，避免`rev-parse MERGE_HEAD`误命中普通分支。根引用查询复用现有命令步骤，不在成功路径拼接整段refs输出作为错误提示。已查看拒绝截图，原因与“先保存内容，再手动完成或中止”的建议可见。

### 历史宿主阻塞的隔离证据

只加载真实Tern SDK、不加载业务模块且不启用trace的最小探针，对同一路径调用真实realpath：callback接口完成200次；awaitable接口在第174次提交边界触发同类50ms上限。证据：`/private/tmp/twm-process-probe-z0bbzteo/outcomes.json` 与其 `await/logs/tern-serve.log:525-530`。这些证据尚不能细分SDK原生调用、系统调度或临时日志的影响；不能把猜测写成根因。

没有放大hook时限、自动重载或失败重试，也没有停止用户应用。局部场景通过临时原生启动器执行，保留原有真实断言和finally清理，不修改永久回归的通过标准，不替代完整运行。

## 历史：创建与基准分支回归

创建与基准分支调整完成时，`python3 tests/integration.py` 全部通过20组检查，其中包含24条在Tern原生Luau运行时执行的辅助函数断言。以下是该历史阶段的记录，不代表当前管理功能的整套验收已通过。

1. 插件清单和入口加载成功，动作及默认快捷键注册成功。
2. 24 条 Luau 断言：Git NUL 分隔输出、含引号/换行/中文的路径、主工作树与 linked worktree 候选目录、配置路径、名称清理和 Git argv。
3. 实际快捷键启动，非法名称可重填；嵌套分支名成功创建；新标签页命名、聚焦和目录正确；原工作树修改及 .env 保留原处。
4. 从 linked worktree 创建，使用它独有的 HEAD 提交，候选目录符合规则。
5. 创建方式、名称、目录三个阶段取消，均不增加工作树或分支。
6. 已有本地分支创建后仍附着该分支。
7. 远程跟踪分支创建本地跟踪分支，upstream 正确，无 fetch。
8. Detached 工作树成功，未创建同名分支。
9. 已有目录冲突保留输入，重试到含空格、单引号和中文的路径成功；原目录文件未改动。
10. 同名分支冲突可改名重试。
11. 选择分支后被另一个工作树占用，执行前能检测并拒绝重复检出。
12. 从 linked worktree 发起时，配置相对目录仍以主仓库为基准。
13. Git checkout hook 延迟期间关闭来源 Tern 会话，成功创建的工作树被保留，并报告路径及标签页失败。
14. 非 Git 目录报错后能重新发起流程；未遗留流程锁。
15. config.json 改为 `ctrl+b>shift+h` 后，原生组合键可以触发命令。
16. keybinding 为空时回退到 `ctrl+b>shift+g`，原生组合键可以触发命令。
17. 已在其他 worktree 检出的本地分支可作为基准；存在同名 tag 时仍选择正确分支。选择后移动基准分支并触发路径冲突，重试创建的工作树仍使用已固定的提交。
18. 远程跟踪分支可作为新分支的基准，目标提交正确，不建立 upstream，也不额外创建远程分支同名的本地分支。
19. 新分支与 Detached 的基准选择阶段均可取消，Git refs 和工作树列表不变，随后可重新发起流程。
20. Detached 使用指定分支基准的提交，不创建同名分支。

实际检查了原生基准选择框和目录选择框截图。测试完全使用隔离配置与临时仓库；未在用户项目中创建测试分支或 worktree。

基准分支选择调整后的完整 20 组测试记录：
`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-9d6g0vo2/report.json`

该目录包含 `shots/`、`logs/`、`last-state.json`、`last-tree.json`，属于可清理的临时测试产物。

验证期间修正了测试驱动的分支选取方式：Tern 的 `picker.selected` 会拼接 label 与 detail，且名称子串可能命中其他分支；现在按行末完整 ref 选择，避免误选。修正后完整测试通过。

## 验证边界

没有宣称已验证 Linux、Windows、远程 SSH、iOS 或 web。未安装额外 Luau 静态分析器；入口及模块已由本机 Tern 加载执行，行为通过原生运行时和真实 Git 验证。

## Kiku 助手：依赖与命名阶段验收

`PYTHONDONTWRITEBYTECODE=1 python3 tests/integration.py --dependencies-only` 在 macOS / Tern 0.9.5 通过6组原生场景。证据：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-ud5i4urz/dependency-report.json`。

- PATH 不含 Git 时，含空格的显式程序路径仍能实际创建并登记正确 worktree。
- 显式路径失效可回退 PATH；插件加载／重载后，未调用命令也能完成依赖探测并显示入口。
- 缺 realpath 不禁用创建与打开，只隐藏移除选项。
- 配置路径含 shell 特殊字符时仍为单个可执行文件，不产生注入文件。
- Git 两种解析来源均失效时，快捷键明确拒绝且 pane、refs、登记不变；依赖恢复并重载后流程可再次使用。

测试夹具将显式程序目录与 PATH 目录分离，避免回退掩盖错误；macOS 系统 Git 启动器保留 `git` basename。重载入口曾实际保持不可用，现改为加载时直接启动非阻塞探测，不依赖只触发一次的 `window_start`。

已观察真实命令面板的“Kiku 助手”分组：`/tmp/kas-eHG7Dx/shots/serve/kiku-assistant-palette-ready.png`。这仅为依赖与命名阶段证据，不替代后续快捷工具生命周期与完整 worktree 回归。

### 依赖集成后的完整 worktree 回归

2026-10-21，在 macOS / Tern 0.9.5 上，以禁写字节码及独立 `pycache_prefix` 运行 `tests/integration.py`，完整通过83组原生场景。证据目录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-ne_dq4zz/`。覆盖创建、跨会话管理、安全关闭、正常／危险移除、确认期间变更、fsmonitor、未完成 Git 操作与全部既有保护；不代表快捷工具或 Linux 已验收。

此前正常移除未出现确认框，原生错误通知捕获于 `tern-kiku-test-zbkg02t2/observed-error-303.json`；实际原因是 `removeWorktree` 仍引用已移除的 `activePrograms` 全局。现使用该流程的 `flow.programs.paths.realpath`，与审查和执行使用同一依赖快照。管理快捷键夹具在重载后先等待真实依赖就绪，再区分未绑定快捷键与暂时不可用状态，没有取消安全断言或放宽超时。

### 快捷工具安全模式的决定依据

`tern-kiku-test-z6g4pw39` 的真实回归证明：恢复扫描将仅展示旧工具 prefix 文本的普通终端误认成工具。后续只读审查确认，数字 PID／精确握手文本仍不能证明候选 pane 与旧进程的绑定。用户明确取消本轮跨重载自动接管，改为旧实例及代次未知的失败卡片交由 Tern 原生管理；此处记录授权边界，不宣称安全模式代码已经验收。

在 `serve`／无 daemon 的来源关闭探针中，Carly `cx.layout:close` 和原生 `Cmd+W` 都未发出所期待的 `pane_closed` 通知；真实来源 shell 执行 `exit 0` 则会产生事件。证据分别为 `tern-kiku-test-f_ni9nzw`、`tern-kiku-test-7idjkmqa` 与 `tern-kiku-test-oj0hrj7w`。这不代表正常 GUI 的全部事件行为；不能只用 `exit 0` 替代原生关闭验收，也不能跳过进程身份验证来收起工具。

安全模式候选的6组原生场景已通过 `tern-kiku-test-_td7qtk_`；原生停放恢复另见 `tern-kiku-test-dbvpp867/native-parked-fallback.json`：重载后旧pane6仍收起、任务PID26803存活，经原生卡片恢复后pane/PID/cwd保持。已查看 `tern-kiku-test-z3pabwwn/shots/serve/native-hand-expanded.png` 的展开卡片。这些记录不替代来源消失观察器与lazygit的最终验收。

随后在独立正常 GUI＋私有 daemon 中，原生 `Cmd+W` 关闭来源后，观察器已将工具 pane9 收起，真实前台任务 PID71910 仍存活。证据：`/tmp/kigu-rwhugdp9/native-close-evidence.json`。同版本 `serve` 的定时回调只在启动阶段触发，不能作为该观察器的验收环境；完整工具生命周期改用独立原生 GUI。GUI 必须处于解锁桌面，锁屏会阻塞渲染相关回调。

Tern 0.9.5 的 daemon 模式另有独立限制：已解锁的全新私有实例中，普通非插件终端 `exit 7` 后，Enter 与官方 `restart` 动作均未启动新 shell，见 `/private/tmp/kign-rcz6p9xf/failure-state.json`。因此 Restart 的进程代次防护保留为独立真实 `serve` 回归，其他生命周期用 GUI 验证；`--tools-only` 必须执行两者，不删除或放宽 Restart 断言。

### 临时终端阶段验收

提交 `5fc44a828bb3396718a85cb969be84d8240e9f85` 已集成。macOS / Tern 0.9.5 共通过11组工具场景：

- `tern-kiku-test-onvqrfq8`：正常 GUI＋私有 daemon 的9组生命周期场景，包含真实前台任务保活、同源复用／跨源隔离、结束取消与确认、来源退出、原生 Cmd+W、独立恢复保持、旧记录清理边界、重载后标记及跨会话未知实例拒绝。
- `tern-kiku-test-64b9nach`：独立 `serve` 的1组 Restart 代次回归；原生重启后的新 shell 不会被旧工具记录打开、收起或结束。
- `tern-kiku-test-i26qo4z8`：正常 GUI 的1组非本机上下文拒绝；使用 Tern 自带 loopback 宿主，不连接真实 SSH 主机。

上述目录均位于 `/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/`。已查看此前同路径通过场景的原生浮窗图 `tern-kiku-test-xxxnmqib/target/shots/tern/live/scratch-terminal-restored.png`。本阶段不宣称 lazygit、真实远端或 Linux 已验收。

### 集成回归的预算复核

当前无插桩分支的完整回归在 `tern-kiku-test-c9sv1jtm` 首次普通移除确认前被宿主 `process exceeded 50 ms` 中断；实际日志位于 `logs/tern-serve.log:15-16`。没有据此修改既有移除保护。

仅在隔离诊断 checkout 增加同步边界日志后，`tern-kiku-test-19s5mzlu` 全83组通过，耗时246.24秒。`budget-summary.json` 中，7782次 `physicalPath` 回调的最大同步耗时为22.004 ms，其中提交本机进程的最大耗时为20.872 ms；`manager.visiblePanes` 最大7.996 ms。该次测量没有重现超限，不能据此认定先前中断的具体根因；日志本身也有测量扰动。诊断代码不合入，未放宽预算、添加自动重载／重试或减少断言；最终无插桩集成回归仍须单独记录。

### lazygit 原生夹具与通知边界

正常 GUI 的私有 daemon 环境不会把任意 `CONFIG_DIR` 传入默认 shell；SDK `process.run` 则会继承该变量及 `PATH`。证据：`/private/tmp/kas-_98ebh4f/lazy-native-env-va89q1v8/evidence.json` 与 `lazy-sdk-env-7ojk1z12/evidence.json`。因此 lazygit 夹具通过透明 wrapper 执行真实程序，并显式传入私有 `--use-config-dir`；包括缺 Git 场景中的可用 lazygit。仅给宿主设置环境变量不构成配置隔离证据。

lazygit 的真实 `--version` 探测也会调用 Git，不能把第一条 Git 日志当作 TUI 使用了指定 Git；实际启动证据须匹配本次执行桥、真实父进程与私有仓库状态。macOS `/usr/bin/git` 启动器另依赖 `git` basename；将其软链命名为 `configured git` 会实际返回72，不能把该夹具算作“Git 可用”。

依赖错误的原生 `tree`、`tree .toast` 和 `a11y` 均在120字符处截断通知正文，证据为 `/private/tmp/kas-_98ebh4f/lazy-toast-xkmucv7d/evidence.json`。程序、配置键与关键原因须放在长路径之前；不能承诺任意长路径完整进入通知树，也不使用整句提示文案作为安全结果的验收依据。

`tern-kiku-test-dh56wuef` 已通过真实 lazygit 界面、指定 Git、同源双工具切换／正常退出、跨来源隔离、PATH 回退及非 Git 拒绝的5组场景；`tern-kiku-test-66v00pns` 另通过缺 Git 的独立门控。后续生命周期与最终整分支验收仍须单独记录，这些结果不替代它们。

现有 worktree 入口也修复了同类提示缺项：非空的 `errors.git` 原先遮蔽了含 `executables.git` 的备用提示。临时原生探针在 `tern-kiku-test-q6jo_yxu` 实际失败；改为先显示依赖摘要再附具体原因后，`tern-kiku-test-7nodb7bz` 通过配置位置、PATH 和零新增 pane 断言。没有增加永久措辞锁定测试。

### lazygit 阶段验收

提交 `e5f908a27dbf22675c8f34388c7716444efa9593` 已集成。macOS / Tern 0.9.5 / lazygit 0.65.1 共通过12组真实场景：

- `tern-kiku-test-qhi4qcky`：正常 GUI 的9组场景，包括含空格与 shell 特殊字符的程序路径、实际 Git 执行桥、双工具切换、跨源隔离、路径回退、非 Git 拒绝、双工具来源关闭后独立恢复且不抢焦点、失败卡片、重载后旧 lazygit／执行桥保持，以及配置程序文件消失后的同进程收起、恢复、结束。
- `tern-kiku-test-u24es6ey`：独立 `serve` 的 Restart 场景。此前 `tern-kiku-test-nxuo6k9t` 证明，拒绝操作未知同源实例前仍创建了一个新终端；现改为创建前预检，实际收起前仍重新核验，最终拒绝不新增 pane、不触碰重启后的代次。
- `tern-kiku-test-b4shmxg2` 与 `tern-kiku-test-e0_zsvj1`：分别缺 Git、缺 lazygit；只报告实际缺失项，不创建工具 pane。

已读取原生截图 `tern-kiku-test-751_5vlf/target/shots/tern/live/lazygit-real-tui.png`：右下角是真实 lazygit，包含隔离仓库的文件列表与未提交差异。上述结果不替代集成后的临时终端／完整 worktree 回归，也不代表 Linux 已验收。

### 集成后的完整验收（固定基线审查前）

在 `e5f908a` 加工作区依赖提示修正的实际代码上，无诊断插桩运行完成：

| 范围 | 通过组数 | 证据目录 |
| --- | ---: | --- |
| 临时终端 Restart | 1 | `tern-kiku-test-hb0phwp2` |
| 临时终端 GUI 与非本机拒绝 | 10 | `tern-kiku-test-8wdgg_vi` |
| 外部程序独立解析与门控 | 6 | `tern-kiku-test-5l5rik_b` |
| 完整 worktree 创建、管理、正常／危险移除 | 83 | `tern-kiku-test-b6snyubr` |

结合上一节的12组 lazygit 场景，共112组通过。最后两组命令的串行总耗时248.32秒；本次完整 worktree 运行没有重现此前50ms预算中断，不据此声称已定位或修复宿主预算问题。固定基线审查及其修正仍须单独完成。

已另外查看 `tern-kiku-test-qhi4qcky/target/shots/tern/live/lazygit-failure-retained.png`：失败的原生卡片、Restart／Close 控件以及原先 lazygit 输出均保留可查看。

### 固定基线审查与最终修正

固定基线为 `4f63305a76ebd4f0831a54837cd4a7b7ed620eef`，首次审查 HEAD 为 `b2229e0`；修正以 `04ce13004a4920b993fc727345e3bbf0a65a6f8e` 集成：

- **Standards**：首次与增量复查均为0项。
- **Spec**：两项 P2 已修正。非 Git 目录不再被插件预拒绝，仓库交互交给真实 lazygit；配置读取错误传递至两个新工具入口，拒绝新建但不阻断已确认实例的管理。
- **Security**：一项 P2 已静态复核修正。双工具切换改为先验证目标、再验证上一实例，在同一回调同步复核并立即收起上一实例，之后重新验证目标才显示；收起授权不再跨越另一次异步验证。精确竞态间隙未动态复现，真实切换、Restart、失败卡片场景不能冒充该精确时序的回归证明。

上文历史记录中的“非 Git 拒绝”是此次发现的规格偏差，不是最终验收行为。真实 red `tern-kiku-test-fbfgxcy8` 未能启动程序；修正后的原生截图 `tern-kiku-test-9nm8nid7/target/shots/tern/live/lazygit-non-git.png` 已由主线程查看：真实程序在来源目录询问是否创建 Git 仓库（y/N），插件没有自动初始化。完整与独立入口的最终通过证据见下表。

配置错误的 red `tern-kiku-test-o5sefiji` 也有实际副作用证据：启动前只有 pane4294967298／7300，失败状态却聚焦新增 pane4294967302，且已执行工具身份初始化。测试最初通过 Carly 调用动作，其关闭会清除新守卫的同步错误提示；最终改为真实原生快捷键，不给生产提示添加延时或截断。

增量复查另发现非 Git 共用测试误把累计日志当作本次启动，并在 PATH 回退后仍期待失效的配置路径。`tern-kiku-test-3p9o_pw3` 实际暴露了4条累计启动记录；改为记录启动前基线、仅验证新增记录及该场景应使用的 wrapper，保留后续生命周期断言。复查后 Standards、Spec 均为0项，安全复查无新增问题。

| 最终验证范围 | 通过情况 | 证据目录 |
| --- | --- | --- |
| 外部程序解析与独立门控 | 6组 | `tern-kiku-test-fo7hqi9m` |
| 完整 worktree 创建、管理、正常／危险移除 | 83组 | `tern-kiku-test-38z4p3s0` |
| 临时终端、Restart、来源关闭与非本机拒绝 | 11组 | `tern-kiku-test-rid2bfbb`、`tern-kiku-test-ygdi08qj` |
| lazygit 完整 GUI、Restart、独立缺 Git／缺 lazygit | 12组 | `tern-kiku-test-l2fd92c1`、`tern-kiku-test-3iusn2bb`、`tern-kiku-test-enxvqamk`、`tern-kiku-test-osjgn8_k` |
| 未知字段／错误类型 × 两个新工具入口 | 4种组合 | `tern-kiku-test-x_o5rlyy` |
| 独立非 Git 入口 | 1组，与完整 lazygit 场景共用行为验证 | `tern-kiku-test-2gtgsrjq` |

上述最终工具候选与 `04ce130` 中对应文件已逐字节核对一致。终端批次耗时160.96秒；最终完整 lazygit 与独立非 Git 批次耗时148.01秒。所有结果均来自 macOS 的真实 Tern／进程，不代表 Linux 或真实远程主机已验收。

依赖与完整 worktree 在集成分支 `04ce130` 上串行通过，合计239.14秒，没有诊断插桩。结合工具场景，共112组核心回归及额外4种配置错误组合通过；独立非 Git 入口不重复计入核心组数。本次未重现此前宿主50ms预算中断，不据此声称已定位其根因。

已另行查看最终 `tern-kiku-test-l2fd92c1/target/shots/tern/live/` 下的 `lazygit-real-tui.png` 和 `lazygit-failure-retained.png`：真实仓库差异、右下角浮窗、失败卡片及原生 Restart／Close 控件均实际可见。

规范及01–04任务均已关闭。本轮8个独立实施 clone、1个临时 linked worktree 已清理，另5个历史 checkout 此前已不存在；保留原生测试产物与日志。用户 `.gitignore` 的暂存状态、`config.json` 和忽略的 `TODO.md` 均保持原样；未推送、未创建 PR、未实际重命名本地目录或远端仓库。

## 快捷工具布局与固定归属复用（2026-10-21，仅代码级验收）

用户在完成设计访谈后授权实施，随后明确选择“静态检查加隔离逻辑测试”，不做新版真机验收。本节取代旧记录对当前工具布局／复用行为的描述，但不改写历史112组原生回归的事实；历史结果不能证明这次改造通过原生验收。

### 实现与验证范围

- lazygit 右侧普通 block，临时终端右下角原生 PiP；固定创建 tab／启动目录／类型去重，重复打开恢复默认形态，不重启程序；仅临时终端保留 park／结束／恢复入口。
- 执行实际 `lib/tools.luau`、`lib/tool_identity.luau` 和 `lib/lazygit_launch.luau`，替身只提供 Tern SDK 的布局、事件、进程采样、文件及选择器边界；没有把生产身份函数改成恒真。split tree、PiP owner/corner、采样代次、异步回调及定时器在边界内可观察、可推进。
- 官方 Luau `0.743` 工具包只放在临时目录，没有全局安装或改项目工具链。新增公开运行入口：`python3 tests/code_validation.py --luau /path/to/luau`，可用 `--case` 单独选择场景。

| 验证 | 实际结果 |
| --- | --- |
| 工具代码级场景 | 26场景、116条断言全部通过 |
| 原有工作树／路径／移除纯逻辑 | 48条断言通过；未运行 Git／Tern 集成 |
| `window.luau`、全部 `lib/*.luau`、Luau 夹具与场景编译 | 通过 |
| 独立 `luau-analyze` | 0错误；1条原有 `tool_identity.luau:25` 的 `TableOperations` 类型推断告警（经相对／绝对路径重复显示） |
| `tests/code_validation.py`、`tests/tools.py`、`tests/lazygit.py` Python语法 | 通过 |
| 公开命令烟测（SDK边界替身） | 创建终端 → 停放 → 打开 lazygit → 恢复同一终端；观察到终端身份保持、lazygit仍为tiled、PiP为`br`且承载者为lazygit |
| 规格与安全只读审查 | 所有可行动项已修正并复核，无未解决阻断项 |

独立分析器使用其默认非严格模式，Tern 原生模块仍有动态类型；该结果不等同于完整 SDK 严格类型检查。实际布局／进程方法签名已与本机 Tern `0.9.5 (2863c37)` 导出声明逐项对照。没有添加类型忽略来清除原有告警。

### 关键先红后绿证据

- 未改实现的“同 tab、同启动目录、不同来源窗格”场景实际产生两个工具，断言 `2 != 1`；改造后复用同一 pane。
- 异步身份核验期间来源目录变化，旧候选实现仍抢回工具焦点；新增场景失败 `31 != 1` 后补齐上下文重核。
- 工具 Restart 后从新目录再发起打开，候选实现创建第二个工具；新增场景失败 `2 != 1` 后补齐来源身份门禁。
- 确认结束的最后父进程查询等待期间发生 Restart，原检查顺序关闭了新代次；回归失败 `false != true` 后改成父进程先验、子代次最后核验。
- token 准备等待期间来源 Restart，候选实现继续创建；回归失败 `2 != 1` 后在最后准备完成处重新核验来源。
- 复用目标工具等待期间来源 Restart，候选实现切换焦点到目标；回归失败 `32 != 31` 后增加来源／目标的联合最终采样，同时拒绝截断库存。
- 创建抛异常且未观察到 pane 时，候选实现释放占位，后续请求重新创建；回归失败 `1 != 0` 后区分正常 `nil` 与异常无候选。此为代码契约回归，不是实证的 Tern 晚到 pane 缺陷。

完整场景还覆盖目录／类型／tab隔离、固定归属、工具内部当前目录继承、跨tab找回、单键并发、防止重置cwd、source关闭不park、原tab消失后的恢复及冲突取消、明确失败释放、候选关闭后定时观察释放、默认右侧／`br`布局与无关分屏保持。

### 证据与限制

- 结果与最终代码指纹：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-code-proof-2n9p5j3f/`，包含 `validation_summary.json`、各命令结果、`existing_helpers_result.json`、`tool_smoke.json` 和 `metadata.json`。临时执行脚本已删除，保留证据 JSON。
- `tests/tools.py`、`tests/lazygit.py` 已同步新契约，并保留真实 PID、cwd、lazygit TUI／Git bridge、Restart、重载及普通 pane 不可认领的原生断言。静态审查发现的缺失导入、非 ASCII 路径转义、过期 pane 快照及 reveal 参数已修正。
- 用户选择代码验证后，没有启动真实 Tern GUI／serve／daemon，也没有运行原生套件、浏览器自动化或 Linux 验收。此前官方 PiP 的隔离调查见设计文档，只证明旧版宿主能力。
- 真实布局、焦点、shell 握手、进程采样时序和原生关闭／Restart仍待后续实机验收；代码边界替身不能代替这些证据。SDK进程采样也不构成原子OS身份保证。
- 用户配置与既有 worktree 运行代码未改；未提交、未推送。

## OMP／Git 等 block 来源修复（2026-10-22，仅代码级验证）

用户报告激活 OMP 或 Git 等 block 时两类工具均拒绝，截图为“无法确定本机终端来源及其工作目录”。根因是 `ownerFor` 将**来源**也限制为 `terminal`，即使有有效目录仍提前拒绝。

- 去除来源 kind 门禁，继续要求可靠绝对 `PaneInfo.cwd`、本机及有效标签页；缺失目录不将 file/root `path` 或 tab cwd 猜作兜底。
- `liveTool`、`managedNow` 与身份模块仍只管理已验证的 terminal 工具；来源 block 不会变为受管工具。固定归属键、single-flight、联合进程采样及异步上下文复核未变。
- 新增来源回归先红后绿：修复前 agent 来源实际创建 0 个工具，预期 1，断言 `0 != 1`；修复后从 agent／Git 启动、交叉复用及 Git 来源 park／restore 通过。其余新增场景覆盖空／缺失 cwd 即使有 path 仍拒绝、非本机拒绝、原生来源异步变更 cwd 时中止并允许重新发起。

| 检查 | 实际结果 |
| --- | --- |
| `python3 tests/code_validation.py --luau <官方 Luau 0.743>` | 30 个场景、151 条断言通过 |
| 生产公开命令的 SDK 边界烟测 | agent／Git 目录正确；同一 scratch 被复用及恢复；普通 Git block 上管理动作保留两个工具；未向 agent／Git 来源注入命令 |
| Luau 编译 | window、lib、helper、fixture 和场景脚本通过 |
| Luau 静态分析 | 0 错误；保留 `tool_identity.luau:25` 的 1 条原有 `TableOperations` 告警，同一文件以两个路径显示 |
| Python 语法 | 修改后的代码验证 runner 通过 |

只读审查未发现本轮可行动缺陷。证据与最终执行代码指纹：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-block-source-proof-ps4xv8yk/`，包含 `validation_summary.json`、分项命令结果、`public_command_smoke.json` 和 `metadata.json`；临时烟测执行脚本已删除。

继续遵循用户选择：未启动 Tern GUI／serve／daemon，未运行原生或浏览器测试，没有重载用户插件。SDK 边界替身不证明真实 block 的 cwd 报告、原生布局、焦点或进程时序；旧版真机证据也不作为本轮新版验收。用户配置及其他 worktree 行为未改，未提交、未推送。

## 工具终端静默启动（2026-10-22，代码级 + 一次获准的隔离原生验证）

用户截图确认旧实现把 `/bin/sh -c 'printf "KIKU_TOOL_V1:…" "$PPID"'` 及标记输出留在新终端里。根因是 `cx:run` 的公开语义就是“像键入一样”写入 PTY，身份采集只能移到进程启动阶段。

### 修复

- `lib/tool_identity.luau`：新增 `launch(token, cwd)` 与 `spawn(spec)`。前者为每次启动创建 `<plugin data>/tool-start/<标记>/request.json`；后者在宿主 `spawn` 钩子中只认这个私有目录，把 `cwd` 还原为真实目录，并用一次性初始 shell 在 `exec` 原 `program`／`args` 前静默写入 `$$`。删除旧的 `command` 输出与 `cx:run` 注入。
- `host.luau` + `plugin.toml`：注册宿主半部。非本插件启动的 pane 原样返回；插件块不经过该钩子。
- `lib/tools.luau`：创建时以私有启动目录作为 `split` 的 `cwd`；等待 prompt 后从 `pid` 文件取身份，不再检查或输入终端内容；创建失败或异常路径删除该标记目录。`liveTool`／`managedNow`／身份核验链保持 terminal-only 与进程代次检查。
- 默认 shell 不受支持时写 `error` 并以 125 退出，窗口显示原因；不降级成无身份工具。

### 隔离原生验证（zsh，真实 Tern 0.9.5）

使用私有 `TERN_CONFIG_DIR`、私有 daemon、独立控制 socket 与临时目录，链接本工作区的插件副本；未连接或重载用户日常 Tern。

| 观察 | 实际结果 |
| --- | --- |
| 工具窗格 | `kind = terminal`、`program = zsh`、`floating = true`、到达真实 prompt |
| 启动目录 | 等于来源目录 |
| 回滚内容 | 只有提示行；无 `KIKU_TOOL`，也无 `/bin/sh -c` 握手 |
| 进程身份 | `tool-start/<标记>/pid` 的 PID 为存活 zsh，父进程是本次私有 daemon |
| 收起／恢复 | `q` 后 `parked = true`；恢复后同一 pane 回到浮动、聚焦，输出仍无握手 |
| 结束 | 确认后 pane 关闭，该标记的 `tools/<标记>.json` 与 `tool-start/<标记>/` 一并删除 |

进程身份取自 `ps -p <pid> -o pid=,ppid=,comm=`：`comm = /bin/zsh`，父进程 PID 等于本次私有 daemon（`pid_is_daemon_child = true`），不是滚动区文本推断。

跨 `reload_plugins` 之前创建的工具，其记录与启动目录按安全模式保留、不自动认领；本轮用插件自身的结束动作验证清理，未把重载前的旧实例算作清理失败。

### 代码级与真实 shell 验证

| 检查 | 实际结果 |
| --- | --- |
| `python3 tests/code_validation.py --luau <Luau 0.743>` | 32 个场景、165 条断言通过；新增“静默记录身份且不键入任何内容”和“默认 shell 不支持时不接管” |
| `python3 tests/startup_code.py <luau>` | 用生产过滤器生成的真实命令行在 zsh、bash、sh、dash、ksh 中静默退出码 0、无 stdout/stderr、PID 与最终 shell 一致、原参数原样传递；重跑同一规格不覆盖首代次 PID。fish 未安装，未验证 |
| Luau 编译 | `window.luau`、`host.luau`、lib、fixture 与场景脚本通过 |
| Luau 静态分析 | 0 错误；仅剩 `tool_identity.luau` 那条原有 `TableOperations` 告警 |
| Python 语法 | `code_validation.py`、`startup_code.py`、`tools.py` 通过 |

`tests/tools.py` 的原生契约已同步：工具到达 prompt 后在清屏前断言回滚区没有内部标记或握手；旧“回滚区标记认领”探针改用私有记录中的标记，仍验证普通 pane 打印同样文本不能被采纳。

### 证据与限制

- 证据目录：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-quiet-start-proof-4db6z39a/`：`native_spawn_probe.json`（钩子收到的启动规格）、`native_exec_probe.json`（早期裸执行探针）、`native_red_before.json`（修复前可见标记）、`native_silent_tool_verification.json`（工具 pane、回滚区、pid 与 `ps` 父子关系）、`native_silent_tool_lifecycle.json`（收起／恢复／结束与清理）、`startup_code.json`、`final_summary.json`、`metadata.json`（文件指纹）。隔离原生实例与私有 daemon 均已关闭，临时目录未清理以供复核。
- 修复前同一驱动在真实插件上读到可见 `KIKU_TOOL_V1` 已完成命令；修复后同一路径无该内容。
- 本机默认 shell 为 zsh，原生只验证 zsh。bash／fish 的 Tern 集成参数是在钩子前后由宿主添加，其顺序公开资料未说明；bash 的 `--posix` 与 `ENV` 由 bootstrap 依据钩子可见环境补齐，属于代码级验证，未做原生确认；fish 无安装，完全未验证。
- 宿主半部是该机制的前提；缺失时工具身份无法确认，插件安全拒绝而不是无身份启动。SDK 进程采样仍不是原子 OS 身份操作。
- 未提交、未推送；用户配置与其他 worktree 行为未改。

## 依赖解析回退登录 PATH（2026-10-22）

用户截图报告打开 lazygit 提示“executables.lazygit 与本机 PATH 均不可用”。本机 lazygit 只存在于 `/opt/homebrew/bin/lazygit`，而依赖探测读取的是宿主进程 `PATH`；Finder／daemon 启动的 Tern 不继承 shell 配置里的 Homebrew 目录，`/usr/bin/git` 仍存在，因此只有 lazygit 被判缺失。

### 修复

- `lib/executables.luau`：解析顺序仍为显式 `executables.<name>` → 进程 `PATH`；仍未命中时用本机登录 shell 执行一次 `printf` 读取用户 `PATH`（`$SHELL -l -c`，缺失或非绝对路径时按平台取 `/bin/zsh`／`/bin/sh`），只重试缺失项并按插件 VM 缓存。
- 回退成功时启动环境使用“登录 PATH + 进程 PATH”（登录目录在前），显式配置与显式路径的优先／回退提示不变；登录 shell 不可用或输出异常时沿用原缺失提示。缺失的 `executables` 配置项按空处理。

### 验证

| 检查 | 实际结果 |
| --- | --- |
| 最小 PATH 的真实 Tern（隔离实例） | 私有 daemon 以 `PATH=/usr/bin:/bin:/usr/sbin:/sbin` 启动：`command -v lazygit` 为空，登录 shell 解析到 `/opt/homebrew/bin/lazygit`；插件成功打开 lazygit，pane 运行 `exec /usr/bin/env PATH='<私有 git 目录>:<登录 PATH>:<进程 PATH>' /opt/homebrew/bin/lazygit`，无错误提示 |
| 代码级场景 | 34 场景、177 断言通过；新增“进程 PATH 缺失、登录 PATH 命中时使用登录目录并只探测一次”和“两处都缺失仍报错” |
| 编译／分析／Python 语法 | 通过；仅剩 `tool_identity.luau` 那条原有告警 |

证据：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-quiet-start-proof-4db6z39a/native_lazygit_login_path.json`、`final_summary_with_login_path.json`。隔离实例已关闭，未连接或重载用户日常 Tern；未提交、未推送。

## PiP glance 下临时终端快捷键失效（2026-10-22）

用户截图报告：打开的临时终端浮层停留一段时间后，`Ctrl+B → q` 与 `Ctrl+B → Shift+Q` 失效，报“工具身份未确认／未识别当前窗格：未执行结束操作”。

### 根因

隔离原生实例（私有配置、daemon、控制 socket 与临时目录）复现了同一状态：pane 仍存活、身份记录仍在、进程代次未变，变化的是焦点。

- 工具刚打开时 PiP 为 `mode = focus`，`cx.session:focused()` 即工具 pane。
- 窗口失焦或点击底层 pane 后，Tern 把同一 PiP 降为 `mode = glance`（缩小、倾斜），并把聚焦交回 owner pane。
- 旧实现只按 `byPane[cx.session:focused()]` 取 leader 目标，因此 glance 状态下必然查不到工具，直接命中“未识别当前窗格”的拒绝分支。

原生观测（修复前，`/private/tmp/kiku-glance-c1mvlm8s/evidence.json`）：`mode` 由 `focus` 变 `glance`、`focused` 回到 `4294967300`；随后 `Ctrl+B q` 出现 error toast（`role=alert`、`class` 含 `toast err`），`parked = false`，pane 仍在。

### 修复

`lib/tools.luau` 新增 `leaderTool(cx)`：

1. 先按聚焦 pane 命中（原有行为不变）。
2. 未命中时，在当前 host／session 内枚举本插件登记、且 `floating`、`tab` 等于当前标签页、未 `parked`、未 `exited` 的临时终端。
3. 唯一候选作为 `q`／`Shift+Q` 的目标；多个候选不猜测，提示先点击目标浮层；零候选或聚焦 pane 无 tab 时保留原拒绝提示。

身份校验、`park` 保活、`Shift+Q` 二次确认、异步上下文核对均未放宽。

### 验证

| 检查 | 实际结果 |
| --- | --- |
| 原生修复前（红） | glance 后 `Ctrl+B q` 出现 error toast，`parked = false`；随后 `restore_tools` 无 picker（从未停放） |
| 原生修复后（绿） | glance 后 `Ctrl+B q` 无 error toast 且 `parked = true`；`restore_tools` 恢复 `floating = true` 并聚焦；再次 glance 后 `Ctrl+B Shift+Q` 弹出“取消／结束此临时终端”确认，选结束后 pane 消失 |
| 代码级场景 | 37 场景、193 断言通过；新增 `glance_pip_keeps_leader_actions`、`glance_ambiguous_pip_refuses_to_guess`、`glance_other_tab_keeps_pip`（先红后绿已核对） |
| 原生工具套件 | 11 组 PASS，含 hide／restore、确认结束、来源关闭与跨 tab 恢复，无回归 |

证据：`/private/tmp/kiku-glance-c1mvlm8s/`（修复前）、`/private/tmp/kiku-glance-p7uqn50b/`、`/private/tmp/kiku-glance-w9656_5y/`（修复后，含 `evidence.json`）、`/private/tmp/kiku-stale-sp231thk/evidence.json`（空闲 40 秒后自动掉为 glance 的时间线）。隔离实例与私有 daemon 均已关闭，未连接或重载用户日常 Tern；未提交、未推送。

## 创建即浮动：工具不再先以分屏出现（2026-10-22）

用户询问“打开临时终端是否必须先开一个 panel 再转成 PiP”。核查后的结论是：Tern 0.9.5 没有“直接创建终端 PiP”的入口，`Launch` 只有 `cwd`／`command`／`block`／`args`，`LayoutCx` 只提供 `new_tab`／`split` 创建 pane，`float(pane, over, corner)` 仅转换已有 pane；内置命令只有 `new_browser_pip` 能从零创建 PiP，终端只有 `pip`（弹出聚焦的 split pane）。因此保留“先 split 再 float”，但把 `float` 提前到身份握手之前。

### 修复

`lib/tools.luau` 的 `create()` 在 `split` 成功后立即 `cx.layout:float(pane, owner.anchor, "br", { focus = false })`：

- 焦点保持在来源 pane，因为 `handshake`／`requestValid` 全程要求 `cx.session:focused() == request.pane`；
- 失败时提示“工具已创建但未能浮动”，继续握手，`presentTool` 会再次尝试；
- 握手完成后 `displayTool` 仍按原逻辑 `float` 并显式 `focus`，重复 `float` 已验证为幂等。

### 验证

| 检查 | 实际结果 |
| --- | --- |
| SDK 语义探针（隔离 GUI，私有窗口） | `split` 后立即 `float(source, "br", { focus = false })` 返回 `ok = true`，PiP 出现且 `mode = glance`，`focused` 仍为来源 pane；再次 `float(..., { focus = true })` 不产生重复 PiP，也不改变焦点；显式 `cx.layout:focus(pane)` 后 `mode = focus` |
| 暴露时间线对照（~40 ms 采样 + Carly 触发） | 修复前：9 个“仅分屏、无 PiP”采样，跨度 316 ms，首个 PiP 在 358 ms 后出现；修复后：0 个该采样，PiP 直接出现（先 `glance`，握手后 `focus`） |
| 真实插件端到端（隔离 GUI） | 打开工具后 `pips` 立即出现，最终 `pips[0].mode = focus`、`focused` 等于工具 pane、`panes` 保持 2 |
| 代码级场景 | 38 场景、204 断言通过；新增 `creation_floats_before_identity_handshake`（创建阶段 `floating` 已为真、`focused` 仍是来源、记录未验证，flush 后 PiP 保持且取得焦点） |

限制：`tests/integration.py --tools-only` 在本机未能完成，首次创建时 Tern 禁用插件 `process` hook（`plugin hook exceeded its budget`／`tern: process exceeded 50 ms`），随后不再执行插件命令。临时移除本次改动后运行同一场景得到相同的超时与空 `pips`，确认该阻塞与本次改动无关，属于既有的宿主预算问题；原生结论以上述隔离 GUI 探针与代码级场景为准。

证据：`/tmp/pip_probe_observations.json`（SDK 语义）、`/tmp/kiku_exposure_red.json` 与 `/tmp/kiku_exposure_green.json`（暴露时间线）、`/tmp/kiku_float_probe.json`（真实插件端到端）。隔离实例与私有 daemon 均已关闭，未连接或重载用户日常 Tern；未提交、未推送。

## 工具统一浮动与激活描边（2026-10-22）

用户要求 lazygit 与临时终端使用同一套 PiP 交互，并为主题色激活 block 增加圆角描边、去掉原有顶部渐变线；随后补充希望 PiP 自动最大化。

### 实现

- `lib/tools.luau`：`displayTool` 对两种工具都调用 `float(pane, target, "br", { focus = true })`，不再为 lazygit 走 `dock`／`move`。`hide`、`endTool`、`restore` 去掉 terminal-only 限制，共用 single-flight、身份核验、park／unpark 和冲突处理路径；恢复列表按工具类型显示 lazygit 或终端，结束确认区分两者。
- 创建阶段仍先 `split` 再立即 `float`（`focus = false`），握手完成后再次浮动并聚焦；lazygit 的 Git bridge、进程身份和原生退出清理未改。
- `lib/style.luau` + `window.luau`：插件加载时注册全局样式 `plugin:local:kiku:active-block`。激活 block 使用 `--accent` 色的 2px 圆角描边和轻微内发光，隐藏 Tern 原顶部 1px 渐变线；float／studio 布局按 4px 内边距对齐卡片；PiP 聚焦时也绘制主题色描边。
- lazygit 仓库预检：依赖检查通过后，用已解析的 Git 执行 `-C <启动目录> rev-parse --is-inside-work-tree`；非仓库、超时或来源变化时不创建 pane、不启动 lazygit，只显示错误提示。临时终端仍可用于非 Git 目录。
- PiP 尺寸：Tern 0.9.5 窗口插件 API 没有 `expand`／`resize`，`pip expand` 只存在于场景脚本，`cx:action`／`cx.actions:run` 均返回 unknown action；因此插件只能以 `focus` 模式打开（原生最大标准尺寸），没有用固定视口尺寸的 CSS 覆盖伪造最大化。

### 验证

| 检查 | 实际结果 |
| --- | --- |
| 原生 lazygit 套件 `python3 tests/integration.py --lazygit-only` | 9 组 PASS：真实 lazygit 以浮动、聚焦的 PiP 打开；同源复用／跨 tab 带回；与临时终端共存；第二个 tab 独立实例；配置路径回退；非 Git 来源拒绝且临时终端仍可打开；失败卡片；重载不接管；可执行文件移除后 q 停放、再次打开恢复、Shift+Q 弹确认并取消、原生关闭清理进程与 bridge |
| 隔离原生 GUI（私有 config／daemon／socket） | `tern ctl css` 列出 `plugin:local:kiku:active-block`，5 条规则；light 与 dark 主题截图均显示圆角主题色描边，原顶部渐变线不再出现 |
| 原生非 Git 来源 `python3 tests/integration.py --lazygit-non-git-only` | PASS：lazygit 拒绝创建 pane、未启动真实 lazygit、未初始化仓库；同一目录的临时终端仍正常打开 |
| 代码级 | 40 场景、221 条断言通过（`tests/code_validation.py --luau`），含非 Git 拒绝与仓库检查期间来源变化中止 |
| Luau 编译／静态分析 | 通过；仅保留 `tool_identity.luau:100` 的原有 `TableOperations` 告警和 `window.luau` 一条既有 `MultiLineStatement` 提示 |
| Python 语法 | `tests/*.py` 通过 |

证据：

- 原生 lazygit：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-w8g__4kx`、`.../tern-kiku-test-e32mge4n`，含 `lazygit-real-tui.png`、非 Git 拒绝、重载与清理截图。
- 原生非 Git 拒绝：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-wo50aoix`（`lazygit-non-git-refusal.png`、`last-state.json`）与 `/tmp/kiku-native-nongit-toast2-tinh23hq/target/shots/tern/live/non-git-toast2.png`；真实提示为“无法打开 lazygit / 当前目录不是 Git 仓库：<完整路径>”，未创建 pane。
- 原生描边：`/tmp/kiku-native-outline-tm9g02v8/target/shots/tern/live/outline-native.png`、`/tmp/kiku-native-outline2-uv4s62c3/target/shots/tern/live/outline-native-dark.png`。
- 无头 CSS 选择器探针：light／tiles、light／float 截图，以及 `tern ctl css` 规则加载结果；用于验证圆角、顶部线移除和主题变量解析。临时无头实例均已 `quit`。

限制：自动展开 PiP 需要 Tern 上游提供窗口 API；当前只保证打开即 `focus`。未提交、未推送，未修改用户日常 Tern 配置或会话。

## 自身仓库 Git 元数据触发插件热重载（2026-10-22）

用户报告 lazygit 打开后不自动聚焦，`Ctrl+B → q / Shift+Q` 显示“工具身份未确认／未识别当前窗格”。真实隔离复现确定原因不是快捷键或进程验证失败：开发链接指向包含 `.git` 的仓库根目录，lazygit 的 Git 元数据刷新触发 Tern 0.9.5（2863c37）重载插件 VM，清空运行期工具登记并中断启动后的聚焦。

按用户选择保留源码热加载，不改为独立安装副本：13 个运行源码／配置文件整体移入 `plugin/`，与迁移前逐字节一致；实际开发链接更新为仓库的 `plugin/` 子目录。测试与文档保持在仓库根目录，运行包内相对导入不变，用户配置不丢失。源码热加载仍会遵守原有安全模式，不自动认领或关闭重载前旧工具。

### 已执行验证

| 检查 | 实际结果 |
| --- | --- |
| 原生红：包根等于 Git 根 | lazygit 创建期间 VM 代次从 1 变为 2；5 秒采样始终为 glance，未自动聚焦；q 未停放，Shift+Q 无结束确认 |
| 原生重载因果对照 | 仅在已链接包内 `.git` 新增文件，VM 代次从 2 变为 3；改从独立仓库打开 lazygit，代次保持 2，能够自动聚焦 |
| 原生绿：源码包位于 Git 根下的 `plugin/` | VM 代次保持 1；约 1397 ms 采样到 PiP focus；q 停放、同 pane 恢复并聚焦、Shift+Q 确认及取消均通过 |
| 新增源码文件与包外 Git 变化 | 在 `plugin/lib/` 新增模块后 VM 从 1 变为 2，证明新增文件仍热加载；随后仅修改包外 `.git`，VM 保持 2 |
| 生产文件与配置迁移 | 13 个包文件与 HEAD 中旧路径逐字节一致；旧根入口、配置和 `lib/` 副本不存在 |
| 代码级工具场景 | `python3 tests/code_validation.py --luau /tmp/luau743/luau` 的 40 个场景全部通过 |
| 真实 lazygit 完整原生回归 | `python3 tests/integration.py --lazygit-only` 最终 10 组 PASS（独立 Restart 组 + 9 组主套件），包括新增的包含插件包的仓库 Git 元数据更新后自动聚焦、q 保活、同 pane／PID 恢复、Shift+Q 取消与确认退出；跨重载不认领、缺失依赖管理等原有场景保持通过 |
| 工作树完整回归 | `python3 tests/integration.py` 83 组 PASS，包含包外 `tests/helpers.luau` 装载、创建／管理／安全关闭及正常／危险移除；包目录迁移未破坏既有工作树流程 |
| 静默 shell 启动 | `tests/startup_code.py` 在 zsh、bash、sh、dash、ksh 上通过首代次 PID 与重启验证；fish 未安装，未验证 |
| 编译与语法 | `luau-compile --null plugin/window.luau plugin/host.luau plugin/lib/*.luau` 通过；改动 Python 脚本的语法编译通过 |

首次原生检查在前置 Restart 场景发现测试新增导入时误删了既有 `signal` 导入；恢复后完整重跑通过，没有跳过或弱化该场景。最终原生证据目录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-61q6dhx2`（Restart）和 `.../tern-kiku-test-hb28d08c`（主套件）。
工作树完整回归证据目录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-hfcuaj3n`，报告包含 `count = 83`。

红绿探针结构化结果：`local://tern-plugin-watch-boundary-evidence.json`。探针仅使用私有配置、daemon、GUI 和 socket；相关临时实例已关闭。日常环境只更新插件源码链接，没有执行关闭、重开或重新认领旧工具的动作。

本次不改变 lazygit 的启动命令／PATH 语义，不修改快捷键配置，不放宽身份核验。未提交、未推送。

## 用户选择回迁至独立插件仓库根布局（2026-10-22）

此前的 `plugin/` 子包方案已由用户明确取代：用户选择官方文档所列的“独立插件分发布局”，即仓库根目录本身就是插件包根。该选择不基于“SDK 只允许根目录”的错误前提；官方 `plugins/examples/jsonx`、`canvas`、`longrun` 实际位于 SDK 仓库子目录，两种组织方式都被官方支持。

### 变更

- 13 个运行源码与配置（`plugin.toml`、`window.luau`、`host.luau`、`config.json`、`lib/` 下 9 个模块）从 `plugin/` 移回仓库根，字节内容完全不变；`plugin/` 目录不再存在。用户配置（含 `manageKeybinding` 与 `executables.lazygit`）原样保留。
- 实际开发链接由 `tern plugin link` 重新指向仓库根，`tern plugin list` 显示 `kiku 0.1.0 … window ready`。
- `tests/integration.py` 复制来源恢复为仓库根（排除 `.git`、`.test-artifacts`、`tern.d.luau`、`__pycache__`），`helpers.luau` 从临时包副本的 `tests/` 读取；`tests/code_validation.py`、`tests/startup_code.py` 生产源码路径恢复为根 `lib/`。
- README 的链接、`tern plugin types .`、配置位置与目录树同步为根布局；设计文档把子包方案标注为已被取代的历史决定。

### 已执行验证

| 检查 | 实际结果 |
| --- | --- |
| 回迁内容一致性 | 回迁前后 13 个文件的 SHA-256 逐一相等；`plugin/` 残留目录不存在 |
| 代码级工具场景 | 40 个场景全部通过 |
| 静默 shell 启动 | zsh、bash、sh、dash、ksh 通过首代次 PID 与重启验证；fish 未安装，未验证 |
| 编译与语法 | `luau-compile --null window.luau host.luau lib/*.luau` 通过；改动 Python 脚本语法编译通过 |
| 真实 lazygit 原生回归 | `--lazygit-only` 10 组 PASS（Restart 组 + 9 组主套件），证据目录 `…/tern-kiku-test-jna8mo39`、`…/tern-kiku-test-67_putpv` |
| 完整工作树回归 | `python3 tests/integration.py` 83 组 PASS，证据目录 `…/tern-kiku-test-68c6riod` |

一次并行执行两个原生套件时，`window.luau` 的 `load` 钩子超过 50 ms 预算被 Tern 禁用，导致 action 缺失与 lazygit 打开超时；串行重跑全部通过，确认是并发负载而非布局回归。

### 剩余风险（未解决）

根布局使 `.git` 回到被监听目录内。此前隔离实验已证明：链接包内的 `.git` 元数据变化会重载插件。因此在**本仓库自身**打开 lazygit（lazygit 会刷新该仓库的 Git 状态）仍可能触发重载，清空运行期工具登记，表现为不自动聚焦、`q / Shift+Q` 报“未识别当前窗格”。本次回迁不声称消除该问题，也未放宽身份校验或重新认领旧实例。`tests/lazygit.py` 的“包含插件包的仓库”回归覆盖外层仓库的 Git 元数据，不等于根布局下本仓库自身的该场景。

## `q` 触发 await 预算超限（2026-10-22）

用户按 `Ctrl+B → q` 时窗口提示 “Plugin Kiku 助手: await failed / runtime error: tern: await exceeded 50 ms”。窗口日志确认 `plugin hook exceeded its budget; disabled until reload plugin="kiku" hook="await"`，即该 hook 被禁用直到重载，后续调用会被静默跳过。

### 原因

窗口侧每次调用预算 50 ms，且 await 沿用同一截止时间。工具窗格运行 lazygit 时没有 shell 的 OSC 133 提示符标记，`session:settle(pane, ms)` 只能等到超时才返回。原实现有三处此类长等待：

| 位置 | 原等待 | 影响 |
| --- | --- | --- |
| `lib/tool_identity.luau` 新鲜采样 | `settle(pane, 100)` | 每次身份校验：`q`、`Shift+Q`、复用、打开 |
| `lib/tools.luau` 启动握手 | `settle(pane, 100)` | 所有工具启动 |
| `lib/tools.luau` lazygit 呈现前 | `settle(pane, 500)` | 打开 lazygit |

因此只要进程采样未更新，`q` 必然超预算。

### 修复

改为每次 10 ms 的短结算切片轮询：`freshSample` 与启动握手各以 10 ms 切片推进，lazygit 呈现等待为 50 个 10 ms 切片。仍要求采样晚于校验开始，切片用尽或窗格消失时保守拒绝，不接管未知实例，不改变身份校验与安全模式。

### 已执行验证

| 检查 | 实际结果 |
| --- | --- |
| 代码级工具场景 | 41 个场景通过，新增 `stale_process_sample_never_awaits_shell`：采样冻结时拒绝执行收起、窗格保留、单次等待不超过 10 ms；采样恢复后同一工具正常收起 |
| 原生工具套件（GUI） | 11 组 PASS，`native-tern.log` 中 `exceeded 50 ms` 为 0 次 |
| 真实 lazygit 原生回归 | 10 组 PASS（含 Restart 子场景、自仓库元数据、q 收起、Shift+Q 确认），证据目录 `…/tern-kiku-test-r9u8z1fw`、`…/tern-kiku-test-faz1knzk` |
| 无头重启场景 | `--lazygit-restart-only` PASS，证据目录 `…/tern-kiku-test-hs_2zids` |

限制：`--tool-restart-only` 在本机仍然因既有的 `process` 钩子超过 50 ms 而失败；用同一场景跑未修改的 `HEAD` 快照得到相同结果，属本机既有环境限制，与本次改动无关。另经隔离实验确认，无头 `serve` 只在窗口活动时才服务插件定时器，因此该修复没有采用定时器链。

