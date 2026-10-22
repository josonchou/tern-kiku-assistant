# 快捷工具布局与固定归属单实例

Status: resolved

## 授权与来源

用户于 2026-10-21 完成 grill-with-docs 并选择“确认设计，并开始实施”。权威决定为 [设计访谈中的快捷工具布局与复用章节](../../docs/design.md) 与本规范；本规范覆盖旧 kiku-assistant 规范中冲突的工具布局、复用及生命周期部分。领域术语见根 GLOSSARY.md。

用户随后明确改为代码验证，选择“静态检查加隔离逻辑测试”：执行生产 Luau 命令入口，用隔离替身提供 Tern 布局／事件／进程采样；不启动 Tern GUI、serve、daemon 或原生回归。之前 PiP 原生观察不作为新代码验收。不得提交、推送或改写用户配置；集成在当前工作分支的未提交工作区，相关提交记为未创建。

2026-10-22 用户额外批准一次最小隔离原生验证（私有配置、daemon、控制 socket 与临时目录，不连接或重载日常会话），用于核实静默启动；其余原生套件与 PiP 观察仍不作为新代码验收。

## 已确认行为

1. lazygit 以当前 tab 内右侧普通分屏打开；临时终端以右下角原生 PiP 打开。采用 Tern 原生尺寸，不保证精确一半或百分比，不重排无关 block。
2. 两种工具按“创建时的 tab + 启动目录 + 工具类型”各保留一个受管实例；同 tab 同目录不同来源 pane 复用，不按来源 pane 隔离。当前窗口插件 VM 内保证，不承诺跨窗口并发或跨重载全局唯一。
3. 启动上下文取当前聚焦 block，包括 OMP/agent、Git 等非终端 block；有可靠绝对 `PaneInfo.cwd` 时按该目录启动，不固定最初来源、不切到 Git 根。可靠目录或本机身份未知则拒绝；不将 file/root `path` 或 tab cwd 猜作兜底。目录键不额外合并符号链接别名。
4. 启动目录固定归属：从 A 打开的工具 cd 到 B 后，从 A 再打开仍复用它，不改变其内部 cwd；新操作仍从当时当前 pane 的目录计算请求键。kind 和 origin tab 同样参与独立索引，不用有路径分隔符碰撞的字符串拼接。
5. 手动移动到其他 tab 不改变创建归属；原 tab 再打开将工具带回来。T2 可以创建属于 T2 的同目录实例，不能为屏幕上去重而自动杀掉 T1 的实例。
6. 每次打开／复用恢复默认形态：lazygit 右侧 tiled、scratch br PiP，手动停靠或移动不固定为下次布局。复用不重启程序、不重复创建；打开另一种工具不 park 前一种，两者可共存。
7. scratch 保留 Ctrl+B→q 的 park 保活、Shift+Q 的安全结束，以及专用恢复入口；这些动作不作用于 lazygit／普通pane。原生 PiP 的聚焦／失焦、缩放、展开、拖动、stash、dock、关闭照常可用。park 不是 stash，不调用全 tab stash-all 模拟单实例收起，不抢占裸 Esc/Ctrl+C。
8. q 后优先返回最近一次唤出该终端的 pane；若已消失沿用原生焦点，不创建替代源。自身已聚焦时不能将自己当自己的布局target；可使用可靠的同tab tiled承载者，无可用target时保留并提示，不误造额外终端。
9. 来源 pane 不再是生命周期归属，单独关闭来源不主动 park/结束工具。原生关闭tab/session/宿主可能结束任务，插件不拦截或复活。
10. 存活的 parked scratch 可通过恢复入口找回。原归属tab存在时保持归属并回到该tab；原tab已不存在时，用户显式选择恢复到当前tab并重新归属，若当前tab已有同键实例先让用户选择，不替换或杀进程。不得让两个实例占同一个归属键；未被选择的实例保持原状可恢复。lazygit不新增专用孤儿恢复。
11. 安全模式继续：仅本VM身份已确认的实例能复用／移动／结束；进程代次不明、Restart、失败卡片不凭旧文本或pane ID重新认领。重载后旧工具交原生，不自动迁移／重启／关闭，旧记录只能用于保守拒绝，不能授予归属。
12. 同键创建／恢复single-flight在异步检查前占位；连续触发不会重复启动，完成回调只释放自己的代次。异常但可能已创建pane时保留待核实占位，不自动重试；确认未创建或pane已关闭才释放。异步完成前重新核对请求上下文，不将结果重定向到新焦点。
13. lazygit退出呈现遵循原生；scratch正常退出／错误保留沿用现有契约。安全结束的进程身份和busy检查不得弱化，取消无副作用。程序路径失效不影响已确认存活实例管理。
14. 保持稳定插件ID kiku、action IDs open_lazygit/open_terminal/hide_tool/end_tool/restore_tools、配置键与用户覆盖规则。仅更新命令说明使管理动作明确为临时终端；不改用户config.json。
15. 本机macOS/Linux范围、程序解析/回退、Git桥、worktree管理安全不变量不变。parked/floating工具仍被manager的独立pane枚举看到，不能绕过使用中保护。
16. 新建工具终端不向可见输入或输出注入内部身份握手；不以强制清屏或 ANSI 擦除掩盖。保留默认交互 shell、登录参数、shell integration 与严格实例身份保护，不修改用户 shell 配置。
17. 外部程序解析保持显式配置优先；显式路径无效时回退进程 PATH，仍未命中时用本机登录 shell 的用户 PATH 解析一次并缓存。登录 shell 不可用时保持缺失提示；不自动安装程序、不改用户 shell 配置，依赖仍按功能独立门控。

## 实现与文件责任

- 01 owns lib/tools.luau，必要的 lib/tool_identity.luau 记录字段调整，以及新代码级验证runner/fixture。保留register(config,resolver,configError)公开interface；若要改exported interface先查引用。优先复用已有identity/launch模块，不另造进程身份机制或持久化接管。
- 02 owns tests/tools.py、tests/lazygit.py、必要的tests/integration.py。只更新现有真实回归契约及必要的新行为场景，不运行原生测试。不可删弱安全拒绝、真实PID、cwd、TUI或worktree保护断言。
- 主代理串行整合两套隔离改动、处理冲突并运行代码验证；README、plugin.toml说明、docs/design.md、docs/verification.md和任务状态由主代理维护。
- 两个切片只通过稳定命令与本规范行为交互，文件不重叠，可使用独立checkout。不得写父工作区，子代理均跳过测试/build/lint/formatter。

## 代码验证seam

用户已明确批准：通过注册后的生产命令入口及原生事件handler运行真实Luau逻辑，边界替身只提供Tern SDK依赖，不mock工具私有方法、不替换生产身份校验为恒真、不测源码文本或转发回声。至少用一条先红后绿的同tab同启动目录不同来源复用场景证明旧方案缺口，后续按纵向场景覆盖状态转换。

覆盖：目录/tab/kind区分、固定归属、single-flight异步竞争、默认布局恢复、跨tab带回、scratch park/恢复/结束、lazygit不受管理动作、来源关闭不park、孤儿恢复冲突、未知身份/Restart/重载保守拒绝、创建结果不确定、焦点变化中止。运行实际Luau编译器语法检查；可用类型检查按实际能力报告，不以忽略未知require等错误伪装通过。Python回归脚本只做语法检查。

不执行Tern原生套件，不加载用户Tern配置，不做浏览器自动化。交付标明代码验证范围和未执行原生验证的风险；不能用边界替身证明SDK真实时序或UI效果。

## 任务图

- [01 工具单实例与布局实现](issues/01-tool-runtime.md)：无依赖。
- [02 原生回归契约同步](issues/02-native-contracts.md)：无依赖，公共命令interface固定。
- [03 文档与代码级验收](issues/03-code-validation.md)：依赖01、02；主代理整合后审查与验收。
- [04 OMP／Git等block来源修复](issues/04-block-sources.md)：依赖03；针对2026-10-22用户运行反馈，仍仅代码验证。
- [05 工具启动不显示内部握手](issues/05-quiet-tool-startup.md)：依赖04；保留安全身份校验，仍遵循仅代码验证的授权，尚未宣告宿主静默启动能力已核实。
- [06 依赖解析回退登录 PATH](issues/06-login-path-fallback.md)：依赖01；修复 GUI／daemon 启动时 shell 管理的程序（如 Homebrew lazygit）被判缺失。

实现ticket只在集成与用户选择的代码验收通过后resolved。03记录未执行native验证，不暗示此前native结果仍覆盖新版。所有tickets完成后spec resolved；无用户授权不创建提交。

## Result

- 01–03均已完成并关闭，运行实现、原生回归契约及文档已串行集成在当前工作区，没有创建用户提交或推送。
- 26个代码级场景116条断言、既有48条纯逻辑断言、Luau编译和Python语法检查通过；公开命令的隔离SDK边界烟测通过。
- 规格与安全审查发现项均已修正并复核；未为清零诊断加入类型抑制，保留1条原有静态推断告警。
- 04针对OMP／Git等非终端block来源提前拒绝的问题完成：只去除来源kind门禁，仍要求可靠绝对cwd与本机／标签页上下文；工具身份保护不变。代码回归扩展为30个场景151条断言，先红后绿、公开命令边界烟测、编译／分析及Python语法检查通过；本轮仍未做真机验证或重载用户插件。
- 按用户决定没有进行新版真机验证，不将代码边界替身视为Tern原生验收。详细证据、先红后绿记录和限制见 [验证记录](../../docs/verification.md) 最新章节。
- 05完成静默启动：每次工具启动使用私有启动交接目录，宿主 `spawn` 钩子仅在命中该目录时静默记录 shell PID 后 exec 原 shell／参数，窗口不再向 PTY 键入握手。原生工具仍为 terminal 类型；Restart 保留首代次 PID 因而拒绝管理；不支持 shell 显式报错不降级。
- 05的验证：隔离原生 zsh 确认回滚区无内部命令、cwd 与进程身份正确、q／恢复／结束及清理通过；代码级 32 场景、165 断言与真实 shell 冒烟（zsh／bash／sh／dash／ksh；fish 未安装）通过。bash／fish 在真实 Tern 的集成参数顺序仍未原生验证，未提交、未推送。
- 06修复依赖解析：进程 PATH 未命中时用本机登录 shell 读取用户 PATH 再解析，显式配置优先级不变。隔离真实 Tern 以最小 PATH 启动时可正常打开 `/opt/homebrew/bin/lazygit`；代码级套件增至 34 场景、177 断言，未提交、未推送。
