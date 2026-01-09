#Requires -Version 5.1
<#
.SYNOPSIS
    Diretta UPnP Renderer - Windows Launcher

.DESCRIPTION
    Enhanced launcher for Diretta UPnP Renderer with:
    - Automatic Administrator elevation (UAC prompt)
    - Npcap verification before launch
    - Configuration persistence (remembers last settings)
    - Interactive menu or command-line operation

.PARAMETER Target
    Diretta target index (1, 2, 3...). Use --list-targets to see available targets.

.PARAMETER Name
    Renderer name visible to UPnP control points.

.PARAMETER Port
    UPnP port (default: auto-assigned).

.PARAMETER Verbose
    Enable verbose debug output.

.PARAMETER ListTargets
    List available Diretta targets and exit.

.PARAMETER Menu
    Show interactive menu (default if no parameters specified).

.PARAMETER NoSave
    Don't save settings to configuration file.

.EXAMPLE
    .\Start-DirettaRenderer.ps1
    Opens interactive menu.

.EXAMPLE
    .\Start-DirettaRenderer.ps1 -Target 1
    Starts renderer with target 1 using saved settings.

.EXAMPLE
    .\Start-DirettaRenderer.ps1 -Target 1 -Name "Living Room" -Verbose
    Starts renderer with specific settings.

.EXAMPLE
    .\Start-DirettaRenderer.ps1 -ListTargets
    Lists available Diretta targets.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [int]$Target,

    [string]$Name,

    [int]$Port,

    [switch]$Verbose,

    [Alias("l")]
    [switch]$ListTargets,

    [Alias("m")]
    [switch]$Menu,

    [switch]$NoSave
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"

$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:BinDir = Join-Path $ScriptDir "bin\x64\Release"
$Script:ExePath = Join-Path $BinDir "DirettaRendererUPnP.exe"
$Script:VcpkgBin = "C:\vcpkg\installed\x64-windows\bin"

# Configuration file location
$Script:ConfigDir = Join-Path $env:APPDATA "DirettaRenderer"
$Script:ConfigFile = Join-Path $ConfigDir "config.json"

# Default configuration
$Script:DefaultConfig = @{
    Target = 1
    Name = "Diretta Renderer"
    Port = 0
    Verbose = $false
    LastRun = $null
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-ColorHost {
    param(
        [string]$Text,
        [ConsoleColor]$Color = "White",
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-ColorHost "  ╔═══════════════════════════════════════════════════════╗" Cyan
    Write-ColorHost "  ║                                                       ║" Cyan
    Write-ColorHost "  ║         Diretta UPnP Renderer for Windows             ║" Cyan
    Write-ColorHost "  ║                                                       ║" Cyan
    Write-ColorHost "  ╚═══════════════════════════════════════════════════════╝" Cyan
    Write-Host ""
}

function Write-Status {
    param([string]$Label, [string]$Value, [ConsoleColor]$ValueColor = "White")
    Write-ColorHost "  $Label : " Gray -NoNewline
    Write-ColorHost $Value $ValueColor
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    if (-not (Test-Administrator)) {
        Write-ColorHost "Requesting Administrator privileges..." Yellow

        # Build argument list preserving all parameters
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.PSCommandPath)`""

        if ($Target -gt 0) { $arguments += " -Target $Target" }
        if ($Name) { $arguments += " -Name `"$Name`"" }
        if ($Port -gt 0) { $arguments += " -Port $Port" }
        if ($Verbose) { $arguments += " -Verbose" }
        if ($ListTargets) { $arguments += " -ListTargets" }
        if ($Menu) { $arguments += " -Menu" }
        if ($NoSave) { $arguments += " -NoSave" }

        try {
            Start-Process PowerShell -Verb RunAs -ArgumentList $arguments -Wait
        }
        catch {
            Write-ColorHost "Failed to elevate privileges. Please run as Administrator." Red
            Read-Host "Press Enter to exit"
        }
        exit
    }
}

function Pause-Script {
    param([string]$Message = "Press any key to continue...")
    Write-Host ""
    Write-ColorHost $Message Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ============================================================================
# Configuration Management
# ============================================================================

function Get-SavedConfig {
    if (Test-Path $ConfigFile) {
        try {
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            # Merge with defaults for any missing properties
            $result = $DefaultConfig.Clone()
            foreach ($prop in $config.PSObject.Properties) {
                if ($result.ContainsKey($prop.Name)) {
                    $result[$prop.Name] = $prop.Value
                }
            }
            return $result
        }
        catch {
            Write-ColorHost "Warning: Could not read config file, using defaults." Yellow
            return $DefaultConfig.Clone()
        }
    }
    return $DefaultConfig.Clone()
}

function Save-Config {
    param([hashtable]$Config)

    if ($NoSave) { return }

    try {
        if (-not (Test-Path $ConfigDir)) {
            New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
        }

        $Config.LastRun = (Get-Date).ToString("o")
        $Config | ConvertTo-Json | Set-Content $ConfigFile -Force

        Write-ColorHost "  Settings saved." DarkGray
    }
    catch {
        Write-ColorHost "Warning: Could not save config file." Yellow
    }
}

# ============================================================================
# System Checks
# ============================================================================

function Test-Executable {
    if (-not (Test-Path $ExePath)) {
        Write-ColorHost "ERROR: DirettaRendererUPnP.exe not found!" Red
        Write-ColorHost "Expected location: $ExePath" Gray
        Write-Host ""
        Write-ColorHost "Please build the project first:" Yellow
        Write-ColorHost "  .\install.ps1" White
        Write-Host ""
        return $false
    }
    return $true
}

function Test-Npcap {
    $npcapPath = "${env:ProgramFiles}\Npcap"
    $dumpcap = Join-Path $npcapPath "dumpcap.exe"

    if (-not (Test-Path $dumpcap)) {
        return @{
            Installed = $false
            Working = $false
            Message = "Npcap not installed"
            Interfaces = 0
        }
    }

    try {
        $output = & $dumpcap -D 2>&1
        $interfaces = ($output | Where-Object { $_ -match "^\d+\." }).Count

        if ($interfaces -gt 0) {
            return @{
                Installed = $true
                Working = $true
                Message = "OK ($interfaces interfaces)"
                Interfaces = $interfaces
            }
        }
        else {
            return @{
                Installed = $true
                Working = $false
                Message = "No interfaces detected"
                Interfaces = 0
            }
        }
    }
    catch {
        return @{
            Installed = $true
            Working = $false
            Message = "Error: $_"
            Interfaces = 0
        }
    }
}

function Copy-DllsIfNeeded {
    $upnpDll = Join-Path $BinDir "libupnp.dll"

    if (-not (Test-Path $upnpDll)) {
        if (Test-Path $VcpkgBin) {
            Write-ColorHost "  Copying required DLLs..." Gray
            Copy-Item "$VcpkgBin\*.dll" $BinDir -Force -ErrorAction SilentlyContinue
            Write-ColorHost "  DLLs copied." DarkGray
        }
        else {
            Write-ColorHost "  Warning: vcpkg DLLs not found at $VcpkgBin" Yellow
        }
    }
}

function Show-SystemStatus {
    Write-Host ""
    Write-ColorHost "  System Status:" Cyan
    Write-ColorHost "  ─────────────────────────────────────────────────" DarkGray

    # Executable
    if (Test-Path $ExePath) {
        $version = (Get-Item $ExePath).VersionInfo.FileVersion
        if (-not $version) { $version = "built" }
        Write-Status "Executable" "Found ($version)" Green
    }
    else {
        Write-Status "Executable" "NOT FOUND" Red
    }

    # Npcap
    $npcap = Test-Npcap
    if ($npcap.Working) {
        Write-Status "Npcap" $npcap.Message Green
        Write-Status "Socket Mode" "RAW (MSMODE3)" Green
    }
    elseif ($npcap.Installed) {
        Write-Status "Npcap" $npcap.Message Yellow
        Write-Status "Socket Mode" "UDP fallback (MSMODE2)" Yellow
    }
    else {
        Write-Status "Npcap" $npcap.Message Red
        Write-Status "Socket Mode" "UDP fallback (MSMODE2)" Yellow
    }

    # Admin status
    if (Test-Administrator) {
        Write-Status "Privileges" "Administrator" Green
    }
    else {
        Write-Status "Privileges" "Standard User" Yellow
    }

    Write-Host ""
}

# ============================================================================
# Renderer Operations
# ============================================================================

function Get-DirettaTargets {
    Write-ColorHost "  Scanning for Diretta targets..." Cyan
    Write-Host ""

    & $ExePath --list-targets

    Write-Host ""
}

function Start-Renderer {
    param(
        [int]$TargetIndex,
        [string]$RendererName,
        [int]$UPnPPort,
        [switch]$VerboseMode
    )

    # Build command line
    $arguments = @()

    if ($TargetIndex -gt 0) {
        $arguments += "--target"
        $arguments += $TargetIndex
    }

    if ($RendererName) {
        $arguments += "--name"
        $arguments += "`"$RendererName`""
    }

    if ($UPnPPort -gt 0) {
        $arguments += "--port"
        $arguments += $UPnPPort
    }

    if ($VerboseMode) {
        $arguments += "--verbose"
    }

    # Display startup info
    Write-Host ""
    Write-ColorHost "  ╔═══════════════════════════════════════════════════════╗" Green
    Write-ColorHost "  ║              Starting Diretta Renderer                ║" Green
    Write-ColorHost "  ╚═══════════════════════════════════════════════════════╝" Green
    Write-Host ""

    if ($TargetIndex -gt 0) {
        Write-Status "Target" "#$TargetIndex" Cyan
    }
    else {
        Write-Status "Target" "Auto-detect" Cyan
    }

    if ($RendererName) {
        Write-Status "Name" $RendererName Cyan
    }

    if ($UPnPPort -gt 0) {
        Write-Status "Port" $UPnPPort Cyan
    }
    else {
        Write-Status "Port" "Auto" Cyan
    }

    Write-Status "Verbose" $(if ($VerboseMode) { "Enabled" } else { "Disabled" }) Cyan

    Write-Host ""
    Write-ColorHost "  Press Ctrl+C to stop the renderer." Yellow
    Write-Host ""
    Write-ColorHost "  ─────────────────────────────────────────────────────────" DarkGray
    Write-Host ""

    # Save configuration
    $config = @{
        Target = $TargetIndex
        Name = $RendererName
        Port = $UPnPPort
        Verbose = [bool]$VerboseMode
    }
    Save-Config $config

    # Copy DLLs if needed
    Copy-DllsIfNeeded

    # Start the renderer
    $argString = $arguments -join " "
    if ($argString) {
        & $ExePath $arguments
    }
    else {
        & $ExePath
    }
}

# ============================================================================
# Interactive Menu
# ============================================================================

function Show-Menu {
    $config = Get-SavedConfig

    while ($true) {
        Write-Banner
        Show-SystemStatus

        Write-ColorHost "  Current Settings:" Cyan
        Write-ColorHost "  ─────────────────────────────────────────────────" DarkGray
        Write-Status "Target" $(if ($config.Target -gt 0) { "#$($config.Target)" } else { "Auto" }) White
        Write-Status "Name" $(if ($config.Name) { $config.Name } else { "(default)" }) White
        Write-Status "Verbose" $(if ($config.Verbose) { "Enabled" } else { "Disabled" }) White

        if ($config.LastRun) {
            $lastRun = [DateTime]::Parse($config.LastRun)
            Write-Status "Last Run" $lastRun.ToString("g") DarkGray
        }

        Write-Host ""
        Write-ColorHost "  Menu:" Cyan
        Write-ColorHost "  ─────────────────────────────────────────────────" DarkGray
        Write-ColorHost "  [1] " White -NoNewline
        Write-ColorHost "Start renderer (with saved settings)" Gray

        Write-ColorHost "  [2] " White -NoNewline
        Write-ColorHost "List available Diretta targets" Gray

        Write-ColorHost "  [3] " White -NoNewline
        Write-ColorHost "Change target" Gray

        Write-ColorHost "  [4] " White -NoNewline
        Write-ColorHost "Change renderer name" Gray

        Write-ColorHost "  [5] " White -NoNewline
        Write-ColorHost "Toggle verbose mode" Gray

        Write-ColorHost "  [6] " White -NoNewline
        Write-ColorHost "Configure Windows Firewall" Gray

        Write-ColorHost "  [7] " White -NoNewline
        Write-ColorHost "Start renderer (verbose, for troubleshooting)" Gray

        Write-Host ""
        Write-ColorHost "  [Q] " White -NoNewline
        Write-ColorHost "Quit" Gray

        Write-Host ""
        $choice = Read-Host "  Select option"

        switch ($choice.ToUpper()) {
            "1" {
                if (-not (Test-Executable)) {
                    Pause-Script
                    continue
                }
                Start-Renderer -TargetIndex $config.Target -RendererName $config.Name -UPnPPort $config.Port -VerboseMode:$config.Verbose
                Pause-Script
            }

            "2" {
                if (-not (Test-Executable)) {
                    Pause-Script
                    continue
                }
                Write-Host ""
                Get-DirettaTargets
                Pause-Script
            }

            "3" {
                Write-Host ""
                $newTarget = Read-Host "  Enter target number (1, 2, 3...) or 0 for auto"
                if ($newTarget -match "^\d+$") {
                    $config.Target = [int]$newTarget
                    Save-Config $config
                    Write-ColorHost "  Target set to #$($config.Target)" Green
                }
                else {
                    Write-ColorHost "  Invalid input." Yellow
                }
                Start-Sleep -Milliseconds 500
            }

            "4" {
                Write-Host ""
                $newName = Read-Host "  Enter renderer name (or press Enter for default)"
                if ($newName) {
                    $config.Name = $newName
                }
                else {
                    $config.Name = "Diretta Renderer"
                }
                Save-Config $config
                Write-ColorHost "  Name set to: $($config.Name)" Green
                Start-Sleep -Milliseconds 500
            }

            "5" {
                $config.Verbose = -not $config.Verbose
                Save-Config $config
                Write-ColorHost "  Verbose mode: $(if ($config.Verbose) { 'Enabled' } else { 'Disabled' })" Green
                Start-Sleep -Milliseconds 500
            }

            "6" {
                Write-Host ""
                Configure-Firewall
                Pause-Script
            }

            "7" {
                if (-not (Test-Executable)) {
                    Pause-Script
                    continue
                }
                Start-Renderer -TargetIndex $config.Target -RendererName $config.Name -UPnPPort $config.Port -VerboseMode
                Pause-Script
            }

            "Q" {
                Write-Host ""
                Write-ColorHost "  Goodbye!" Cyan
                Write-Host ""
                return
            }

            default {
                Write-ColorHost "  Invalid option." Yellow
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

function Configure-Firewall {
    Write-ColorHost "  Configuring Windows Firewall..." Cyan
    Write-Host ""

    $rules = @(
        @{ Name = "Diretta Renderer - Inbound"; Dir = "in"; Program = $ExePath },
        @{ Name = "Diretta Renderer - Outbound"; Dir = "out"; Program = $ExePath },
        @{ Name = "UPnP SSDP Discovery"; Dir = "in"; Protocol = "udp"; Port = "1900" },
        @{ Name = "UPnP SSDP Multicast"; Dir = "out"; Protocol = "udp"; Port = "1900" },
        @{ Name = "UPnP HTTP Ports"; Dir = "in"; Protocol = "tcp"; Port = "49152-65535" }
    )

    foreach ($rule in $rules) {
        $existing = netsh advfirewall firewall show rule name="$($rule.Name)" 2>$null

        if ($existing -match "Rule Name") {
            Write-ColorHost "  [SKIP] $($rule.Name) (exists)" DarkGray
        }
        else {
            $cmd = "netsh advfirewall firewall add rule name=`"$($rule.Name)`" dir=$($rule.Dir) action=allow enable=yes profile=any"

            if ($rule.Program) { $cmd += " program=`"$($rule.Program)`"" }
            if ($rule.Protocol) { $cmd += " protocol=$($rule.Protocol)" }
            if ($rule.Port) {
                if ($rule.Dir -eq "in") {
                    $cmd += " localport=$($rule.Port)"
                }
                else {
                    $cmd += " remoteport=$($rule.Port)"
                }
            }

            $result = Invoke-Expression $cmd 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-ColorHost "  [OK] $($rule.Name)" Green
            }
            else {
                Write-ColorHost "  [FAIL] $($rule.Name)" Red
            }
        }
    }

    Write-Host ""
    Write-ColorHost "  Firewall configuration complete." Green
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Request elevation
Request-Elevation

# Handle command-line modes
if ($ListTargets) {
    Write-Banner
    if (Test-Executable) {
        Get-DirettaTargets
    }
    exit
}

# If parameters provided, run directly without menu
if ($Target -gt 0 -or $Name -or $Port -gt 0) {
    Write-Banner
    Show-SystemStatus

    if (-not (Test-Executable)) {
        Pause-Script
        exit 1
    }

    # Load saved config and override with command-line params
    $config = Get-SavedConfig

    $targetIndex = if ($Target -gt 0) { $Target } else { $config.Target }
    $rendererName = if ($Name) { $Name } else { $config.Name }
    $upnpPort = if ($Port -gt 0) { $Port } else { $config.Port }
    $verboseMode = $Verbose -or $config.Verbose

    Start-Renderer -TargetIndex $targetIndex -RendererName $rendererName -UPnPPort $upnpPort -VerboseMode:$verboseMode

    Pause-Script
    exit
}

# Default: show interactive menu
Show-Menu
