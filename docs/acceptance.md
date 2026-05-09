# 验收步骤

## 第一轮：重开终端

关闭所有 PowerShell / Windows Terminal 窗口，重新打开 PowerShell 7。

先执行语法自检：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
```

确认 `config.ps1` 的路径适配当前机器后，再执行：

执行：

```powershell
Get-Command pwsh
Get-Command rg,bat,fd,git,gh,oh-my-posh,fzf,zoxide,delta
Get-Command python,pip,uv,java,javac
$settings = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Raw | ConvertFrom-Json
$settings.defaultProfile
$settings.profiles.list | Where-Object { $_.guid -eq $settings.defaultProfile } | Select-Object name,commandline,source
$settings.profiles.defaults.font.face
git status
python --version
java -version
echo $env:Path
```

如果第一阶段是用 Windows PowerShell 5.1 安装 PowerShell 7，必须关闭旧窗口，打开新的 PowerShell 7 后再执行上述验收。

## 第二轮：重启后验证

重启电脑后重复第一轮命令。

## 外观验收

- prompt 图标正常显示。
- `Get-ChildItem` 图标正常显示。
- Git 仓库中能看到分支/状态提示。
- Windows Terminal 字体为指定 Nerd Font。
- Windows Terminal 默认 profile 是 PowerShell 7，而不是 Windows PowerShell 5.1 或其他 shell。
- Windows Terminal `profiles.defaults.font.face` 为 `CaskaydiaCove Nerd Font` 或你在 `config.ps1` 中指定的 Nerd Font。
- `minimal.omp.json` 存在且被加载。
