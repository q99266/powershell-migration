# PowerShell Migration

这是个人 Windows + PowerShell 7 终端环境迁移方案。默认配置绑定作者当前机器路径；迁移到新电脑前，先检查并按需修改 `config.ps1`。

正式入口只有一个：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1
```

`restore-draft.ps1` 和 `restore-terminal-combined.ps1` 是历史脚本，保留作参考，不再作为正式入口。

## 职责边界

`terminal-setup` 负责基础美化：

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
- Python 运行时检查
- Java 运行时只审计，不自动迁移
- Nerd Font 下载、当前用户安装、Windows Terminal 默认字体设置
- profile 追加片段，默认不覆盖已有 profile

## 推荐顺序

0. 新电脑先打开 `config.ps1`，确认 `ProjectRoot`、`ToolsRoot`、`TerminalSetupRoot`、`ThemePath`、PATH 优先级等路径是否符合新机器。
1. 新电脑先跑语法自检：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
   ```
   如果 `pwsh` 还没有安装，先用 Windows PowerShell 跑：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -Install
   ```
   该流程只做 bootstrap：安装 `Microsoft.PowerShell` 后会停止后续阶段。安装完成后必须重新打开 PowerShell 7，再继续执行本脚本。
2. 先运行 `terminal-setup` 完成基础美化。
3. 运行 `restore.ps1` 做 dry-run 审计。
4. 如果 Windows Terminal 默认 profile 不是 PowerShell 7，确认后运行：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -SetWindowsTerminalDefaultPwsh
   ```
5. 安装 Nerd Font 并设置 Windows Terminal 默认字体：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -InstallNerdFont -SetWindowsTerminalFont
   ```
6. 确认 PATH 预览后运行 `restore.ps1 -FixPath`。
7. 确认缺失工具后运行 `restore.ps1 -Install`。
8. 运行 `restore.ps1 -ApplyGitConfig`。
9. 查看 `restore.ps1 -ShowProfileSnippet`，确认后运行 `restore.ps1 -AppendProfileSnippet`。
10. 关闭所有终端，重新打开 Windows Terminal 验收。

## 迁移边界

本项目不是通用装机脚本。它以 `config.ps1` 为配置入口，默认路径适配作者当前机器。

Java 当前只有审计能力：脚本会报告 `JAVA_HOME`、`java`、`javac` 的解析状态，但不会设置 `JAVA_HOME`，也不会把 `JavaBinPath` 写入 PATH。若后续要做 Java 迁移，需要先确定固定 JDK 目录或版本管理方案。

Windows Terminal 默认 shell 当前有显式审计和可选修复能力：默认只报告，只有传入 `-SetWindowsTerminalDefaultPwsh` 才会备份并修改 Windows Terminal `settings.json` 的 `defaultProfile`。

PowerShell 7 安装采用两阶段策略：如果当前机器还没有 `pwsh`，`restore.ps1 -Install` 只安装 PowerShell 7 并停止，避免同一轮继续调用尚未出现在当前进程 PATH 中的 `pwsh`。

下载源策略：

- `winget` 使用 `config.ps1` 中的 `WingetSource`，默认是官方 `winget` 源。本项目不伪造 winget 国内镜像；安装失败会按 `NetworkRetryCount` 重试。
- npm 全局包内置 registry fallback：默认先走当前 npm 配置，失败再走 `https://registry.npmmirror.com`；传入 `-UseChinaMirrors` 时优先走 npmmirror，再回退到当前 npm 配置。
- PowerShell 模块安装固定使用 `PowerShellGallery` 配置项，脚本会先尝试信任该仓库，安装失败会按 `NetworkRetryCount` 重试。
- Nerd Font 内置多个下载候选：GitHub release 和若干 GitHub 加速代理。默认会自动逐个尝试；`-UseChinaMirrors` 只是把加速源排到前面。
- PowerShell Gallery 暂不自动切换镜像；模块安装失败时需要人工处理网络或 PSGallery 信任/代理。

## 新电脑语法报错处理

优先使用：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
```

如果 `pwsh` 还没安装，先用 Windows PowerShell 做解析检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
```

安装 PowerShell 7：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -Install
```

安装完成后打开新的 PowerShell 7：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1
```

国内 npm 网络较慢时：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -Install -UseChinaMirrors
```

国内 GitHub 字体下载较慢时，脚本会自动尝试内置加速源；你也可以显式让加速源优先：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -InstallNerdFont -SetWindowsTerminalFont -UseChinaMirrors
```

常见原因：

- 文件不是 UTF-8 或被错误转码。
- profile 里存在未闭合字符串。
- PowerShell 版本过旧。
- 从网页/聊天复制脚本时混入不可见字符。
- 执行策略阻止脚本加载。

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
