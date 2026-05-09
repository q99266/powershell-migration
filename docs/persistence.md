# 持久化说明

## PATH

`restore.ps1 -FixPath` 修改的是当前用户 PATH：

```powershell
[Environment]::SetEnvironmentVariable('Path', ..., 'User')
```

脚本会先备份原始 User PATH 到：

```text
D:\codexwork\powershell-migration\backups
```

当前进程 PATH 会立即刷新，但已经打开的其他终端不会自动刷新。

## Profile

`restore.ps1 -AppendProfileSnippet` 只追加带 marker 的片段：

```text
# >>> powershell-migration extras >>>
# <<< powershell-migration extras <<<
```

重复执行会检测 marker，避免重复追加。

## Git

`restore.ps1 -ApplyGitConfig` 使用 `git config --global`，属于当前用户级持久化配置。

## PowerShell 模块

模块使用 `Install-Module -Scope CurrentUser` 安装，属于当前用户持久化安装。
