# PowerShell Migration 整改清单

本文档从专业运维与终端美化两个角度，整理当前 `powershell-migration` 项目的建议整改项。

目标不是继续堆安装命令，而是把项目提升为：
- 可重复执行
- 可审计
- 可迁移
- 可持久化验证
- 可验收

## 当前定位

当前项目更接近“个人 Windows PowerShell 终端环境重建脚本”，还不是“低风险、可复用的环境迁移方案”。

已具备的优点：
- 区分了检查模式和执行模式
- 已开始拆分基础终端美化与个人迁移补丁
- 已覆盖 PATH、PowerShell 模块、npm 全局 CLI、git delta、fzf 预览等高频链路

当前主要短板：
- 硬编码路径过多
- 幂等性不足
- 持久化行为说明不足
- 终端美化缺少验收标准
- `pyenv` 只做了 PATH 补丁，运行时恢复不完整
- Java 运行时管理还未纳入设计

## P0：先解决的高优先级问题

### 1. 明确唯一正式入口脚本

- 目标：只保留一个“正式入口”脚本。
- 建议：
  - `restore-terminal-combined.ps1` 作为正式入口
  - `restore-draft.ps1` 标记为草稿、历史版本，或后续删除
- 原因：避免维护时出现“双入口、双逻辑源”的漂移问题。

### 2. 把硬编码路径集中到配置区

- 目标：不要在脚本正文中散落 `D:\tools`、`D:\work`、`D:\codexwork` 等机器路径。
- 建议整理成集中配置项：
  - `ToolsRoot`
  - `CliBinPath`
  - `FzfPath`
  - `NodePath`
  - `PyenvRoot`
  - `JadxPath`
  - `X64dbgPath`
  - `IdaPath`
  - `ThemePath`
  - `BackupRoot`
- 原因：换盘符、换目录、换机器时只改一处。

### 3. 限制别名/函数覆盖的作用域

- 当前风险：`cat`、`grep` 被直接重定义。
- 建议：
  - 只在交互式 shell 中定义这些函数
  - 或改为新的命令名，而不是覆盖系统常用名
- 典型候选：
  - `batcat`
  - `rgrep`
  - `lg`
  - `ff`
  - `ffd`
- 原因：避免脚本、模块、远程会话被非预期行为污染。

### 4. 去掉核心执行路径中的 `Invoke-Expression`

- 目标：减少命令拼接执行。
- 建议：
  - 能用直接命令调用的地方就不用字符串命令
  - 对带空格路径、复杂参数的命令优先使用参数数组或原生命令调用
- 原因：
  - 更稳
  - 更容易排错
  - 更容易处理引号和转义

### 5. PATH 修复必须补“变更预览”

- 当前已有：
  - 备份 User PATH
  - 重写 User PATH
  - 立即刷新当前会话 PATH
- 还应补充：
  - 变更前 PATH 顺序摘要
  - 变更后 PATH 顺序摘要
  - 哪些条目被前置/后置
  - 哪些条目不存在
  - 哪些命令解析路径发生变化
- 原因：PATH 调整属于高影响动作，必须可审计。

## P1：结构与可维护性改造

### 6. 增加 README

- README 应至少包含：
  - 项目目标
  - 支持范围
  - 唯一正式入口
  - 推荐执行顺序
  - 风险说明
  - 持久化说明
  - 字体要求
  - 验收步骤

### 7. 明确配置层与执行层分离

- 建议结构：
  - 一层只存配置
  - 一层负责检查/安装/修复
  - 一层负责 profile 片段输出
  - 一层负责验收
- 原因：以后补工具、换路径、替换主题时不需要改执行逻辑。

### 8. 补足幂等性说明与检查

- 需要为每类动作明确：
  - 已安装是否跳过
  - 已配置是否跳过
  - 重复执行是否安全
- 当前应重点补幂等检查的区域：
  - npm 全局包
  - PowerShell 模块
  - git 全局配置
  - profile 片段追加

### 9. 统一脚本职责

- 当前不一致点：
  - 一个脚本负责完整模块清单
  - 另一个脚本假设基础美化由外部项目负责
- 建议：
  - 在正式入口中明确哪些能力由 `terminal-setup` 托管
  - 明确本项目只负责哪些增量
- 原因：避免职责边界模糊。

## P1：持久化与环境变量说明

### 10. 补“作用域与重启后行为”章节

- 需要明确区分：
  - 当前进程临时变量
  - 当前用户持久化配置
  - 全机持久化配置
  - 终端程序自己的配置
- README 里建议明确写清楚：
  - `$env:Path = ...` 只影响当前 shell
  - `[Environment]::SetEnvironmentVariable('Path', ..., 'User')` 会持久化到当前用户，重启后仍有效
  - PowerShell profile 会在每次新开 PowerShell 时重新加载
  - `git config --global` 为用户级持久化配置
  - `Install-Module -Scope CurrentUser` 为当前用户持久化安装

### 11. 增加“重启后验收”步骤

- 至少分两轮验证：
  - 关闭所有终端，重新打开 Windows Terminal 验证
  - 重启电脑后再次验证
- 验收命令建议：
  - `Get-Command rg,bat,fd,git,gh,oh-my-posh`
  - `Get-ChildItem`
  - `git status`
  - `python --version`
  - `java -version`
  - `echo $env:Path`

## P1：终端美化与字体体系

### 12. 明确 Nerd Font 要求

- 结论：`oh-my-posh`、`Terminal-Icons`、带图标的 prompt 基本依赖 Nerd Font。
- README 应明确：
  - 需要安装 Nerd Font
  - Windows Terminal 必须设置为对应字体
  - 字体未正确配置时，图标显示异常不算“恢复成功”

### 13. 指定推荐字体

- 建议选一个默认推荐项并固定：
  - `JetBrainsMono Nerd Font`
  - 或 `CaskaydiaCove Nerd Font`
- 不建议让项目长期停留在“你自己记得装那个图标字体”的状态。

### 14. 把终端外观也纳入验收

- 建议补充检查项：
  - prompt 图标是否正常
  - `Terminal-Icons` 图标是否正常
  - Git 分支图标是否正常
  - Windows Terminal 字体是否是指定 Nerd Font
  - 主题文件是否存在且被正确加载

### 15. 主题资产要单独归档

- 当前关键资产：`minimal.omp.json`
- 建议：
  - 明确其来源和用途
  - 明确它是手工文件还是项目受管文件
  - 如果是项目资产，应该纳入版本管理或给出明确拷贝路径

## P1：运行时管理（Python / Java）

### 16. 把 `pyenv` 从“PATH 补丁”升级为正式能力

- 当前状态：只加入了 `pyenv-win` 的 PATH，尚未形成完整恢复逻辑。
- 应补内容：
  - `pyenv-win` 是否安装检查
  - `pyenv-win\bin` / `pyenv-win\shims` 是否进 User PATH
  - 默认 Python 版本检查
  - `python` / `pip` / `uv` / `uvx` 命中路径检查
  - 常用 Python 工具链恢复策略说明

### 17. 增加 Python 验收项

- 建议至少验证：
  - `pyenv --version`
  - `pyenv version`
  - `python --version`
  - `pip --version`
  - `uv --version`
  - `Get-Command python,pip,uv`

### 18. Java 运行时管理要纳入方案

- 需要决定：
  - 是坚持 `jenv`
  - 还是采用更适合 Windows PowerShell 的 Java 版本管理方式
- 当前项目至少应补：
  - `java` / `javac` 检查
  - `JAVA_HOME` 检查
  - Java 路径持久化策略
  - 重启后验收逻辑

### 19. Java 方案建议

- 如果主要运行环境是 Windows PowerShell：
  - 优先考虑 `JAVA_HOME + 固定 JDK 目录 + 切换脚本`
  - 或使用更适合 Windows 的 Java 管理工具
- 如果主要运行环境是 WSL / bash / zsh：
  - 再考虑 `jenv`
- 建议不要在设计未定之前直接把 `jenv` 生搬到现有脚本里。

## P2：执行体验与运维交付质量

### 20. 增加失败处理策略

- 每类失败都应有说明：
  - winget 失败怎么办
  - 模块安装失败怎么办
  - npm 全局包失败怎么办
  - PATH 改完解析不对怎么办
  - 字体已装但图标仍异常怎么办

### 21. 增加执行摘要/日志输出

- 建议最终输出至少包含：
  - 已满足项
  - 缺失项
  - 已变更项
  - 失败项
  - 需要手动处理项
- 原因：便于迁移后回看，也便于二次执行。

### 22. 增加 profile 管理策略

- 需要明确：
  - 当前 profile 是否可直接覆盖
  - 还是只允许 append 片段
  - 如何避免重复追加同一段内容
- 建议提供：
  - 安全追加模式
  - 重复检测逻辑

### 23. 补全外部依赖说明

- 当前依赖但尚未完全文档化的内容：
  - `terminal-setup` 项目
  - `minimal.omp.json`
  - Everything `es.exe` / `es1` 工作流
  - 可选的 Python/Java 运行时工具

## 推荐目录结构草案

建议未来整理成：

```text
powershell-migration/
  README.md
  IMPROVEMENT_CHECKLIST.md
  restore.ps1
  config.ps1
  docs/
    acceptance.md
    persistence.md
    terminal-style.md
    runtimes-python-java.md
```

说明：
- `restore.ps1`：唯一正式入口
- `config.ps1`：所有机器相关路径、主题路径、字体名、备份目录、PATH 优先级
- `docs/acceptance.md`：执行后验收
- `docs/persistence.md`：环境变量与持久化行为
- `docs/terminal-style.md`：字体、主题、外观要求
- `docs/runtimes-python-java.md`：`pyenv` 与 Java 运行时管理

## 推荐执行顺序

1. 先收敛主入口脚本，只保留一个正式入口。
2. 抽离所有路径与主题配置。
3. 修复别名覆盖与 `Invoke-Expression` 风险。
4. 给 PATH 修复补变更预览和摘要。
5. 补 README 与持久化说明。
6. 补 Nerd Font 与终端外观验收。
7. 把 `pyenv` 做完整，把 Java 运行时方案定下来。
8. 最后补日志、失败处理和重启后验收。

## 最终验收目标

完成整改后，这个项目应当达到以下标准：

- 新机器上可按固定顺序执行
- 关键行为有副作用说明
- PATH 与 profile 改动可追踪
- PowerShell 7、Git、fzf、bat、fd、rg、delta、zoxide 可正确解析
- `oh-my-posh` 与 `Terminal-Icons` 视觉效果稳定
- Nerd Font 配置明确且可验证
- `pyenv` 与 Python 工具链可恢复
- Java 运行时管理方案明确
- 重开终端与重启电脑后行为一致
