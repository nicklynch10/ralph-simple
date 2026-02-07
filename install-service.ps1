#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Windows Service Installer (NSSM)
# Version: 2.2.2
#
# REQUIREMENT: PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
#
# This script installs Ralph as a Windows Service using NSSM (Non-Sucking Service Manager)
# for true 24/7 operation that survives reboots and runs even when no user is logged in.
#
# Usage:
#   .\install-service.ps1 -Install          # Install the service
#   .\install-service.ps1 -Uninstall        # Remove the service
#   .\install-service.ps1 -Status           # Check service status
#   .\install-service.ps1 -Restart          # Restart the service
#
# Why NSSM instead of Task Scheduler?
#   - Runs as SYSTEM (before user login)
#   - Automatic restart on failure
#   - Proper service management (start/stop/restart)
#   - Logs to Windows Event Log
#   - More reliable for 24/7 operation

#requires -Version 5.1

param(
    [Parameter()]
    [switch]$Install,
    
    [Parameter()]
    [switch]$Uninstall,
    
    [Parameter()]
    [switch]$Status,
    
    [Parameter()]
    [switch]$Restart,
    
    [Parameter()]
    [string]$ServiceName = "RalphDaemon",
    
    [Parameter()]
    [string]$WorkspaceDir = (Get-Location),
    
    [Parameter()]
    [string]$NssmPath = "",
    
    [Parameter()]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RalphVersion = "2.2.2"
$script:DefaultNssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
$script:NssmDir = Join-Path $env:TEMP "nssm-2.24"

# ==============================================================================
# HELP
# ==============================================================================

if ($Help) {
    @"
Ralph Windows Service Installer v$script:RalphVersion

USAGE:
    .\install-service.ps1 [options]

OPTIONS:
    -Install          Install Ralph as a Windows Service
    -Uninstall        Remove the Ralph service
    -Status           Check service status
    -Restart          Restart the service
    -ServiceName      Service name (default: RalphDaemon)
    -WorkspaceDir     Project directory (default: current directory)
    -NssmPath         Path to nssm.exe (auto-downloaded if not specified)

EXAMPLES:
    # Install the service
    .\install-service.ps1 -Install

    # Check status
    .\install-service.ps1 -Status

    # Restart the service
    .\install-service.ps1 -Restart

    # Remove the service
    .\install-service.ps1 -Uninstall

REQUIREMENTS:
    - PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
    - Administrator privileges (for service installation)
    - NSSM (auto-downloaded if not found)

NOTES:
    This creates a true Windows Service that:
    - Starts automatically on boot
    - Runs as SYSTEM (no login required)
    - Restarts automatically on failure
    - Logs to Windows Event Log
"@ | Write-Host
    exit 0
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# ==============================================================================
# NSSM MANAGEMENT
# ==============================================================================

function Get-NssmPath {
    # If user specified a path, use it
    if ($NssmPath -and (Test-Path $NssmPath)) {
        return $NssmPath
    }
    
    # Check common locations
    $possiblePaths = @(
        "C:\nssm\nssm.exe",
        "C:\Program Files\nssm\nssm.exe",
        "C:\ProgramData\chocolatey\bin\nssm.exe",
        (Join-Path $script:NssmDir "win64\nssm.exe"),
        (Join-Path $script:NssmDir "win32\nssm.exe")
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

function Install-Nssm {
    Write-Status "NSSM not found. Downloading..." "WARN"
    
    $zipPath = Join-Path $env:TEMP "nssm.zip"
    
    try {
        # Download NSSM
        Invoke-WebRequest -Uri $script:DefaultNssmUrl -OutFile $zipPath -UseBasicParsing
        
        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
        
        # Find nssm.exe
        $nssmExe = Get-ChildItem -Path $env:TEMP -Recurse -Filter "nssm.exe" | Select-Object -First 1
        
        if ($nssmExe) {
            Write-Status "NSSM downloaded to: $($nssmExe.FullName)" "SUCCESS"
            return $nssmExe.FullName
        }
        else {
            throw "Could not find nssm.exe after extraction"
        }
    }
    catch {
        Write-Status "Failed to download NSSM: $_" "ERROR"
        Write-Status "Please download manually from https://nssm.cc/" "ERROR"
        exit 1
    }
}

# ==============================================================================
# SERVICE MANAGEMENT
# ==============================================================================

function Install-RalphService {
    param([string]$NssmExe)
    
    Write-Status "Installing Ralph Windows Service..." "INFO"
    
    # Check if service already exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Status "Service '$ServiceName' already exists. Removing first..." "WARN"
        & $NssmExe remove $ServiceName confirm
    }
    
    # Find ralph-daemon.ps1
    $daemonScript = Join-Path $WorkspaceDir "ralph-daemon.ps1"
    if (-not (Test-Path $daemonScript)) {
        Write-Status "ralph-daemon.ps1 not found at $daemonScript" "ERROR"
        exit 1
    }
    
    # Create log directories
    $logDir = Join-Path $WorkspaceDir ".ralph\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    
    # Install service (use powershell.exe for PS 5.1 compatibility)
    $arguments = @(
        "install",
        $ServiceName,
        "powershell.exe",
        "-NoProfile -ExecutionPolicy Bypass -File `"$daemonScript`""
    )
    
    & $NssmExe $arguments
    
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to install service" "ERROR"
        exit 1
    }
    
    # Configure service
    & $NssmExe set $ServiceName DisplayName "Ralph AI Agent Daemon"
    & $NssmExe set $ServiceName Description "24/7 autonomous AI agent for software development"
    & $NssmExe set $ServiceName Start SERVICE_AUTO_START
    & $NssmExe set $ServiceName AppDirectory $WorkspaceDir
    & $NssmExe set $ServiceName AppStdout (Join-Path $logDir "service-stdout.log")
    & $NssmExe set $ServiceName AppStderr (Join-Path $logDir "service-stderr.log")
    & $NssmExe set $ServiceName AppRotateFiles 1
    & $NssmExe set $ServiceName AppRotateBytes 10485760  # 10MB
    
    # Restart settings
    & $NssmExe set $ServiceName AppExit Default Restart
    & $NssmExe set $ServiceName AppRestartDelay 10000  # 10 seconds
    
    Write-Status "Service installed successfully!" "SUCCESS"
    Write-Status "Starting service..." "INFO"
    
    Start-Service -Name $ServiceName
    
    Write-Status "Service started!" "SUCCESS"
    Write-Status ""
    Write-Status "Useful commands:" "INFO"
    Write-Host "  Get-Service $ServiceName"
    Write-Host "  Stop-Service $ServiceName"
    Write-Host "  Start-Service $ServiceName"
    Write-Host "  Restart-Service $ServiceName"
    Write-Host "  & '$NssmExe' edit $ServiceName"
}

function Uninstall-RalphService {
    param([string]$NssmExe)
    
    Write-Status "Uninstalling Ralph Windows Service..." "INFO"
    
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existingService) {
        Write-Status "Service '$ServiceName' not found" "WARN"
        return
    }
    
    # Stop service first
    if ($existingService.Status -eq "Running") {
        Write-Status "Stopping service..." "INFO"
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }
    
    # Remove service
    & $NssmExe remove $ServiceName confirm
    
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Service uninstalled successfully!" "SUCCESS"
    }
    else {
        Write-Status "Failed to uninstall service" "ERROR"
    }
}

function Get-RalphServiceStatus {
    param([string]$NssmExe)
    
    Write-Status "Ralph Service Status" "INFO"
    Write-Host ""
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if ($service) {
        Write-Host "  Service Name: $ServiceName" -ForegroundColor Cyan
        Write-Host "  Status: $($service.Status)" -ForegroundColor $(
            if ($service.Status -eq "Running") { "Green" } else { "Yellow" }
        )
        Write-Host "  Start Type: $($service.StartType)" -ForegroundColor White
        
        # Get process info if running
        if ($service.Status -eq "Running") {
            $process = Get-CimInstance Win32_Service -Filter "Name = '$ServiceName'" | 
                Select-Object -ExpandProperty ProcessId
            if ($process -and $process -ne 0) {
                Write-Host "  Process ID: $process" -ForegroundColor White
            }
        }
        
        Write-Host ""
        Write-Status "Recent log entries:" "INFO"
        $logFile = Join-Path $WorkspaceDir ".ralph\logs\service-stdout.log"
        if (Test-Path $logFile) {
            Get-Content $logFile -Tail 10 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "    (no log file)" -ForegroundColor Gray
        }
    }
    else {
        Write-Status "Service '$ServiceName' not installed" "WARN"
    }
}

function Restart-RalphService {
    param([string]$NssmExe)
    
    Write-Status "Restarting Ralph Service..." "INFO"
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Status "Service '$ServiceName' not found" "ERROR"
        return
    }
    
    Restart-Service -Name $ServiceName -Force
    Write-Status "Service restarted!" "SUCCESS"
}

# ==============================================================================
# MAIN
# ==============================================================================

Write-Host ""
Write-Host "Ralph Windows Service Manager v$script:RalphVersion" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Check admin privileges
if (-not (Test-Admin)) {
    Write-Status "Administrator privileges required for service management" "ERROR"
    Write-Status "Please run PowerShell as Administrator" "ERROR"
    exit 1
}

# Get NSSM
$nssmExe = Get-NssmPath
if (-not $nssmExe) {
    $nssmExe = Install-Nssm
}

Write-Status "Using NSSM: $nssmExe" "INFO"

# Execute command
if ($Install) {
    Install-RalphService -NssmExe $nssmExe
}
elseif ($Uninstall) {
    Uninstall-RalphService -NssmExe $nssmExe
}
elseif ($Status) {
    Get-RalphServiceStatus -NssmExe $nssmExe
}
elseif ($Restart) {
    Restart-RalphService -NssmExe $nssmExe
}
else {
    Write-Status "No action specified. Use -Install, -Uninstall, -Status, or -Restart" "WARN"
    Write-Status "Use -Help for more information" "INFO"
}

Write-Host ""
