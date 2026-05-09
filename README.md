# PowerShell Migration

这是个人 Windows + PowerShell 7 终端环境迁移方案。默认按 `D:\tools`、`D:\work`、`D:\codexwork` 这套布局恢复；基础美化脚本已随仓库放在 `terminal-setup/`，只有新电脑沿用同一套目录布局和资产位置时，通常才不需要先改 `config.ps1`。

总入口只有一个：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1
```

`migrate.ps1` 会先做语法预检，再调用内部实现 `restore.ps1`。日常迁移只跑 `migrate.ps1`；`restore.ps1` 是内部实现，不作为用户入口。`restore-draft.ps1` 和 `restore-terminal-combined.ps1` 是历史脚本，保留作参考。

## 职责边界

仓库内 bundled `terminal-setup/setup-terminal-en.ps1` 负责基础美化：

- `oh-my-posh`
- `PSReadLine`
- `Terminal-Icons`
- `z`
- Windows Terminal 字体与主题

本项目负责迁移增量：

- PATH 顺序修复与备份
- `fzf` / `PSFzf`
- `bat` / `fd` / `rg` / `jq` / `delta` / `lazygit` / `zoxide` / `es.exe`
- npm 全局 CLI（先检测，缺失才安装，避免无差别升级）
- Git delta 全局配置
- nvm-windows / pyenv-win / JEnv for Windows 版本管理器安装与 PATH 规划
- Python 运行时检查，不强行安装具体 Python 版本
- Java 运行时检查，不强行切换具体 JDK 版本
- Windows Terminal 安装检测、最小 settings 初始化、默认 PowerShell 7 profile 设置
- Nerd Font 下载、当前用户安装、Windows Terminal 默认字体设置
- profile 追加片段，默认不覆盖已有 profile

## 推荐顺序

0. 先快速扫一眼 `config.ps1`。如果你沿用本项目的完整默认布局，通常可以不改；如果新电脑没有 D 盘、工具目录不同、PowerShell 主题文件不在默认位置，先改配置再跑。
1. 新电脑先跑语法自检：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -TestSyntax
   ```
   如果 `pwsh` 还没有安装，先用 Windows PowerShell 跑：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -TestSyntax
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -Install
   ```
   该流程只做 bootstrap：安装 `Microsoft.PowerShell` 后会停止后续阶段。安装完成后必须重新打开 PowerShell 7，再继续执行本脚本。
2. 先运行 bundled `terminal-setup/setup-terminal-en.ps1` 完成基础美化。该脚本是交互式脚本，按提示确认即可：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -RunTerminalSetup
   ```
3. 运行 `migrate.ps1` 做 dry-run 审计。
4. 确认缺失工具后运行 `migrate.ps1 -Install`。这一步也会安装 Windows Terminal，并在缺失时创建最小 `settings.json`。脚本会在 winget 安装后刷新当前进程的临时 PATH，然后继续后续检查和配置；如果个别安装器仍未让命令在当前进程可见，按输出提示重开 PowerShell 7 / Windows Terminal 后再跑一次 dry-run。
5. 如果 Windows Terminal 默认 profile 不是 PowerShell 7，确认后运行：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -SetWindowsTerminalDefaultPwsh
   ```
6. 安装 Nerd Font 并设置 Windows Terminal 默认字体：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont
   ```
   `terminal-setup` 里的字体安装交互只作为 fallback；推荐用本命令，因为它使用当前用户字体安装和内置下载 fallback。
7. 确认 PATH 预览后运行 `migrate.ps1 -FixPath`。
8. 运行 `migrate.ps1 -ApplyGitConfig`。
9. 查看 `migrate.ps1 -ShowProfileSnippet`，确认后运行 `migrate.ps1 -AppendProfileSnippet`。
10. 关闭所有终端，重新打开 Windows Terminal 验收。

## 封版原则

封版后只做三类维护：

- 修 bug。
- 补文档。
- 调整个人路径或版本号。

不要继续扩展新的语言管理器、终端主题系统或下载镜像策略。这个仓库的定位是恢复个人 PowerShell / Windows Terminal 日常体验，不是继续长成全语言装机平台。

## 真实演练清单

封版前按下面顺序做最后演练：

1. 无修改 dry-run：`migrate.ps1` 默认审计应不产生持久化改动。
2. Bootstrap 流程：在没有 `pwsh` 的新机上，用 Windows PowerShell 运行 `migrate.ps1 -Install`，脚本应只安装 PowerShell 7 并提示重开 `pwsh`。
3. 完整安装流程：重开 PowerShell 7 后运行 `migrate.ps1 -Install`，安装缺失 CLI、Windows Terminal、运行时管理器和模块。
4. 样式流程：运行 `migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont`，必要时再运行 `migrate.ps1 -SetWindowsTerminalDefaultPwsh`。
5. 持久化流程：审计 PATH 后运行 `migrate.ps1 -FixPath`，再运行 `migrate.ps1 -ApplyGitConfig` 和 `migrate.ps1 -AppendProfileSnippet`。
6. 重开 Windows Terminal 后执行 `docs/acceptance.md`。
7. 重启电脑后再次执行 `docs/acceptance.md`。

## 迁移边界

本项目不是通用装机脚本，也不是企业级无交互装机器。它是面向个人环境的高质量半自动恢复器：默认按作者的 D 盘布局恢复终端体验，尽量把可自动化的安装、PATH、profile、字体和 Git 配置做掉；遇到 Windows Terminal 动态 profile、winget 安装器刷新、具体 Python/JDK 版本选择这类环境相关点，会审计、提示并要求复跑或人工确认。`config.ps1` 是集中配置入口，不是每次迁移前都必须改，但也不能只看“有 D 盘”就跳过。

尤其要确认这些路径是否沿用：

- `D:\codexwork\powershell-migration\terminal-setup\setup-terminal-en.ps1`
- `D:\tools\nvm`
- `D:\tools\pyenv\pyenv-win`
- `D:\tools\jenv`
- `C:\Users\DP\Documents\PowerShell\themes\minimal.omp.json`

Java 当前会安装/检查 JEnv 管理器，并报告 `JAVA_HOME`、`java`、`javac` 的解析状态；脚本不会强行设置 `JAVA_HOME`，也不会切换具体 JDK 版本。

运行时版本管理器会自动安装/配置到 D 盘默认布局：

- `nvm-windows`：`D:\tools\nvm`，Node symlink 为 `D:\tools\nodejs`，默认启用 `24.14.1`。
- `pyenv-win`：`D:\tools\pyenv\pyenv-win`。
- `JEnv for Windows`：`D:\tools\jenv`。

三套管理器的闭环程度不一样：`nvm-windows` 会安装管理器、配置 D 盘目录，并安装/启用默认 Node 版本；`pyenv-win` 只安装管理器和 PATH，不强行安装 Python 版本；`JEnv for Windows` 只安装管理器和 PATH，真实 Java 可用性仍依赖后续 `jenv add/change/use` 或固定 `JAVA_HOME` 策略。

Windows Terminal 现在属于 baseline：总入口会检测 `wt` 命令和 `settings.json`。传入 `-Install` 时，如果 Windows Terminal 缺失，会通过 winget 安装 `Microsoft.WindowsTerminal`；如果 `settings.json` 尚未生成，会创建一个最小配置，默认 profile 指向 PowerShell 7 fallback GUID，并预写 Nerd Font 默认字体。正式判断默认 shell 时，脚本优先读取 `profiles.list` 里的真实 PowerShell 7 profile；fallback GUID 只作为 bootstrap 线索，不再当作“已经验证成功”。默认 shell 修改仍然只有传入 `-SetWindowsTerminalDefaultPwsh` 才会备份并持久化。

PowerShell 7 安装采用两阶段策略：如果当前机器还没有 `pwsh`，`migrate.ps1 -Install` 只安装 PowerShell 7 并停止，避免同一轮继续调用尚未出现在当前进程 PATH 中的 `pwsh`。

winget 安装普通 CLI 后，本脚本会从 User/Machine PATH 和本项目 D 盘规划刷新当前进程的临时 PATH，尽量让 `git`、`gh`、`fd`、`bat`、`rg` 等命令在同一轮后续步骤里可见。少数安装器需要新 shell 才能完成 App Execution Alias 或安装目录刷新；遇到这种情况，重开 PowerShell 7 / Windows Terminal 后再运行 `migrate.ps1` 做审计和后续配置。

下载源策略：

- `winget` 使用 `config.ps1` 中的 `WingetSource`，默认是官方 `winget` 源。本项目不伪造 winget 国内镜像；安装失败会按 `NetworkRetryCount` 重试。
- Windows Terminal 通过 winget 包 `Microsoft.WindowsTerminal` 安装；安装后当前进程如果还看不到 `wt`，重开 Windows Terminal / PowerShell 7 后继续跑脚本。
- nvm-windows 通过 winget 包 `CoreyButler.NVMforWindows` 安装，并修正 `NVM_HOME` / `NVM_SYMLINK` 到 D 盘布局。
- pyenv-win 与 JEnv for Windows 使用脚本内置 GitHub ZIP 下载源和加速代理 fallback。
- npm 全局包内置 registry fallback：默认先走当前 npm 配置，失败再走 `https://registry.npmmirror.com`；传入 `-UseChinaMirrors` 时优先走 npmmirror，再回退到当前 npm 配置。
- PowerShell 模块安装固定使用 `PowerShellGallery` 配置项，脚本会先尝试信任该仓库，安装失败会按 `NetworkRetryCount` 重试。
- Nerd Font 内置多个下载候选：GitHub release 和若干 GitHub 加速代理。默认会自动逐个尝试；`-UseChinaMirrors` 只是把加速源排到前面。
- PowerShell Gallery 暂不自动切换镜像；模块安装失败时需要人工处理网络或 PSGallery 信任/代理。

## 新电脑语法报错处理

优先使用：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -TestSyntax
```

如果 `pwsh` 还没安装，先用 Windows PowerShell 做解析检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -TestSyntax
```

安装 PowerShell 7：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -Install
```

安装完成后打开新的 PowerShell 7：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1
```

国内 npm 网络较慢时：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -Install -UseChinaMirrors
```

国内 GitHub 字体下载较慢时，脚本会自动尝试内置加速源；你也可以显式让加速源优先：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont -UseChinaMirrors
```

常见原因：

- 文件不是 UTF-8 或被错误转码。
- profile 里存在未闭合字符串。
- PowerShell 版本过旧。
- 从网页/聊天复制脚本时混入不可见字符。
- 执行策略阻止脚本加载。

## 版本管理器用法

本项目默认安装三套运行时版本管理器：

```text
nvm-windows: D:\tools\nvm
Node symlink: D:\tools\nodejs
pyenv-win:   D:\tools\pyenv\pyenv-win
JEnv:        D:\tools\jenv
```

### nvm / Node.js

常用命令：

```powershell
nvm version
nvm list
nvm install 24.14.1
nvm use 24.14.1
node -v
npm -v
```

本项目默认配置：

```text
NVM_HOME=D:\tools\nvm
NVM_SYMLINK=D:\tools\nodejs
```

新开终端后，`node` 和 `npm` 应该从 `D:\tools\nodejs` 解析。

### pyenv-win / Python

常用命令：

```powershell
pyenv --version
pyenv versions
pyenv install 3.13.13
pyenv global 3.13.13
pyenv rehash
python --version
pip --version
```

本项目只安装/配置 `pyenv-win` 和 PATH，不强行安装或切换具体 Python 版本。

### JEnv / Java

常用命令：

```powershell
jenv list
jenv add jdk11 D:\tools\jdk11
jenv add jdk21 D:\tools\jdk21
jenv change jdk21
jenv use jdk11
java -version
javac -version
```

`jenv change` 是全局切换，`jenv use` 是当前 shell 临时切换。本项目安装/配置 JEnv 管理器，但不强行切换具体 JDK。

## 持久化说明

- `$env:Path = ...` 只影响当前 shell。
- `[Environment]::SetEnvironmentVariable('Path', ..., 'User')` 会持久化当前用户 PATH，重开终端后生效。
- `Install-Module -Scope CurrentUser` 是当前用户持久化安装。
- `git config --global` 是当前用户级 Git 配置。
- PowerShell profile 会在每次新开 PowerShell 时加载。

## 字体要求

推荐字体：`CaskaydiaCove Nerd Font`。

`oh-my-posh`、`Terminal-Icons` 和 prompt 图标依赖 Nerd Font。字体没配好时，图标异常不算恢复成功。

字体安装是当前用户级操作：脚本会下载 `CaskaydiaCove.zip`，解压 `.ttf/.otf` 到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`，写入 `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`，然后可选修改 Windows Terminal `profiles.defaults.font.face`。

## 验收

详见：

- `docs/acceptance.md`
- `docs/persistence.md`
- `docs/terminal-style.md`
- `docs/runtimes-python-java.md`
