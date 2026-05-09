# Python / Java 运行时

## Python

当前策略：检查 `pyenv-win` 与常用命令解析，不在本轮自动安装 Python 版本。

验收命令：

```powershell
pyenv --version
pyenv version
python --version
pip --version
uv --version
Get-Command python,pip,uv,uvx
```

重点检查：

- `D:\tools\pyenv\pyenv-win\bin`
- `D:\tools\pyenv\pyenv-win\shims`
- `python` / `pip` / `uv` 是否命中预期路径

## Java

Windows PowerShell 下优先采用：

```text
JAVA_HOME + 固定 JDK 目录 + PATH
```

当前脚本默认只检测 Java 状态，不预设新电脑 JDK 路径。

如果后续决定采用固定 JDK 目录，再在 `config.ps1` 中设置：

```powershell
JavaHome = 'D:\tools\jdk11'
JavaBinPath = 'D:\tools\jdk11\bin'
```

验收命令：

```powershell
java -version
javac -version
echo $env:JAVA_HOME
Get-Command java,javac
```

`jenv` 暂不作为正式方案。脚本只提示 `java` 是否命中 `jenv`，不会修改它。
