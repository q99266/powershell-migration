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
    & powershell -NoProfile -ExecutionPolicy Bypass -File $MigrateScript -Install @mirrorArgs

    Write-Host ''
    Write-Host '[STOP] Open a new PowerShell 7 window, then run this script again:' -ForegroundColor Yellow
    Write-Host "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $($mirrorArgs -join ' ')" -ForegroundColor Cyan
    exit 0
}

[void](Invoke-MigratePhase -Name 'Syntax preflight' -Arguments @('-TestSyntax'))

if (-not $SkipTerminalSetup) {
    [void](Invoke-MigratePhase -Name 'Bundled terminal-setup base beautification' -Arguments (@('-RunTerminalSetup') + $mirrorArgs))
} else {
    Write-Host ''
    Write-Host '== Bundled terminal-setup base beautification ==' -ForegroundColor Cyan
    Write-Host '[SKIP] SkipTerminalSetup was specified.' -ForegroundColor Yellow
}

[void](Invoke-MigratePhase -Name 'Dry-run audit before install' -Arguments @())
[void](Invoke-MigratePhase -Name 'Install missing tools and runtime managers' -Arguments (@('-Install') + $mirrorArgs))
[void](Invoke-MigratePhase -Name 'Set Windows Terminal default profile to PowerShell 7' -Arguments @('-SetWindowsTerminalDefaultPwsh'))
[void](Invoke-MigratePhase -Name 'Install Nerd Font and set Windows Terminal font' -Arguments (@('-InstallNerdFont','-SetWindowsTerminalFont') + $mirrorArgs))
[void](Invoke-MigratePhase -Name 'Persist User PATH ordering' -Arguments @('-FixPath'))
[void](Invoke-MigratePhase -Name 'Apply Git delta config' -Arguments @('-ApplyGitConfig'))

if (-not $SkipProfileSnippet) {
    $profileArgs = @('-AppendProfileSnippet')
    if ($AcceptProfileCommandOverrides) { $profileArgs += '-AcceptProfileCommandOverrides' }
    [void](Invoke-MigratePhase -Name 'Append PowerShell profile migration snippet' -Arguments $profileArgs)
} else {
    Write-Host ''
    Write-Host '== Append PowerShell profile migration snippet ==' -ForegroundColor Cyan
    Write-Host '[SKIP] SkipProfileSnippet was specified.' -ForegroundColor Yellow
}

if (-not $NoFinalAudit) {
    [void](Invoke-MigratePhase -Name 'Final dry-run audit' -Arguments @())
}

Write-Host ''
Write-Host '[DONE] One-click sequence finished.' -ForegroundColor Green
Write-Host 'Close all PowerShell / Windows Terminal windows, reopen Windows Terminal, then run docs/acceptance.md checks.' -ForegroundColor Yellow
