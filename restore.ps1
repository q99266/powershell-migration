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
        (Join-Path $ScriptRoot 'migrate.ps1'),
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

function Get-WingetInstallArguments {
    param([string]$Id)

    $args = @(
        'install',
        '--id', $Id,
        '--accept-package-agreements',
        '--accept-source-agreements'
    )
    $source = $MigrationConfig.WingetSource
    if ([string]::IsNullOrWhiteSpace($source)) {
        return $args
    }
    return @($args + @('--source', $source))
}

function Get-NerdFontDownloadUrls {
    $urls = @()
    if ($UseChinaMirrors -and $MigrationConfig.NerdFontChinaMirrorUrls) {
        $urls += @($MigrationConfig.NerdFontChinaMirrorUrls)
    } else {
        $urls += @($MigrationConfig.NerdFontDownloadUrls)
    }
    return @($urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-OrderedDownloadUrls {
    param(
        [string[]]$DefaultUrls,
        [string[]]$ChinaMirrorUrls
    )

    $urls = @()
    if ($UseChinaMirrors -and $ChinaMirrorUrls) {
        $urls += @($ChinaMirrorUrls)
    } else {
        $urls += @($DefaultUrls)
    }
    return @($urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Invoke-DownloadWithFallback {
    param(
        [string[]]$Urls,
        [string]$OutFile
    )

    if (-not $Urls -or $Urls.Count -eq 0) {
        Write-Host '[WARN] No download URLs configured.' -ForegroundColor Yellow
        return $false
    }

    $timeoutSec = 90
    if ($MigrationConfig.DownloadTimeoutSec) {
        $timeoutSec = [int]$MigrationConfig.DownloadTimeoutSec
    }

    $lastError = $null
    foreach ($url in $Urls) {
        Write-Host "[RUN] Download: $url" -ForegroundColor Yellow
        try {
            if (Test-Path -LiteralPath $OutFile) {
                Remove-Item -LiteralPath $OutFile -Force
            }
            Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec $timeoutSec -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -gt 0)) {
                Write-Host "[OK] Downloaded: $url"
                return $true
            }
            $lastError = 'Downloaded file is missing or empty'
        } catch {
            $lastError = $_.Exception.Message
            Write-Host "[WARN] Download failed: $lastError" -ForegroundColor Yellow
        }
    }

    Write-Host "[WARN] All download URLs failed. Last error: $lastError" -ForegroundColor Yellow
    return $false
}

function Expand-ZipToDirectory {
    param(
        [string]$ZipPath,
        [string]$ExtractPath,
        [string]$TargetPath
    )

    if (Test-Path -LiteralPath $ExtractPath) {
        Remove-Item -LiteralPath $ExtractPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $root = Get-ChildItem -LiteralPath $ExtractPath -Directory | Select-Object -First 1
    if (-not $root) {
        throw "No extracted directory found in $ExtractPath"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetPath) | Out-Null
    if (Test-Path -LiteralPath $TargetPath) {
        Remove-Item -LiteralPath $TargetPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
    Copy-Item -Path (Join-Path $root.FullName '*') -Destination $TargetPath -Recurse -Force
}

function Set-CurrentRuntimeManagerEnvironment {
    if ($MigrationConfig.NvmRoot) { $env:NVM_HOME = $MigrationConfig.NvmRoot }
    if ($MigrationConfig.NvmSymlink) { $env:NVM_SYMLINK = $MigrationConfig.NvmSymlink }

    $runtimePaths = @(
        $MigrationConfig.NvmRoot,
        $MigrationConfig.NvmSymlink,
        $MigrationConfig.PyenvBinPath,
        $MigrationConfig.PyenvShimsPath,
        $MigrationConfig.JenvRoot
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    [array]::Reverse($runtimePaths)
    foreach ($path in $runtimePaths) {
        if ($env:Path -notlike "*$path*") {
            $env:Path = "$path;$env:Path"
        }
    }
}

function Ensure-NvmBaseline {
    $nvmExe = Join-Path $MigrationConfig.NvmRoot 'nvm.exe'
    if (-not (Test-Path -LiteralPath $nvmExe)) {
        Write-Host "[MISS] nvm -> $nvmExe" -ForegroundColor Yellow
        Add-Summary Missing 'nvm'
        if ($Install) {
            [void](Invoke-NativeWithRetry -FilePath 'winget' -Arguments @(
                'install',
                '--id', $MigrationConfig.NvmPackageId,
                '--location', $MigrationConfig.NvmRoot,
                '--accept-package-agreements',
                '--accept-source-agreements',
                '--source', $MigrationConfig.WingetSource
            ) -Label 'Install nvm-windows' -ShouldRun:$true -RetryCount $MigrationConfig.NetworkRetryCount)
        } else {
            Write-Host 'Run with -Install to install nvm-windows.'
            return
        }
    } else {
        Write-Host "[OK] nvm -> $nvmExe"
        Add-Summary Ok 'nvm present'
    }

    if (-not (Test-Path -LiteralPath $nvmExe)) {
        Write-Host '[WARN] nvm install did not produce nvm.exe yet. Reopen terminal and rerun if winget requested elevation.' -ForegroundColor Yellow
        Add-Summary Manual 'nvm install pending; rerun after installer completes'
        return
    }

    $settingsPath = Join-Path $MigrationConfig.NvmRoot 'settings.txt'
    $expectedSettings = @(
        "root: $($MigrationConfig.NvmRoot)",
        "path: $($MigrationConfig.NvmSymlink)",
        ''
    )
    $currentSettings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        $currentSettings = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction SilentlyContinue
    }
    $nvmHome = [Environment]::GetEnvironmentVariable('NVM_HOME', 'User')
    $nvmSymlink = [Environment]::GetEnvironmentVariable('NVM_SYMLINK', 'User')
    $needsNvmConfig = ($currentSettings -notmatch [regex]::Escape("root: $($MigrationConfig.NvmRoot)")) -or
        ($currentSettings -notmatch [regex]::Escape("path: $($MigrationConfig.NvmSymlink)")) -or
        ($nvmHome -ne $MigrationConfig.NvmRoot) -or
        ($nvmSymlink -ne $MigrationConfig.NvmSymlink)

    if ($needsNvmConfig) {
        if ($Install) {
            New-Item -ItemType Directory -Force -Path $MigrationConfig.NvmRoot | Out-Null
            Set-Content -LiteralPath $settingsPath -Value $expectedSettings -Encoding utf8
            [Environment]::SetEnvironmentVariable('NVM_HOME', $MigrationConfig.NvmRoot, 'User')
            [Environment]::SetEnvironmentVariable('NVM_SYMLINK', $MigrationConfig.NvmSymlink, 'User')
            Add-Summary Changed 'Configured nvm D: drive environment'
        } else {
            Write-Host '[WARN] nvm environment/settings differ from config.ps1. Run with -Install to persist the D: drive layout.' -ForegroundColor Yellow
            Add-Summary Manual 'nvm environment/settings need D: drive layout'
        }
    }
    Set-CurrentRuntimeManagerEnvironment

    $nodeVersion = $MigrationConfig.NvmNodeVersion
    $nodeVersionDir = Join-Path $MigrationConfig.NvmRoot "v$nodeVersion"
    if (-not (Test-Path -LiteralPath $nodeVersionDir)) {
        [void](Invoke-NativeWithRetry -FilePath $nvmExe -Arguments @('install', $nodeVersion) -Label "Install node $nodeVersion via nvm" -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount)
        if (-not $Install) { Add-Summary Missing "nvm node version $nodeVersion" }
    }
    if ($Install) {
        [void](Invoke-Native -FilePath $nvmExe -Arguments @('use', $nodeVersion) -Label "Use node $nodeVersion via nvm" -ShouldRun:$true)
        Set-CurrentRuntimeManagerEnvironment
    } elseif (Test-Path -LiteralPath $nodeVersionDir) {
        Add-Summary Ok "nvm node version $nodeVersion"
    }
}

function Ensure-PyenvBaseline {
    $pyenvCommand = Join-Path $MigrationConfig.PyenvBinPath 'pyenv.ps1'
    if (Test-Path -LiteralPath $pyenvCommand) {
        Write-Host "[OK] pyenv-win -> $($MigrationConfig.PyenvRoot)"
        Add-Summary Ok 'pyenv-win present'
        return
    }

    Write-Host "[MISS] pyenv-win -> $($MigrationConfig.PyenvRoot)" -ForegroundColor Yellow
    Add-Summary Missing 'pyenv-win'
    if (-not $Install) {
        Write-Host 'Run with -Install to download and install pyenv-win.'
        return
    }

    $urls = Get-OrderedDownloadUrls -DefaultUrls $MigrationConfig.PyenvDownloadUrls -ChinaMirrorUrls $MigrationConfig.PyenvChinaMirrorUrls
    $zipPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.PyenvDownloadPath)
    $extractPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.PyenvExtractPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zipPath) | Out-Null
    if (-not (Invoke-DownloadWithFallback -Urls $urls -OutFile $zipPath)) {
        Add-Summary Failed 'pyenv-win download failed from all built-in sources'
        return
    }
    try {
        Expand-ZipToDirectory -ZipPath $zipPath -ExtractPath $extractPath -TargetPath $MigrationConfig.PyenvProjectRoot
        Write-Host "[OK] Installed pyenv-win: $($MigrationConfig.PyenvRoot)"
        Add-Summary Changed 'Installed pyenv-win'
    } catch {
        Write-Host "[WARN] pyenv-win install failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Add-Summary Failed "pyenv-win install failed: $($_.Exception.Message)"
    }
}

function Ensure-JenvBaseline {
    $jenvBat = Join-Path $MigrationConfig.JenvRoot 'jenv.bat'
    if (Test-Path -LiteralPath $jenvBat) {
        Write-Host "[OK] jenv -> $jenvBat"
        Add-Summary Ok 'jenv present'
        return
    }

    Write-Host "[MISS] jenv -> $jenvBat" -ForegroundColor Yellow
    Add-Summary Missing 'jenv'
    if (-not $Install) {
        Write-Host 'Run with -Install to download and install JEnv for Windows.'
        return
    }

    $urls = Get-OrderedDownloadUrls -DefaultUrls $MigrationConfig.JenvDownloadUrls -ChinaMirrorUrls $MigrationConfig.JenvChinaMirrorUrls
    $zipPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.JenvDownloadPath)
    $extractPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.JenvExtractPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zipPath) | Out-Null
    if (-not (Invoke-DownloadWithFallback -Urls $urls -OutFile $zipPath)) {
        Add-Summary Failed 'jenv download failed from all built-in sources'
        return
    }
    try {
        Expand-ZipToDirectory -ZipPath $zipPath -ExtractPath $extractPath -TargetPath $MigrationConfig.JenvRoot
        Write-Host "[OK] Installed jenv: $($MigrationConfig.JenvRoot)"
        Add-Summary Changed 'Installed jenv'
    } catch {
        Write-Host "[WARN] jenv install failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Add-Summary Failed "jenv install failed: $($_.Exception.Message)"
    }
}

function Test-FontInstalled {
    param([string]$FontName)

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $families = [System.Drawing.Text.InstalledFontCollection]::new().Families
        return [bool]($families | Where-Object { $_.Name -eq $FontName } | Select-Object -First 1)
    } catch {
        Write-Host "[WARN] Failed to inspect installed fonts: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Install-NerdFont {
    $fontName = $MigrationConfig.NerdFontName
    if (Test-FontInstalled -FontName $fontName) {
        Write-Host "[OK] Nerd Font already installed: $fontName"
        Add-Summary Ok "Nerd Font installed: $fontName"
        return
    }

    if (-not $InstallNerdFont) {
        Write-Host "[MISS] Nerd Font not installed: $fontName" -ForegroundColor Yellow
        Write-Host 'Run with -InstallNerdFont to download and install it for current user.'
        Add-Summary Missing "Nerd Font $fontName"
        return
    }

    $urls = Get-NerdFontDownloadUrls
    $zipPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.NerdFontDownloadPath)
    $extractPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.NerdFontExtractPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zipPath) | Out-Null
    New-Item -ItemType Directory -Force -Path $extractPath | Out-Null

    try {
        Write-Host "[INFO] Using built-in Nerd Font download sources: $($urls.Count)"
        if (-not (Invoke-DownloadWithFallback -Urls $urls -OutFile $zipPath)) {
            Add-Summary Failed 'Nerd Font download failed from all built-in sources'
            return
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    } catch {
        Write-Host "[WARN] Nerd Font download/extract failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Add-Summary Failed "Nerd Font download/extract failed: $($_.Exception.Message)"
        return
    }

    $fontFiles = Get-ChildItem -LiteralPath $extractPath -Recurse -File |
        Where-Object { $_.Extension -in @('.ttf','.otf') -and $_.Name -match 'CaskaydiaCove|NerdFont|Nerd Font' }
    if (-not $fontFiles) {
        Write-Host '[WARN] No Nerd Font .ttf/.otf files found after extraction.' -ForegroundColor Yellow
        Add-Summary Failed 'No Nerd Font files found after extraction'
        return
    }

    $fontsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $fontsDir | Out-Null
    foreach ($font in $fontFiles) {
        $target = Join-Path $fontsDir $font.Name
        Copy-Item -LiteralPath $font.FullName -Destination $target -Force
        $regName = $font.BaseName + ' (TrueType)'
        New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $regName -Value $target -PropertyType String -Force | Out-Null
    }

    Write-Host "[OK] Installed Nerd Font files for current user: $($fontFiles.Count)"
    Add-Summary Changed "Installed Nerd Font files: $($fontFiles.Count)"
}

function Set-WindowsTerminalDefaultFont {
    $state = Get-WindowsTerminalState
    if (-not $state.Found) {
        Write-Host "[WARN] Cannot update Windows Terminal font: $($state.Error)" -ForegroundColor Yellow
        Add-Summary Manual "Windows Terminal font not updated: $($state.Error)"
        return
    }

    if (-not $SetWindowsTerminalFont) {
        Write-Host "Run with -SetWindowsTerminalFont to set Windows Terminal default font to $($MigrationConfig.NerdFontName)."
        return
    }

    if ((-not $InstallNerdFont) -and (-not (Test-FontInstalled -FontName $MigrationConfig.NerdFontName))) {
        Write-Host "[WARN] Refusing to set Windows Terminal font because it is not installed: $($MigrationConfig.NerdFontName)" -ForegroundColor Yellow
        Write-Host 'Run with -InstallNerdFont -SetWindowsTerminalFont to download, install, and apply it in one pass.'
        Add-Summary Manual "Install Nerd Font before setting Windows Terminal font: $($MigrationConfig.NerdFontName)"
        return
    }

    New-Item -ItemType Directory -Force -Path $MigrationConfig.BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $MigrationConfig.BackupRoot "windows-terminal-settings-font-$stamp.json"
    Copy-Item -LiteralPath $state.Path -Destination $backupFile -Force

    $settings = Get-Content -LiteralPath $state.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{}) -Force
    }
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value ([pscustomobject]@{}) -Force
    }
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value ([pscustomobject]@{}) -Force
    }
    $settings.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name face -Value $MigrationConfig.NerdFontName -Force
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $state.Path -Encoding utf8
    Write-Host "[OK] Windows Terminal default font set to $($MigrationConfig.NerdFontName). Backup: $backupFile" -ForegroundColor Green
    Add-Summary Changed "Windows Terminal default font set: $($MigrationConfig.NerdFontName)"
}

function Get-NpmInstallArguments {
    param([string]$Package)

    $argumentSets = @()
    $defaultArgs = @('install','-g',$Package)
    $configuredArgs = $defaultArgs
    if (-not [string]::IsNullOrWhiteSpace($MigrationConfig.NpmRegistry)) {
        $configuredArgs = @('install','-g',$Package,'--registry',$MigrationConfig.NpmRegistry)
    }
    $mirrorArgs = $null
    if (-not [string]::IsNullOrWhiteSpace($MigrationConfig.NpmChinaMirror)) {
        $mirrorArgs = @('install','-g',$Package,'--registry',$MigrationConfig.NpmChinaMirror)
    }

    if ($UseChinaMirrors) {
        if ($mirrorArgs) { $argumentSets += ,$mirrorArgs }
        $argumentSets += ,$configuredArgs
    } else {
        $argumentSets += ,$configuredArgs
        if ($mirrorArgs) { $argumentSets += ,$mirrorArgs }
    }

    return $argumentSets
}

function Invoke-NativeWithRetry {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label,
        [switch]$ShouldRun,
        [int]$RetryCount = 1
    )

    if (-not $ShouldRun) {
        return (Invoke-Native -FilePath $FilePath -Arguments $Arguments -Label $Label -ShouldRun:$false)
    }

    $attempts = [Math]::Max(1, $RetryCount)
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $attemptLabel = $Label
        if ($attempts -gt 1) {
            $attemptLabel = "$Label (attempt $attempt/$attempts)"
        }
        if (Invoke-Native -FilePath $FilePath -Arguments $Arguments -Label $attemptLabel -ShouldRun:$true) {
            return $true
        }
        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

function Invoke-NativeWithFallback {
    param(
        [string]$FilePath,
        [object[]]$ArgumentSets,
        [string]$Label,
        [switch]$ShouldRun,
        [int]$RetryCount = 1
    )

    if (-not $ArgumentSets -or $ArgumentSets.Count -eq 0) {
        Write-Host "[WARN] No command candidates configured for $Label" -ForegroundColor Yellow
        Add-Summary Failed "No command candidates configured for $Label"
        return $false
    }

    if (-not $ShouldRun) {
        Write-Host "[TODO] $Label" -ForegroundColor Yellow
        foreach ($arguments in $ArgumentSets) {
            Write-Host "      $FilePath $($arguments -join ' ')"
        }
        return $true
    }

    foreach ($arguments in $ArgumentSets) {
        if (Invoke-NativeWithRetry -FilePath $FilePath -Arguments ([string[]]$arguments) -Label $Label -ShouldRun:$true -RetryCount $RetryCount) {
            return $true
        }
        Write-Host "[WARN] Candidate failed, trying next fallback for $Label" -ForegroundColor Yellow
    }
    Add-Summary Failed "$Label failed across all fallback candidates"
    return $false
}

function Get-PowerShellModuleInstallArguments {
    param([string]$Name)

    $gallery = $MigrationConfig.PowerShellGallery
    if ([string]::IsNullOrWhiteSpace($gallery)) {
        $gallery = 'PSGallery'
    }
    $command = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
Set-PSRepository -Name '$gallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
Install-Module -Name '$Name' -Repository '$gallery' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
"@
    return @('-NoProfile','-Command',$command)
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
        return [pscustomobject]@{
            Succeeded = $false
            Packages = @{}
            Error = 'npm is missing'
        }
    }

    try {
        $json = (& npm list -g --depth=0 --json 2>$null) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($json)) {
            return [pscustomobject]@{
                Succeeded = $false
                Packages = @{}
                Error = 'npm list returned empty output'
            }
        }

        $parsed = $json | ConvertFrom-Json
        $map = @{}
        if ($parsed.dependencies) {
            $parsed.dependencies.PSObject.Properties | ForEach-Object {
                $map[$_.Name] = $_.Value.version
            }
        }
        return [pscustomobject]@{
            Succeeded = $true
            Packages = $map
            Error = $null
        }
    } catch {
        return [pscustomobject]@{
            Succeeded = $false
            Packages = @{}
            Error = $_.Exception.Message
        }
    }
}

function Get-WindowsTerminalState {
    $settingsPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.WindowsTerminalSettingsPath)
    $wtCommand = Get-Command wt -ErrorAction SilentlyContinue
    $wtCommandFound = [bool]$wtCommand
    $wtCommandSource = $null
    if ($wtCommand) {
        $wtCommandSource = $wtCommand.Source
    }
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return [pscustomobject]@{
            Found = $false
            CommandFound = $wtCommandFound
            CommandSource = $wtCommandSource
            Path = $settingsPath
            SettingsExists = $false
            DefaultGuid = $null
            PwshGuid = $null
            PwshName = $null
            IsDefaultPwsh = $false
            Error = 'Windows Terminal settings.json not found'
        }
    }

    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profiles = @()
        if ($settings.profiles -and $settings.profiles.list) {
            $profiles = @($settings.profiles.list)
        }

        $pwshProfile = $profiles |
            Where-Object {
                ($_.commandline -match 'pwsh(\.exe)?') -or
                ($_.source -eq 'Windows.Terminal.PowershellCore') -or
                ($_.name -match $MigrationConfig.WindowsTerminalPwshProfileNamePattern)
            } |
            Select-Object -First 1

        $pwshGuid = $null
        $pwshName = $null
        if ($pwshProfile) {
            $pwshGuid = $pwshProfile.guid
            $pwshName = $pwshProfile.name
        } elseif ($MigrationConfig.WindowsTerminalPwshFallbackGuid) {
            $pwshGuid = $MigrationConfig.WindowsTerminalPwshFallbackGuid
            $pwshName = 'PowerShell 7'
        }

        return [pscustomobject]@{
            Found = $true
            CommandFound = $wtCommandFound
            CommandSource = $wtCommandSource
            Path = $settingsPath
            SettingsExists = $true
            DefaultGuid = $settings.defaultProfile
            PwshGuid = $pwshGuid
            PwshName = $pwshName
            IsDefaultPwsh = ($pwshGuid -and $settings.defaultProfile -eq $pwshGuid)
            Error = $null
        }
    } catch {
        return [pscustomobject]@{
            Found = $false
            CommandFound = $wtCommandFound
            CommandSource = $wtCommandSource
            Path = $settingsPath
            SettingsExists = (Test-Path -LiteralPath $settingsPath)
            DefaultGuid = $null
            PwshGuid = $null
            PwshName = $null
            IsDefaultPwsh = $false
            Error = $_.Exception.Message
        }
    }
}

function New-MinimalWindowsTerminalSettings {
    $settingsPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.WindowsTerminalSettingsPath)
    $settingsDir = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

    $settings = [ordered]@{
        '$schema' = 'https://aka.ms/terminal-profiles-schema'
        defaultProfile = $MigrationConfig.WindowsTerminalPwshFallbackGuid
        profiles = [ordered]@{
            defaults = [ordered]@{
                font = [ordered]@{
                    face = $MigrationConfig.NerdFontName
                }
            }
        }
    }
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding utf8
    Write-Host "[OK] Created minimal Windows Terminal settings: $settingsPath" -ForegroundColor Green
    Add-Summary Changed 'Created minimal Windows Terminal settings.json'
}

function Ensure-WindowsTerminalBaseline {
    $wtCommand = Get-Command wt -ErrorAction SilentlyContinue
    if ($wtCommand) {
        Write-Host "[OK] wt -> $($wtCommand.Source)"
        Add-Summary Ok "wt -> $($wtCommand.Source)"
    } else {
        Write-Host '[MISS] Windows Terminal command: wt' -ForegroundColor Yellow
        Add-Summary Missing 'Windows Terminal'
        $installed = Invoke-NativeWithRetry -FilePath 'winget' -Arguments (Get-WingetInstallArguments -Id $MigrationConfig.WindowsTerminalPackageId) -Label 'Install Windows Terminal' -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount
        $wtCommand = Get-Command wt -ErrorAction SilentlyContinue
        if (-not $wtCommand -and $Install -and -not $installed) {
            Write-Host '[WARN] Windows Terminal install failed; settings bootstrap skipped.' -ForegroundColor Yellow
            Add-Summary Failed 'Windows Terminal install failed; settings bootstrap skipped'
            return
        }
    }

    $settingsPath = [Environment]::ExpandEnvironmentVariables($MigrationConfig.WindowsTerminalSettingsPath)
    if (Test-Path -LiteralPath $settingsPath) {
        return
    }

    if ($Install) {
        New-MinimalWindowsTerminalSettings
        Write-Host '[WARN] Windows Terminal may need a fresh process after first install before wt is visible in PATH.' -ForegroundColor Yellow
        Add-Summary Manual 'Reopen Windows Terminal after first install if wt is still unavailable in this process'
    } else {
        Write-Host "[WARN] Windows Terminal settings.json not found: $settingsPath" -ForegroundColor Yellow
        Write-Host 'Run with -Install to install Windows Terminal and create a minimal settings.json.'
        Add-Summary Manual 'Windows Terminal settings.json missing; run migrate.ps1 -Install'
    }
}

function Set-WindowsTerminalDefaultPwshProfile {
    $state = Get-WindowsTerminalState
    if (-not $state.Found) {
        Write-Host "[WARN] Cannot update Windows Terminal default profile: $($state.Error)" -ForegroundColor Yellow
        Add-Summary Manual "Windows Terminal default profile not updated: $($state.Error)"
        return
    }
    if (-not $state.PwshGuid) {
        Write-Host '[WARN] No PowerShell 7 profile found in Windows Terminal settings.' -ForegroundColor Yellow
        Add-Summary Manual 'Windows Terminal PowerShell 7 profile missing'
        return
    }
    if ($state.IsDefaultPwsh) {
        Write-Host "[OK] Windows Terminal default profile is already PowerShell 7: $($state.PwshName)"
        Add-Summary Ok 'Windows Terminal default profile is PowerShell 7'
        return
    }

    New-Item -ItemType Directory -Force -Path $MigrationConfig.BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $MigrationConfig.BackupRoot "windows-terminal-settings-$stamp.json"
    Copy-Item -LiteralPath $state.Path -Destination $backupFile -Force

    $settings = Get-Content -LiteralPath $state.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $settings.defaultProfile = $state.PwshGuid
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $state.Path -Encoding utf8
    Write-Host "[OK] Windows Terminal default profile set to PowerShell 7: $($state.PwshName). Backup: $backupFile" -ForegroundColor Green
    Add-Summary Changed "Windows Terminal default profile set to PowerShell 7; backup: $backupFile"
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

function Update-CurrentProcessPathFromRegistry {
    $userPath = Split-PathList ([Environment]::GetEnvironmentVariable('Path', 'User'))
    $machinePath = Split-PathList ([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $currentPath = Split-PathList $env:Path
    $plannedFirst = @($MigrationConfig.PreferredPathFirst | ForEach-Object { Normalize-PathEntry $_ } | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

    $env:Path = (($plannedFirst + $userPath + $machinePath + $currentPath) | Select-Object -Unique) -join ';'
    Set-CurrentRuntimeManagerEnvironment
    Write-Host '[OK] Current process PATH refreshed from User/Machine PATH.'
    Write-Host '[WARN] Some winget installers only become visible after reopening PowerShell 7 / Windows Terminal.' -ForegroundColor Yellow
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
Write-Host "SetWindowsTerminalDefaultPwsh: $SetWindowsTerminalDefaultPwsh"
Write-Host "InstallNerdFont: $InstallNerdFont"
Write-Host "SetWindowsTerminalFont: $SetWindowsTerminalFont"
Write-Host "UseChinaMirrors: $UseChinaMirrors"
Write-Host 'Default mode audits only.'
Write-Host 'Run with -TestSyntax first on a new machine if profile/script parsing looks suspicious.'
if (Test-Path -LiteralPath 'D:\') {
    Write-Host 'Path layout: using default D: drive layout from config.ps1.'
} else {
    Write-Host '[WARN] D: drive not found. Review config.ps1 before installing or fixing PATH.' -ForegroundColor Yellow
    Add-Summary Manual 'D: drive missing; review config.ps1 path layout'
}
if ($UseChinaMirrors) {
    Write-Host "NPM registry override: $($MigrationConfig.NpmChinaMirror)"
    Write-Host 'NPM install fallback order: npmmirror first, then configured/default registry.'
    Write-Host 'Winget source is still the configured winget source; winget has no project-managed domestic mirror here.'
} else {
    Write-Host 'NPM install fallback order: configured/default registry first, then npmmirror.'
}

Write-Section 'Official entry'
Write-Host 'Formal entry script: migrate.ps1'
Write-Host 'Internal restore implementation: restore.ps1'
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

Write-Section 'PowerShell 7 baseline'
$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
$requiresPwshRerun = $false
if ($pwshCommand) {
    Write-Host "[OK] pwsh -> $($pwshCommand.Source)"
    Add-Summary Ok "pwsh -> $($pwshCommand.Source)"
} else {
    Write-Host '[MISS] pwsh' -ForegroundColor Yellow
    Add-Summary Missing 'pwsh'
    [void](Invoke-NativeWithRetry -FilePath 'winget' -Arguments (Get-WingetInstallArguments -Id 'Microsoft.PowerShell') -Label 'Install PowerShell 7' -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount)
    $requiresPwshRerun = $true
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host '[WARN] Current host is not PowerShell 7. Install PowerShell 7, then rerun with pwsh.' -ForegroundColor Yellow
    Add-Summary Manual "Current host is PowerShell $($PSVersionTable.PSVersion), not PowerShell 7"
    $requiresPwshRerun = $true
}
if ($Install -and $requiresPwshRerun) {
    Write-Host '[STOP] Bootstrap phase complete or required. Open a new PowerShell 7 (pwsh) session and rerun migrate.ps1 for modules/profile/tools.' -ForegroundColor Yellow
    Add-Summary Manual 'Rerun from a new PowerShell 7 session before continuing'
    Write-Section 'Summary'
    foreach ($kind in $script:Summary.Keys) {
        Write-Host "[$kind] $($script:Summary[$kind].Count)"
        foreach ($item in $script:Summary[$kind]) {
            Write-Host "  - $item"
        }
    }
    return
}

Write-Section 'Windows Terminal baseline'
Ensure-WindowsTerminalBaseline

Write-Section 'Windows Terminal default shell'
$wtState = Get-WindowsTerminalState
if (-not $wtState.Found) {
    Write-Host "[WARN] Windows Terminal settings not available: $($wtState.Error)" -ForegroundColor Yellow
    Add-Summary Manual "Windows Terminal settings unavailable: $($wtState.Error)"
} elseif (-not $wtState.PwshGuid) {
    Write-Host '[WARN] No PowerShell 7 profile found in Windows Terminal settings.' -ForegroundColor Yellow
    Add-Summary Manual 'Windows Terminal PowerShell 7 profile missing'
} elseif ($wtState.IsDefaultPwsh) {
    Write-Host "[OK] Windows Terminal default profile is PowerShell 7: $($wtState.PwshName)"
    Add-Summary Ok 'Windows Terminal default profile is PowerShell 7'
} else {
    Write-Host "[WARN] Windows Terminal default profile is not PowerShell 7. Current default: $($wtState.DefaultGuid); PowerShell 7: $($wtState.PwshName) $($wtState.PwshGuid)" -ForegroundColor Yellow
    Add-Summary Manual 'Windows Terminal default profile is not PowerShell 7'
    if ($SetWindowsTerminalDefaultPwsh) {
        Set-WindowsTerminalDefaultPwshProfile
    } else {
        Write-Host 'Run with -SetWindowsTerminalDefaultPwsh to persist this change after reviewing settings.'
    }
}

Write-Section 'PATH audit'
$pathPlan = Get-PathPlan
Show-PathPlan -Plan $pathPlan
if ($FixPath) {
    Set-UserPathFromPlan -Plan $pathPlan
} else {
    Write-Host 'Run with -FixPath to persist User PATH ordering.'
}

Write-Section 'Runtime version managers'
Ensure-NvmBaseline
Ensure-PyenvBaseline
Ensure-JenvBaseline
Set-CurrentRuntimeManagerEnvironment

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
$wingetInstallAttempted = $false
foreach ($pkg in $MigrationConfig.WingetPackages) {
    if ($pkg.Command -and (Test-CommandExists $pkg.Command)) {
        Write-Host "[OK] $($pkg.Command)"
        Add-Summary Ok "winget command present: $($pkg.Command)"
    } else {
        if ($Install) { $wingetInstallAttempted = $true }
        [void](Invoke-NativeWithRetry -FilePath 'winget' -Arguments (Get-WingetInstallArguments -Id $pkg.Id) -Label "Install $($pkg.Id)" -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount)
        if (-not $Install) { Add-Summary Missing "winget package candidate: $($pkg.Id)" }
    }
}
if ($wingetInstallAttempted) {
    Update-CurrentProcessPathFromRegistry
    foreach ($pkg in $MigrationConfig.WingetPackages | Where-Object { $_.Command }) {
        if (Test-CommandExists $pkg.Command) {
            Write-Host "[OK] visible after PATH refresh: $($pkg.Command)"
            Add-Summary Ok "winget command visible after PATH refresh: $($pkg.Command)"
        } else {
            Write-Host "[WARN] still not visible in current process: $($pkg.Command). Reopen PowerShell 7 and rerun migrate.ps1." -ForegroundColor Yellow
            Add-Summary Manual "reopen PowerShell 7 and rerun for command: $($pkg.Command)"
        }
    }
}

Write-Section 'PowerShell modules'
foreach ($module in $MigrationConfig.PowerShellModules) {
    $state = Test-ModuleAvailableCompat -Name $module.Name
    if ($state.Found) {
        Write-Host "[OK] module $($module.Name) -> $($state.Path)"
        Add-Summary Ok "module $($module.Name)"
    } else {
        [void](Invoke-NativeWithRetry -FilePath 'pwsh' -Arguments (Get-PowerShellModuleInstallArguments -Name $module.Name) -Label "Install module $($module.Name)" -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount)
        if (-not $Install) { Add-Summary Missing "module $($module.Name)" }
    }
}

Write-Section 'npm global packages'
if (Test-CommandExists npm) {
    $npmInspection = Get-NpmGlobalPackageMap
    if (-not $npmInspection.Succeeded) {
        Write-Host "[WARN] Failed to inspect npm global packages: $($npmInspection.Error)" -ForegroundColor Yellow
        Write-Host '[WARN] Skipping npm global package installation to avoid accidental mass upgrades.' -ForegroundColor Yellow
        Add-Summary Manual 'npm global package inspection failed; skipped npm install stage'
    } else {
        $npmGlobal = $npmInspection.Packages
        foreach ($pkg in $MigrationConfig.NpmGlobalPackages) {
            if ($npmGlobal.ContainsKey($pkg)) {
                Write-Host "[OK] npm global package $pkg@$($npmGlobal[$pkg])"
                Add-Summary Ok "npm global package $pkg"
            } else {
                [void](Invoke-NativeWithFallback -FilePath 'npm' -ArgumentSets (Get-NpmInstallArguments -Package $pkg) -Label "Install missing npm global package $pkg" -ShouldRun:$Install -RetryCount $MigrationConfig.NetworkRetryCount)
                if (-not $Install) { Add-Summary Missing "npm global package $pkg" }
            }
        }
    }
} else {
    Write-Host '[WARN] npm is missing. Install/activate Node.js with nvm first.'
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
Write-Host 'Java mode: installs/checks JEnv manager, but does not force a specific JDK version.'
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
Install-NerdFont
Set-WindowsTerminalDefaultFont
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
Write-Host '2. Run migrate.ps1 without switches.'
Write-Host '3. Review package output, then run migrate.ps1 -Install if needed.'
Write-Host '4. If needed, run migrate.ps1 -SetWindowsTerminalDefaultPwsh.'
Write-Host '5. Run migrate.ps1 -InstallNerdFont -SetWindowsTerminalFont if needed.'
Write-Host '6. Review PATH preview, then run migrate.ps1 -FixPath.'
Write-Host '7. Run migrate.ps1 -ApplyGitConfig.'
Write-Host '8. Run migrate.ps1 -ShowProfileSnippet, then migrate.ps1 -AppendProfileSnippet if acceptable.'
Write-Host '9. Close all terminals, reopen Windows Terminal, verify commands and visual style.'
