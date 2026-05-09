param(
    [switch]$Install,
    [switch]$FixPath,
    [switch]$ShowProfileAppendSnippet,
    [switch]$ShowTerminalSetupCommand
)

# Legacy script. Formal entry is .\restore.ps1.
# Keep this file only for historical comparison.

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$TerminalSetupRoot = 'D:\tools\terminal-setup-master\terminal-setup-master'
$TerminalSetupMain = Join-Path $TerminalSetupRoot 'zed.ps1'
$TerminalSetupLegacy = Join-Path $TerminalSetupRoot 'setup-terminal-cn.ps1'
$BackupRoot = 'D:\codexwork\powershell-migration\backups'

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

function Normalize-PathEntry {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($expanded.Length -gt 3) {
        $expanded = $expanded.TrimEnd('\')
    }
    return $expanded
}

function Split-PathList {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }

    return @(
        $PathValue -split ';' |
            ForEach-Object { Normalize-PathEntry $_ } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
}

function Set-UserPathOrdered {
    param(
        [string[]]$PreferredFirst,
        [string[]]$PreferredAppend
    )

    $userPathRaw = [Environment]::GetEnvironmentVariable('Path', 'User')
    $currentUser = Split-PathList $userPathRaw
    $preferredFirstNorm = @($PreferredFirst | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ })
    $preferredAppendNorm = @($PreferredAppend | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ })

    $existingPreferredFirst = @($preferredFirstNorm | Where-Object { Test-Path -LiteralPath $_ })
    $existingPreferredAppend = @($preferredAppendNorm | Where-Object { Test-Path -LiteralPath $_ })
    $missing = @($preferredFirstNorm + $preferredAppendNorm | Where-Object { -not (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    $firstLookup = @{}
    foreach ($path in $existingPreferredFirst) { $firstLookup[$path.ToLowerInvariant()] = $true }

    $appendLookup = @{}
    foreach ($path in $existingPreferredAppend) { $appendLookup[$path.ToLowerInvariant()] = $true }

    $kept = @(
        $currentUser |
            Where-Object {
                $key = $_.ToLowerInvariant()
                -not $firstLookup.ContainsKey($key) -and -not $appendLookup.ContainsKey($key)
            }
    )

    $newUserPath = @($existingPreferredFirst + $kept + $existingPreferredAppend) | Select-Object -Unique

    if ($FixPath) {
        New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupFile = Join-Path $BackupRoot "user-path-$stamp.txt"
        Set-Content -LiteralPath $backupFile -Value $userPathRaw -Encoding utf8
        [Environment]::SetEnvironmentVariable('Path', ($newUserPath -join ';'), 'User')
        $env:Path = (($newUserPath + (Split-PathList ([Environment]::GetEnvironmentVariable('Path', 'Machine')))) -join ';')
        Write-Host "[OK] User PATH updated. Backup: $backupFile" -ForegroundColor Green
    } else {
        Write-Host '[DRY] User PATH would be rewritten in this order:'
        $newUserPath | ForEach-Object { Write-Host "     $_" }
        Write-Host 'Run with -FixPath to persist this User PATH order.'
    }

    if ($missing.Count -gt 0) {
        Write-Host '[WARN] These planned PATH entries do not exist yet:'
        $missing | ForEach-Object { Write-Host "       $_" }
    }
}

function Test-ModuleAvailableCompat {
    param([string]$Name)

    $found = Get-Module -ListAvailable -Name $Name | Select-Object -First 1
    if ($found) {
        return [pscustomobject]@{
            Found = $true
            Path = $found.ModuleBase
        }
    }

    $legacyRoot = Join-Path $HOME 'Documents\WindowsPowerShell\Modules'
    $legacyModule = Join-Path $legacyRoot $Name
    if (Test-Path -LiteralPath $legacyModule) {
        return [pscustomobject]@{
            Found = $true
            Path = $legacyModule
        }
    }

    return [pscustomobject]@{
        Found = $false
        Path = $null
    }
}

Write-Section 'Mode'
Write-Host "Install: $Install"
Write-Host "FixPath: $FixPath"
Write-Host 'Default mode only checks and prints suggestions.'

Write-Section 'Terminal setup project'
if (Test-Path -LiteralPath $TerminalSetupMain) {
    Write-Host "[OK] terminal-setup found: $TerminalSetupRoot"
    Write-Host '[INFO] terminal-setup owns base beautification: oh-my-posh, PSReadLine, Terminal-Icons, z, Windows Terminal font/theme.'
    Write-Host '[INFO] This combined script only adds migration extras and PATH ordering.'
    if ($ShowTerminalSetupCommand) {
        Write-Host "Suggested command:"
        Write-Host "pwsh -ExecutionPolicy Bypass -File `"$TerminalSetupMain`""
    }
} elseif (Test-Path -LiteralPath $TerminalSetupLegacy) {
    Write-Host "[OK] legacy terminal setup found: $TerminalSetupLegacy"
} else {
    Write-Host "[WARN] terminal-setup project was not found at $TerminalSetupRoot"
}

Write-Section 'PATH ordering fix'
$preferredFirst = @(
    'D:\tools\cli-bin',
    'D:\tools\fzf',
    'D:\tools\nodejs',
    'C:\Users\DP\AppData\Roaming\npm',
    'D:\tools\pyenv\pyenv-win\bin',
    'D:\tools\pyenv\pyenv-win\shims'
)

$preferredAppend = @(
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\Program Files\GitHub CLI',
    'D:\tools\Microsoft VS Code\bin',
    'D:\tools\jadx\bin',
    'D:\tools\adb\platform-tools',
    'D:\work\hacktools\nuclei'
)

Set-UserPathOrdered -PreferredFirst $preferredFirst -PreferredAppend $preferredAppend

Write-Section 'Command resolution after current PATH'
$commands = @('rg','bat','fd','jq','delta','lazygit','zoxide','fzf','es.exe','node','npm','pnpm','pyenv','git','gh','oh-my-posh')
foreach ($name in $commands) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK] $name -> $($cmd.Source)"
    } else {
        Write-Host "[MISS] $name"
    }
}
Write-Host '[NOTE] If rg still resolves to a Codex vendor path, run this script with -FixPath and open a new terminal.'

Write-Section 'Extra packages not owned by terminal-setup'
$wingetPackages = @(
    @{ Id = 'Git.Git'; Command = 'git' },
    @{ Id = 'GitHub.cli'; Command = 'gh' },
    @{ Id = 'junegunn.fzf'; Command = 'fzf' },
    @{ Id = 'sharkdp.bat'; Command = 'bat' },
    @{ Id = 'sharkdp.fd'; Command = 'fd' },
    @{ Id = 'BurntSushi.ripgrep.MSVC'; Command = 'rg' },
    @{ Id = 'jqlang.jq'; Command = 'jq' },
    @{ Id = 'dandavison.delta'; Command = 'delta' },
    @{ Id = 'jesseduffield.lazygit'; Command = 'lazygit' },
    @{ Id = 'ajeetdsouza.zoxide'; Command = 'zoxide' },
    @{ Id = 'voidtools.Everything.Alpha'; Command = $null },
    @{ Id = 'OpenJS.NodeJS'; Command = 'node' }
)

foreach ($pkg in $wingetPackages) {
    if ($pkg.Command -and (Test-CommandExists $pkg.Command)) {
        Write-Host "[OK] $($pkg.Command)"
    } else {
        Invoke-OrPrint -Label "Install $($pkg.Id)" -Command "winget install --id $($pkg.Id) --source winget"
    }
}

Write-Section 'PowerShell extras not fully covered by terminal-setup'
$modules = @('PSFzf','posh-git')
foreach ($module in $modules) {
    $moduleState = Test-ModuleAvailableCompat -Name $module
    if ($moduleState.Found) {
        Write-Host "[OK] module $module -> $($moduleState.Path)"
    } else {
        Invoke-OrPrint -Label "Install module $module" -Command "Install-Module $module -Scope CurrentUser -Force -AllowClobber"
    }
}

Write-Section 'npm global CLIs'
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

Write-Section 'Profile append snippet'
$appendSnippet = @'
# ---- Migration extras after terminal-setup ----
# terminal-setup owns: oh-my-posh, PSReadLine, Terminal-Icons, z, Windows Terminal look.
# This block only adds tools that terminal-setup does not fully manage.

Import-Module PSFzf -ErrorAction SilentlyContinue
if (Get-Module PSFzf) {
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
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
# ---- /Migration extras after terminal-setup ----
'@

if ($ShowProfileAppendSnippet) {
    $appendSnippet
} else {
    Write-Host 'Run with -ShowProfileAppendSnippet to print the safe append-only profile block.'
    Write-Host 'Append it after terminal-setup generated profile. Do not replace the whole profile with it.'
}

Write-Section 'Recommended order on a new PC'
Write-Host '1. Run terminal-setup first for base beautification.'
Write-Host '2. Run this script without switches to audit missing tools.'
Write-Host '3. Run this script with -Install only after reviewing package commands.'
Write-Host '4. Run this script with -FixPath to persist PATH ordering.'
Write-Host '5. Append the -ShowProfileAppendSnippet block after terminal-setup profile content.'
Write-Host '6. Open a new PowerShell 7 window and verify: rg, fzf, zoxide, PSFzf, es1, delta.'
