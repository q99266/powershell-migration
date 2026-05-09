# 终端美化说明

基础美化由仓库内 bundled `terminal-setup/setup-terminal-en.ps1` 托管。本项目不覆盖它生成的 profile。

## 字体

推荐：

```text
CaskaydiaCove Nerd Font
```

字体未正确设置时，`oh-my-posh` 和 `Terminal-Icons` 的图标可能显示为方块或乱码。

本项目可以自己完成字体闭环，不需要用户手动添加下载源：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont
```

`terminal-setup/setup-terminal-en.ps1` 中的字体安装交互只作为 fallback。正式迁移时优先使用上面的命令，因为它使用当前用户字体目录和脚本内置下载 fallback。

脚本内置 GitHub release 和多个 GitHub 加速代理。默认自动逐个尝试；国内网络不稳时可以加 `-UseChinaMirrors`，脚本会把加速源排到前面：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont -UseChinaMirrors
```

字体安装为当前用户级操作：复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`，并写入 `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`。设置 Windows Terminal 字体前会备份 `settings.json`。

## 主题

当前关键主题文件：

```text
C:\Users\DP\Documents\PowerShell\themes\minimal.omp.json
```

迁移新电脑时需要复制该文件，或运行 bundled `terminal-setup/setup-terminal-en.ps1` 重新生成。

## Profile 策略

bundled `terminal-setup/setup-terminal-en.ps1` 负责基础 profile。

`migrate.ps1` 只追加迁移增量：

- `PSFzf`
- `zoxide`
- `fzf` 默认参数
- `batcat` / `rgrep` / `lg` / `ff` / `ffd` / `es1`

默认不覆盖 `cat` / `grep`，需要时可使用 `-AcceptProfileCommandOverrides` 生成覆盖版片段。
