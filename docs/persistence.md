# 持久化说明

## PATH

`migrate.ps1 -FixPath` 修改的是当前用户 PATH：

```powershell
[Environment]::SetEnvironmentVariable('Path', ..., 'User')
```

脚本会先备份原始 User PATH 到：

```text
D:\codexwork\powershell-migration\backups
```

当前进程 PATH 会立即刷新，但已经打开的其他终端不会自动刷新。

## Profile

`migrate.ps1 -AppendProfileSnippet` 只追加带 marker 的片段：

```text
# >>> powershell-migration extras >>>
# <<< powershell-migration extras <<<
```

重复执行会检测 marker，避免重复追加。

## Git

`migrate.ps1 -ApplyGitConfig` 使用 `git config --global`，属于当前用户级持久化配置。

## PowerShell 模块

模块使用 `Install-Module -Scope CurrentUser` 安装，属于当前用户持久化安装。

## 下载源

- `winget` 使用 `config.ps1` 中的 `WingetSource`，并按 `NetworkRetryCount` 重试；winget 没有在本项目中配置伪国内镜像。
- Windows Terminal 缺失时，`migrate.ps1 -Install` 会通过 winget 安装 `Microsoft.WindowsTerminal`。
- nvm-windows 通过 winget 安装到 `D:\tools\nvm`，并设置 `NVM_HOME=D:\tools\nvm`、`NVM_SYMLINK=D:\tools\nodejs`。
- pyenv-win 通过内置 GitHub ZIP 下载源安装到 `D:\tools\pyenv`。
- JEnv for Windows 通过内置 GitHub ZIP 下载源安装到 `D:\tools\jenv`。
- npm 安装使用脚本内置 registry fallback。默认先使用当前 npm 配置，失败后尝试 `https://registry.npmmirror.com`；传入 `-UseChinaMirrors` 时优先尝试 npmmirror，再回退当前 npm 配置。
- PowerShell 模块安装会使用 `PowerShellGallery` 配置项，先尝试把仓库设为 trusted，失败后按 `NetworkRetryCount` 重试。
- Nerd Font 下载内置多个 URL 候选。默认先尝试 GitHub release，失败后自动尝试加速代理；传入 `-UseChinaMirrors` 时优先尝试加速代理。
- PowerShell Gallery 没有在脚本中自动替换为镜像源；网络失败时应手工处理 PSGallery、代理或离线安装。

## Windows Terminal

如果 Windows Terminal `settings.json` 不存在，`migrate.ps1 -Install` 会创建最小配置：

```json
{
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
  "profiles": {
    "defaults": {
      "font": {
        "face": "CaskaydiaCove Nerd Font"
      }
    }
  }
}
```

`defaultProfile` 使用 PowerShell 7 的 Windows Terminal fallback GUID。后续运行 `migrate.ps1 -SetWindowsTerminalDefaultPwsh` 时会备份并更新同一个 `settings.json`。

## 字体

`migrate.ps1 -InstallNerdFont` 是当前用户级安装：

- 字体文件复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
- 字体注册写入 `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`

`migrate.ps1 -SetWindowsTerminalFont` 会备份 Windows Terminal `settings.json`，然后设置：

```json
"profiles": {
  "defaults": {
    "font": {
      "face": "CaskaydiaCove Nerd Font"
    }
  }
}
```
