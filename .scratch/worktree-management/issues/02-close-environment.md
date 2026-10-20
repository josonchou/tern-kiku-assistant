# 02 安全关闭工作环境

Status: resolved
Type: task
Blocked by: 01
Spec: ../spec.md

## 目标

从管理入口关闭选定的绑定标签页，保留工作树与分支，并阻止不安全或模糊的关闭。

## 修改范围

01 的管理 module/窗口接入、真实集成场景和 `README.md`。复用 01 的工作树身份、绑定和候选发现，不另建注册表或状态机。

## 交付契约

- 只关闭用户选定的有效绑定 tab，不连带扫描关闭同 cwd 的其他 tabs。
- 审查该 tab 的所有 tiled/floating pane 和所属 session/host；被锁定 session 或未知归属拒绝自动关闭。
- terminal/agent 只有明确 idle/at_prompt 且无运行状态或错误才可关闭；file/notebook/database 只有可读且明确无未保存内容、无运行任务才可关闭。其余无明确安全契约的类型保守拒绝。
- 展示将关闭的环境和 pane，默认取消，确认后重新检查 tab/pane 集合、身份及全部安全状态；任何变化停止操作。
- 不提供强制关闭；不删除磁盘目录、分支或 worktree 登记。部分关闭失败时明确报告现场，不扩大关闭范围。

## 验收

1. 空闲、已绑定的多 pane tab 经确认关闭，其他 tab/session 不受影响，Git worktree 和分支仍在。
2. 运行中命令、工具未保存内容、未知类型或无法判断状态均拒绝且保留环境。
3. 取消以及确认期间新建 pane/开始命令/改变环境归属均不能触发盲目关闭。
4. 多候选情况下只关闭选中的绑定；关闭后同一 worktree 可重新打开。

## 测试与实施

先增加真实 Tern 的安全关闭失败场景交主线程运行 red，再实施。子代理不运行测试/build/lint/formatter；主线程负责实际 red/green 和烟测。不得通过 mock 宿主安全字段制造假验证。

## Result

- 实现提交：`c92800a33d24119dc9ce512fbdda472284ac1238`。
- 集成合并：`1cf5026186c896c1422ac26e6266f71670de3f4e`，分支 `integration/worktree-management`。
- 真实 red：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-hykgeuu4/`，关闭动作缺失。
- 真实 green：`/private/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/tern-kiku-test-ytvddzqn/report.json`，30 组集成场景通过。
- 覆盖无绑定拒绝、未保存文件、锁定会话、忙碌终端、未知原生面板、干净 Notebook、浮动 pane、预览期间新增 pane、确认期间启动命令、取消，以及关闭后复用剩余环境；其他 tabs/panes/sessions、文件字节、refs 和 worktree 登记均按场景核验保留。
- 原生截图位于同一报告目录的 `shots/serve/management-close-confirm.png` 与 `management-close-pane.png`；主线程已检查确认列表和单行可滚动信息预览。
