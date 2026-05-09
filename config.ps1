$MigrationConfig = @{
    MinimumPowerShellMajor = 5
    RecommendedPowerShellMajor = 7

    ProjectRoot = 'D:\codexwork\powershell-migration'
    BackupRoot = 'D:\codexwork\powershell-migration\backups'
    LogRoot = 'D:\codexwork\powershell-migration\logs'

    ToolsRoot = 'D:\tools'
    WorkRoot = 'D:\work'
    CodexWorkRoot = 'D:\codexwork'

    TerminalSetupRoot = 'D:\tools\terminal-setup-master\terminal-setup-master'
    TerminalSetupMain = 'D:\tools\terminal-setup-master\terminal-setup-master\zed.ps1'
    TerminalSetupLegacy = 'D:\tools\terminal-setup-master\terminal-setup-master\setup-terminal-cn.ps1'
    WindowsTerminalSettingsPath = 'C:\Users\DP\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    WindowsTerminalPwshProfileNamePattern = '^PowerShell 7$'
    WingetSource = 'winget'
    NpmRegistry = $null
    NpmChinaMirror = 'https://registry.npmmirror.com'
    PowerShellGallery = 'PSGallery'
    NetworkRetryCount = 2

    CliBinPath = 'D:\tools\cli-bin'
    FzfPath = 'D:\tools\fzf'
    NodePath = 'D:\tools\nodejs'
    NpmGlobalPath = 'C:\Users\DP\AppData\Roaming\npm'
    PyenvRoot = 'D:\tools\pyenv\pyenv-win'
    PyenvBinPath = 'D:\tools\pyenv\pyenv-win\bin'
    PyenvShimsPath = 'D:\tools\pyenv\pyenv-win\shims'

    JavaHome = $null
    JavaBinPath = $null

    JadxPath = 'D:\tools\jadx\bin'
    AdbPath = 'D:\tools\adb\platform-tools'
    VscodeBinPath = 'D:\tools\Microsoft VS Code\bin'
    NucleiPath = 'D:\work\hacktools\nuclei'

    ThemePath = 'C:\Users\DP\Documents\PowerShell\themes\minimal.omp.json'
    RecommendedNerdFont = 'CaskaydiaCove Nerd Font'
    NerdFontName = 'CaskaydiaCove Nerd Font'
    NerdFontAssetName = 'CaskaydiaCove.zip'
    NerdFontVersion = 'v3.4.0'
    NerdFontDownloadUrls = @(
        'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://gh-proxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://mirror.ghproxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip'
    )
    NerdFontChinaMirrorUrls = @(
        'https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://gh-proxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://mirror.ghproxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip',
        'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CaskaydiaCove.zip'
    )
    NerdFontDownloadPath = 'D:\codexwork\powershell-migration\downloads\CaskaydiaCove.zip'
    NerdFontExtractPath = 'D:\codexwork\powershell-migration\downloads\CaskaydiaCove'
    DownloadTimeoutSec = 90

    PreferredPathFirst = @(
        'D:\tools\cli-bin',
        'D:\tools\fzf',
        'D:\tools\nodejs',
        'C:\Users\DP\AppData\Roaming\npm',
        'D:\tools\pyenv\pyenv-win\bin',
        'D:\tools\pyenv\pyenv-win\shims'
    )

    PreferredPathAppend = @(
        'C:\Program Files\Git\cmd',
        'C:\Program Files\Git\bin',
        'C:\Program Files\GitHub CLI',
        'D:\tools\Microsoft VS Code\bin',
        'D:\tools\jadx\bin',
        'D:\tools\adb\platform-tools',
        'D:\work\hacktools\nuclei'
    )

    WingetPackages = @(
        @{ Id = 'Git.Git'; Command = 'git'; Owner = 'migration' },
        @{ Id = 'GitHub.cli'; Command = 'gh'; Owner = 'migration' },
        @{ Id = 'junegunn.fzf'; Command = 'fzf'; Owner = 'migration' },
        @{ Id = 'sharkdp.bat'; Command = 'bat'; Owner = 'migration' },
        @{ Id = 'sharkdp.fd'; Command = 'fd'; Owner = 'migration' },
        @{ Id = 'BurntSushi.ripgrep.MSVC'; Command = 'rg'; Owner = 'migration' },
        @{ Id = 'jqlang.jq'; Command = 'jq'; Owner = 'migration' },
        @{ Id = 'dandavison.delta'; Command = 'delta'; Owner = 'migration' },
        @{ Id = 'jesseduffield.lazygit'; Command = 'lazygit'; Owner = 'migration' },
        @{ Id = 'ajeetdsouza.zoxide'; Command = 'zoxide'; Owner = 'migration' },
        @{ Id = 'voidtools.Everything.Alpha'; Command = $null; Owner = 'migration' },
        @{ Id = 'OpenJS.NodeJS'; Command = 'node'; Owner = 'runtime' }
    )

    PowerShellModules = @(
        @{ Name = 'PSFzf'; Owner = 'migration' },
        @{ Name = 'posh-git'; Owner = 'migration' }
    )

    NpmGlobalPackages = @(
        '@openai/codex',
        '@anthropic-ai/claude-code',
        '@modelcontextprotocol/server-filesystem',
        '@modelcontextprotocol/server-postgres',
        'opencode-ai',
        'pnpm',
        'yarn',
        'zcf',
        '@cometix/ccline'
    )

    GitConfig = @(
        @{ Key = 'core.pager'; Value = 'delta' },
        @{ Key = 'interactive.diffFilter'; Value = 'delta --color-only' },
        @{ Key = 'delta.navigate'; Value = 'true' },
        @{ Key = 'merge.conflictstyle'; Value = 'zdiff3' }
    )

    AcceptanceCommands = @(
        'rg',
        'bat',
        'fd',
        'git',
        'gh',
        'oh-my-posh',
        'fzf',
        'zoxide',
        'delta',
        'python',
        'pip',
        'uv',
        'java',
        'javac'
        'wt'
    )
}
