# Windows Terminal Minimalist Beautification Script
# Author: Cascade AI Assistant
# Features: Auto install and configure Windows Terminal + Oh My Posh + Dracula Theme
# Encoding: UTF-8 with BOM

# Temporarily allow script execution (bypass execution policy)
$currentPolicy = Get-ExecutionPolicy -Scope Process
if ($currentPolicy -ne 'Bypass' -and $currentPolicy -ne 'Unrestricted') {
    try {
        $null = Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
    } catch {
        # Silently ignore if setting fails
    }
}

function Split-PathEntries {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return @($PathValue -split ';' | ForEach-Object {
        $entry = [Environment]::ExpandEnvironmentVariables($_.Trim())
        if ($entry.Length -gt 3) { $entry = $entry.TrimEnd('\') }
        $entry
    } | Where-Object { $_ } | Select-Object -Unique)
}

function Update-CurrentProcessPath {
    $machinePath = Split-PathEntries ([Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath = Split-PathEntries ([Environment]::GetEnvironmentVariable('Path', 'User'))
    $currentPath = Split-PathEntries $env:Path
    $knownAliasPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\WindowsApps')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $env:Path = (($machinePath + $userPath + $knownAliasPaths + $currentPath) | Select-Object -Unique) -join ';'
    Write-Host "[OK] Current process PATH refreshed" -ForegroundColor Green
}

function Resolve-Command {
    param([string]$Name)
    return (Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows Terminal Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 0: Compatibility Check
Write-Host "[*] Step 0: Compatibility Check..." -ForegroundColor Green

# Check OS Version
$osVersion = [Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    Write-Host "[ERROR] ERROR: This script only supports Windows 10 (1903+) or Windows 11." -ForegroundColor Red
    Write-Host "   Windows Terminal is NOT officially supported on Windows 7." -ForegroundColor Yellow
    Write-Host "   Solution: If you are on Win7, please follow the manual guide for PS 5.1 only." -ForegroundColor Cyan
    Write-Host "   See: MANUAL-PLUGIN-INSTALLATION.md" -ForegroundColor Gray
    Write-Host ""
    pause
    exit
}

# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[ERROR] ERROR: PowerShell version is too low ($($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host "   This script requires PS 5.1+ features (like Expand-Archive)." -ForegroundColor Yellow
    Write-Host "   Please upgrade to PowerShell 5.1 or install PowerShell 7." -ForegroundColor Cyan
    Write-Host ""
    pause
    exit
}

Write-Host "[OK] OS Version: $([Environment]::OSVersion) (Compatible)" -ForegroundColor Gray
Write-Host "[OK] PowerShell Version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) (Compatible)" -ForegroundColor Gray
Write-Host ""

# Check for special characters in path
$scriptPath = $PSScriptRoot
if ($scriptPath -match '[^\x00-\x7F]') {
    Write-Host "[WARN] WARNING: Script path contains non-ASCII characters" -ForegroundColor Yellow
    Write-Host "Current path: $scriptPath" -ForegroundColor Gray
    Write-Host "Recommend moving script to English path (e.g., C:\temp\) to avoid encoding issues" -ForegroundColor Cyan
    Write-Host ""
    $continue = Read-Host "Continue execution? (Y/N)"
    if ($continue -ne 'Y' -and $continue -ne 'y') {
        Write-Host "Script terminated" -ForegroundColor Red
        exit
    }
}
Write-Host ""

# Check network connection and proxy settings
Write-Host "[NET] Checking network connection..." -ForegroundColor Yellow
try {
    $testConnection = Test-Connection -ComputerName "github.com" -Count 1 -Quiet -ErrorAction Stop
} catch {
    $testConnection = $false
    Write-Host "   Network test failed, proxy may be needed" -ForegroundColor Gray
}

if (!$testConnection) {
    Write-Host "[WARN] WARNING: Cannot connect to GitHub, proxy may be needed" -ForegroundColor Yellow
    Write-Host ""
    $useProxy = Read-Host "Do you need to set up a proxy? (Y/N)"

    if ($useProxy -eq 'Y' -or $useProxy -eq 'y') {
        Write-Host ""
        Write-Host "Select proxy scope:" -ForegroundColor Cyan
        Write-Host "1. Current session only (temporary, recommended)" -ForegroundColor White
        Write-Host "2. System-wide (persistent)" -ForegroundColor White
        Write-Host ""
        $proxyScope = Read-Host "Please select (1/2)"

        Write-Host ""
        Write-Host "Select proxy type:" -ForegroundColor Cyan
        Write-Host "1. Common proxy (127.0.0.1:7890)" -ForegroundColor White
        Write-Host "2. Common proxy (127.0.0.1:1080)" -ForegroundColor White
        Write-Host "3. Custom proxy address" -ForegroundColor White
        Write-Host ""
        $proxyChoice = Read-Host "Please select (1/2/3)"

        switch ($proxyChoice) {
            "1" { $proxyUrl = "http://127.0.0.1:7890" }
            "2" { $proxyUrl = "http://127.0.0.1:1080" }
            "3" {
                Write-Host "Enter proxy address (e.g., http://127.0.0.1:7890)" -ForegroundColor Cyan
                $proxyUrl = Read-Host "Proxy address"
            }
            default {
                Write-Host "Invalid selection, skipping proxy setup" -ForegroundColor Yellow
                $proxyUrl = $null
            }
        }

        if ($proxyUrl) {
            if ($proxyScope -eq "1") {
                $env:http_proxy = $proxyUrl
                $env:https_proxy = $proxyUrl
                $env:HTTP_PROXY = $proxyUrl
                $env:HTTPS_PROXY = $proxyUrl

                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyUrl)
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

                Write-Host "[OK] Temporary proxy set: $proxyUrl" -ForegroundColor Green
                Write-Host "   (Valid only for current session)" -ForegroundColor Gray
            } else {
                $env:http_proxy = $proxyUrl
                $env:https_proxy = $proxyUrl
                $env:HTTP_PROXY = $proxyUrl
                $env:HTTPS_PROXY = $proxyUrl

                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyUrl)
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

                try {
                    [System.Environment]::SetEnvironmentVariable("http_proxy", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("https_proxy", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
                    Write-Host "[OK] System-wide proxy set: $proxyUrl" -ForegroundColor Green
                    Write-Host "   (Persistent after terminal restart)" -ForegroundColor Gray
                } catch {
                    Write-Host "[WARN] WARNING: Failed to set system environment variables" -ForegroundColor Yellow
                }
            }
        }
    }
} else {
    Write-Host "[OK] Network connection OK" -ForegroundColor Green
    Write-Host ""

    $askProxy = Read-Host "Do you still need proxy to accelerate GitHub access? (Y/N)"

    if ($askProxy -eq 'Y' -or $askProxy -eq 'y') {
        Write-Host ""
        Write-Host "Select proxy scope:" -ForegroundColor Cyan
        Write-Host "1. Current session only (temporary, recommended)" -ForegroundColor White
        Write-Host "2. System-wide (persistent)" -ForegroundColor White
        Write-Host ""
        $proxyScope = Read-Host "Please select (1/2)"

        Write-Host ""
        Write-Host "Select proxy type:" -ForegroundColor Cyan
        Write-Host "1. Common proxy (127.0.0.1:7890)" -ForegroundColor White
        Write-Host "2. Common proxy (127.0.0.1:1080)" -ForegroundColor White
        Write-Host "3. Custom proxy address" -ForegroundColor White
        Write-Host ""
        $proxyChoice = Read-Host "Please select (1/2/3)"

        switch ($proxyChoice) {
            "1" { $proxyUrl = "http://127.0.0.1:7890" }
            "2" { $proxyUrl = "http://127.0.0.1:1080" }
            "3" {
                Write-Host "Enter proxy address (e.g., http://127.0.0.1:7890)" -ForegroundColor Cyan
                $proxyUrl = Read-Host "Proxy address"
            }
            default {
                Write-Host "Invalid selection, skipping proxy setup" -ForegroundColor Yellow
                $proxyUrl = $null
            }
        }

        if ($proxyUrl) {
            if ($proxyScope -eq "1") {
                $env:http_proxy = $proxyUrl
                $env:https_proxy = $proxyUrl
                $env:HTTP_PROXY = $proxyUrl
                $env:HTTPS_PROXY = $proxyUrl

                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyUrl)
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

                Write-Host "[OK] Temporary proxy set: $proxyUrl" -ForegroundColor Green
                Write-Host "   (Valid only for current session)" -ForegroundColor Gray
            } else {
                $env:http_proxy = $proxyUrl
                $env:https_proxy = $proxyUrl
                $env:HTTP_PROXY = $proxyUrl
                $env:HTTPS_PROXY = $proxyUrl

                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyUrl)
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

                try {
                    [System.Environment]::SetEnvironmentVariable("http_proxy", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("https_proxy", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
                    [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
                    Write-Host "[OK] System-wide proxy set: $proxyUrl" -ForegroundColor Green
                    Write-Host "   (Persistent after terminal restart)" -ForegroundColor Gray
                } catch {
                    Write-Host "[WARN] WARNING: Failed to set system environment variables" -ForegroundColor Yellow
                }
            }
        }
    }
}
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "[WARN] WARNING: Administrator privileges required" -ForegroundColor Yellow
    Write-Host "Restarting script as administrator..." -ForegroundColor Yellow

    $args = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($env:http_proxy) {
        $args += " -Proxy `"$env:http_proxy`""
    }

    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit
}

# Check if proxy parameters were passed
if ($args -contains "-Proxy") {
    $proxyIndex = [Array]::IndexOf($args, "-Proxy")
    if ($proxyIndex -ge 0 -and $proxyIndex + 1 -lt $args.Count) {
        $proxyValue = $args[$proxyIndex + 1]
        $env:http_proxy = $proxyValue
        $env:https_proxy = $proxyValue
        $env:HTTP_PROXY = $proxyValue
        $env:HTTPS_PROXY = $proxyValue
        Write-Host "[OK] Proxy restored: $proxyValue" -ForegroundColor Green
        Write-Host ""
    }
}

# Step 1: Check and modify execution policy
Write-Host "[INFO] Step 1: Checking PowerShell execution policy..." -ForegroundColor Green

$currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
$effectivePolicy = Get-ExecutionPolicy

Write-Host "   Current user policy: $currentUserPolicy" -ForegroundColor Gray
Write-Host "   Effective policy: $effectivePolicy" -ForegroundColor Gray

if ($effectivePolicy -eq 'Restricted' -or $currentUserPolicy -eq 'Restricted' -or $currentUserPolicy -eq 'Undefined') {
    Write-Host ""
    Write-Host "[WARN] WARNING: Current execution policy is restrictive" -ForegroundColor Yellow
    Write-Host "   Recommend changing to RemoteSigned" -ForegroundColor Gray
    Write-Host ""

    $modifyPolicy = Read-Host "Modify execution policy? (Y/N)"

    if ($modifyPolicy -eq 'Y' -or $modifyPolicy -eq 'y') {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "[OK] Execution policy changed to RemoteSigned" -ForegroundColor Green
        } catch {
            $newEffectivePolicy = Get-ExecutionPolicy
            if ($newEffectivePolicy -eq 'Bypass' -or $newEffectivePolicy -eq 'Unrestricted' -or $newEffectivePolicy -eq 'RemoteSigned') {
                Write-Host "[OK] Execution policy is already permissive ($newEffectivePolicy)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] WARNING: Failed to modify execution policy" -ForegroundColor Yellow
                Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "[SKIP] Skipped execution policy modification" -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] Execution policy allows script execution ($effectivePolicy)" -ForegroundColor Green
}
Write-Host ""

# Step 2: Check winget availability
Write-Host "[TOOL] Step 2: Checking winget..." -ForegroundColor Green
Update-CurrentProcessPath
$wingetAvailable = Resolve-Command winget
if (!$wingetAvailable) {
    Write-Host "[ERROR] ERROR: winget not installed or unavailable" -ForegroundColor Red
    Write-Host ""
    Write-Host "Solutions:" -ForegroundColor Yellow
    Write-Host "1. Update Windows to latest version" -ForegroundColor White
    Write-Host "2. Install 'App Installer' from Microsoft Store" -ForegroundColor White
    Write-Host "3. Visit: https://github.com/microsoft/winget-cli/releases" -ForegroundColor White
    Write-Host ""
    $continueWithoutWinget = Read-Host "Skip winget installation steps and continue? (Y/N)"
    if ($continueWithoutWinget -ne 'Y' -and $continueWithoutWinget -ne 'y') {
        Write-Host "Script terminated" -ForegroundColor Red
        exit
    }
    $skipWinget = $true
} else {
    Write-Host "[OK] winget is available" -ForegroundColor Green
    $skipWinget = $false
}
Write-Host ""

# Step 3: Install Windows Terminal
Write-Host "[PACK] Step 3: Checking/Installing Windows Terminal..." -ForegroundColor Green

$wtInstalled = $false
try {
    $wtPackage = Get-AppxPackage -Name "*WindowsTerminal*" -ErrorAction Stop
    if ($wtPackage) {
        $wtInstalled = $true
        Write-Host "[OK] Windows Terminal is already installed" -ForegroundColor Green
    }
} catch {
    Write-Host "   Cannot detect Windows Terminal (AppxPackage not supported)" -ForegroundColor Gray

    if (!$skipWinget) {
        try {
            $wingetList = winget list --id Microsoft.WindowsTerminal 2>&1
            if ($wingetList -match "Microsoft.WindowsTerminal") {
                $wtInstalled = $true
                Write-Host "[OK] Windows Terminal is already installed (detected via winget)" -ForegroundColor Green
            }
        } catch {
            # Cannot detect, assume not installed
        }
    }
}

if (!$wtInstalled) {
    if (!$skipWinget) {
        Write-Host "Installing Windows Terminal..." -ForegroundColor Yellow
        try {
            if ($env:http_proxy) {
                Write-Host "   Using proxy: $env:http_proxy" -ForegroundColor Gray
                winget install Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements --proxy $env:http_proxy
            } else {
                winget install Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements
            }
            Write-Host "[OK] Windows Terminal installation completed" -ForegroundColor Green
            Update-CurrentProcessPath
            $wtCommand = Resolve-Command wt
            if ($wtCommand) {
                Write-Host "[OK] wt is visible in current process: $($wtCommand.Source)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] wt is still not visible in current process. Reopen PowerShell or Windows Terminal after this script." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[WARN] WARNING: Auto installation failed" -ForegroundColor Yellow
            Write-Host "   Please install manually from Microsoft Store" -ForegroundColor Cyan
            Write-Host "   Or visit: https://github.com/microsoft/terminal/releases" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[WARN] WARNING: winget unavailable, cannot auto install" -ForegroundColor Yellow
        Write-Host "   Please install manually from Microsoft Store" -ForegroundColor Cyan
        Write-Host "   Or visit: https://github.com/microsoft/terminal/releases" -ForegroundColor Cyan
    }
}
Write-Host ""

# Step 4: Install Oh My Posh
Write-Host "[THEME] Step 4: Checking/Installing Oh My Posh..." -ForegroundColor Green
$ohMyPoshPath = Resolve-Command oh-my-posh
if ($ohMyPoshPath) {
    Write-Host "[OK] Oh My Posh is already installed" -ForegroundColor Green
} else {
    if (!$skipWinget) {
        Write-Host "Installing Oh My Posh..." -ForegroundColor Yellow
        try {
            if ($env:http_proxy) {
                winget install JanDeDobbeleer.OhMyPosh -s winget --accept-source-agreements --accept-package-agreements --proxy $env:http_proxy 2>&1 | Out-Null
            } else {
                winget install JanDeDobbeleer.OhMyPosh -s winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            }
            Write-Host "[OK] Oh My Posh installation completed" -ForegroundColor Green

            Update-CurrentProcessPath
            $ohMyPoshPath = Resolve-Command oh-my-posh
            if ($ohMyPoshPath) {
                Write-Host "[OK] oh-my-posh is visible in current process: $($ohMyPoshPath.Source)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] oh-my-posh is still not visible in current process. Reopen PowerShell and rerun if font/profile setup needs it." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[WARN] WARNING: Auto installation failed" -ForegroundColor Yellow
            Write-Host "Please install manually: winget install JanDeDobbeleer.OhMyPosh" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[WARN] WARNING: winget unavailable, skipping Oh My Posh installation" -ForegroundColor Yellow
        Write-Host "Visit: https://ohmyposh.dev/docs/installation/windows" -ForegroundColor Cyan
    }
}
Write-Host ""

# Step 4.5: Install PowerShell Modules (Auto-completion & Icons)
Write-Host "[PACK] Step 4.5: Installing PowerShell Modules..." -ForegroundColor Green
$modules = @("PSReadLine", "Terminal-Icons", "z")
foreach ($module in $modules) {
    Write-Host "Checking module: $module..." -ForegroundColor Yellow
    if (!(Get-Module -ListAvailable $module)) {
        try {
            Write-Host "Installing $module..." -ForegroundColor Cyan
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "[OK] $module installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Failed to install $module automatically. You can install it later." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[OK] $module is already installed" -ForegroundColor Green
    }
}
Write-Host ""

# Step 5: Install Nerd Font
Write-Host "[FONT] Step 5: Installing Nerd Font..." -ForegroundColor Green
Update-CurrentProcessPath
$ohMyPoshPath = Resolve-Command oh-my-posh

$fontInstalled = Test-Path "C:\Windows\Fonts\CaskaydiaCoveNerdFont-Regular.ttf"
if ($fontInstalled) {
    Write-Host "[OK] Nerd Font is already installed" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Select font installation method:" -ForegroundColor Cyan
    Write-Host "1. Use oh-my-posh installer (recommended, interactive)" -ForegroundColor White
    Write-Host "2. Auto download CascadiaCode Nerd Font (about 46MB)" -ForegroundColor White
    Write-Host "3. Skip font installation (install manually later)" -ForegroundColor White
    Write-Host ""
    $fontChoice = Read-Host "Please select (1/2/3)"

    if ($fontChoice -eq "1") {
        if ($ohMyPoshPath) {
            Write-Host ""
            Write-Host "Select font to install:" -ForegroundColor Cyan
            Write-Host "1. CaskaydiaCove NF (Recommended)" -ForegroundColor White
            Write-Host "2. MesloLGM NF" -ForegroundColor White
            Write-Host "3. FiraCode NF" -ForegroundColor White
            Write-Host "4. JetBrainsMono NF" -ForegroundColor White
            Write-Host "5. Open interactive font selector" -ForegroundColor White
            Write-Host ""
            $fontSelect = Read-Host "Please select (1/2/3/4/5)"

            Write-Host ""
            switch ($fontSelect) {
                "1" {
                    Write-Host "Installing CaskaydiaCove NF..." -ForegroundColor Yellow
                    oh-my-posh font install CaskaydiaCove
                }
                "2" {
                    Write-Host "Installing MesloLGM NF..." -ForegroundColor Yellow
                    oh-my-posh font install MesloLGM
                }
                "3" {
                    Write-Host "Installing FiraCode NF..." -ForegroundColor Yellow
                    oh-my-posh font install FiraCode
                }
                "4" {
                    Write-Host "Installing JetBrainsMono NF..." -ForegroundColor Yellow
                    oh-my-posh font install JetBrainsMono
                }
                "5" {
                    Write-Host "Starting interactive font selector..." -ForegroundColor Yellow
                    Write-Host "Note: If the selector doesn't display properly, press Ctrl+C and choose option 1-4" -ForegroundColor Gray
                    Write-Host ""
                    oh-my-posh font install
                }
                default {
                    Write-Host "Invalid selection, installing CaskaydiaCove NF (default)..." -ForegroundColor Yellow
                    oh-my-posh font install CaskaydiaCove
                }
            }
            Write-Host "[OK] Font installation completed" -ForegroundColor Green
        } else {
            Write-Host "[WARN] WARNING: Oh My Posh not installed, cannot use this method" -ForegroundColor Yellow
            Write-Host "Using auto download method..." -ForegroundColor Yellow
            $fontChoice = "2"
        }
    }

    if ($fontChoice -eq "2") {
        Write-Host ""
        Write-Host "Downloading CascadiaCode Nerd Font..." -ForegroundColor Yellow

        $fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/CascadiaCode.zip"
        $tempPath = "$env:TEMP\CascadiaCode.zip"
        $extractPath = "$env:TEMP\CascadiaCode"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "PowerShell")

            if ($env:http_proxy) {
                $webClient.Proxy = New-Object System.Net.WebProxy($env:http_proxy)
                Write-Host "Using proxy for download: $env:http_proxy" -ForegroundColor Cyan
            }

            Write-Host "Downloading from GitHub (about 46MB, please wait)..." -ForegroundColor Yellow
            $webClient.DownloadFile($fontUrl, $tempPath)

            Write-Host "Extracting font files..." -ForegroundColor Yellow
            Expand-Archive -Path $tempPath -DestinationPath $extractPath -Force

            Write-Host "Installing fonts..." -ForegroundColor Yellow
            $fonts = Get-ChildItem -Path $extractPath -Filter "*.ttf" -Recurse | Where-Object { $_.Name -like "*NF*" }

            $installedCount = 0
            foreach ($font in $fonts) {
                try {
                    $fontName = $font.Name
                    $fontPath = $font.FullName

                    Copy-Item $fontPath "C:\Windows\Fonts\" -Force -ErrorAction Stop

                    $fontRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                    New-ItemProperty -Path $fontRegistryPath -Name $fontName -Value $fontName -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

                    $installedCount++
                } catch {
                    # Ignore individual font installation failures
                }
            }

            if ($installedCount -gt 0) {
                Write-Host "[OK] Nerd Font installation completed ($installedCount font files installed)" -ForegroundColor Green
            } else {
                throw "No fonts were successfully installed"
            }

            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        } catch {
            Write-Host "[WARN] WARNING: Auto font installation failed: $_" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Alternative solutions:" -ForegroundColor Yellow
            Write-Host "1. If Oh My Posh is installed, run: oh-my-posh font install" -ForegroundColor White
            Write-Host "2. Manual download: https://github.com/ryanoasis/nerd-fonts/releases" -ForegroundColor White
            Write-Host "3. If network issue, set proxy and re-run script" -ForegroundColor White
            Write-Host ""

            if ($ohMyPoshPath) {
                $useOMP = Read-Host "Try using oh-my-posh to install fonts? (Y/N)"
                if ($useOMP -eq 'Y' -or $useOMP -eq 'y') {
                    Write-Host "Starting oh-my-posh font installer..." -ForegroundColor Yellow
                    oh-my-posh font install
                }
            }
        }
    } elseif ($fontChoice -eq "3") {
        Write-Host "[SKIP] Skipped font installation" -ForegroundColor Yellow
        Write-Host "   You can install later with: oh-my-posh font install" -ForegroundColor Cyan
    } else {
        Write-Host "[WARN] WARNING: Invalid selection, skipping font installation" -ForegroundColor Yellow
    }
}
Write-Host ""

# Step 6: Configure PowerShell Profile
Write-Host "Step 6: Configuring PowerShell Profile..." -ForegroundColor Green

$minimalThemeConfig = @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "blocks": [
    {
      "alignment": "left",
      "segments": [
        {
          "foreground": "#8BE9FD",
          "style": "plain",
          "template": "{{ .Path }}",
          "type": "path",
          "properties": {
            "style": "short"
          }
        },
        {
          "foreground": "#F1FA8C",
          "style": "plain",
          "template": " ({{ .HEAD }})",
          "type": "git"
        },
        {
          "foreground": "#50FA7B",
          "style": "plain",
          "template": " > ",
          "type": "text"
        }
      ],
      "type": "prompt"
    }
  ],
  "final_space": false,
  "version": 2
}
'@

$themeDir = "$env:USERPROFILE\Documents\PowerShell\themes"
if (!(Test-Path $themeDir)) {
    New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
}
$themePath = Join-Path $themeDir "minimal.omp.json"
$minimalThemeConfig | Out-File -FilePath $themePath -Encoding UTF8 -Force
Write-Host "[OK] Theme file written: $themePath" -ForegroundColor Green

$profileContent = @"
# --- Auto-completion & UI Enhancements ---
Import-Module PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }
if (Get-Module -ListAvailable z) { Import-Module z }

# --- Oh My Posh - Minimalist Style ---
`$themePath = "`$HOME\Documents\PowerShell\themes\minimal.omp.json"
if (Test-Path `$themePath) {
  oh-my-posh init pwsh --config `$themePath | Invoke-Expression
} else {
  oh-my-posh init pwsh | Invoke-Expression
}
"@

# Create Windows PowerShell 5.1 configuration
$ps5ProfilePath = "$env:USERPROFILE\Documents\WindowsPowerShell"
if (!(Test-Path $ps5ProfilePath)) {
    New-Item -ItemType Directory -Path $ps5ProfilePath -Force | Out-Null
}
$profileContent | Out-File -FilePath "$ps5ProfilePath\Microsoft.PowerShell_profile.ps1" -Encoding UTF8 -Force
Write-Host "[OK] Windows PowerShell 5.1 configuration completed" -ForegroundColor Green

# Create PowerShell 7 configuration
$ps7ProfilePath = "$env:USERPROFILE\Documents\PowerShell"
if (!(Test-Path $ps7ProfilePath)) {
    New-Item -ItemType Directory -Path $ps7ProfilePath -Force | Out-Null
}
$profileContent | Out-File -FilePath "$ps7ProfilePath\Microsoft.PowerShell_profile.ps1" -Encoding UTF8 -Force
Write-Host "[OK] PowerShell 7 configuration completed" -ForegroundColor Green
Write-Host ""

# Step 7: Configure Windows Terminal
Write-Host "[THEME] Step 7: Configuring Windows Terminal (Dracula Theme)..." -ForegroundColor Green

$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

if (Test-Path $wtSettingsPath) {
    $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json

    $draculaScheme = @{
        name = "Dracula"
        background = "#282A36"
        foreground = "#F8F8F2"
        black = "#21222C"
        blue = "#BD93F9"
        cyan = "#8BE9FD"
        green = "#50FA7B"
        purple = "#FF79C6"
        red = "#FF5555"
        white = "#F8F8F2"
        yellow = "#F1FA8C"
        brightBlack = "#6272A4"
        brightBlue = "#D6ACFF"
        brightCyan = "#A4FFFF"
        brightGreen = "#69FF94"
        brightPurple = "#FF92DF"
        brightRed = "#FF6E6E"
        brightWhite = "#FFFFFF"
        brightYellow = "#FFFFA5"
    }

    $hasDracula = $false
    if ($settings.schemes) {
        $hasDracula = $settings.schemes | Where-Object { $_.name -eq "Dracula" }
    } else {
        $settings | Add-Member -MemberType NoteProperty -Name "schemes" -Value @() -Force
    }

    if (!$hasDracula) {
        $settings.schemes += $draculaScheme
    }

    if (!$settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name "profiles" -Value @{} -Force
    }
    if (!$settings.profiles.defaults) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value @{} -Force
    }

    $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name "colorScheme" -Value "Dracula" -Force
    $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value @{face = "CaskaydiaCove NF"} -Force

    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $wtSettingsPath -Encoding UTF8 -Force
    Write-Host "[OK] Windows Terminal configuration completed" -ForegroundColor Green
} else {
    Write-Host "[WARN] WARNING: Windows Terminal settings file not found" -ForegroundColor Yellow
}
Write-Host ""

# Step 8: Set Windows Terminal as default
Write-Host "[START] Step 8: Setting Windows Terminal as default terminal..." -ForegroundColor Green
try {
    $regPath = "HKCU:\Console\%%Startup"
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" -Force
    Write-Host "[OK] Default terminal setting completed" -ForegroundColor Green
} catch {
    Write-Host "[WARN] WARNING: Failed to set default terminal" -ForegroundColor Yellow
}
Write-Host ""

# Completion
Write-Host "========================================" -ForegroundColor Green
Write-Host "[DONE]  Configuration Completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Please follow these steps:" -ForegroundColor Yellow
Write-Host "1. Close all terminal windows" -ForegroundColor White
Write-Host "2. Reopen Windows Terminal" -ForegroundColor White
Write-Host "3. Enjoy your minimalist beautified terminal!" -ForegroundColor White
Write-Host ""
Write-Host "If fonts display incorrectly, run: oh-my-posh font install" -ForegroundColor Cyan
Write-Host ""

# Ask if open Windows Terminal immediately
$response = Read-Host "Open Windows Terminal now to see the result? (Y/N)"
if ($response -eq 'Y' -or $response -eq 'y') {
    Update-CurrentProcessPath
    $wtCommand = Resolve-Command wt
    if ($wtCommand) {
        Start-Process $wtCommand.Source
    } else {
        Write-Host "[WARN] wt is not visible in current process. Reopen Windows Terminal manually after closing this window." -ForegroundColor Yellow
    }
}
