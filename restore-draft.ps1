param(
    [switch]$Install,
    [switch]$ShowProfileSnippet
)

# Draft script. Formal entry is .\restore.ps1.
# Keep this file only for historical comparison.

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-OrPrint {
    param(
        [string]$Label,
        [string]$Command
    )

    if ($Install) {
        Write-Host "[RUN] $Label" -ForegroundColor Yellow
        Invoke-Expression $Command
    } else {
        Write-Host "[TODO] $Label" -ForegroundColor Yellow
        Write-Host "      $Command"
    }
}

Write-Section 'Mode'
if ($Install) {
    Write-Host 'Install mode is ON. Commands may change this machine.' -ForegroundColor Yellow
} else {
    Write-Host 'Dry-run mode. No install commands will run. Add -Install to execute suggested commands.'
}

Write-Section 'PowerShell'
Write-Host "PSEdition: $($PSVersionTable.PSEdition)"
Write-Host "PSVersion: $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Invoke-OrPrint -Label 'Install PowerShell 7' -Command 'winget install --id Microsoft.PowerShell --source winget'
}

Write-Section 'Winget CLI packages'
$wingetPackages = @(
    @{ Id = 'Git.Git'; Command = 'git'; Reason = 'Git command line' },
    @{ Id = 'GitHub.cli'; Command = 'gh'; Reason = 'GitHub CLI' },
    @{ Id = 'JanDeDobbeleer.OhMyPosh'; Command = 'oh-my-posh'; Reason = 'Prompt theme engine' },
    @{ Id = 'voidtools.Everything.Alpha'; Command = $null; Reason = 'Everything 1.5 alpha for es.exe/es1 workflow' },
    @{ Id = 'junegunn.fzf'; Command = 'fzf'; Reason = 'Fuzzy finder and PSFzf backend' },
    @{ Id = 'sharkdp.bat'; Command = 'bat'; Reason = 'Syntax-highlighted file viewer' },
    @{ Id = 'sharkdp.fd'; Command = 'fd'; Reason = 'Fast file search' },
    @{ Id = 'BurntSushi.ripgrep.MSVC'; Command = 'rg'; Reason = 'Fast text search' },
    @{ Id = 'jqlang.jq'; Command = 'jq'; Reason = 'JSON processor' },
    @{ Id = 'dandavison.delta'; Command = 'delta'; Reason = 'Git diff pager' },
    @{ Id = 'jesseduffield.lazygit'; Command = 'lazygit'; Reason = 'Git TUI' },
    @{ Id = 'ajeetdsouza.zoxide'; Command = 'zoxide'; Reason = 'Smart directory jumping' },
    @{ Id = 'OpenJS.NodeJS'; Command = 'node'; Reason = 'Node.js runtime for npm global CLIs' },
    @{ Id = 'Microsoft.VisualStudioCode'; Command = 'code'; Reason = 'Editor CLI' }
)

foreach ($pkg in $wingetPackages) {
    $installed = $false
    if ($pkg.Command) {
        $installed = Test-CommandExists $pkg.Command
    }

    if ($installed) {
        $cmd = Get-Command $pkg.Command -ErrorAction SilentlyContinue
        Write-Host "[OK] $($pkg.Command) -> $($cmd.Source)"
    } else {
        Invoke-OrPrint -Label "Install $($pkg.Id) ($($pkg.Reason))" -Command "winget install --id $($pkg.Id) --source winget"
    }
}

Write-Section 'Manual path-backed tools currently seen on old machine'
$manualTools = @(
    'D:\tools\cli-bin\bat.exe',
    'D:\tools\cli-bin\delta.exe',
    'D:\tools\cli-bin\es.exe',
    'D:\tools\cli-bin\fd.exe',
    'D:\tools\cli-bin\jq.exe',
    'D:\tools\cli-bin\lazygit.exe',
    'D:\tools\cli-bin\rg.exe',
    'D:\tools\cli-bin\zoxide.exe',
    'D:\tools\fzf\fzf.exe',
    'D:\tools\pyenv\pyenv-win'
)
foreach ($item in $manualTools) {
    Write-Host "[OLD] $item"
}
Write-Host 'Path migration is intentionally left for the next pass.'

Write-Section 'PowerShell modules'
$modules = @(
    @{ Name = 'PSReadLine'; Version = '2.4.5'; Required = $true },
    @{ Name = 'posh-git'; Version = '1.1.0'; Required = $true },
    @{ Name = 'PSFzf'; Version = '2.7.10'; Required = $true },
    @{ Name = 'Terminal-Icons'; Version = '0.11.0'; Required = $true },
    @{ Name = 'z'; Version = '1.1.14'; Required = $true }
)

foreach ($module in $modules) {
    $found = Get-Module -ListAvailable -Name $module.Name | Sort-Object Version -Descending | Select-Object -First 1
    if ($found) {
        Write-Host "[OK] module $($module.Name) $($found.Version) -> $($found.ModuleBase)"
    } else {
        Invoke-OrPrint -Label "Install PowerShell module $($module.Name)" -Command "Install-Module $($module.Name) -Scope CurrentUser -Force -AllowClobber"
    }
}

Write-Section 'npm global packages'
$npmPackages = @(
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

if (Test-CommandExists npm) {
    foreach ($pkg in $npmPackages) {
        Invoke-OrPrint -Label "Install npm global package $pkg" -Command "npm install -g $pkg"
    }
} else {
    Write-Host '[WARN] npm is missing. Install Node.js first.'
}

Write-Section 'Git delta config'
$gitConfigCommands = @(
    'git config --global core.pager delta',
    'git config --global interactive.diffFilter "delta --color-only"',
    'git config --global delta.navigate true',
    'git config --global merge.conflictstyle zdiff3'
)

if (Test-CommandExists git) {
    foreach ($cmd in $gitConfigCommands) {
        Invoke-OrPrint -Label "Apply $cmd" -Command $cmd
    }
} else {
    Write-Host '[WARN] git is missing. Install Git first.'
}

Write-Section 'Profile snippet'
$profileSnippet = @'
# ---- Interactive shell extras ----
$cliBin = 'D:\tools\cli-bin'
if (($env:PATH -split ';') -notcontains $cliBin) { $env:PATH = $cliBin + ';' + $env:PATH }

$script:IsInteractiveConsole = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected

if ($script:IsInteractiveConsole) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (Get-Module PSReadLine) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
        Set-PSReadLineOption -EditMode Windows -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction SilentlyContinue
    }

    Import-Module posh-git -ErrorAction SilentlyContinue
    Import-Module PSFzf -ErrorAction SilentlyContinue
    if (Get-Module PSFzf) {
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
    }
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    Import-Module z -ErrorAction SilentlyContinue

    $themePath = "$HOME\Documents\PowerShell\themes\minimal.omp.json"
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if ($omp) {
        try {
            if (Test-Path $themePath) {
                oh-my-posh init pwsh --config $themePath | Invoke-Expression
            } else {
                oh-my-posh init pwsh | Invoke-Expression
            }
        } catch {
            Write-Verbose "oh-my-posh initialization skipped: $($_.Exception.Message)"
        }
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression ((zoxide init powershell) -join [Environment]::NewLine)
}

$env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
$env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
$env:FZF_DEFAULT_OPTS = "--height 70% --layout=reverse --border --preview 'bat --style=numbers --color=always --line-range :500 {}'"

function cat { bat @args }
function grep { rg @args }
function lg { lazygit @args }
function ff { fd --type f @args }
function ffd { fd --type d @args }
function es1 { es.exe -instance 1.5a @args }

# pyenv/Python wrappers from the old machine are path-sensitive.
# Revisit these after D:\tools\pyenv migration is decided:
# python, python3, python3.13, pythonw, pip, pip3, pip3.13, uv, uvx, sqlmap, frida
# ---- /Interactive shell extras ----
'@

if ($ShowProfileSnippet) {
    $profileSnippet
} else {
    Write-Host 'Run with -ShowProfileSnippet to print the profile block.'
    Write-Host 'Do not paste it blindly on the new machine until path migration is decided.'
}

Write-Section 'Manual files to carry over'
Write-Host "$HOME\Documents\PowerShell\themes\minimal.omp.json"
Write-Host "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1 (reference only; prefer the generated snippet)"

Write-Section 'Checklist'
Write-Host '[ ] Install PowerShell 7, Git, Oh My Posh, fzf, bat, fd, rg, jq, delta, lazygit, zoxide.'
Write-Host '[ ] Install PowerShell modules: PSReadLine, posh-git, PSFzf, Terminal-Icons, z.'
Write-Host '[ ] Restore npm global CLIs if needed.'
Write-Host '[ ] Apply Git delta config.'
Write-Host '[ ] Copy minimal.omp.json or choose a new Oh My Posh theme.'
Write-Host '[ ] Review the profile snippet after D:\tools path migration is settled.'
Write-Host '[ ] Re-authenticate CLIs manually: gh, codex, claude-code, npm registry, MCP configs.'
