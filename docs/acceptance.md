# 验收步骤

## 第一轮：重开终端

关闭所有 PowerShell / Windows Terminal 窗口，重新打开 PowerShell 7。

先执行语法自检：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\codexwork\powershell-migration\restore.ps1 -TestSyntax
```

执行：

```powershell
Get-Command rg,bat,fd,git,gh,oh-my-posh,fzf,zoxide,delta
Get-Command python,pip,uv,java,javac
git status
python --version
java -version
echo $env:Path
```

## 第二轮：重启后验证

重启电脑后重复第一轮命令。

## 外观验收

- prompt 图标正常显示。
- `Get-ChildItem` 图标正常显示。
- Git 仓库中能看到分支/状态提示。
- Windows Terminal 字体为指定 Nerd Font。
- `minimal.omp.json` 存在且被加载。
