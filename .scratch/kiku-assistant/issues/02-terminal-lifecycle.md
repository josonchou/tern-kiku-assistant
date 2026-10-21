# 02 临时终端与完整生命周期

Status: ready-for-agent
Type: task
Blocked by: 01
Spec: ../spec.md

## 目标

交付可实际使用的本机临时终端以及共同的工具生命周期，不创建 lazygit 占位入口。

## 文件边界

拥有 `lib/tools.luau`、window.luau 最小注册调用、必要的本机身份帮助代码、tests/tools.py 及共享驱动接入。复用01配置和依赖模块，不复制解析器；不得改README、清单、用户config或worktree安全语义。

## 契约与验收

完整落实 spec 2–7、11–12：来源cwd／本机身份、原生右下角float、同源复用跨源隔离、不嵌套；Ctrl+B→t/q/Shift+Q；park保活与同pane恢复；安全结束的确认/取消/执行前重核；shell正常退出关闭、失败保留；来源关闭后存活工具可通过restore_tools列表恢复为独立tab；重载后可靠归属，不因ID复用误关普通pane；已运行程序不因依赖消失失去管理入口。

必须以真实进程与pane状态证明收起没有结束任务，不用仅检查表项或调用次数。原生关闭整个tab/session不被偷偷覆盖。浮动或启动失败要披露已启动对象，不误杀、不重复创建。隐藏工具仍在worktree使用者审查内。

## 实施与测试

读取tdd，先提交一条真实终端打开／收起恢复的失败场景交主线程red，再实施该纵向路径并逐步覆盖安全边界。子代理不跑测试/build/lint/formatter。报告前中文Conventional Commit并合并integration/kiku-assistant tip。验收与resolved由集成人完成。

## Comments
