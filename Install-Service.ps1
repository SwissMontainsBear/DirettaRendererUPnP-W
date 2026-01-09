#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diretta UPnP Renderer - Windows Service Installer

.DESCRIPTION
    Installs Diretta UPnP Renderer as a Windows Service for appliance-mode operation.
    Uses NSSM (Non-Sucking Service Manager) to wrap the console application.

    The service will:
    - Start automatically when Windows boots
    - Restart automatically if it crashes
    - Run with Administrator privileges
    - Log output to files

.PARAMETER Install
    Install the service (default action if no parameter specified).

.PARAMETER Uninstall
    Remove the service completely.

.PARAMETER Configure
    Reconfigure an existing service installation.

.PARAMETER Start
    Start the service.

.PARAMETER Stop
    Stop the service.

.PARAMETER Restart
    Restart the service.

.PARAMETER Status
    Show service status.

.PARAMETER Logs
    Show recent service logs.

.PARAMETER Target
    Diretta target index (1, 2, 3...).

.PARAMETER Name
    Renderer name visible to UPnP control points.

.PARAMETER Verbose
    Enable verbose logging in the renderer.

.EXAMPLE
    .\Install-Service.ps1 -Install -Target 1
    Install service configured for target 1.

.EXAMPLE
    .\Install-Service.ps1 -Uninstall
    Remove the service.

.EXAMPLE
    .\Install-Service.ps1 -Status
    Show current service status.

.EXAMPLE
    .\Install-Service.ps1 -Logs
    Show recent log output.
#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName = "Install")]
    [switch]$Install,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "Configure")]
    [switch]$Configure,

    [Parameter(ParameterSetName = "Start")]
    [switch]$Start,

    [Parameter(ParameterSetName = "Stop")]
    [switch]$Stop,

    [Parameter(ParameterSetName = "Restart")]
    [switch]$Restart,

    [Parameter(ParameterSetName = "Status")]
    [switch]$Status,

    [Parameter(ParameterSetName = "Logs")]
    [switch]$Logs,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Configure")]
    [int]$Target = 0,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Configure")]
    [string]$Name,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Configure")]
    [int]$Port = 0,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Configure")]
    [switch]$Verbose
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"

$Script:ServiceName = "DirettaRenderer"
$Script:ServiceDisplayName = "Diretta UPnP Renderer"
$Script:ServiceDescription = "UPnP/DLNA audio renderer using Diretta protocol for bit-perfect playback"

$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:BinDir = Join-Path $ScriptDir "bin\x64\Release"
$Script:ExePath = Join-Path $BinDir "DirettaRendererUPnP.exe"

# NSSM paths
$Script:ToolsDir = Join-Path $ScriptDir "tools"
$Script:NssmDir = Join-Path $ToolsDir "nssm"
$Script:NssmExe = Join-Path $NssmDir "nssm.exe"
$Script:NssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
$Script:NssmZip = Join-Path $ToolsDir "nssm.zip"

# Log paths
$Script:LogDir = Join-Path $ScriptDir "logs"
$Script:StdoutLog = Join-Path $LogDir "diretta-stdout.log"
$Script:StderrLog = Join-Path $LogDir "diretta-stderr.log"

# Service config file
$Script:ServiceConfigFile = Join-Path $ScriptDir "service-config.json"

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

function Write-Warn {
    param([string]$Text)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Text
}

function Write-Err {
    param([string]$Text)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Text
}

function Pause-Script {
    param([string]$Message = "Press any key to continue...")
    Write-Host ""
    Write-Host $Message -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Confirm-Action {
    param([string]$Message)
    $response = Read-Host "$Message [Y/n]"
    return ($response -eq "" -or $response -match "^[Yy]")
}

# ============================================================================
# NSSM Management
# ============================================================================

function Test-NssmInstalled {
    return (Test-Path $NssmExe)
}

function Install-Nssm {
    Write-Info "NSSM not found, downloading..."

    # Create tools directory
    if (-not (Test-Path $ToolsDir)) {
        New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
    }

    # Download NSSM
    try {
        Write-Info "Downloading from $NssmUrl..."

        # Use TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($NssmUrl, $NssmZip)

        Write-Info "Extracting NSSM..."

        # Extract ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractPath = Join-Path $ToolsDir "nssm-extract"

        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }

        [System.IO.Compression.ZipFile]::ExtractToDirectory($NssmZip, $extractPath)

        # Find and copy the 64-bit executable
        $nssmSource = Get-ChildItem -Path $extractPath -Recurse -Filter "nssm.exe" |
                      Where-Object { $_.DirectoryName -match "win64" } |
                      Select-Object -First 1

        if (-not $nssmSource) {
            throw "Could not find nssm.exe in downloaded archive"
        }

        # Create nssm directory and copy
        if (-not (Test-Path $NssmDir)) {
            New-Item -ItemType Directory -Path $NssmDir -Force | Out-Null
        }

        Copy-Item $nssmSource.FullName $NssmExe -Force

        # Cleanup
        Remove-Item $NssmZip -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "NSSM installed to: $NssmExe"
        return $true
    }
    catch {
        Write-Err "Failed to download NSSM: $_"
        Write-Host ""
        Write-Host "Please download NSSM manually:" -ForegroundColor Yellow
        Write-Host "  1. Visit: https://nssm.cc/download" -ForegroundColor Gray
        Write-Host "  2. Download nssm-2.24.zip" -ForegroundColor Gray
        Write-Host "  3. Extract nssm.exe (win64) to: $NssmDir" -ForegroundColor Gray
        return $false
    }
}

function Invoke-Nssm {
    param([string[]]$Arguments)

    $process = Start-Process -FilePath $NssmExe -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    return $process.ExitCode
}

# ============================================================================
# Service Configuration
# ============================================================================

function Get-ServiceConfig {
    if (Test-Path $ServiceConfigFile) {
        try {
            return Get-Content $ServiceConfigFile -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warn "Could not read service config file"
        }
    }

    return @{
        Target = 1
        Name = "Diretta Renderer"
        Port = 0
        Verbose = $false
    }
}

function Save-ServiceConfig {
    param([hashtable]$Config)

    try {
        $Config | ConvertTo-Json | Set-Content $ServiceConfigFile -Force
        Write-Info "Service configuration saved to: $ServiceConfigFile"
    }
    catch {
        Write-Warn "Could not save service config: $_"
    }
}

function Get-RendererArguments {
    param([object]$Config)

    $args = @()

    if ($Config.Target -gt 0) {
        $args += "--target"
        $args += $Config.Target
    }

    if ($Config.Name) {
        $args += "--name"
        $args += "`"$($Config.Name)`""
    }

    if ($Config.Port -gt 0) {
        $args += "--port"
        $args += $Config.Port
    }

    if ($Config.Verbose) {
        $args += "--verbose"
    }

    return ($args -join " ")
}

# ============================================================================
# Service Operations
# ============================================================================

function Test-ServiceExists {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return ($null -ne $service)
}

function Get-ServiceState {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        return $service.Status
    }
    return "NotInstalled"
}

function Install-DirettaService {
    Write-Header "Installing Diretta Renderer Service"

    # Check executable exists
    if (-not (Test-Path $ExePath)) {
        Write-Err "Renderer executable not found: $ExePath"
        Write-Host "Please build the project first using: .\install.ps1" -ForegroundColor Yellow
        return $false
    }

    # Check if service already exists
    if (Test-ServiceExists) {
        Write-Warn "Service '$ServiceName' already exists."

        if (-not (Confirm-Action "Remove existing service and reinstall?")) {
            Write-Info "Installation cancelled."
            return $false
        }

        Uninstall-DirettaService -Silent
    }

    # Ensure NSSM is available
    if (-not (Test-NssmInstalled)) {
        if (-not (Install-Nssm)) {
            return $false
        }
    }

    # Create log directory
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Write-Info "Created log directory: $LogDir"
    }

    # Get configuration
    $config = @{
        Target = if ($Target -gt 0) { $Target } else { 1 }
        Name = if ($Name) { $Name } else { "Diretta Renderer" }
        Port = $Port
        Verbose = [bool]$Verbose
    }

    # If no target specified, ask user
    if ($Target -eq 0) {
        Write-Host ""
        Write-Host "Service Configuration:" -ForegroundColor Cyan
        Write-Host ""

        # List available targets
        Write-Info "Scanning for Diretta targets..."
        & $ExePath --list-targets
        Write-Host ""

        $inputTarget = Read-Host "Enter target number (1, 2, 3...) [default: 1]"
        if ($inputTarget -match "^\d+$") {
            $config.Target = [int]$inputTarget
        }

        $inputName = Read-Host "Enter renderer name [default: Diretta Renderer]"
        if ($inputName) {
            $config.Name = $inputName
        }

        $inputVerbose = Read-Host "Enable verbose logging? [y/N]"
        if ($inputVerbose -match "^[Yy]") {
            $config.Verbose = $true
        }
    }

    # Save configuration
    Save-ServiceConfig $config

    # Build arguments string
    $rendererArgs = Get-RendererArguments $config

    Write-Host ""
    Write-Info "Installing service with NSSM..."
    Write-Info "  Executable: $ExePath"
    Write-Info "  Arguments: $rendererArgs"
    Write-Host ""

    # Install service
    $result = Invoke-Nssm @("install", $ServiceName, $ExePath)
    if ($result -ne 0) {
        Write-Err "Failed to install service (exit code: $result)"
        return $false
    }

    Write-Success "Service installed"

    # Configure service parameters
    Write-Info "Configuring service parameters..."

    # Set arguments
    if ($rendererArgs) {
        Invoke-Nssm @("set", $ServiceName, "AppParameters", $rendererArgs) | Out-Null
    }

    # Set display name and description
    Invoke-Nssm @("set", $ServiceName, "DisplayName", $ServiceDisplayName) | Out-Null
    Invoke-Nssm @("set", $ServiceName, "Description", $ServiceDescription) | Out-Null

    # Set working directory
    Invoke-Nssm @("set", $ServiceName, "AppDirectory", $BinDir) | Out-Null

    # Configure logging
    Invoke-Nssm @("set", $ServiceName, "AppStdout", $StdoutLog) | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppStderr", $StderrLog) | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppStdoutCreationDisposition", "4") | Out-Null  # Append
    Invoke-Nssm @("set", $ServiceName, "AppStderrCreationDisposition", "4") | Out-Null  # Append
    Invoke-Nssm @("set", $ServiceName, "AppRotateFiles", "1") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppRotateBytes", "1048576") | Out-Null  # 1MB

    # Configure restart behavior
    Invoke-Nssm @("set", $ServiceName, "AppExit", "Default", "Restart") | Out-Null
    Invoke-Nssm @("set", $ServiceName, "AppRestartDelay", "5000") | Out-Null  # 5 seconds

    # Set startup type to automatic
    Invoke-Nssm @("set", $ServiceName, "Start", "SERVICE_AUTO_START") | Out-Null

    Write-Success "Service configured"

    # Ask to start service
    Write-Host ""
    if (Confirm-Action "Start the service now?") {
        Start-DirettaService
    }

    Write-Host ""
    Write-Header "Installation Complete"

    Write-Host "Service Management Commands:" -ForegroundColor Cyan
    Write-Host "  .\Install-Service.ps1 -Start      # Start service" -ForegroundColor Gray
    Write-Host "  .\Install-Service.ps1 -Stop       # Stop service" -ForegroundColor Gray
    Write-Host "  .\Install-Service.ps1 -Restart    # Restart service" -ForegroundColor Gray
    Write-Host "  .\Install-Service.ps1 -Status     # Check status" -ForegroundColor Gray
    Write-Host "  .\Install-Service.ps1 -Logs       # View logs" -ForegroundColor Gray
    Write-Host "  .\Install-Service.ps1 -Uninstall  # Remove service" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or use Windows Services (services.msc):" -ForegroundColor Cyan
    Write-Host "  Service name: $ServiceName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Log files:" -ForegroundColor Cyan
    Write-Host "  $StdoutLog" -ForegroundColor Gray
    Write-Host "  $StderrLog" -ForegroundColor Gray
    Write-Host ""

    return $true
}

function Uninstall-DirettaService {
    param([switch]$Silent)

    if (-not $Silent) {
        Write-Header "Uninstalling Diretta Renderer Service"
    }

    if (-not (Test-ServiceExists)) {
        if (-not $Silent) {
            Write-Warn "Service '$ServiceName' is not installed."
        }
        return $true
    }

    # Stop service if running
    $state = Get-ServiceState
    if ($state -eq "Running") {
        Write-Info "Stopping service..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Ensure NSSM is available
    if (-not (Test-NssmInstalled)) {
        # Try using sc.exe as fallback
        Write-Info "Removing service using sc.exe..."
        $result = & sc.exe delete $ServiceName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Service removed"
            return $true
        }
        else {
            Write-Err "Failed to remove service: $result"
            return $false
        }
    }

    Write-Info "Removing service..."
    $result = Invoke-Nssm @("remove", $ServiceName, "confirm")

    if ($result -eq 0) {
        Write-Success "Service removed"

        # Ask about removing logs
        if (-not $Silent -and (Test-Path $LogDir)) {
            if (Confirm-Action "Remove log files?") {
                Remove-Item $LogDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Info "Log files removed"
            }
        }

        return $true
    }
    else {
        Write-Err "Failed to remove service (exit code: $result)"
        return $false
    }
}

function Start-DirettaService {
    Write-Info "Starting service..."

    if (-not (Test-ServiceExists)) {
        Write-Err "Service '$ServiceName' is not installed."
        Write-Host "Run: .\Install-Service.ps1 -Install" -ForegroundColor Yellow
        return $false
    }

    try {
        Start-Service -Name $ServiceName
        Start-Sleep -Seconds 2

        $state = Get-ServiceState
        if ($state -eq "Running") {
            Write-Success "Service started"
            return $true
        }
        else {
            Write-Err "Service failed to start (state: $state)"
            Write-Host "Check logs: .\Install-Service.ps1 -Logs" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Err "Failed to start service: $_"
        return $false
    }
}

function Stop-DirettaService {
    Write-Info "Stopping service..."

    if (-not (Test-ServiceExists)) {
        Write-Warn "Service '$ServiceName' is not installed."
        return $true
    }

    $state = Get-ServiceState
    if ($state -ne "Running") {
        Write-Info "Service is not running (state: $state)"
        return $true
    }

    try {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2

        $state = Get-ServiceState
        if ($state -eq "Stopped") {
            Write-Success "Service stopped"
            return $true
        }
        else {
            Write-Warn "Service state: $state"
            return $false
        }
    }
    catch {
        Write-Err "Failed to stop service: $_"
        return $false
    }
}

function Restart-DirettaService {
    Write-Info "Restarting service..."

    if (-not (Test-ServiceExists)) {
        Write-Err "Service '$ServiceName' is not installed."
        return $false
    }

    Stop-DirettaService | Out-Null
    Start-Sleep -Seconds 1
    return Start-DirettaService
}

function Show-ServiceStatus {
    Write-Header "Diretta Renderer Service Status"

    # Service status
    if (Test-ServiceExists) {
        $service = Get-Service -Name $ServiceName
        $state = $service.Status

        $stateColor = switch ($state) {
            "Running" { "Green" }
            "Stopped" { "Yellow" }
            default { "Gray" }
        }

        Write-Host "  Service Name    : " -NoNewline
        Write-Host $ServiceName -ForegroundColor White

        Write-Host "  Display Name    : " -NoNewline
        Write-Host $ServiceDisplayName -ForegroundColor White

        Write-Host "  Status          : " -NoNewline
        Write-Host $state -ForegroundColor $stateColor

        Write-Host "  Startup Type    : " -NoNewline
        Write-Host $service.StartType -ForegroundColor White

        # Get process info if running
        if ($state -eq "Running") {
            $process = Get-Process -Name "DirettaRendererUPnP" -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host "  Process ID      : " -NoNewline
                Write-Host $process.Id -ForegroundColor Cyan

                $uptime = (Get-Date) - $process.StartTime
                Write-Host "  Uptime          : " -NoNewline
                Write-Host ("{0:d}d {1:hh\:mm\:ss}" -f $uptime.Days, $uptime) -ForegroundColor Cyan

                Write-Host "  Memory          : " -NoNewline
                Write-Host ("{0:N0} MB" -f ($process.WorkingSet64 / 1MB)) -ForegroundColor Cyan
            }
        }
    }
    else {
        Write-Host "  Service Status  : " -NoNewline
        Write-Host "Not Installed" -ForegroundColor Red
    }

    Write-Host ""

    # Configuration
    Write-Host "  Configuration:" -ForegroundColor Cyan
    if (Test-Path $ServiceConfigFile) {
        $config = Get-ServiceConfig
        Write-Host "    Target        : #$($config.Target)" -ForegroundColor Gray
        Write-Host "    Name          : $($config.Name)" -ForegroundColor Gray
        Write-Host "    Verbose       : $($config.Verbose)" -ForegroundColor Gray
    }
    else {
        Write-Host "    (no configuration file)" -ForegroundColor Gray
    }

    Write-Host ""

    # Log files
    Write-Host "  Log Files:" -ForegroundColor Cyan
    if (Test-Path $StdoutLog) {
        $logInfo = Get-Item $StdoutLog
        Write-Host "    stdout        : $($logInfo.Length / 1KB) KB" -ForegroundColor Gray
    }
    if (Test-Path $StderrLog) {
        $logInfo = Get-Item $StderrLog
        Write-Host "    stderr        : $($logInfo.Length / 1KB) KB" -ForegroundColor Gray
    }

    Write-Host ""
}

function Show-ServiceLogs {
    param([int]$Lines = 50)

    Write-Header "Diretta Renderer Service Logs"

    if (Test-Path $StdoutLog) {
        Write-Host "=== stdout (last $Lines lines) ===" -ForegroundColor Cyan
        Get-Content $StdoutLog -Tail $Lines
        Write-Host ""
    }
    else {
        Write-Warn "stdout log not found: $StdoutLog"
    }

    if (Test-Path $StderrLog) {
        $stderrContent = Get-Content $StderrLog -Tail $Lines
        if ($stderrContent) {
            Write-Host "=== stderr (last $Lines lines) ===" -ForegroundColor Yellow
            Write-Host $stderrContent -ForegroundColor Yellow
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Host "Full log paths:" -ForegroundColor Gray
    Write-Host "  $StdoutLog" -ForegroundColor Gray
    Write-Host "  $StderrLog" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To follow logs in real-time:" -ForegroundColor Gray
    Write-Host "  Get-Content '$StdoutLog' -Wait -Tail 20" -ForegroundColor White
}

function Configure-ExistingService {
    Write-Header "Reconfigure Diretta Renderer Service"

    if (-not (Test-ServiceExists)) {
        Write-Err "Service '$ServiceName' is not installed."
        Write-Host "Run: .\Install-Service.ps1 -Install" -ForegroundColor Yellow
        return $false
    }

    if (-not (Test-NssmInstalled)) {
        Write-Err "NSSM not found. Cannot reconfigure."
        return $false
    }

    # Get current config
    $config = Get-ServiceConfig

    Write-Host "Current configuration:" -ForegroundColor Cyan
    Write-Host "  Target  : #$($config.Target)" -ForegroundColor Gray
    Write-Host "  Name    : $($config.Name)" -ForegroundColor Gray
    Write-Host "  Verbose : $($config.Verbose)" -ForegroundColor Gray
    Write-Host ""

    # Update with new values
    if ($Target -gt 0) { $config.Target = $Target }
    if ($Name) { $config.Name = $Name }
    if ($Verbose) { $config.Verbose = $true }

    # If no parameters, ask interactively
    if ($Target -eq 0 -and -not $Name -and -not $Verbose) {
        $inputTarget = Read-Host "Enter new target number [current: $($config.Target)]"
        if ($inputTarget -match "^\d+$") {
            $config.Target = [int]$inputTarget
        }

        $inputName = Read-Host "Enter new renderer name [current: $($config.Name)]"
        if ($inputName) {
            $config.Name = $inputName
        }

        $inputVerbose = Read-Host "Enable verbose logging? (y/n) [current: $($config.Verbose)]"
        if ($inputVerbose -match "^[Yy]") {
            $config.Verbose = $true
        }
        elseif ($inputVerbose -match "^[Nn]") {
            $config.Verbose = $false
        }
    }

    # Save configuration
    Save-ServiceConfig $config

    # Update NSSM arguments
    $rendererArgs = Get-RendererArguments $config
    Write-Info "Updating service arguments: $rendererArgs"

    Invoke-Nssm @("set", $ServiceName, "AppParameters", $rendererArgs) | Out-Null

    Write-Success "Service reconfigured"

    # Offer to restart
    $state = Get-ServiceState
    if ($state -eq "Running") {
        if (Confirm-Action "Restart service to apply changes?") {
            Restart-DirettaService
        }
    }

    return $true
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Determine action based on parameters
$action = $PSCmdlet.ParameterSetName

# Default to Install if no specific action
if ($action -eq "Install" -and -not $Install -and -not $Target -and -not $Name) {
    # No parameters at all - show menu
    Write-Header "Diretta Renderer Service Manager"

    Write-Host "  Usage:" -ForegroundColor Cyan
    Write-Host "    .\Install-Service.ps1 -Install     Install as Windows service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Uninstall   Remove service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Configure   Reconfigure service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Start       Start service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Stop        Stop service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Restart     Restart service" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Status      Show status" -ForegroundColor Gray
    Write-Host "    .\Install-Service.ps1 -Logs        View logs" -ForegroundColor Gray
    Write-Host ""

    Show-ServiceStatus

    exit 0
}

# Execute action
switch ($action) {
    "Install" {
        $result = Install-DirettaService
        Pause-Script
        exit $(if ($result) { 0 } else { 1 })
    }

    "Uninstall" {
        $result = Uninstall-DirettaService
        Pause-Script
        exit $(if ($result) { 0 } else { 1 })
    }

    "Configure" {
        $result = Configure-ExistingService
        Pause-Script
        exit $(if ($result) { 0 } else { 1 })
    }

    "Start" {
        $result = Start-DirettaService
        exit $(if ($result) { 0 } else { 1 })
    }

    "Stop" {
        $result = Stop-DirettaService
        exit $(if ($result) { 0 } else { 1 })
    }

    "Restart" {
        $result = Restart-DirettaService
        exit $(if ($result) { 0 } else { 1 })
    }

    "Status" {
        Show-ServiceStatus
        exit 0
    }

    "Logs" {
        Show-ServiceLogs
        exit 0
    }
}
