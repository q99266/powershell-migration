# PowerShell 插件手动安装指南

本指南详细介绍了如何手动安装和配置 Windows Terminal 插件，特别适用于没有互联网访问权限或无法使用 `winget` 的**内网/离线环境**，以及 **Windows 7** 等旧版系统。

## 0. 系统与软件要求

| 组件 | 要求 | 备注 |
| :--- | :--- | :--- |
| **操作系统** | Windows 10 (1903+) / Windows 11 | **Windows 7 不支持 Windows Terminal** |
| **PowerShell** | 5.1 或 7.x | 建议 Win7 用户升级到 5.1 |
| **管理员权限** | 需要 | 用于修改执行策略和安装字体 |

> **注意 (Win7 用户)**：由于 Windows Terminal 官方不支持 Windows 7，你仍可以在原有的 PowerShell 窗口中使用此指南安装 `PSReadLine` 等插件，以获得自动补全体验。

## 1. 运行前准备

在安装任何插件之前，请确保已正确设置脚本执行策略：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

## 2. 在线安装方式（推荐）

大多数插件都可以通过 [PowerShell Gallery](https://www.powershellgallery.com/) 直接下载。

### 2.1 安装核心插件
在以管理员身份运行的 PowerShell 中执行：
```powershell
# 安装自动补全核心 (PSReadLine)
Install-Module -Name PSReadLine -Force -AllowClobber -Scope CurrentUser

# 安装文件图标 (Terminal-Icons)
Install-Module -Name Terminal-Icons -Force -Scope CurrentUser

# 安装目录跳转工具 (z)
Install-Module -Name z -Force -Scope CurrentUser
```

### 2.2 配置 PowerShell 配置文件 (Profile)
使用记事本打开配置文件：
```powershell
notepad $PROFILE
```
将以下内容复制到文件末尾：
```powershell
# 导入模块
Import-Module PSReadLine
Import-Module Terminal-Icons
Import-Module z

# PSReadLine 预测性补全设置 (ZSH 风格)
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
```

## 3. 离线部署方式（针对内网机器）

如果目标机器无法连接互联网，请遵循以下步骤：

1. **在有网的机器上下载模块**：
   ```powershell
   Save-Module -Name PSReadLine -Path C:\temp\PSReadLine
   Save-Module -Name Terminal-Icons -Path C:\temp\Terminal-Icons
   Save-Module -Name z -Path C:\temp\z
   ```
2. **拷贝到离线机器**：
   将上述文件夹拷贝到离线机器的以下路径（如果目录不存在请手动创建）：
   `C:\Users\你的用户名\Documents\PowerShell\Modules`
3. **验证安装**：
   在离线机器上运行：
   ```powershell
   Get-Module -ListAvailable
   ```

## 4. 常见问题排查

### 4.1 "找不到模块" 或 "无法加载"
请检查 `$PROFILE` 文件是否存在。你可以运行以下命令确认：
```powershell
Test-Path $PROFILE
```
如果返回 `False`，请手动创建它：
```powershell
New-Item -Type File -Path $PROFILE -Force
```

### 4.2 编码问题（中文乱码）
手动编辑配置文件时，务必使用 **UTF-8 with BOM** 编码保存。否则在 PowerShell 5.1 环境下可能会因无法识别中文字符而报错。

---
*提示：如需自动化安装，请优先使用本项目提供的 `setup-terminal-cn.ps1` 脚本。*
