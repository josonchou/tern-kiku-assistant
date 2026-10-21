# 01 本机程序解析与依赖门控

Status: ready-for-agent
Type: task
Blocked by: none
Spec: ../spec.md

## 目标

让现有 worktree 功能真正使用可配置 Git／realpath，并独立按依赖启用；为后续工具提供同一套本机程序解析结果。

## 文件边界

拥有 `lib/config.luau`、`lib/executables.luau`、`window.luau` 配置读取与旧 Git／realpath 入口、`tests/dependencies.py` 和必要的共享原生测试驱动扩展。不得改 plugin.toml、README.md、用户 config.json、其他任务文件或纯安全模块的既有规则。

## 契约

遵循 spec 的配置字段、依赖 interface 及完整路径回退规则。所有旧 Git调用包括 removalRun 安全调用必须使用解析结果，不能漏掉 realpath。missing realpath 只隐藏/拒绝两个移除子动作；Git缺失只禁用依赖它的功能。available 不做阻塞探测，直接调用与快捷键仍保护。异步前捕获来源并重核，不能跟随另一焦点执行。先确认本机；无远程代码。

## 验收

- 真实可执行 Git 路径含空格时仍能创建正确 worktree，不依赖 PATH 中同名版本。
- 显式路径失效且 PATH 有程序时成功回退并可看到最终路径；两者无效时隐藏/拒绝且Git状态不变。
- realpath 不可用时仍能创建、打开，普通与危险移除不可执行。
- 所有配置错误明确处理，旧配置无需修改继续可用；特殊字符不执行额外命令。
- 旧安全行为保持，完整回归由主线程最终执行。

## 实施与测试

先读取 tdd 技能及 spec 约定 seam。阶段A只写一条可定向运行的真实配置路径行为测试，返回工作区路径和运行命令供主线程 red；主线程反馈后继续实施。禁止子代理运行测试/build/lint/formatter。主线程green后，提交中文Conventional Commit，合并integration/kiku-assistant tip再报告；不修改票据状态为resolved（集成人负责）。

## Comments
