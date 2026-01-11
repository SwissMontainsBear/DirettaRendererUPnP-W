#Requires -Version 5.1
<#
.SYNOPSIS
    Diretta UPnP Renderer - Windows Installation Script

.DESCRIPTION
    Automates the build process for Diretta UPnP Renderer on Windows.
    Checks prerequisites, installs dependencies via vcpkg, builds the project,
    and configures the Windows Firewall.

.NOTES
    Requirements:
    - MSBuild and C++ compiler (cl.exe) - one of:
      * Visual Studio 2026 with C++ workload
      * Build Tools for Visual Studio 2026
      * Run from 'x64 Native Tools Command Prompt' (adds compilers to PATH)
    - Git for Windows (must be installed manually)
    - Npcap (must be installed manually for RAW socket mode)
    - Diretta Host SDK (must be downloaded manually)

.PARAMETER Platform
    Target platform: x64, ARM64, or All. Default is x64.
    Use "All" to build both x64 and ARM64 (cross-compilation).

.EXAMPLE
    .\install.ps1
    Build for x64 (default).

.EXAMPLE
    .\install.ps1 -Platform ARM64
    Cross-compile for ARM64 from x64 host.

.EXAMPLE
    .\install.ps1 -Platform All
    Build for both x64 and ARM64 platforms.

.EXAMPLE
    .\install.ps1 -SkipBuild
    Only check prerequisites and install dependencies, don't build.

.EXAMPLE
    .\install.ps1 -Force
    Rebuild even if executable already exists.
#>

param(
    [ValidateSet("x64", "ARM64", "All")]
    [string]$Platform = "x64",
    [switch]$SkipBuild,
    [switch]$Force,
    [switch]$SkipFirewall,
    [switch]$Help
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Speed up web requests

$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ProjectDir = $ScriptDir
$Script:VcpkgRoot = "C:\vcpkg"

# Platform configuration
$Script:PlatformConfig = @{
    "x64" = @{
        VcpkgTriplet = "x64-windows"
        DirettaLib = "libDirettaHost_x64-win.lib"
        AcquaLib = "libACQUA_x64-win.lib"
    }
    "ARM64" = @{
        VcpkgTriplet = "arm64-windows"
        DirettaLib = "libDirettaHost_arm64-win.lib"
        AcquaLib = "libACQUA_arm64-win.lib"
    }
}

# Determine which platforms to build
$Script:TargetPlatforms = if ($Platform -eq "All") { @("x64", "ARM64") } else { @($Platform) }

# SDK search paths (in order of preference)
$Script:SdkSearchPaths = @(
    (Join-Path $ProjectDir "..\DirettaHostSDK_147"),
    (Join-Path $env:USERPROFILE "DirettaHostSDK_147"),
    "C:\DirettaHostSDK_147",
    (Join-Path $ProjectDir "DirettaHostSDK_147")
)

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Text
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Text
}

function Write-Warning {
    param([string]$Text)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-Error {
    param([string]$Text)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Text
}

function Write-Step {
    param([int]$Number, [string]$Text)
    Write-Host ""
    Write-Host "--- Step $Number : $Text ---" -ForegroundColor Magenta
    Write-Host ""
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    if (-not (Test-Administrator)) {
        # Check if we have build tools in current PATH (e.g., Native Tools Command Prompt)
        $hasBuildTools = (Get-Command cl.exe -ErrorAction SilentlyContinue) -or
                         (Get-Command msbuild.exe -ErrorAction SilentlyContinue)

        if ($hasBuildTools) {
            Write-Warning "This script requires Administrator privileges."
            Write-Warning "You appear to be running from a Developer/Native Tools Command Prompt."
            Write-Warning "The elevated session will NOT inherit your current PATH with build tools."
            Write-Host ""
            Write-Host "Please do ONE of the following:" -ForegroundColor Yellow
            Write-Host "  1. Run this script from an ELEVATED Native Tools Command Prompt" -ForegroundColor White
            Write-Host "     (Right-click 'x64 Native Tools Command Prompt' -> Run as Administrator)" -ForegroundColor Gray
            Write-Host "  2. Or press Enter to continue anyway (may fail to find compilers)" -ForegroundColor White
            Write-Host ""
            $response = Read-Host "Press Enter to continue or Ctrl+C to abort"
        }

        Write-Warning "This script requires Administrator privileges."
        Write-Info "Restarting with elevation..."

        $scriptPath = $MyInvocation.PSCommandPath
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

        if ($SkipBuild) { $arguments += " -SkipBuild" }
        if ($Force) { $arguments += " -Force" }
        if ($SkipFirewall) { $arguments += " -SkipFirewall" }

        Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
        exit
    }
}

function Pause-Script {
    param([string]$Message = "Press any key to continue...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Confirm-Continue {
    param([string]$Message)
    Write-Host ""
    $response = Read-Host "$Message [Y/n]"
    return ($response -eq "" -or $response -match "^[Yy]")
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

function Find-VisualStudio {
    Write-Info "Checking for Visual Studio 2026..."

    # Try vswhere first (most reliable)
    $vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

    if (Test-Path $vswherePath) {
        $vsInstalls = & $vswherePath -all -format json | ConvertFrom-Json

        foreach ($install in $vsInstalls) {
            # VS 2026 is version 18.x
            if ($install.installationVersion -match "^18\.") {
                Write-Success "Found Visual Studio 2026 at: $($install.installationPath)"
                return $install.installationPath
            }
        }
    }

    # Fallback: check common paths (VS 2026 = version 18.x)
    # Check both naming conventions: year-based (2026) and version-based (18)
    $commonPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\Community",
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\Professional",
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\Enterprise",
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\Insiders",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\Community",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\Professional",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\Enterprise",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\Insiders"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Success "Found Visual Studio 2026 at: $path"
            return $path
        }
    }

    return $null
}

function Find-MSBuild {
    param([string]$VsPath)

    # Try VS installation path first
    if ($VsPath) {
        $msbuildPath = Join-Path $VsPath "MSBuild\Current\Bin\MSBuild.exe"
        if (Test-Path $msbuildPath) {
            Write-Success "Found MSBuild at: $msbuildPath"
            return $msbuildPath
        }
    }

    # Try to find in PATH
    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($msbuild) {
        Write-Success "Found MSBuild in PATH: $($msbuild.Source)"
        return $msbuild.Source
    }

    # Fallback: search common MSBuild locations
    Write-Info "Searching for MSBuild in common locations..."
    $msbuildPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\*\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\*\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2026\*\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\*\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\MSBuild\Current\Bin\MSBuild.exe"
    )

    foreach ($pattern in $msbuildPaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Success "Found MSBuild at: $($found.FullName)"
            return $found.FullName
        }
    }

    return $null
}

function Test-CLCompiler {
    Write-Info "Checking for C++ compiler (cl.exe)..."

    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($cl) {
        try {
            $version = & cl.exe 2>&1 | Select-Object -First 1
            Write-Success "Found C++ compiler: $version"
            return $true
        }
        catch {
            Write-Success "Found C++ compiler at: $($cl.Source)"
            return $true
        }
    }

    # Fallback: search common cl.exe locations
    Write-Info "Searching for cl.exe in common locations..."
    $clPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2026\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\18\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2026\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe"
    )

    foreach ($pattern in $clPaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Success "Found C++ compiler at: $($found.FullName)"
            Write-Warning "cl.exe is not in PATH - build may fail without proper environment setup"
            Write-Info "Consider running from 'x64 Native Tools Command Prompt for VS'"
            return $true
        }
    }

    return $false
}

function Test-Git {
    Write-Info "Checking for Git..."

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        $version = & git --version 2>$null
        Write-Success "Found Git: $version"
        return $true
    }

    return $false
}

function Test-Vcpkg {
    Write-Info "Checking for vcpkg..."

    if (Test-Path (Join-Path $VcpkgRoot "vcpkg.exe")) {
        Write-Success "Found vcpkg at: $VcpkgRoot"
        return $true
    }

    return $false
}

function Test-Npcap {
    Write-Info "Checking for Npcap..."

    # Check multiple indicators of Npcap installation
    $npcapFound = $false
    $npcapPath = "${env:ProgramFiles}\Npcap"

    # Method 1: Check Program Files installation directory
    if (Test-Path $npcapPath) {
        # Look for common Npcap files
        $npcapFiles = @(
            (Join-Path $npcapPath "NPFInstall.exe"),
            (Join-Path $npcapPath "NpcapHelper.exe"),
            (Join-Path $npcapPath "LICENSE")
        )
        foreach ($file in $npcapFiles) {
            if (Test-Path $file) {
                Write-Success "Found Npcap at: $npcapPath"
                $npcapFound = $true
                break
            }
        }
    }

    # Method 2: Check System32 for Npcap DLLs
    if (-not $npcapFound) {
        $npcapSys32 = "${env:SystemRoot}\System32\Npcap"
        $wpcapDll = Join-Path $npcapSys32 "wpcap.dll"
        if (Test-Path $wpcapDll) {
            Write-Success "Found Npcap DLLs at: $npcapSys32"
            $npcapFound = $true
        }
    }

    # Method 3: Check registry
    if (-not $npcapFound) {
        $regPath = "HKLM:\SOFTWARE\Npcap"
        if (Test-Path $regPath) {
            Write-Success "Found Npcap in registry"
            $npcapFound = $true
        }
    }

    # Method 4: Check for Npcap service
    if (-not $npcapFound) {
        $npcapService = Get-Service -Name "npcap" -ErrorAction SilentlyContinue
        if ($npcapService) {
            Write-Success "Found Npcap service (status: $($npcapService.Status))"
            $npcapFound = $true
        }
    }

    if ($npcapFound) {
        # Try to get version from registry
        try {
            $regPath = "HKLM:\SOFTWARE\Npcap"
            if (Test-Path $regPath) {
                $version = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).VersionNumber
                if ($version) {
                    Write-Info "Npcap version: $version"
                }
            }
        }
        catch { }
        return $true
    }

    return $false
}

function Find-DirettaSDK {
    param([string[]]$Platforms = $TargetPlatforms)

    Write-Info "Checking for Diretta Host SDK..."

    foreach ($path in $SdkSearchPaths) {
        $resolvedPath = [System.IO.Path]::GetFullPath($path)
        $allLibsFound = $true
        $missingLibs = @()

        foreach ($plat in $Platforms) {
            $libName = $PlatformConfig[$plat].DirettaLib
            $libPath = Join-Path $resolvedPath "lib\$libName"

            if (-not (Test-Path $libPath)) {
                $allLibsFound = $false
                $missingLibs += $libName
            }
        }

        if ($allLibsFound) {
            Write-Success "Found Diretta SDK at: $resolvedPath"
            foreach ($plat in $Platforms) {
                Write-Info "  - $($PlatformConfig[$plat].DirettaLib) found"
            }
            return $resolvedPath
        }
    }

    return $null
}

function Get-MissingSDKLibraries {
    param([string]$SdkPath, [string[]]$Platforms = $TargetPlatforms)

    $missing = @()
    foreach ($plat in $Platforms) {
        $libName = $PlatformConfig[$plat].DirettaLib
        $libPath = Join-Path $SdkPath "lib\$libName"
        if (-not (Test-Path $libPath)) {
            $missing += @{ Platform = $plat; Library = $libName }
        }
    }
    return $missing
}

function Test-VcpkgDependencies {
    param([string[]]$Platforms = $TargetPlatforms)

    Write-Info "Checking vcpkg dependencies..."

    $allFound = $true
    foreach ($plat in $Platforms) {
        $triplet = $PlatformConfig[$plat].VcpkgTriplet
        $vcpkgBinPath = Join-Path $VcpkgRoot "installed\$triplet\bin"

        $ffmpegDll = Join-Path $vcpkgBinPath "avformat.dll"
        $upnpDll = Join-Path $vcpkgBinPath "libupnp.dll"

        $hasFFmpeg = Test-Path $ffmpegDll
        $hasUpnp = Test-Path $upnpDll

        if ($hasFFmpeg -and $hasUpnp) {
            Write-Success "  [$plat] vcpkg dependencies installed"
        }
        else {
            if (-not $hasFFmpeg) { Write-Warning "  [$plat] FFmpeg not found" }
            if (-not $hasUpnp) { Write-Warning "  [$plat] libupnp not found" }
            $allFound = $false
        }
    }

    return $allFound
}

# ============================================================================
# Installation Functions
# ============================================================================

function Install-Vcpkg {
    Write-Info "Installing vcpkg..."

    if (Test-Path $VcpkgRoot) {
        Write-Warning "vcpkg directory exists, updating..."
        Push-Location $VcpkgRoot
        & git pull 2>$null
        Pop-Location
    }
    else {
        Write-Info "Cloning vcpkg repository..."
        & git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone vcpkg"
        }
    }

    Write-Info "Bootstrapping vcpkg..."
    Push-Location $VcpkgRoot
    & .\bootstrap-vcpkg.bat -disableMetrics

    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to bootstrap vcpkg"
    }

    Write-Info "Integrating vcpkg with Visual Studio..."
    & .\vcpkg.exe integrate install
    Pop-Location

    Write-Success "vcpkg installed successfully"
}

function Install-VcpkgDependencies {
    param([string[]]$Platforms = $TargetPlatforms)

    Write-Info "Installing vcpkg dependencies (this may take several minutes)..."

    Push-Location $VcpkgRoot

    foreach ($plat in $Platforms) {
        $triplet = $PlatformConfig[$plat].VcpkgTriplet

        Write-Info "Installing FFmpeg for $plat ($triplet)..."
        & .\vcpkg.exe install "ffmpeg:$triplet"

        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "Failed to install FFmpeg for $plat"
        }

        Write-Info "Installing libupnp for $plat ($triplet)..."
        & .\vcpkg.exe install "libupnp[webserver]:$triplet"

        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "Failed to install libupnp for $plat"
        }

        Write-Success "  [$plat] Dependencies installed"
    }

    Pop-Location

    Write-Success "All dependencies installed successfully"
}

function Build-Project {
    param(
        [string]$MSBuildPath,
        [string[]]$Platforms = $TargetPlatforms
    )

    Write-Info "Building Diretta UPnP Renderer..."

    $vcxproj = Join-Path $ProjectDir "DirettaRendererUPnP.vcxproj"

    if (-not (Test-Path $vcxproj)) {
        throw "Project file not found: $vcxproj"
    }

    $builtPlatforms = @()

    foreach ($plat in $Platforms) {
        $binDir = Join-Path $ProjectDir "bin\$plat\Release"
        $exePath = Join-Path $binDir "DirettaRendererUPnP.exe"

        # Create output directory
        if (-not (Test-Path $binDir)) {
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        }

        Write-Info "Building for $plat..."
        & $MSBuildPath $vcxproj /p:Configuration=Release /p:Platform=$plat /verbosity:minimal

        if ($LASTEXITCODE -ne 0) {
            throw "Build failed for $plat with exit code $LASTEXITCODE"
        }

        if (-not (Test-Path $exePath)) {
            throw "Build completed but executable not found at: $exePath"
        }

        Write-Success "  [$plat] Build successful: $exePath"
        $builtPlatforms += $plat
    }

    Write-Success "All builds completed successfully!"
    return $builtPlatforms
}

function Copy-Dependencies {
    param([string[]]$Platforms = $TargetPlatforms)

    Write-Info "Copying DLLs to output directories..."

    foreach ($plat in $Platforms) {
        $triplet = $PlatformConfig[$plat].VcpkgTriplet
        $vcpkgBinPath = Join-Path $VcpkgRoot "installed\$triplet\bin"
        $binDir = Join-Path $ProjectDir "bin\$plat\Release"

        if (-not (Test-Path $vcpkgBinPath)) {
            Write-Warning "  [$plat] vcpkg bin directory not found: $vcpkgBinPath"
            continue
        }

        if (-not (Test-Path $binDir)) {
            Write-Warning "  [$plat] Output directory not found: $binDir"
            continue
        }

        $dlls = Get-ChildItem -Path $vcpkgBinPath -Filter "*.dll"
        $copied = 0

        foreach ($dll in $dlls) {
            $destPath = Join-Path $binDir $dll.Name
            if (-not (Test-Path $destPath) -or $Force) {
                Copy-Item $dll.FullName $destPath -Force
                $copied++
            }
        }

        Write-Success "  [$plat] Copied $copied DLL(s)"
    }
}

function Configure-Firewall {
    param([string[]]$Platforms = $TargetPlatforms)

    Write-Info "Configuring Windows Firewall..."

    # Build list of rules - start with program-specific rules for each platform
    $rules = @()

    foreach ($plat in $Platforms) {
        $exePath = Join-Path $ProjectDir "bin\$plat\Release\DirettaRendererUPnP.exe"
        if (Test-Path $exePath) {
            $rules += @{
                Name = "Diretta Renderer ($plat) - Inbound"
                Direction = "Inbound"
                Program = $exePath
                Action = "Allow"
            }
            $rules += @{
                Name = "Diretta Renderer ($plat) - Outbound"
                Direction = "Outbound"
                Program = $exePath
                Action = "Allow"
            }
        }
    }

    # Add common UPnP rules
    $rules += @(
        @{
            Name = "UPnP SSDP Discovery"
            Direction = "Inbound"
            Protocol = "UDP"
            LocalPort = "1900"
            Action = "Allow"
        },
        @{
            Name = "UPnP SSDP Multicast"
            Direction = "Outbound"
            Protocol = "UDP"
            RemotePort = "1900"
            Action = "Allow"
        },
        @{
            Name = "UPnP HTTP Ports"
            Direction = "Inbound"
            Protocol = "TCP"
            LocalPort = "49152-65535"
            Action = "Allow"
        }
    )

    foreach ($rule in $rules) {
        $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue

        if ($existingRule) {
            Write-Info "  [SKIP] $($rule.Name) (already exists)"
        }
        else {
            try {
                $params = @{
                    DisplayName = $rule.Name
                    Direction = $rule.Direction
                    Action = $rule.Action
                    Enabled = "True"
                    Profile = "Any"
                }

                if ($rule.Program) { $params.Program = $rule.Program }
                if ($rule.Protocol) { $params.Protocol = $rule.Protocol }
                if ($rule.LocalPort) { $params.LocalPort = $rule.LocalPort }
                if ($rule.RemotePort) { $params.RemotePort = $rule.RemotePort }

                New-NetFirewallRule @params | Out-Null
                Write-Success "  [OK] $($rule.Name)"
            }
            catch {
                Write-Warning "  [FAIL] $($rule.Name): $_"
            }
        }
    }

    Write-Success "Firewall configuration complete"
}

# ============================================================================
# Main Script
# ============================================================================

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Request elevation for firewall configuration
Request-Elevation

Write-Header "Diretta UPnP Renderer - Windows Installation"

$platformList = $TargetPlatforms -join ", "
Write-Host "Target platform(s): " -ForegroundColor White -NoNewline
Write-Host $platformList -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor White
Write-Host "  1. Check prerequisites (MSBuild, cl.exe, Git, Npcap, SDK)"
Write-Host "  2. Install/update vcpkg and dependencies for: $platformList"
Write-Host "  3. Build the project for: $platformList"
Write-Host "  4. Copy required DLLs"
Write-Host "  5. Configure Windows Firewall"
Write-Host ""

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================

Write-Step 1 "Checking Prerequisites"

$prereqsMissing = @()

# Visual Studio 2026 or standalone build tools
$vsPath = Find-VisualStudio
$msbuildPath = Find-MSBuild $vsPath
$hasCL = Test-CLCompiler

if (-not $msbuildPath) {
    Write-Error "MSBuild not found!"
    $prereqsMissing += @{
        Name = "MSBuild"
        Instructions = @(
            "Option 1: Install Visual Studio 2026 with 'Desktop development with C++' workload",
            "Option 2: Install 'Build Tools for Visual Studio 2026' from:",
            "          https://visualstudio.microsoft.com/downloads/#build-tools",
            "Option 3: Run this script from 'x64 Native Tools Command Prompt'"
        )
    }
}
elseif (-not $vsPath) {
    Write-Info "Visual Studio not found, but MSBuild is available in PATH"
    Write-Success "Found MSBuild at: $msbuildPath"
}

if (-not $hasCL) {
    Write-Error "C++ compiler (cl.exe) not found!"
    $prereqsMissing += @{
        Name = "C++ Compiler (cl.exe)"
        Instructions = @(
            "Option 1: Install Visual Studio 2026 with 'Desktop development with C++' workload",
            "Option 2: Install 'Build Tools for Visual Studio 2026' with C++ tools",
            "Option 3: Run this script from 'x64 Native Tools Command Prompt'",
            "          which sets up the compiler environment automatically"
        )
    }
}

# Git
if (-not (Test-Git)) {
    Write-Error "Git not found!"
    $prereqsMissing += @{
        Name = "Git for Windows"
        Instructions = @(
            "Download from: https://git-scm.com/download/win",
            "Install with default options",
            "Restart this script after installation"
        )
    }
}

# Npcap
$hasNpcap = Test-Npcap
if (-not $hasNpcap) {
    Write-Warning "Npcap not found or not working correctly!"
    Write-Warning "RAW socket mode (MSMODE3) will not be available."
    $prereqsMissing += @{
        Name = "Npcap (Required for optimal performance)"
        Instructions = @(
            "Download from: https://npcap.com/#download",
            "Run installer as Administrator",
            "Select: 'Install Npcap in WinPcap API-compatible Mode'",
            "Reboot after installation"
        )
        Optional = $true
    }
}

# Diretta SDK
$sdkPath = Find-DirettaSDK -Platforms $TargetPlatforms
if (-not $sdkPath) {
    Write-Error "Diretta Host SDK not found or missing platform libraries!"
    $requiredLibs = ($TargetPlatforms | ForEach-Object { $PlatformConfig[$_].DirettaLib }) -join ", "
    $prereqsMissing += @{
        Name = "Diretta Host SDK v147"
        Instructions = @(
            "Download from: https://www.diretta.link",
            "Required libraries: $requiredLibs",
            "Extract to one of these locations:",
            "  - $($SdkSearchPaths[0])",
            "  - $($SdkSearchPaths[1])",
            "  - $($SdkSearchPaths[2])"
        )
    }
}

# Report missing prerequisites
$criticalMissing = $prereqsMissing | Where-Object { -not $_.Optional }

if ($criticalMissing.Count -gt 0) {
    Write-Host ""
    Write-Header "Missing Prerequisites"

    foreach ($prereq in $prereqsMissing) {
        $color = if ($prereq.Optional) { "Yellow" } else { "Red" }
        $prefix = if ($prereq.Optional) { "[OPTIONAL]" } else { "[REQUIRED]" }

        Write-Host "$prefix $($prereq.Name)" -ForegroundColor $color
        foreach ($instruction in $prereq.Instructions) {
            Write-Host "    $instruction" -ForegroundColor Gray
        }
        Write-Host ""
    }

    if ($criticalMissing.Count -gt 0) {
        Write-Error "Cannot continue without required prerequisites."
        Write-Host ""
        Write-Host "Please install the missing components and run this script again." -ForegroundColor Yellow
        Pause-Script
        exit 1
    }
}

Write-Success "All critical prerequisites found!"

# ============================================================================
# Step 2: vcpkg Setup
# ============================================================================

Write-Step 2 "Setting up vcpkg"

if (-not (Test-Vcpkg)) {
    Write-Info "vcpkg not found, installing..."
    Install-Vcpkg
}

if (-not (Test-VcpkgDependencies)) {
    Write-Info "Installing vcpkg dependencies..."
    Install-VcpkgDependencies
}
else {
    Write-Success "vcpkg dependencies already installed"
}

# ============================================================================
# Step 3: Build
# ============================================================================

Write-Step 3 "Building Project"

$builtPlatforms = @()

if ($SkipBuild) {
    Write-Info "Skipping build (--SkipBuild specified)"
    # Check which executables already exist
    foreach ($plat in $TargetPlatforms) {
        $exePath = Join-Path $ProjectDir "bin\$plat\Release\DirettaRendererUPnP.exe"
        if (Test-Path $exePath) {
            $builtPlatforms += $plat
        }
    }
}
else {
    # Check if any executables already exist
    $existingExes = @()
    foreach ($plat in $TargetPlatforms) {
        $exePath = Join-Path $ProjectDir "bin\$plat\Release\DirettaRendererUPnP.exe"
        if (Test-Path $exePath) {
            $existingExes += $plat
        }
    }

    if ($existingExes.Count -gt 0 -and -not $Force) {
        Write-Info "Executables already exist for: $($existingExes -join ', ')"

        if (Confirm-Continue "Rebuild anyway?") {
            $builtPlatforms = Build-Project -MSBuildPath $msbuildPath -Platforms $TargetPlatforms
        }
        else {
            Write-Info "Skipping build"
            $builtPlatforms = $existingExes
        }
    }
    else {
        $builtPlatforms = Build-Project -MSBuildPath $msbuildPath -Platforms $TargetPlatforms
    }
}

# ============================================================================
# Step 4: Copy DLLs
# ============================================================================

Write-Step 4 "Copying Dependencies"

if ($builtPlatforms.Count -gt 0) {
    Copy-Dependencies -Platforms $builtPlatforms
}
else {
    Write-Warning "No executables found, skipping DLL copy"
}

# ============================================================================
# Step 5: Firewall Configuration
# ============================================================================

Write-Step 5 "Configuring Firewall"

if ($SkipFirewall) {
    Write-Info "Skipping firewall configuration (--SkipFirewall specified)"
}
elseif ($builtPlatforms.Count -gt 0) {
    Configure-Firewall -Platforms $builtPlatforms
}
else {
    Write-Warning "No executables found, skipping firewall configuration"
}

# ============================================================================
# Complete
# ============================================================================

Write-Header "Installation Complete!"

if ($builtPlatforms.Count -gt 0) {
    Write-Success "Diretta UPnP Renderer is ready to use!"
    Write-Host ""
    Write-Host "Built executables:" -ForegroundColor Cyan

    foreach ($plat in $builtPlatforms) {
        $exePath = Join-Path $ProjectDir "bin\$plat\Release\DirettaRendererUPnP.exe"
        Write-Host "  [$plat] $exePath" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor Cyan

    # Show example using first built platform
    $firstPlat = $builtPlatforms[0]
    $firstExePath = Join-Path $ProjectDir "bin\$firstPlat\Release\DirettaRendererUPnP.exe"

    Write-Host "  1. List available targets:"
    Write-Host "     `"$firstExePath`" --list-targets" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Start the renderer:"
    Write-Host "     `"$firstExePath`" --target 1" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Or use the launcher:"
    Write-Host "     .\Launch-DirettaRenderer.bat" -ForegroundColor White
    Write-Host ""

    if (-not $hasNpcap) {
        Write-Host ""
        Write-Warning "Npcap is not installed - performance may be limited!"
        Write-Host "  Install Npcap for RAW socket mode (MSMODE3)" -ForegroundColor Yellow
        Write-Host "  Download: https://npcap.com/#download" -ForegroundColor Gray
    }
}
else {
    Write-Warning "Build was skipped or failed. Run the script again with -Force to rebuild."
}

Write-Host ""
Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - BUILD_WINDOWS.md - Detailed build instructions"
Write-Host "  - README.md - Overview and usage"
Write-Host ""

Pause-Script "Press any key to exit..."
