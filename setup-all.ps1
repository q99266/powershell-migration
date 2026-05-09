param(
    [switch]$UseChinaMirrors,
    [switch]$SkipTerminalSetup,
    [switch]$SkipProfileSnippet,
    [switch]$AcceptProfileCommandOverrides,
    [switch]$NoFinalAudit
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot = Split-Path -Parent $PSCommandPath
$MigrateScript = Join-Path $ScriptRoot 'migrate.ps1'

function Invoke-MigratePhase {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    Write-Host ''
    Write-Host "== $Name ==" -ForegroundColor Cyan
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$MigrateScript`" $($Arguments -join ' ')" -ForegroundColor DarkGray

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $MigrateScript @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Phase failed or requested attention: $Name (exit=$LASTEXITCODE)" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-RequiredMigratePhase {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    if (-not (Invoke-MigratePhase -Name $Name -Arguments $Arguments)) {
        Write-Host "[STOP] Stopping one-click sequence at phase: $Name" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $MigrateScript)) {
    Write-Host "[ERR] migrate.ps1 not found: $MigrateScript" -ForegroundColor Red
    exit 1
}

$mirrorArgs = @()
if ($UseChinaMirrors) { $mirrorArgs += '-UseChinaMirrors' }

Write-Host '== One-click PowerShell migration ==' -ForegroundColor Cyan
Write-Host "Project: $ScriptRoot"
Write-Host "PowerShell host: $($PSVersionTable.PSVersion)"
Write-Host ''

$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwsh -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host '[BOOTSTRAP] PowerShell 7 is missing or current host is not pwsh.' -ForegroundColor Yellow
    Write-Host '[BOOTSTRAP] Running migrate.ps1 -Install from the current host. This phase installs PowerShell 7 and then stops.' -ForegroundColor Yellow

    & powershell -NoProfile -ExecutionPolicy Bypass -File $MigrateScript -TestSyntax
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[STOP] Syntax preflight failed during bootstrap. exit=$LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $MigrateScript -Install @mirrorArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[STOP] PowerShell 7 bootstrap install phase failed. exit=$LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host ''
    Write-Host '[STOP] Open a new PowerShell 7 window, then run this script again:' -ForegroundColor Yellow
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($mirrorArgs -join ' ')" -ForegroundColor Cyan
    exit 0
}

Invoke-RequiredMigratePhase -Name 'Syntax preflight' -Arguments @('-TestSyntax')

if (-not $SkipTerminalSetup) {
    Invoke-RequiredMigratePhase -Name 'Bundled terminal-setup base beautification' -Arguments (@('-RunTerminalSetup') + $mirrorArgs)
} else {
    Write-Host ''
    Write-Host '== Bundled terminal-setup base beautification ==' -ForegroundColor Cyan
    Write-Host '[SKIP] SkipTerminalSetup was specified.' -ForegroundColor Yellow
}

Invoke-RequiredMigratePhase -Name 'Dry-run audit before install' -Arguments @()
Invoke-RequiredMigratePhase -Name 'Install missing tools and runtime managers' -Arguments (@('-Install') + $mirrorArgs)
Invoke-RequiredMigratePhase -Name 'Set Windows Terminal default profile to PowerShell 7' -Arguments @('-SetWindowsTerminalDefaultPwsh')
Invoke-RequiredMigratePhase -Name 'Install Nerd Font and set Windows Terminal font' -Arguments (@('-InstallNerdFont','-SetWindowsTerminalFont') + $mirrorArgs)
Invoke-RequiredMigratePhase -Name 'Persist User PATH ordering' -Arguments @('-FixPath')
Invoke-RequiredMigratePhase -Name 'Apply Git delta config' -Arguments @('-ApplyGitConfig')

if (-not $SkipProfileSnippet) {
    $profileArgs = @('-AppendProfileSnippet')
    if ($AcceptProfileCommandOverrides) { $profileArgs += '-AcceptProfileCommandOverrides' }
    Invoke-RequiredMigratePhase -Name 'Append PowerShell profile migration snippet' -Arguments $profileArgs
} else {
    Write-Host ''
    Write-Host '== Append PowerShell profile migration snippet ==' -ForegroundColor Cyan
    Write-Host '[SKIP] SkipProfileSnippet was specified.' -ForegroundColor Yellow
}

if (-not $NoFinalAudit) {
    Invoke-RequiredMigratePhase -Name 'Final dry-run audit' -Arguments @()
}

Write-Host ''
Write-Host '[DONE] One-click sequence finished.' -ForegroundColor Green
Write-Host 'Close all PowerShell / Windows Terminal windows, reopen Windows Terminal, then run docs/acceptance.md checks.' -ForegroundColor Yellow
