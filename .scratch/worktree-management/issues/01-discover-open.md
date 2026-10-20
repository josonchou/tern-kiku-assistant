# 01 发现并复用打开工作树

Status: claimed
Type: task
Blocked by: none
Spec: ../spec.md

## 目标

提供可用的原生管理入口，列出当前仓库全部登记工作树，并正确打开或复用其标签页。为后续关闭和移除提供同一套身份与可见环境发现逻辑。

## 修改范围

`window.luau`、`lib/worktree.luau`，必要的新 `lib/manager.luau`；`config.json`、`tests/integration.py`、必要的独立管理场景文件及 `README.md`。沿用已有 flow/pick/prompt/Git argv，不复制第二套近似异步状态机，不无关重构。

## 交付契约

- 注册 `plugin.kiku.manage_worktrees`；`manageKeybinding` 默认为空，独立于已有创建快捷键。
- Git worktree 行保留 HEAD、branch、bare、detached、locked／原因、prunable／原因，供列表展示和后续保护使用。
- 以真实 Git root/common-dir 与 pane 的主机身份发现候选，覆盖来源子目录、符号链接和多个会话；不以标题或字符串前缀单独判断。
- 一个有效绑定优先复用；多个候选由用户选择；无候选创建命名 tab。新创建的 worktree 与管理打开共用绑定规则。
- 不关闭、移除或搬迁工作树。尚未实现的操作不要显示占位按钮。
- 管理流程与创建流程共享窗口内锁，取消和错误释放锁；拒绝远程上下文。

## 验收

1. 用 Git 直接创建的 linked worktree 能从管理入口打开，cwd/分支/名称正确。
2. 再次打开同一 worktree 复用已有 tab；不同会话内也能切换到正确目标。
3. 同一目标有多个手工打开的候选时须选择；无关或相似前缀目录、其他仓库不能被当成目标。
4. 基于子目录或符号链接识别同一工作树；取消不创建 tab 或改变 Git。
5. 原创建命令/快捷键/目录策略保持；管理快捷键默认无绑定且自定义可触发。

## 测试与实施

用户确认的 seams 见 spec。先只增加一条真实管理打开的失败场景，交主线程运行 red；得到结果后再实施该纵向功能。子代理不得运行测试、build、lint 或 formatter。主线程验证 green。不要新增文案精确匹配、argv 转发或 mock 回声测试；保留用户可见行为断言。

## Result

待实施后记录实际集成提交和验收证据。
