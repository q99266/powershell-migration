param(
    [switch]$Install,
    [switch]$FixPath,
    [switch]$ApplyGitConfig,
    [switch]$AppendProfileSnippet,
    [switch]$ShowProfileSnippet,
    [switch]$RunTerminalSetup,
    [switch]$SetWindowsTerminalDefaultPwsh,
    [switch]$InstallNerdFont,
    [switch]$SetWindowsTerminalFont,
    [switch]$AcceptProfileCommandOverrides,
    [switch]$UseChinaMirrors,
    [switch]$TestSyntax,
    [switch]$SkipSyntaxCheck
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot = Split-Path -Parent $PSCommandPath
$RestoreScript = Join-Path $ScriptRoot 'restore.ps1'

function Test-MigrationScriptSyntax {
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

if (-not (Test-Path -LiteralPath $RestoreScript)) {
    Write-Host "[ERR] restore.ps1 not found: $RestoreScript" -ForegroundColor Red
    exit 1
}

$syntaxFiles = @(
    (Join-Path $ScriptRoot 'migrate.ps1'),
    (Join-Path $ScriptRoot 'config.ps1'),
    $RestoreScript,
    (Join-Path $ScriptRoot 'restore-terminal-combined.ps1'),
    (Join-Path $ScriptRoot 'restore-draft.ps1')
) | Where-Object { Test-Path -LiteralPath $_ }

if ($TestSyntax) {
    if (Test-MigrationScriptSyntax -Paths $syntaxFiles) {
        exit 0
    }
    exit 1
}

if (-not $SkipSyntaxCheck -and -not $ShowProfileSnippet) {
    Write-Host '== Syntax preflight ==' -ForegroundColor Cyan
    if (-not (Test-MigrationScriptSyntax -Paths $syntaxFiles)) {
        Write-Host '[STOP] Syntax preflight failed. Fix parse errors before continuing.' -ForegroundColor Red
        exit 1
    }
}

& $RestoreScript `
    -Install:$Install `
    -FixPath:$FixPath `
    -ApplyGitConfig:$ApplyGitConfig `
    -AppendProfileSnippet:$AppendProfileSnippet `
    -ShowProfileSnippet:$ShowProfileSnippet `
    -RunTerminalSetup:$RunTerminalSetup `
    -SetWindowsTerminalDefaultPwsh:$SetWindowsTerminalDefaultPwsh `
    -InstallNerdFont:$InstallNerdFont `
    -SetWindowsTerminalFont:$SetWindowsTerminalFont `
    -AcceptProfileCommandOverrides:$AcceptProfileCommandOverrides `
    -UseChinaMirrors:$UseChinaMirrors
if ($?) {
    exit 0
}
exit 1
