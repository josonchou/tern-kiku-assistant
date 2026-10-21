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
