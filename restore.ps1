param(
    [switch]$Install,
    [switch]$FixPath,
    [switch]$ApplyGitConfig,
    [switch]$AppendProfileSnippet,
    [switch]$ShowProfileSnippet,
    [switch]$RunTerminalSetup,
    [switch]$AcceptProfileCommandOverrides,
    [switch]$TestSyntax
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptRoot 'config.ps1')

function Test-ScriptSyntax {
    param([string[]]$Paths)

    $hasError = $false
    foreach ($path in $Paths) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) > $null
        if ($errors -and $errors.Count -gt 0) {
            $hasError = $true
            Write-Host "[ERR] $path" -ForegroundColor Red
            $errors | ForEach-Object {
                Write-Host "  Line $($_.Extent.StartLineNumber), Column $($_.Extent.StartColumnNumber): $($_.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "[OK] $path"
        }
    }
    return (-not $hasError)
}

if ($TestSyntax) {
    $syntaxFiles = @(
        (Join-Path $ScriptRoot 'config.ps1'),
        (Join-Path $ScriptRoot 'restore.ps1'),
        (Join-Path $ScriptRoot 'restore-terminal-combined.ps1'),
        (Join-Path $ScriptRoot 'restore-draft.ps1')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    [void](Test-ScriptSyntax -Paths $syntaxFiles)
    return
}

if ($PSVersionTable.PSVersion.Major -lt $MigrationConfig.MinimumPowerShellMajor) {
    Write-Host "[ERR] PowerShell $($PSVersionTable.PSVersion) is too old. Minimum supported major version: $($MigrationConfig.MinimumPowerShellMajor)." -ForegroundColor Red
    return
}

if ($PSVersionTable.PSVersion.Major -lt $MigrationConfig.RecommendedPowerShellMajor) {
    Write-Host "[WARN] PowerShell 7 is recommended. Current: $($PSVersionTable.PSVersion)." -ForegroundColor Yellow
}

$script:Summary = @{
    Ok = New-Object System.Collections.Generic.List[string]
    Missing = New-Object System.Collections.Generic.List[string]
    Changed = New-Object System.Collections.Generic.List[string]
    Failed = New-Object System.Collections.Generic.List[string]
    Manual = New-Object System.Collections.Generic.List[string]
}

function Add-Summary {
    param(
        [ValidateSet('Ok','Missing','Changed','Failed','Manual')]
        [string]$Kind,
        [string]$Message
    )
    $script:Summary[$Kind].Add($Message) | Out-Null
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Normalize-PathEntry {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($expanded.Length -gt 3) { $expanded = $expanded.TrimEnd('\') }
    return $expanded
}

function Split-PathList {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return @($PathValue -split ';' | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ } | Select-Object -Unique)
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label,
        [switch]$ShouldRun
    )

    $display = "$FilePath $($Arguments -join ' ')"
    if (-not $ShouldRun) {
        Write-Host "[TODO] $Label" -ForegroundColor Yellow
        Write-Host "      $display"
        return $true
    }

    Write-Host "[RUN] $Label" -ForegroundColor Yellow
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Add-Summary Changed $Label
            return $true
        }
        Add-Summary Failed "$Label exited with code $LASTEXITCODE"
        return $false
    } catch {
        Add-Summary Failed "$Label failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-ModuleAvailableCompat {
    param([string]$Name)

    $found = Get-Module -ListAvailable -Name $Name | Select-Object -First 1
    if ($found) {
        return [pscustomobject]@{ Found = $true; Path = $found.ModuleBase }
    }

    $legacyModule = Join-Path (Join-Path $HOME 'Documents\WindowsPowerShell\Modules') $Name
    if (Test-Path -LiteralPath $legacyModule) {
        return [pscustomobject]@{ Found = $true; Path = $legacyModule }
    }

    return [pscustomobject]@{ Found = $false; Path = $null }
}

function Get-NpmGlobalPackageMap {
    if (-not (Test-CommandExists npm)) {
        return @{}
    }

    try {
        $json = (& npm list -g --depth=0 --json 2>$null) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($json)) {
            return @{}
        }

        $parsed = $json | ConvertFrom-Json
        $map = @{}
        if ($parsed.dependencies) {
            $parsed.dependencies.PSObject.Properties | ForEach-Object {
                $map[$_.Name] = $_.Value.version
            }
        }
        return $map
    } catch {
        Write-Host "[WARN] Failed to inspect npm global packages: $($_.Exception.Message)" -ForegroundColor Yellow
        Add-Summary Manual 'npm global package inspection failed; review manually'
        return @{}
    }
}

function Get-PathPlan {
    $userPathRaw = [Environment]::GetEnvironmentVariable('Path', 'User')
    $currentUser = Split-PathList $userPathRaw
    $preferredFirst = @($MigrationConfig.PreferredPathFirst | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ })
    $preferredAppend = @($MigrationConfig.PreferredPathAppend | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ })

    $existingFirst = @($preferredFirst | Where-Object { Test-Path -LiteralPath $_ })
    $existingAppend = @($preferredAppend | Where-Object { Test-Path -LiteralPath $_ })
    $missing = @($preferredFirst + $preferredAppend | Where-Object { -not (Test-Path -LiteralPath $_) } | Select-Object -Unique)

    $frontLookup = @{}
    foreach ($path in $existingFirst) { $frontLookup[$path.ToLowerInvariant()] = $true }
    $appendLookup = @{}
    foreach ($path in $existingAppend) { $appendLookup[$path.ToLowerInvariant()] = $true }

    $kept = @($currentUser | Where-Object {
        $key = $_.ToLowerInvariant()
        -not $frontLookup.ContainsKey($key) -and -not $appendLookup.ContainsKey($key)
    })

    $newPath = @($existingFirst + $kept + $existingAppend) | Select-Object -Unique
    return [pscustomobject]@{
        Raw = $userPathRaw
        Before = $currentUser
        After = $newPath
        Front = $existingFirst
        Append = $existingAppend
        Missing = $missing
    }
}

function Show-PathPlan {
    param($Plan)

    Write-Host '[Before] first 12 User PATH entries:'
    $Plan.Before | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
    Write-Host '[After] first 12 User PATH entries:'
    $Plan.After | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }

    Write-Host '[Front entries]'
    $Plan.Front | ForEach-Object { Write-Host "  $_" }
    Write-Host '[Append entries]'
    $Plan.Append | ForEach-Object { Write-Host "  $_" }
    if ($Plan.Missing.Count -gt 0) {
        Write-Host '[Missing planned entries]' -ForegroundColor Yellow
        $Plan.Missing | ForEach-Object { Write-Host "  $_" }
        foreach ($path in $Plan.Missing) { Add-Summary Manual "PATH entry missing: $path" }
    }
}

function Set-UserPathFromPlan {
    param($Plan)

    New-Item -ItemType Directory -Force -Path $MigrationConfig.BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $MigrationConfig.BackupRoot "user-path-$stamp.txt"
    Set-Content -LiteralPath $backupFile -Value $Plan.Raw -Encoding utf8
    [Environment]::SetEnvironmentVariable('Path', ($Plan.After -join ';'), 'User')
    $env:Path = (($Plan.After + (Split-PathList ([Environment]::GetEnvironmentVariable('Path', 'Machine')))) -join ';')
    Add-Summary Changed "User PATH updated; backup: $backupFile"
    Write-Host "[OK] User PATH updated. Backup: $backupFile" -ForegroundColor Green
}

function Get-ProfileAppendSnippet {
    if ($AcceptProfileCommandOverrides) {
        $commandBlock = @'
if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat @args }
}
if (Get-Command rg -ErrorAction SilentlyContinue) {
    function grep { rg @args }
}
'@
    } else {
        $commandBlock = @'
if (Get-Command bat -ErrorAction SilentlyContinue) {
    function batcat { bat @args }
}
if (Get-Command rg -ErrorAction SilentlyContinue) {
    function rgrep { rg @args }
}
'@
    }

    $beforeCommandBlock = @'
# >>> powershell-migration extras >>>
# terminal-setup owns: oh-my-posh, PSReadLine, Terminal-Icons, z, Windows Terminal look.
# This block adds only migration extras and is safe to append once.

$script:IsInteractiveConsole = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected
if ($script:IsInteractiveConsole) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    if (Get-Module PSFzf) {
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression ((zoxide init powershell) -join [Environment]::NewLine)
}

if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
    $env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
}
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Command bat -ErrorAction SilentlyContinue)) {
    $env:FZF_DEFAULT_OPTS = "--height 70% --layout=reverse --border --preview 'bat --style=numbers --color=always --line-range :500 {}'"
} elseif (Get-Command fzf -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_OPTS = "--height 70% --layout=reverse --border"
}

'@

    $afterCommandBlock = @'
if (Get-Command lazygit -ErrorAction SilentlyContinue) {
    function lg { lazygit @args }
}
if (Get-Command fd -ErrorAction SilentlyContinue) {
    function ff { fd --type f @args }
    function ffd { fd --type d @args }
}
if (Get-Command es.exe -ErrorAction SilentlyContinue) {
    function es1 { es.exe -instance 1.5a @args }
}
# <<< powershell-migration extras <<<
'@

    return ($beforeCommandBlock, $commandBlock, $afterCommandBlock) -join [Environment]::NewLine
}

function Add-ProfileSnippet {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $snippet = Get-ProfileAppendSnippet
    $beginMarker = '# >>> powershell-migration extras >>>'
    $endMarker = '# <<< powershell-migration extras <<<'

    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    $current = ''
    if (Test-Path -LiteralPath $profilePath) {
        $current = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
    }

    if ($current.Contains($beginMarker) -and $current.Contains($endMarker)) {
        Write-Host "[OK] Profile snippet already present: $profilePath"
        Add-Summary Ok "Profile snippet already present"
        return
    }

    New-Item -ItemType Directory -Force -Path $MigrationConfig.BackupRoot | Out-Null
    if (Test-Path -LiteralPath $profilePath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $profilePath -Destination (Join-Path $MigrationConfig.BackupRoot "profile-$stamp.ps1") -Force
    }

    Add-Content -LiteralPath $profilePath -Value "`r`n$snippet`r`n" -Encoding utf8
    Write-Host "[OK] Profile snippet appended: $profilePath" -ForegroundColor Green
    Add-Summary Changed "Profile snippet appended"
}

if ($ShowProfileSnippet) {
    Get-ProfileAppendSnippet
    return
}

Write-Section 'Mode'
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "Install: $Install"
Write-Host "FixPath: $FixPath"
Write-Host "ApplyGitConfig: $ApplyGitConfig"
Write-Host "AppendProfileSnippet: $AppendProfileSnippet"
Write-Host 'Default mode audits only.'
Write-Host 'Run with -TestSyntax first on a new machine if profile/script parsing looks suspicious.'

Write-Section 'Official entry'
Write-Host 'Formal script: restore.ps1'
Write-Host 'Legacy scripts: restore-terminal-combined.ps1, restore-draft.ps1'

Write-Section 'Terminal setup boundary'
if (Test-Path -LiteralPath $MigrationConfig.TerminalSetupMain) {
    Write-Host "[OK] terminal-setup found: $($MigrationConfig.TerminalSetupRoot)"
    Add-Summary Ok 'terminal-setup project found'
    if ($RunTerminalSetup) {
        [void](Invoke-Native -FilePath 'pwsh' -Arguments @('-ExecutionPolicy','Bypass','-File',$MigrationConfig.TerminalSetupMain) -Label 'Run terminal-setup zed.ps1' -ShouldRun:$true)
    } else {
        Write-Host 'terminal-setup owns base beautification: oh-my-posh, PSReadLine, Terminal-Icons, z, Windows Terminal font/theme.'
        Write-Host "Run manually when needed: pwsh -ExecutionPolicy Bypass -File `"$($MigrationConfig.TerminalSetupMain)`""
    }
} else {
    Write-Host "[WARN] terminal-setup not found: $($MigrationConfig.TerminalSetupRoot)" -ForegroundColor Yellow
    Add-Summary Manual 'terminal-setup project missing'
}

Write-Section 'PATH audit'
$pathPlan = Get-PathPlan
Show-PathPlan -Plan $pathPlan
if ($FixPath) {
    Set-UserPathFromPlan -Plan $pathPlan
} else {
    Write-Host 'Run with -FixPath to persist User PATH ordering.'
}

Write-Section 'Command resolution'
foreach ($name in $MigrationConfig.AcceptanceCommands) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK] $name -> $($cmd.Source)"
        Add-Summary Ok "$name -> $($cmd.Source)"
    } else {
        Write-Host "[MISS] $name" -ForegroundColor Yellow
        Add-Summary Missing $name
    }
}

Write-Section 'Winget packages'
foreach ($pkg in $MigrationConfig.WingetPackages) {
    if ($pkg.Command -and (Test-CommandExists $pkg.Command)) {
        Write-Host "[OK] $($pkg.Command)"
        Add-Summary Ok "winget command present: $($pkg.Command)"
    } else {
        [void](Invoke-Native -FilePath 'winget' -Arguments @('install','--id',$pkg.Id,'--source','winget') -Label "Install $($pkg.Id)" -ShouldRun:$Install)
        if (-not $Install) { Add-Summary Missing "winget package candidate: $($pkg.Id)" }
    }
}

Write-Section 'PowerShell modules'
foreach ($module in $MigrationConfig.PowerShellModules) {
    $state = Test-ModuleAvailableCompat -Name $module.Name
    if ($state.Found) {
        Write-Host "[OK] module $($module.Name) -> $($state.Path)"
        Add-Summary Ok "module $($module.Name)"
    } else {
        [void](Invoke-Native -FilePath 'pwsh' -Arguments @('-NoProfile','-Command',"Install-Module $($module.Name) -Scope CurrentUser -Force -AllowClobber") -Label "Install module $($module.Name)" -ShouldRun:$Install)
        if (-not $Install) { Add-Summary Missing "module $($module.Name)" }
    }
}

Write-Section 'npm global packages'
if (Test-CommandExists npm) {
    $npmGlobal = Get-NpmGlobalPackageMap
    foreach ($pkg in $MigrationConfig.NpmGlobalPackages) {
        if ($npmGlobal.ContainsKey($pkg)) {
            Write-Host "[OK] npm global package $pkg@$($npmGlobal[$pkg])"
            Add-Summary Ok "npm global package $pkg"
        } else {
            [void](Invoke-Native -FilePath 'npm' -Arguments @('install','-g',$pkg) -Label "Install missing npm global package $pkg" -ShouldRun:$Install)
            if (-not $Install) { Add-Summary Missing "npm global package $pkg" }
        }
    }
} else {
    Write-Host '[WARN] npm is missing. Install Node.js first.'
    Add-Summary Missing 'npm'
}

Write-Section 'Git delta config'
if (Test-CommandExists git) {
    foreach ($item in $MigrationConfig.GitConfig) {
        $current = (& git config --global --get $item.Key 2>$null)
        if ($current -eq $item.Value) {
            Write-Host "[OK] git config $($item.Key)=$($item.Value)"
            Add-Summary Ok "git config $($item.Key)"
        } else {
            [void](Invoke-Native -FilePath 'git' -Arguments @('config','--global',$item.Key,$item.Value) -Label "Set git config $($item.Key)" -ShouldRun:$ApplyGitConfig)
            if (-not $ApplyGitConfig) { Add-Summary Manual "git config pending: $($item.Key)=$($item.Value)" }
        }
    }
} else {
    Add-Summary Missing 'git'
}

Write-Section 'Python runtime'
$pyenv = Get-Command pyenv -ErrorAction SilentlyContinue
if ($pyenv) {
    Write-Host "[OK] pyenv -> $($pyenv.Source)"
    & pyenv version
    Add-Summary Ok 'pyenv present'
} else {
    Write-Host "[MISS] pyenv"
    Add-Summary Missing 'pyenv'
}
foreach ($name in @('python','pip','uv','uvx')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { Write-Host "[OK] $name -> $($cmd.Source)" } else { Write-Host "[MISS] $name" -ForegroundColor Yellow }
}

Write-Section 'Java runtime'
Write-Host 'Java mode: audit only. This script does not set JAVA_HOME or edit Java PATH.'
$javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
if (-not $javaHome) { $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
Write-Host "JAVA_HOME: $javaHome"
$javaCommandSources = @{}
foreach ($name in @('java','javac')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK] $name -> $($cmd.Source)"
        $javaCommandSources[$name] = $cmd.Source
    } else {
        Write-Host "[MISS] $name" -ForegroundColor Yellow
        Add-Summary Missing $name
    }
}
if ($MigrationConfig.JavaHome -and -not $javaHome -and (Test-Path -LiteralPath $MigrationConfig.JavaHome)) {
    Write-Host "Suggested JAVA_HOME: $($MigrationConfig.JavaHome)"
    Add-Summary Manual "Set JAVA_HOME to $($MigrationConfig.JavaHome)"
}
if ($MigrationConfig.JavaHome -and $javaHome -and (Test-Path -LiteralPath $MigrationConfig.JavaHome) -and ((Normalize-PathEntry $javaHome) -ne (Normalize-PathEntry $MigrationConfig.JavaHome))) {
    Write-Host "[WARN] JAVA_HOME differs from configured JavaHome: $($MigrationConfig.JavaHome)" -ForegroundColor Yellow
    Add-Summary Manual "Review JAVA_HOME mismatch: current=$javaHome configured=$($MigrationConfig.JavaHome)"
}
if ($javaCommandSources.ContainsKey('java') -and $javaCommandSources['java'] -match '\\jenv\\') {
    Write-Host '[WARN] java resolves through jenv. This script only reports Java state; choose a Java strategy separately.' -ForegroundColor Yellow
    Add-Summary Manual "Review java command source: $($javaCommandSources['java'])"
}

Write-Section 'Profile append'
if ($AppendProfileSnippet) {
    Add-ProfileSnippet
} else {
    Write-Host 'Run with -ShowProfileSnippet to inspect append-only profile block.'
    Write-Host 'Run with -AppendProfileSnippet to append it once with marker detection.'
    Write-Host 'By default it avoids overriding cat/grep; add -AcceptProfileCommandOverrides to include those wrappers.'
}

Write-Section 'Terminal style acceptance'
Write-Host "Recommended Nerd Font: $($MigrationConfig.RecommendedNerdFont)"
Write-Host "Theme path: $($MigrationConfig.ThemePath)"
if (Test-Path -LiteralPath $MigrationConfig.ThemePath) {
    Write-Host '[OK] minimal.omp.json exists'
    Add-Summary Ok 'minimal.omp.json exists'
} else {
    Write-Host '[MISS] minimal.omp.json'
    Add-Summary Manual 'copy or recreate minimal.omp.json'
}
Write-Host 'Manual visual checks: prompt icons, Terminal-Icons output, Git branch icon, Windows Terminal font.'

Write-Section 'Summary'
foreach ($kind in $script:Summary.Keys) {
    Write-Host "[$kind] $($script:Summary[$kind].Count)"
    foreach ($item in $script:Summary[$kind]) {
        Write-Host "  - $item"
    }
}

Write-Section 'Recommended order'
Write-Host '1. Run terminal-setup for base beautification.'
Write-Host '2. Run restore.ps1 without switches.'
Write-Host '3. Review PATH preview, then run restore.ps1 -FixPath.'
Write-Host '4. Review package output, then run restore.ps1 -Install if needed.'
Write-Host '5. Run restore.ps1 -ApplyGitConfig.'
Write-Host '6. Run restore.ps1 -ShowProfileSnippet, then restore.ps1 -AppendProfileSnippet if acceptable.'
Write-Host '7. Close all terminals, reopen Windows Terminal, verify commands and visual style.'
