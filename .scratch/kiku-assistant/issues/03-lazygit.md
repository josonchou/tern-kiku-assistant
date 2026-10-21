# 03 lazygit 与双工具切换

Status: resolved
Type: task
Blocked by: 02
Spec: ../spec.md

## 目标

在完整工具生命周期上增加真实 lazygit 浮窗，完成同源双工具切换与缺依赖隔离行为。

## 文件边界

lib/tools.luau、tests/tools.py 或独立 tests/lazygit.py、必要的依赖模块适配。仅在确需时调整window接入；不改README/清单/用户config，不重写02已完成的生命周期。

## 契约与验收

- Ctrl+B→Option+G 与 open_lazygit 启动实际 lazygit，使用01解析路径及一致环境，不是Tern原生Git视图或假程序。
- 当前cwd保持来源目录，由lazygit识别Git；插件不自动初始化仓库。
- 明确确认lazyGit实际运行环境可用Git；配置Git可用不能代替该环境验证。缺少lazyGit不阻断worktree和临时终端。
- 同源分别复用lazyGit和终端；切换自动收起另一个，不结束程序，不形成嵌套来源。不同来源不串用。
- lazygit正常退出关闭，失败原因可查看；收起／结束／恢复遵循02的同运行期安全契约，重载后旧实例及身份未知的失败卡片交由Tern原生管理，不自动接管或重跑。身份已确认的存活工具在可执行文件消失后仍可恢复结束。
- 原生界面中能观察到真正lazygit内容，快捷键不与旧worktree动作冲突。

## 实施与测试

读取tdd，首个真实lazygit打开失败场景交主线程red后再实现，随后逐个纵向验证交互边界。只用真实工具/可执行副本或链接，不用打印固定文本的mock代替lazygit验收。子代理不跑测试/build/lint/formatter。完成后中文Conventional Commit并合并integration/kiku-assistant tip；集成和green后由集成人resolved。

## Comments

- 2026-10-21：02 已以 `5fc44a8` 集成并完成11组分模式验收，现领取03。沿用同运行期身份验证与安全模式，不重新引入跨重载接管；真实 lazygit 首条 red 场景先交主代理运行。

## Result

- 以 `e5f908a27dbf22675c8f34388c7716444efa9593` 集成到 `integration/kiku-assistant`；仅包含工具生命周期、lazygit 执行桥及真实集成场景四个文件，未纳入用户配置或暂存内容。
- 真实 lazygit 12组通过：`tern-kiku-test-qhi4qcky`（GUI9组）、`tern-kiku-test-u24es6ey`（serve Restart）、`tern-kiku-test-b4shmxg2`／`tern-kiku-test-e0_zsvj1`（分别缺Git／缺lazygit）。已查看真实TUI与失败卡片截图。
- 集成后临时终端11组通过：`tern-kiku-test-hb0phwp2`（Restart）、`tern-kiku-test-8wdgg_vi`（GUI10组，含非本机安全拒绝）。依赖6组、完整worktree83组分别通过 `tern-kiku-test-5l5rik_b`、`tern-kiku-test-b6snyubr`，未带诊断插桩。
- 均为 macOS / Tern 0.9.5 的实际运行；Linux未实测。完整记录见 `docs/verification.md`。
- 最终审查修正 `04ce130` 移除非Git预拒绝，补全配置错误门控并修正切换授权顺序；Standards、Spec及安全复查均无未解决问题，精确竞态间隙仅完成静态确认。
- 最终lazygit12组通过 `tern-kiku-test-l2fd92c1`／`tern-kiku-test-3iusn2bb`／`tern-kiku-test-enxvqamk`／`tern-kiku-test-osjgn8_k`；独立非Git入口另在 `tern-kiku-test-2gtgsrjq` 通过，未知字段／错误类型与两个新入口的4种组合在 `tern-kiku-test-x_o5rlyy` 通过。
- 最终集成后的依赖6组、完整worktree83组分别通过 `tern-kiku-test-fo7hqi9m`、`tern-kiku-test-38z4p3s0`，没有诊断插桩；规范级审查、关票及实施checkout清理已完成。
