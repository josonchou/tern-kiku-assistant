# 04 插件命名与使用文档

Status: ready-for-agent
Type: task
Blocked by: none
Spec: ../spec.md

## 目标

将显示名与README统一为 Kiku 助手 / Kiku Assistant / tern-kiku-assistant，说明全部已确认本机功能和程序配置，不变更稳定插件ID及实际仓库位置。

## 文件边界

仅 plugin.toml、README.md。不得修改window.luau、任何lib/tests、config.json、docs/design.md、GLOSSARY.md、任务状态或其他文件。

## 契约与验收

- plugin id仍kiku，名称Kiku助手（实际显示字符串“Kiku 助手”），描述准确覆盖worktree与快捷工具。
- README名称、安装示例、命令、四组快捷键、路径配置示例与spec一致；本地目录/远端仓库不实际重命名，不能声称已发布远端地址。
- 明确仅本机支持，未来统一远程；第三方依赖门控、手动路径→PATH回退、realpath独立限制、非Git终端、收起vs结束与恢复、原生小浮窗差异均说明。
- 保留原worktree安全说明、验证命令和旧配置语义；config示例不是要求覆盖用户配置。
- 不做名称文案精确断言测试。集成后用真实插件加载与界面观察验证清单合法和名称可见。

## 实施与测试

读取tdd技能，但此票据仅命名与说明，不写无行为价值的措辞测试，也不运行测试/build/lint/formatter。先核对README现状再局部修改。中文Conventional Commit，报告前合并integration/kiku-assistant tip。集成和原生加载通过后由集成人resolved。

## Comments
