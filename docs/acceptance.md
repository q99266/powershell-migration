# 验收步骤

## 第一轮：重开终端

关闭所有 PowerShell / Windows Terminal 窗口，重新打开 PowerShell 7。

先执行语法自检：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\migrate.ps1 -TestSyntax
```

如果新电脑沿用完整默认布局，可以继续执行；如果工具目录、`terminal-setup` 路径、主题文件位置或 D 盘布局不同，先调整 `config.ps1`。

## 已可调用

```powershell
Get-Command pwsh
Get-Command wt
Get-Command rg,bat,fd,git,gh,oh-my-posh,fzf,zoxide,delta
Get-Command nvm,node,npm
Get-Command pyenv,python,pip,uv
Get-Command jenv,java,javac
```

## 已安装 / 已配置

```powershell
nvm list
pyenv version
jenv list
git config --global --get core.pager
git config --global --get interactive.diffFilter
git config --global --get delta.navigate
git config --global --get merge.conflictstyle
Test-Path C:\Users\DP\Documents\PowerShell\themes\minimal.omp.json
```

## 已是默认

```powershell
$settings = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Raw | ConvertFrom-Json
$settings.defaultProfile
$settings.profiles.list | Where-Object { $_.guid -eq $settings.defaultProfile } | Select-Object name,commandline,source
$settings.profiles.defaults.font.face
```

默认 profile 应该解析为 PowerShell 7，而不是 Windows PowerShell 5.1 或其他 shell。字体应为 `CaskaydiaCove Nerd Font` 或你在 `config.ps1` 中指定的 Nerd Font。

## 运行时版本

```powershell
git status
node -v
npm -v
python --version
java -version
javac -version
echo $env:JAVA_HOME
echo $env:Path
```

如果第一阶段是用 Windows PowerShell 5.1 安装 PowerShell 7，必须关闭旧窗口，打开新的 PowerShell 7 后再执行上述验收。

如果第一阶段安装了 Windows Terminal，也建议关闭旧窗口，重新打开 Windows Terminal 后再验收 `wt`、默认 profile 和字体设置。

## 第二轮：重启后验证

重启电脑后重复第一轮命令。

## 外观验收

- prompt 图标正常显示。
- `Get-ChildItem` 图标正常显示。
- Git 仓库中能看到分支/状态提示。
- `oh-my-posh` / `Terminal-Icons` 图标不是方块或乱码。

## 边界确认

- `terminal-setup` 仍是外部依赖；基础美化不由本项目重写。
- `minimal.omp.json` 必须存在，来源可以是复制旧机器文件，也可以由 `terminal-setup` 重建。
- `pyenv-win` 只证明管理器可用；具体 Python 版本是否安装由 `pyenv version`、`python --version`、`pip --version` 验证。
- `JEnv for Windows` 只证明管理器可用；具体 JDK 是否可用由 `java -version`、`javac -version`、`JAVA_HOME` 和 `jenv list` 验证。
- Windows Terminal 动态 profile 可能需要打开一次 Windows Terminal 后才完整生成；如果脚本提示 fallback GUID 未验证，重开 Windows Terminal 后再跑 `migrate.ps1` 审计。
