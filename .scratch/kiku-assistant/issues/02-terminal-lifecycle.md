# 02 临时终端与完整生命周期

Status: resolved
Type: task
Blocked by: 01
Spec: ../spec.md

## 目标

交付可实际使用的本机临时终端以及共同的工具生命周期，不创建 lazygit 占位入口。

## 文件边界

拥有 `lib/tools.luau`、window.luau 最小注册调用、必要的本机身份帮助代码、tests/tools.py 及共享驱动接入。复用01配置和依赖模块，不复制解析器；不得改README、清单、用户config或worktree安全语义。

## 契约与验收

完整落实 spec 2–7、11–12：来源cwd／本机身份、原生右下角float、同源复用跨源隔离、不嵌套；Ctrl+B→t/q/Shift+Q；本次插件运行期内park保活与同pane恢复；安全结束的确认/取消/执行前重核；shell正常退出关闭、失败卡片交由原生查看／关闭；来源关闭后身份已确认的存活工具可通过restore_tools列表恢复为独立tab。按用户最新批准的安全模式，重载后旧实例不自动认领、收起、移动、结束或重跑；普通窗格展示旧标记不能获得工具归属。已确认的存活实例不因依赖消失失去管理入口。

必须以真实进程与pane状态证明收起没有结束任务，不用仅检查表项或调用次数。原生关闭整个tab/session不被偷偷覆盖。浮动或启动失败要披露已启动对象，不误杀、不重复创建。隐藏工具仍在worktree使用者审查内。

## 实施与测试

读取tdd，先提交一条真实终端打开／收起恢复的失败场景交主线程red，再实施该纵向路径并逐步覆盖安全边界。子代理不跑测试/build/lint/formatter。报告前中文Conventional Commit并合并integration/kiku-assistant tip。验收与resolved由集成人完成。

## Comments

- 2026-10-21：01 已集成验收，临时终端票据进入实施。阶段A先交付真实原生 red 场景；集成基线 `3ee6da59858bc387b4cc71ca35f77ab34c0c9d8a`。身份方案须由实际进程／宿主生命周期探针证明，不得凭旧 pane ID 接管。
- 2026-10-21：用户明确选择“安全模式：未知实例交由 Tern 原生管理”，取消本轮跨重载自动接管；无法确认代次的失败卡片也只由原生查看／关闭。原生 red：`tern-kiku-test-z6g4pw39`，普通窗格展示旧 prefix 文本后被恢复扫描误认领；独立安全审查确认仅补数字 PID 或精确命令仍不能证明候选 pane 承载旧进程。不得通过历史标记或仅旧 ID 重新授权。

## Result

- 已集成：`5fc44a828bb3396718a85cb969be84d8240e9f85`，`feat: 增加安全的临时终端生命周期`。
- 正常原生 GUI＋独立 daemon 的9组场景通过，证据 `tern-kiku-test-onvqrfq8`：实际任务保活、同源复用／跨源隔离、默认取消与确认结束、来源 shell 退出及原生 Cmd+W、独立标签恢复不被再次收起、旧记录不永久阻止新建、重载后标记／跨会话移动均不授予归属。
- Restart 的真实进程代次防护单独通过无 daemon 的 Tern，证据 `tern-kiku-test-64b9nach`；同版本 daemon 下普通终端也无法完成原生 Restart，不将宿主限制当成插件验证通过。
- 非本机上下文拒绝通过，证据 `tern-kiku-test-i26qo4z8`：Tern 自带 loopback 宿主下，快捷键与直接动作均提示拒绝，不在本机创建工具；未连接真实 SSH 主机。
- 已观察原生浮窗截图；测试使用私有配置、socket、daemon、GUI，并清理自己创建的进程，不触及用户日常会话。完整 worktree 回归与 lazygit 双工具组合仍按后续阶段统一验收。
