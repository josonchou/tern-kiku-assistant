# 03 lazygit 与双工具切换

Status: ready-for-agent
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
