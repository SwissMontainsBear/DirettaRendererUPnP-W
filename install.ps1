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

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -SkipBuild
    Only check prerequisites and install dependencies, don't build.

.EXAMPLE
    .\install.ps1 -Force
    Rebuild even if executable already exists.
#>

param(
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
$Script:BinDir = Join-Path $ProjectDir "bin\x64\Release"
$Script:ExePath = Join-Path $BinDir "DirettaRendererUPnP.exe"
$Script:VcpkgRoot = "C:\vcpkg"
$Script:VcpkgBin = Join-Path $VcpkgRoot "installed\x64-windows\bin"

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
    Write-Info "Checking for Diretta Host SDK..."

    foreach ($path in $SdkSearchPaths) {
        $resolvedPath = [System.IO.Path]::GetFullPath($path)
        $libPath = Join-Path $resolvedPath "lib\libDirettaHost_x64-win.lib"

        if (Test-Path $libPath) {
            Write-Success "Found Diretta SDK at: $resolvedPath"
            return $resolvedPath
        }
    }

    return $null
}

function Test-VcpkgDependencies {
    Write-Info "Checking vcpkg dependencies..."

    $ffmpegDll = Join-Path $VcpkgBin "avformat.dll"
    $upnpDll = Join-Path $VcpkgBin "libupnp.dll"

    $hasFFmpeg = Test-Path $ffmpegDll
    $hasUpnp = Test-Path $upnpDll

    if ($hasFFmpeg -and $hasUpnp) {
        Write-Success "vcpkg dependencies are installed"
        return $true
    }

    if (-not $hasFFmpeg) { Write-Warning "FFmpeg not found in vcpkg" }
    if (-not $hasUpnp) { Write-Warning "libupnp not found in vcpkg" }

    return $false
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
    Write-Info "Installing vcpkg dependencies (this may take several minutes)..."

    Push-Location $VcpkgRoot

    Write-Info "Installing FFmpeg..."
    & .\vcpkg.exe install ffmpeg:x64-windows

    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to install FFmpeg"
    }

    Write-Info "Installing libupnp..."
    & .\vcpkg.exe install "libupnp[webserver]:x64-windows"

    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to install libupnp"
    }

    Pop-Location

    Write-Success "Dependencies installed successfully"
}

function Build-Project {
    param([string]$MSBuildPath)

    Write-Info "Building Diretta UPnP Renderer..."

    $vcxproj = Join-Path $ProjectDir "DirettaRendererUPnP.vcxproj"

    if (-not (Test-Path $vcxproj)) {
        throw "Project file not found: $vcxproj"
    }

    # Create output directory
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }

    Write-Info "Running MSBuild..."
    & $MSBuildPath $vcxproj /p:Configuration=Release /p:Platform=x64 /verbosity:minimal

    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path $ExePath)) {
        throw "Build completed but executable not found at: $ExePath"
    }

    Write-Success "Build successful!"
    Write-Info "Executable: $ExePath"
}

function Copy-Dependencies {
    Write-Info "Copying DLLs to output directory..."

    if (-not (Test-Path $VcpkgBin)) {
        Write-Warning "vcpkg bin directory not found: $VcpkgBin"
        return
    }

    $dlls = Get-ChildItem -Path $VcpkgBin -Filter "*.dll"
    $copied = 0

    foreach ($dll in $dlls) {
        $destPath = Join-Path $BinDir $dll.Name
        if (-not (Test-Path $destPath) -or $Force) {
            Copy-Item $dll.FullName $destPath -Force
            $copied++
        }
    }

    Write-Success "Copied $copied DLL(s) to output directory"
}

function Configure-Firewall {
    Write-Info "Configuring Windows Firewall..."

    $rules = @(
        @{
            Name = "Diretta Renderer - Inbound"
            Direction = "Inbound"
            Program = $ExePath
            Action = "Allow"
        },
        @{
            Name = "Diretta Renderer - Outbound"
            Direction = "Outbound"
            Program = $ExePath
            Action = "Allow"
        },
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

Write-Host "This script will:" -ForegroundColor White
Write-Host "  1. Check prerequisites (MSBuild, cl.exe, Git, Npcap, SDK)"
Write-Host "  2. Install/update vcpkg and dependencies"
Write-Host "  3. Build the project"
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
$sdkPath = Find-DirettaSDK
if (-not $sdkPath) {
    Write-Error "Diretta Host SDK not found!"
    $prereqsMissing += @{
        Name = "Diretta Host SDK v147"
        Instructions = @(
            "Download from: https://www.diretta.link",
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

if ($SkipBuild) {
    Write-Info "Skipping build (--SkipBuild specified)"
}
elseif ((Test-Path $ExePath) -and -not $Force) {
    Write-Info "Executable already exists: $ExePath"

    if (Confirm-Continue "Rebuild anyway?") {
        Build-Project $msbuildPath
    }
    else {
        Write-Info "Skipping build"
    }
}
else {
    Build-Project $msbuildPath
}

# ============================================================================
# Step 4: Copy DLLs
# ============================================================================

Write-Step 4 "Copying Dependencies"

if (Test-Path $ExePath) {
    Copy-Dependencies
}
else {
    Write-Warning "Executable not found, skipping DLL copy"
}

# ============================================================================
# Step 5: Firewall Configuration
# ============================================================================

Write-Step 5 "Configuring Firewall"

if ($SkipFirewall) {
    Write-Info "Skipping firewall configuration (--SkipFirewall specified)"
}
elseif (Test-Path $ExePath) {
    Configure-Firewall
}
else {
    Write-Warning "Executable not found, skipping firewall configuration"
}

# ============================================================================
# Complete
# ============================================================================

Write-Header "Installation Complete!"

if (Test-Path $ExePath) {
    Write-Success "Diretta UPnP Renderer is ready to use!"
    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor Cyan
    Write-Host "  1. List available targets:"
    Write-Host "     $ExePath --list-targets" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Start the renderer:"
    Write-Host "     $ExePath --target 1" -ForegroundColor White
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
