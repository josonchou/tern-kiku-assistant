# 依赖解析回退到用户登录 shell 的 PATH

Status: resolved
Type: task
Blocked by: none

## 用户报告

2026-10-22 截图：打开 lazygit 提示“无法打开 lazygit — lazygit（executables.lazygit 与本机 PATH 均不可用）；lazygit…”。本机 lazygit 位于 `/opt/homebrew/bin/lazygit`；`config.json` 未配置 `executables.lazygit`。

## 原因

依赖探测使用 `tern.getenv("PATH")`，即宿主进程自身的 PATH。Tern 由 Finder／daemon 启动时继承的是会话级或最小 PATH，用户 shell 配置文件里的 Homebrew 等目录不在其中，于是“本机 PATH”与用户终端里看到的不一致。`git` 因 `/usr/bin/git` 存在而正常，只有 shell 管理的程序受影响。

## Scope

- 现有显式 `executables.<name>` 仍优先，路径无效时仍按原规则回退 PATH。
- 进程 PATH 中找不到时，用本机登录 shell 读取一次用户 PATH（`$SHELL -l -c`，缺失或非绝对路径时按平台取 `/bin/zsh`／`/bin/sh`），把该 PATH 追加在启动环境前面；不覆盖显式配置，不修改用户 shell 配置，不自动安装程序。
- 结果按插件 VM 缓存；每个解析器只探测一次。登录 shell 不可用或输出异常时保持原失败提示。
- 保持依赖门控按功能独立；缺失时仍拒绝对应功能而不是静默无环境启动。

## 验收

- 代码级回归：进程 PATH 无 lazygit、登录 PATH 有时能启动，且实际启动命令使用登录 PATH 与解析到的绝对路径；再次打开复用实例不再探测。进程 PATH 与登录 PATH 都没有时仍报缺失。
- 隔离真实 Tern：私有实例以最小 PATH 启动，`command -v lazygit` 为空而登录 shell 可解析；插件成功打开 lazygit，无“不可用”提示。
- 运行完整代码级套件、编译／分析与 Python 语法检查；不操作或重载用户日常 Tern，不提交、不推送。

## Result

- `lib/executables.luau` 增加登录 PATH 回退：仅在进程 PATH 解析失败时探测一次并缓存；启动用 PATH 为“登录 PATH + 进程 PATH”，显式配置优先级不变；缺失的显式配置项按空处理。
- 代码级 34 场景、177 断言通过（新增登录回退与真实缺失两例）。隔离真实 Tern 以最小 PATH 启动时成功打开 lazygit，pane 的运行命令为 `exec /usr/bin/env PATH='<登录 PATH 等>' /opt/homebrew/bin/lazygit`，无错误提示。
- 证据：`/var/folders/wh/t3q86s6918nfqd3r15m8_f6w0000gq/T/kiku-quiet-start-proof-4db6z39a/native_lazygit_login_path.json`、同目录 `final_summary_with_login_path.json`。
- 未提交、未推送；用户配置与日常 Tern 会话未改动。
