# 验证记录

日期：2026-10-20。

## 环境

- macOS arm64
- Tern 0.9.5 (2863c37)
- 系统 Git
- Python 3 仅用于驱动集成测试

## 当前管理功能验收

**完整验收仍受阻，03和04不得据此标记 resolved。** 用户已明确批准先集成03并推进04；这只改变实施顺序，不降低验收条件。

- 02集成时，创建、发现/复用打开及安全关闭的完整原生回归通过30组。记录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-ytvddzqn/report.json`。已查看关闭确认和pane预览截图。
- 共享Git操作保护加入后，普通移除模块全部原生场景通过28组记录（含加载及原生helpers）：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-y0btow2_/report.json`。包括普通成功/取消、全部文件及索引风险、独立引用保护、确认期间变化、嵌套/失效/替换身份、fsmonitor、floating/parked/native path 使用者和真实Git读取错误后的数据保留与重入。这是模块整组通过，不替代创建/管理全流程回归。
- 最新完整运行 `PYTHONDONTWRITEBYTECODE=1 python3 tests/integration.py` 在旧创建流程通过12组后，被 `process exceeded 50 ms` 中断，尚未进入新增移除流程。证据：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-evmeqxnq/logs/tern-serve.log:10-11`。
- 04首个真实 red 精确命中尚缺的危险入口：筛选 `危险移除 worktree` 后picker为0行；该次日志没有宿主超限。证据目录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-0vgaryo2`。它不是功能通过记录。
- 共享Git操作保护加入后，04危险移除模块通过19组记录（含加载及原生helpers）：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-td1_dmuo/report.json`。覆盖tracked、独立ignored-only、独立无保护Detached、主动路径与外部确认、只读预览不授权、各级取消和错路径改正；200项纯untracked清单下，完整风险项可查看，未展示的新文件使旧授权失效；main/bare/locked/prunable、隐藏索引和最终pane/HEAD/symbolic-ref/路径替换/新增锁定保护均已实际执行。真实staged rename/copy的两条NUL路径都能完整预览，其他checkout与refs保持。长风险预览先在`tern-kiku-test-nriquast`获得真实red，再修正；已查看首屏截断声明截图。此前R/C夹具遍历不存在prunable路径的问题已修正，仍保留全部登记和路径状态断言。
- 真实Git部分失败烟测先失败再通过，并在当前实现上复验通过3组：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-9hdq8969/report.json`。不可变文件令单次 `--force` 失败，但其他文件及worktree登记已被删除；已查看原生截图，“目录或登记可能已部分移除，请手动核查”完整可见，refs、残留 `.git` 与保护文件均未被进一步清理。最初修正前后证据为`tern-kiku-test-vcpyl6wg`、`tern-kiku-test-o1mahflw`。此烟测使用自建临时文件并在finally清除不可变标志，没有把Git删除顺序或提示文案固化为永久测试。

普通回归过程中修正了测试驱动的确认项漏选和对提示空格的依赖。另一次等待误把`ctl tree`中的常驻`Git  ⌥⌘G`工具栏tooltip当成Git错误，导致夹具过早恢复索引；证据为`tern-kiku-test-tnrhqphq`。现在只匹配实际文本节点且要求picker已关闭，并验证索引字节、refs、登记与流程重入。隔离错误场景`tern-kiku-test-blurbj3d`和上述28组完整普通模块均通过，没有修改生产保护来迎合测试。

另外用真实 `git merge --autostash --no-commit --no-ff` 构造已开始但尚未结束的同树合并：工作目录、索引、HEAD和普通refs均保持原审查值，未提交内容只存在于`MERGE_AUTOSTASH`。修正前原生流程仍删除了目标与恢复指针，证据目录 `tern-kiku-test-zwnbo0zh`。共享审查现验证目标private Git目录/backpointer，同时检查目录标记及目标自己的root refs；files/reftable后端的真实Git实验确认二者不能互相替代。新增原生回归通过9组记录：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-wu2fp1g8/report.json`，覆盖两入口初审与末次拒绝、恢复内容保留、其他pending worktree不误阻止安全目标、合法relative backpointer以及普通`MERGE_HEAD`同名分支。相对metadata先在`tern-kiku-test-wsbchvj0`获得真实red；现按private Git目录解析相对路径，并用目录名/root-ref精确识别操作状态，避免`rev-parse MERGE_HEAD`误命中普通分支。根引用查询复用现有命令步骤，不在成功路径拼接整段refs输出作为错误提示。已查看拒绝截图，原因与“先保存内容，再手动完成或中止”的建议可见。

### 宿主阻塞的隔离证据

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
