# 工具终端启动不显示内部身份握手

Status: resolved
Type: task
Blocked by: 04

## 用户报告与授权

2026-10-22，用户截图确认新建临时终端展示了 `/bin/sh -c 'printf ... "$PPID"'` 及 `KIKU_TOOL_V1` 标记，随后明确要求修复。截图是运行事实，不再启动 Tern 确认。继续此前仅代码验证、不操作或重载用户 Tern 的约定。

## Scope

- 新建工具终端不向可见输入或输出注入内部身份握手，不用强制清屏或 ANSI 擦除掩盖。
- 保留默认交互 shell、登录参数、工作目录和 Tern shell integration；不改用户 shell 配置。
- 身份仍须绑定本次新建的确切 pane 及 shell 进程，并沿用新进程采样、PID／父进程及启动代次核验。不能仅按 cwd、标题或历史文字猜测认领。
- 不削弱固定归属单实例、single-flight、Restart 拒绝、跨重载不接管、来源 block 支持和安全结束保护；不改变两种工具的布局。
- 只使用实际核实过的宿主 API；未知或身份不明安全拒绝，不静默改用无身份工具。

## 验收与验证

- 沿用已批准的公开命令／SDK 边界 seam，补充可锁定静默启动与身份保护的行为验证；在可行接缝先记录失败再修复。
- 用隔离 shell／PTY 代码烟测验证真实启动命令的输出与 exec 进程身份，不把替身或非 Tern 的 PTY 结果称为原生 Tern 验收。
- 运行相关 Luau 回归、编译／分析和 Python 语法检查；执行安全审查，更新说明和证据记录。
- 不启动 Tern GUI／serve／daemon，不跑原生或浏览器套件；不改用户配置、不提交、不推送。保留全部既有未提交改动。

## Comments

- 已确认现有 `cx:run` 的公开语义就是像键入一样写入 PTY；窗口 API 没有 silent 选项。启动时 `Launch.command` 和 host `spawn` filter 为待核实候选，不能把不确定的 shell／integration 语义当作已验证能力。

## Result

- 根因确认：`cx:run` 的公开语义就是向 PTY 键入文本，窗口 API 无静默选项；`Launch.command` 会改变 pane 类型为 agent，不能用于保真启动。
- 改为私有启动交接目录 + 宿主 `spawn` 钩子：只在 `spec.cwd` 命中本插件启动根且 request 校验通过时改写，静默记录 `$$` 后 `exec` 原 shell 与原参数，保留默认交互 shell 与 shell integration 环境；普通 pane 完全不经手。
- 工具窗格仍为原生 `terminal`；身份仍经现有进程采样核验。`pid` 只写一次，原生 Restart 不覆盖首代次，因此新 shell 判为身份不明。默认 shell 不受支持时显式报错并退出 125，不降级。
- 隔离原生（zsh）：工具到达 prompt 后回滚区只有提示行，无 `KIKU_TOOL`／`/bin/sh -c`；cwd 正确；pid 文件为存活 zsh 且父进程是本次私有 daemon；q／恢复／结束与清理通过。
- 代码级：32 场景、165 断言通过；新增静默身份与不支持 shell 场景。真实 shell 冒烟（生产过滤器生成命令）覆盖 zsh／bash／sh／dash／ksh，均静默且 PID 连续、重启不覆盖；fish 未安装，未验证。编译与 Python 语法通过，静态分析只剩原有 1 条告警。
- 限制：bash／fish 在真实 Tern 中的集成参数顺序未做原生验证；宿主半部缺失时安全拒绝而非无身份启动。未提交、未推送。
