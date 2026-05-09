# PowerShell Migration

这是个人 Windows + PowerShell 7 终端环境迁移方案。正式入口只有一个：

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
- npm 全局 CLI
- Git delta 全局配置
- Python / Java 运行时检查
- profile 追加片段，默认不覆盖已有 profile

## 推荐顺序

0. 新电脑先跑语法自检：
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
   ```
1. 先运行 `terminal-setup` 完成基础美化。
2. 运行 `restore.ps1` 做 dry-run 审计。
3. 确认 PATH 预览后运行 `restore.ps1 -FixPath`。
4. 确认缺失工具后运行 `restore.ps1 -Install`。
5. 运行 `restore.ps1 -ApplyGitConfig`。
6. 查看 `restore.ps1 -ShowProfileSnippet`，确认后运行 `restore.ps1 -AppendProfileSnippet`。
7. 关闭所有终端，重新打开 Windows Terminal 验收。

## 新电脑语法报错处理

优先使用：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
```

如果 `pwsh` 还没安装，先用 Windows PowerShell 做解析检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
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

## 验收

详见：

- `docs/acceptance.md`
- `docs/persistence.md`
- `docs/terminal-style.md`
- `docs/runtimes-python-java.md`
