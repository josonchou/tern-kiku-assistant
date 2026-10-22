# 工具单实例与布局实现

Status: resolved
Type: task
Blocked by: none

## Scope

按 ../spec.md 完整实现 lib/tools.luau 的固定创建tab+启动目录+kind归属、同键single-flight、lazygit tiled/scratch PiP默认布局、scratch专用park/end/restore与来源关闭/孤儿处理；必要时最小修改tool_identity记录字段，保持真实进程代次门禁和稳定动作interface。

负责新增代码级验证runner与fixture，通过生产注册命令/event入口、Tern SDK边界替身验证，而非mock私有方法。先提供一条不同来源pane同tab同目录复用的红场景交主代理运行，再继续实现；不自行运行任何tests/build/lint/formatter，不启动Tern。

## Acceptance

满足spec所有运行契约；代码级场景覆盖single-flight、身份失效、布局恢复和固定归属，保留现有安全性。测试不能将identity.verifyProcess替换为恒真，也不能测试源码字符串或mock回声。无无关重构、无配置覆盖、无提交推送。

## Comments

- 用户已授权实施；明确只做静态检查和隔离逻辑验证。真实Tern验收本轮不执行。

## Result

- 已集成到当前工作分支的未提交工作区，无提交或推送。`lib/tools.luau` 完成固定创建 tab／启动目录／类型归属、同键 single-flight、默认布局恢复、仅临时终端 park／end／restore、来源关闭不主动处理及孤儿恢复冲突保护。
- 身份验证保留真实生产模块：单实例检查改为父进程先核对、子代次最后核对；从工具复用另一工具时，以同一份完整新采样同时确认来源、目标及两个父进程，不串联两份会相互失效的授权。
- 创建异常区分正常 nil、已观察候选和异常无候选；不确定结果保留占位，不把一次枚举无新增当成无副作用。没有可观察候选时需原生检查后重载解除，不安排空转轮询。
- `tests/code_validation.py` 执行实际生产 Luau 模块，共26场景116断言通过；包含同 tab 复用、完整 split tree／PiP 角落、失败释放／重试、延迟回调 Restart 及联合采样截断拒绝。多条缺陷场景有先红后绿记录。
- 全部插件 Luau 及代码夹具编译通过；分析器0错误，保留1条原有随机 token 类型推断告警；相关Python脚本语法通过。规格、安全复查无未解决阻断项。
- 未运行新版原生测试，未启动真实 Tern。证据与限制见 `docs/verification.md` 最新章节。
