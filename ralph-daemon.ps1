#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Production Daemon
# Version: 2.1.0 - 24/7 Autonomous CI/CD Agent
#
# REQUIREMENT: PowerShell 7.0+ (Install: winget install Microsoft.PowerShell)
#
# This daemon provides 24/7 autonomous operation with:
# - Process isolation (each bead runs in separate process)
# - Automatic restart on failure
# - Stuck bead detection and recovery
# - Log rotation
# - Health monitoring
#
# Usage:
#   # Run in foreground (for testing)
#   .\ralph-daemon.ps1
#
#   # Run as background job
#   Start-Process powershell -ArgumentList "-File .\ralph-daemon.ps1" -WindowStyle Hidden
#
#   # Install as scheduled task (runs on boot)
#   .\ralph-daemon.ps1 -InstallTask
#
#requires -Version 7.0

param(
    [Parameter()]
    [switch]$InstallTask,
    
    [Parameter()]
    [switch]$UninstallTask,
    
    [Parameter()]
    [switch]$Status,
    
    [Parameter()]
    [int]$PollIntervalSeconds = 30,
    
    [Parameter()]
    [int]$BeadTimeoutMinutes = 120,
    
    [Parameter()]
    [string]$WorkspaceDir = (Get-Location),
    
    [Parameter()]
    [string]$RalphScript = "ralph.ps1"
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:DaemonVersion = "2.1.0"
$script:DaemonName = "RalphDaemon"
$script:TaskName = "RalphHostDaemon"

# Paths
$script:ConfigDir = Join-Path $WorkspaceDir ".ralph"
$script:LogDir = Join-Path $script:ConfigDir "logs"
$script:BeadsDir = Join-Path $script:ConfigDir "beads"
$script:PidFile = Join-Path $script:ConfigDir "daemon.pid"
$script:DaemonLog = Join-Path $script:LogDir "ralph-daemon.log"

# Default configuration
$script:Config = @{
    PollIntervalSeconds = $PollIntervalSeconds
    BeadTimeoutMinutes = $BeadTimeoutMinutes
    MaxLogSizeMB = 10
    MaxLogFiles = 5
    RestartOnFailure = $true
    MaxRetries = 3
}

# Import core module
$coreScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ralph-core.ps1"
if (Test-Path $coreScript) {
    . $coreScript
}

# ==============================================================================
# LOGGING SYSTEM (with rotation)
# ==============================================================================

function Write-DaemonLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors (only in foreground)
    if (-not $script:RunningAsService) {
        switch ($Level) {
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
            "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
            default { Write-Host $logEntry }
        }
    }
    
    # Ensure log directory exists
    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    }
    
    # Write to log file
    try {
        $logEntry | Out-File -FilePath $script:DaemonLog -Append -Encoding UTF8
        
        # Check log rotation
        Invoke-LogRotation
    }
    catch {
        # Silently fail
    }
}

function Invoke-LogRotation {
    try {
        $logFile = Get-Item $script:DaemonLog -ErrorAction SilentlyContinue
        if (-not $logFile) { return }
        
        $maxSize = $script:Config.MaxLogSizeMB * 1MB
        
        if ($logFile.Length -gt $maxSize) {
            Write-DaemonLog "Rotating log file..." -Level "DEBUG"
            
            # Rotate existing log files
            for ($i = $script:Config.MaxLogFiles - 1; $i -ge 1; $i--) {
                $oldFile = "$script:DaemonLog.$i"
                $newFile = "$script:DaemonLog.$($i + 1)"
                
                if (Test-Path $oldFile) {
                    if ($i -eq $script:Config.MaxLogFiles - 1) {
                        Remove-Item $oldFile -Force
                    }
                    else {
                        Move-Item $oldFile $newFile -Force
                    }
                }
            }
            
            # Move current log
            Move-Item $script:DaemonLog "$script:DaemonLog.1" -Force
        }
    }
    catch {
        Write-DaemonLog "Log rotation failed: $_" -Level "WARN"
    }
}

# ==============================================================================
# BEAD MANAGEMENT
# ==============================================================================

<#
.SYNOPSIS
    Loads a bead file with proper UTF-8 BOM handling.
.DESCRIPTION
    Handles both BOM and non-BOM JSON files correctly.
#>
function Get-Bead {
    param([string]$BeadId)
    
    $beadFile = Join-Path $script:BeadsDir "$BeadId.json"
    
    if (-not (Test-Path $beadFile)) {
        return $null
    }
    
    try {
        $content = Get-Content -Path $beadFile -Raw -Encoding UTF8
        
        # Remove BOM if present (0xEF 0xBB 0xBF = `ufeff)
        if ($content.Length -gt 0 -and $content[0] -eq "`ufeff") {
            $content = $content.Substring(1)
        }
        
        return $content | ConvertFrom-Json
    }
    catch {
        Write-DaemonLog "Error reading bead $BeadId`: $_" -Level "ERROR"
        return $null
    }
}

<#
.SYNOPSIS
    Saves a bead file with proper encoding (no BOM).
.DESCRIPTION
    Ensures all required fields exist and writes UTF-8 without BOM.
#>
function Save-Bead {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Bead
    )
    
    try {
        $beadFile = Join-Path $script:BeadsDir "$($Bead.id).json"
        
        if (-not (Test-Path $script:BeadsDir)) {
            New-Item -ItemType Directory -Force -Path $script:BeadsDir | Out-Null
        }
        
        # Ensure metadata exists
        if (-not $Bead.ralph_meta) {
            $Bead | Add-Member -NotePropertyName "ralph_meta" -NotePropertyValue @{} -Force
        }
        
        # Ensure updated_at exists
        if (-not ($Bead.PSObject.Properties.Name -contains "updated_at")) {
            $Bead | Add-Member -NotePropertyName "updated_at" -NotePropertyValue (Get-Date -Format "o") -Force
        }
        else {
            $Bead.updated_at = Get-Date -Format "o"
        }
        
        $Bead.ralph_meta.last_updated = Get-Date -Format "o"
        
        # Write with UTF8 no BOM
        $json = $Bead | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($beadFile, $json, [System.Text.UTF8Encoding]::new($false))
        
        return $true
    }
    catch {
        Write-DaemonLog "Error saving bead: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Gets all pending beads.
.DESCRIPTION
    Returns beads with status "pending" or "retry", sorted by priority.
#>
function Get-PendingBeads {
    if (-not (Test-Path $script:BeadsDir)) {
        return @()
    }
    
    $beadFiles = Get-ChildItem -Path $script:BeadsDir -Filter "*.json" -ErrorAction SilentlyContinue
    $pendingBeads = @()
    
    foreach ($file in $beadFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            
            # Remove BOM if present
            if ($content.Length -gt 0 -and $content[0] -eq "`ufeff") {
                $content = $content.Substring(1)
            }
            
            $bead = $content | ConvertFrom-Json
            
            if ($bead.status -eq "pending" -or $bead.status -eq "retry") {
                $pendingBeads += $bead
            }
        }
        catch {
            Write-DaemonLog "Error parsing bead file $($file.Name): $_" -Level "WARN"
        }
    }
    
    # Sort by priority (default to 999 if not set)
    return $pendingBeads | Sort-Object -Property { 
        if ($_.priority) { $_.priority } else { 999 } 
    }
}

<#
.SYNOPSIS
    Detects and resets stuck beads.
.DESCRIPTION
    Finds beads that have been in_progress for longer than the threshold
    and resets them to retry status.
#>
function Reset-StuckBeads {
    if (-not (Test-Path $script:BeadsDir)) {
        return 0
    }
    
    $resetCount = 0
    $beadFiles = Get-ChildItem -Path $script:BeadsDir -Filter "*.json" -ErrorAction SilentlyContinue
    $thresholdHours = $script:Config.BeadTimeoutMinutes / 60
    
    foreach ($file in $beadFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            
            # Remove BOM if present
            if ($content.Length -gt 0 -and $content[0] -eq "`ufeff") {
                $content = $content.Substring(1)
            }
            
            $bead = $content | ConvertFrom-Json
            
            if ($bead.status -eq "in_progress" -and $bead.ralph_meta.last_attempt) {
                $lastAttempt = [datetime]$bead.ralph_meta.last_attempt
                $hoursSince = ((Get-Date) - $lastAttempt).TotalHours
                
                if ($hoursSince -gt $thresholdHours) {
                    Write-DaemonLog "Resetting stuck bead: $($bead.id) (${hoursSince:.1f}h old)" -Level "WARN"
                    
                    $bead.status = "retry"
                    
                    # Ensure stuck_count exists
                    if (-not $bead.ralph_meta.stuck_count) {
                        $bead.ralph_meta.stuck_count = 0
                    }
                    $bead.ralph_meta.stuck_count++
                    $bead.ralph_meta.reset_reason = "Stuck for ${hoursSince:.1f} hours"
                    
                    Save-Bead -Bead $bead
                    $resetCount++
                }
            }
        }
        catch {
            Write-DaemonLog "Error checking bead $($file.Name): $_" -Level "WARN"
        }
    }
    
    return $resetCount
}

# ==============================================================================
# BEAD EXECUTION (Process Isolation)
# ==============================================================================

<#
.SYNOPSIS
    Executes a single bead with process isolation and timeout.
.DESCRIPTION
    This is the core execution function that:
    1. Spawns ralph.ps1 in a separate process (powershell, NOT pwsh)
    2. Enforces a hard timeout (default 2 hours)
    3. Captures all output to log files
    4. Updates bead status based on result
    
    Process isolation prevents:
    - Memory leaks from accumulating Kimi CLI instances
    - File handle exhaustion
    - Cascading failures from one corrupt bead
#>
function Invoke-Bead {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Bead
    )
    
    $beadId = $Bead.id
    Write-DaemonLog "Starting bead: $beadId" -Level "INFO"
    
    # Update status to in_progress
    $Bead.status = "in_progress"
    
    # Ensure ralph_meta exists
    if (-not $Bead.ralph_meta) {
        $Bead | Add-Member -NotePropertyName "ralph_meta" -NotePropertyValue @{} -Force
    }
    
    $Bead.ralph_meta.last_attempt = Get-Date -Format "o"
    
    # Ensure attempt_count exists
    if (-not $Bead.ralph_meta.attempt_count) {
        $Bead.ralph_meta.attempt_count = 0
    }
    $Bead.ralph_meta.attempt_count++
    
    Save-Bead -Bead $Bead
    
    # Create log files for this bead
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputLog = Join-Path $script:LogDir "bead-$beadId-$timestamp.log"
    $errorLog = "$outputLog.err"
    
    $ralphPath = Join-Path $WorkspaceDir $RalphScript
    
    # Verify ralph script exists
    if (-not (Test-Path $ralphPath)) {
        Write-DaemonLog "Ralph script not found at $ralphPath" -Level "ERROR"
        $Bead.status = "failed"
        $Bead.ralph_meta.last_error = "Ralph script not found"
        Save-Bead -Bead $Bead
        return $false
    }
    
    $process = $null
    
    try {
        # Start process with full isolation
        # Use pwsh (PowerShell 7) for consistency
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "pwsh.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ralphPath`" -MaxIterations 1"
        $psi.WorkingDirectory = $WorkspaceDir
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        $psi.UseShellExecute = $true  # Must be true for WindowStyle to work
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        
        # Start the process
        $process = [System.Diagnostics.Process]::Start($psi)
        
        Write-DaemonLog "Bead $beadId started (PID: $($process.Id))" -Level "DEBUG"
        
        # Wait with timeout (default 2 hours = 7200000 ms)
        $timeoutMs = $script:Config.BeadTimeoutMinutes * 60 * 1000
        $completed = $process.WaitForExit($timeoutMs)
        
        if (-not $completed) {
            Write-DaemonLog "TIMEOUT ($($script:Config.BeadTimeoutMinutes)m): $beadId - killing process" -Level "ERROR"
            
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
            catch {
                Write-DaemonLog "Failed to kill process: $_" -Level "WARN"
            }
            
            $Bead.status = "retry"
            
            # Ensure timeout_count exists
            if (-not $Bead.ralph_meta.timeout_count) {
                $Bead.ralph_meta.timeout_count = 0
            }
            $Bead.ralph_meta.timeout_count++
            Save-Bead -Bead $Bead
            
            return $false
        }
        
        # Check exit code
        $exitCode = $process.ExitCode
        Write-DaemonLog "Bead $beadId completed with exit code: $exitCode" -Level "DEBUG"
        
        # Re-read bead to get updated status
        $updatedBead = Get-Bead -BeadId $beadId
        
        if ($updatedBead) {
            if ($updatedBead.status -eq "completed") {
                Write-DaemonLog "Bead $beadId completed successfully" -Level "SUCCESS"
                return $true
            }
            else {
                # Check retry count
                $retryCount = $updatedBead.ralph_meta.attempt_count
                if (-not $retryCount) { $retryCount = 0 }
                
                if ($retryCount -ge $script:Config.MaxRetries) {
                    Write-DaemonLog "Bead $beadId failed after $retryCount attempts" -Level "ERROR"
                    $updatedBead.status = "failed"
                    Save-Bead -Bead $updatedBead
                }
                else {
                    Write-DaemonLog "Bead $beadId will retry (attempt $retryCount/$($script:Config.MaxRetries))" -Level "WARN"
                    $updatedBead.status = "retry"
                    Save-Bead -Bead $updatedBead
                }
                
                return $false
            }
        }
        else {
            Write-DaemonLog "Could not read updated bead status for $beadId" -Level "WARN"
            return $false
        }
    }
    catch {
        Write-DaemonLog "Exception executing bead $beadId`: $_" -Level "ERROR"
        
        $Bead.status = "retry"
        $Bead.ralph_meta.last_error = $_.Exception.Message
        Save-Bead -Bead $Bead
        
        return $false
    }
    finally {
        if ($process -and -not $process.HasExited) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }
}

# ==============================================================================
# DAEMON LOOP
# ==============================================================================

<#
.SYNOPSIS
    Main daemon loop.
.DESCRIPTION
    Continuously polls for pending beads and executes them with proper
    error handling and recovery.
#>
function Start-DaemonLoop {
    Write-DaemonLog "Ralph Daemon v$script:DaemonVersion starting..." -Level "INFO"
    Write-DaemonLog "Workspace: $WorkspaceDir" -Level "INFO"
    Write-DaemonLog "Poll interval: $($script:Config.PollIntervalSeconds)s" -Level "INFO"
    Write-DaemonLog "Bead timeout: $($script:Config.BeadTimeoutMinutes)m" -Level "INFO"
    
    # Create necessary directories
    @($script:ConfigDir, $script:LogDir, $script:BeadsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Force -Path $_ | Out-Null
        }
    }
    
    # Write PID file
    $PID | Set-Content -Path $script:PidFile -Encoding UTF8 -Force
    
    # Set up Ctrl+C handler (using Console event, NOT trap)
    $cancelRequested = $false
    $cancelHandler = {
        param([object]$sender, [System.ConsoleCancelEventArgs]$e)
        $e.Cancel = $true
        $cancelRequested = $true
        Write-DaemonLog "Shutdown requested" -Level "WARN"
    }
    [Console]::add_CancelKeyPress($cancelHandler)
    
    $iteration = 0
    $consecutiveErrors = 0
    $maxConsecutiveErrors = 5
    
    while (-not $cancelRequested) {
        $iteration++
        
        try {
            # Reset stuck beads
            $resetCount = Reset-StuckBeads
            if ($resetCount -gt 0) {
                Write-DaemonLog "Reset $resetCount stuck beads" -Level "WARN"
            }
            
            # Get pending beads
            $pendingBeads = Get-PendingBeads
            
            if ($pendingBeads.Count -eq 0) {
                if ($iteration % 10 -eq 0) {
                    Write-DaemonLog "No pending beads. Waiting..." -Level "DEBUG"
                }
            }
            else {
                Write-DaemonLog "Found $($pendingBeads.Count) pending bead(s)" -Level "INFO"
                
                # Process each pending bead
                foreach ($bead in $pendingBeads) {
                    if ($cancelRequested) { break }
                    
                    $result = Invoke-Bead -Bead $bead
                    
                    # Small delay between beads
                    if (-not $cancelRequested) {
                        Start-Sleep -Seconds 2
                    }
                }
            }
            
            # Reset error counter on success
            $consecutiveErrors = 0
        }
        catch {
            $consecutiveErrors++
            Write-DaemonLog "Error in daemon loop: $_" -Level "ERROR"
            
            if ($consecutiveErrors -ge $maxConsecutiveErrors) {
                Write-DaemonLog "Too many consecutive errors ($consecutiveErrors). Stopping daemon." -Level "ERROR"
                break
            }
        }
        
        # Wait for next poll
        $sleepSeconds = $script:Config.PollIntervalSeconds
        while ($sleepSeconds -gt 0 -and -not $cancelRequested) {
            Start-Sleep -Seconds 1
            $sleepSeconds--
        }
    }
    
    # Cleanup
    Write-DaemonLog "Daemon shutting down..." -Level "INFO"
    
    if (Test-Path $script:PidFile) {
        Remove-Item $script:PidFile -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# WINDOWS TASK SCHEDULER INTEGRATION
# ==============================================================================

function Install-DaemonTask {
    Write-Host "Installing Ralph Daemon as scheduled task..." -ForegroundColor Cyan
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -File `"$PSCommandPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    
    try {
        Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        Write-Host "Task installed successfully!" -ForegroundColor Green
        Write-Host "The daemon will start automatically when you log in." -ForegroundColor Green
        Write-Host "To start now: Start-ScheduledTask -TaskName '$script:TaskName'" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to install task: $_"
    }
}

function Uninstall-DaemonTask {
    Write-Host "Uninstalling Ralph Daemon scheduled task..." -ForegroundColor Cyan
    
    try {
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Task uninstalled successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to uninstall task: $_"
    }
}

function Get-DaemonStatus {
    Write-Host ""
    Write-Host "Ralph Daemon Status" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if daemon is running
    $pidFile = Join-Path $WorkspaceDir ".ralph\daemon.pid"
    $isRunning = $false
    $processId = $null
    
    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        try {
            $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            if ($process) {
                $isRunning = $true
                $processId = $savedPid
            }
        }
        catch { }
    }
    
    if ($isRunning) {
        Write-Host "Status: " -NoNewline
        Write-Host "RUNNING" -ForegroundColor Green
        Write-Host "Process ID: $processId"
        Write-Host "Workspace: $WorkspaceDir"
    }
    else {
        Write-Host "Status: " -NoNewline
        Write-Host "STOPPED" -ForegroundColor Red
    }
    
    # Check scheduled task
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Scheduled Task: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
    }
    else {
        Write-Host "Scheduled Task: Not installed" -ForegroundColor Gray
    }
    
    # Show recent log entries
    $logFile = Join-Path $WorkspaceDir ".ralph\logs\ralph-daemon.log"
    if (Test-Path $logFile) {
        Write-Host ""
        Write-Host "Recent Log Entries:" -ForegroundColor Cyan
        Get-Content $logFile -Tail 10 | ForEach-Object {
            Write-Host "  $_"
        }
    }
    
    # Show pending beads count
    $beadsDir = Join-Path $WorkspaceDir ".ralph\beads"
    if (Test-Path $beadsDir) {
        $pendingCount = (Get-ChildItem $beadsDir -Filter "*.json" -ErrorAction SilentlyContinue | Where-Object {
            $content = Get-Content $_.FullName -Raw -Encoding UTF8
            if ($content.Length -gt 0 -and $content[0] -eq "`ufeff") { $content = $content.Substring(1) }
            $bead = $content | ConvertFrom-Json
            $bead.status -eq "pending" -or $bead.status -eq "retry"
        }).Count
        
        Write-Host ""
        Write-Host "Pending Beads: $pendingCount" -ForegroundColor $(if ($pendingCount -gt 0) { "Yellow" } else { "Green" })
    }
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

if ($InstallTask) {
    Install-DaemonTask
    exit 0
}

if ($UninstallTask) {
    Uninstall-DaemonTask
    exit 0
}

if ($Status) {
    Get-DaemonStatus
    exit 0
}

# Run daemon
Start-DaemonLoop
