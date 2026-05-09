# 终端美化说明

基础美化由 `terminal-setup` 项目托管。本项目不覆盖它生成的 profile。

## 字体

推荐：

```text
CaskaydiaCove Nerd Font
```

字体未正确设置时，`oh-my-posh` 和 `Terminal-Icons` 的图标可能显示为方块或乱码。

## 主题

当前关键主题文件：

```text
C:\Users\DP\Documents\PowerShell\themes\minimal.omp.json
```

迁移新电脑时需要复制该文件，或让 `terminal-setup` 重新生成。

## Profile 策略

`terminal-setup` 负责基础 profile。

`restore.ps1` 只追加迁移增量：

- `PSFzf`
- `zoxide`
- `fzf` 默认参数
- `batcat` / `rgrep` / `lg` / `ff` / `ffd` / `es1`

默认不覆盖 `cat` / `grep`，需要时可使用 `-AcceptProfileCommandOverrides` 生成覆盖版片段。
