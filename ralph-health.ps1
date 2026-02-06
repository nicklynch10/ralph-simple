#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Health Check and Diagnostics
# Version: 2.1.0
#
# REQUIREMENT: PowerShell 7.0+ (Install: winget install Microsoft.PowerShell)
#
# Usage:
#   .\ralph-health.ps1                    # Full health check
#   .\ralph-health.ps1 -Quick             # Quick status only
#   .\ralph-health.ps1 -Fix               # Attempt auto-fixes
#   .\ralph-health.ps1 -Beads             # Check bead status
#   .\ralph-health.ps1 -Logs              # Show recent logs
#   .\ralph-health.ps1 -ResetStuck        # Reset stuck beads

#requires -Version 7.0

param(
    [Parameter()]
    [switch]$Quick,
    
    [Parameter()]
    [switch]$Fix,
    
    [Parameter()]
    [switch]$Beads,
    
    [Parameter()]
    [switch]$Logs,
    
    [Parameter()]
    [switch]$ResetStuck,
    
    [Parameter()]
    [string]$WorkspaceDir = (Get-Location)
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RalphVersion = "2.2.2"
$script:ConfigDir = Join-Path $WorkspaceDir ".ralph"
$script:LogDir = Join-Path $script:ConfigDir "logs"
$script:BeadsDir = Join-Path $script:ConfigDir "beads"

# ==============================================================================
# OUTPUT HELPERS
# ==============================================================================

function Write-Status {
    param(
        [string]$Label,
        [string]$Status,
        [string]$Color = "White",
        [string]$Details = ""
    )
    
    Write-Host "  $Label`: " -NoNewline
    Write-Host $Status -ForegroundColor $Color -NoNewline
    if ($Details) {
        Write-Host " - $Details" -ForegroundColor Gray
    }
    else {
        Write-Host ""
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $([string]'=' * $Title.Length)" -ForegroundColor Cyan
}

# ==============================================================================
# CHECK FUNCTIONS
# ==============================================================================

function Test-Prerequisites {
    Write-Section "Prerequisites"
    
    $results = @{
        Kimi = $false
        Git = $false
        PowerShell = $false
    }
    
    # Check Kimi CLI
    $kimi = Get-Command kimi -ErrorAction SilentlyContinue
    if ($kimi) {
        try {
            $version = kimi --version 2>&1
            Write-Status "Kimi CLI" "OK" "Green" $version
            $results.Kimi = $true
        }
        catch {
            Write-Status "Kimi CLI" "ERROR" "Red" "Cannot get version"
        }
    }
    else {
        Write-Status "Kimi CLI" "NOT FOUND" "Red" "Install from https://github.com/moonshotai/kimi-cli"
    }
    
    # Check Git
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $version = git --version 2>&1
            Write-Status "Git" "OK" "Green" $version
            $results.Git = $true
        }
        catch {
            Write-Status "Git" "ERROR" "Red" "Cannot get version"
        }
    }
    else {
        Write-Status "Git" "NOT FOUND" "Red" "Install from https://git-scm.com"
    }
    
    # Check PowerShell version (7.0+ required)
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 7) {
        Write-Status "PowerShell" "OK" "Green" "Version $psVersion"
        $results.PowerShell = $true
    }
    else {
        Write-Status "PowerShell" "ERROR" "Red" "Version $psVersion (7.0+ required - Install: winget install Microsoft.PowerShell)"
    }
    
    return $results.Kimi -and $results.Git -and $results.PowerShell
}

function Test-Configuration {
    Write-Section "Configuration"
    
    $results = @{
        PrdFile = $false
        PromptFile = $false
        GitRepo = $false
    }
    
    # Check PRD file
    $prdPath = Join-Path $WorkspaceDir "prd.json"
    if (Test-Path $prdPath) {
        try {
            $content = Get-Content -Path $prdPath -Raw -Encoding UTF8
            if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") { $content = $content.Substring(1) }
            $prd = $content | ConvertFrom-Json
            
            $storyCount = ($prd.userStories | Measure-Object).Count
            $completedCount = ($prd.userStories | Where-Object { $_.passes -eq $true } | Measure-Object).Count
            
            Write-Status "PRD File" "OK" "Green" "$completedCount/$storyCount stories complete"
            $results.PrdFile = $true
        }
        catch {
            Write-Status "PRD File" "ERROR" "Red" "Invalid JSON: $_"
        }
    }
    else {
        Write-Status "PRD File" "NOT FOUND" "Red" "Expected at $prdPath"
    }
    
    # Check prompt file
    $promptPath = Join-Path $WorkspaceDir "KIMI.md"
    if (Test-Path $promptPath) {
        $size = (Get-Item $promptPath).Length
        Write-Status "Prompt File" "OK" "Green" "$size bytes"
        $results.PromptFile = $true
    }
    else {
        Write-Status "Prompt File" "NOT FOUND" "Red" "Expected at $promptPath"
    }
    
    # Check git repository
    $gitDir = Join-Path $WorkspaceDir ".git"
    if (Test-Path $gitDir) {
        try {
            $branch = git -C $WorkspaceDir branch --show-current 2>&1
            $status = git -C $WorkspaceDir status --porcelain 2>&1
            $statusText = if ($status) { "uncommitted changes" } else { "clean" }
            Write-Status "Git Repository" "OK" "Green" "Branch: $branch, $statusText"
            $results.GitRepo = $true
        }
        catch {
            Write-Status "Git Repository" "ERROR" "Red" "Git check failed"
        }
    }
    else {
        Write-Status "Git Repository" "NOT FOUND" "Yellow" "Not a git repository"
    }
    
    return $results
}

function Test-Daemon {
    Write-Section "Daemon Status"
    
    $pidFile = Join-Path $script:ConfigDir "daemon.pid"
    $isRunning = $false
    
    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        try {
            $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
            if ($process) {
                $isRunning = $true
                Write-Status "Daemon Process" "RUNNING" "Green" "PID: $savedPid"
            }
            else {
                Write-Status "Daemon Process" "STOPPED" "Red" "PID file exists but process not found"
            }
        }
        catch {
            Write-Status "Daemon Process" "STOPPED" "Red" "PID file exists but process not found"
        }
    }
    else {
        Write-Status "Daemon Process" "NOT RUNNING" "Yellow" "No PID file found"
    }
    
    # Check scheduled task
    $task = Get-ScheduledTask -TaskName "RalphHostDaemon" -ErrorAction SilentlyContinue
    if ($task) {
        Write-Status "Scheduled Task" $task.State "$(if ($task.State -eq 'Ready') { 'Green' } else { 'Yellow' })"
    }
    else {
        Write-Status "Scheduled Task" "NOT INSTALLED" "Gray"
    }
    
    return $isRunning
}

function Test-Beads {
    Write-Section "Bead Status"
    
    if (-not (Test-Path $script:BeadsDir)) {
        Write-Status "Beads Directory" "NOT FOUND" "Yellow" "No beads created yet"
        return @{
            Total = 0
            Pending = 0
            InProgress = 0
            Completed = 0
            Failed = 0
            Stuck = 0
        }
    }
    
    $beadFiles = Get-ChildItem -Path $script:BeadsDir -Filter "*.json" -ErrorAction SilentlyContinue
    
    if ($beadFiles.Count -eq 0) {
        Write-Status "Beads" "NONE" "Yellow" "No bead files found"
        return @{
            Total = 0
            Pending = 0
            InProgress = 0
            Completed = 0
            Failed = 0
            Stuck = 0
        }
    }
    
    $stats = @{
        Total = 0
        Pending = 0
        InProgress = 0
        Completed = 0
        Failed = 0
        Stuck = 0
    }
    
    $stuckBeads = @()
    
    foreach ($file in $beadFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") { $content = $content.Substring(1) }
            $bead = $content | ConvertFrom-Json
            
            $stats.Total++
            
            switch ($bead.status) {
                "pending" { $stats.Pending++ }
                "in_progress" { 
                    $stats.InProgress++
                    
                    # Check if stuck
                    if ($bead.ralph_meta.last_attempt) {
                        $lastAttempt = [datetime]$bead.ralph_meta.last_attempt
                        $hoursSince = ((Get-Date) - $lastAttempt).TotalHours
                        if ($hoursSince -gt 2) {
                            $stats.Stuck++
                            $stuckBeads += "$($bead.id) (${hoursSince:.1f}h)"
                        }
                    }
                }
                "completed" { $stats.Completed++ }
                "failed" { $stats.Failed++ }
                "retry" { $stats.Pending++ }
                default { $stats.Pending++ }
            }
        }
        catch {
            Write-Status "Bead $($file.Name)" "ERROR" "Red" "Cannot parse JSON"
        }
    }
    
    Write-Status "Total Beads" $stats.Total "White"
    Write-Status "  Pending" $stats.Pending $(if ($stats.Pending -gt 0) { "Yellow" } else { "Green" })
    Write-Status "  In Progress" $stats.InProgress $(if ($stats.InProgress -gt 0) { "Yellow" } else { "Green" })
    Write-Status "  Completed" $stats.Completed $(if ($stats.Completed -gt 0) { "Green" } else { "Gray" })
    Write-Status "  Failed" $stats.Failed $(if ($stats.Failed -gt 0) { "Red" } else { "Green" })
    
    if ($stats.Stuck -gt 0) {
        Write-Status "  Stuck (>2h)" $stats.Stuck "Red"
        foreach ($stuck in $stuckBeads) {
            Write-Host "      - $stuck" -ForegroundColor Red
        }
    }
    
    return $stats
}

function Test-Logs {
    Write-Section "Recent Logs"
    
    $logFile = Join-Path $script:LogDir "ralph-daemon.log"
    
    if (Test-Path $logFile) {
        $entries = Get-Content $logFile -Tail 20 -ErrorAction SilentlyContinue
        if ($entries) {
            $entries | ForEach-Object {
                # Color code log entries
                if ($_ -match "\[ERROR\]") {
                    Write-Host "    $_" -ForegroundColor Red
                }
                elseif ($_ -match "\[WARN\]") {
                    Write-Host "    $_" -ForegroundColor Yellow
                }
                elseif ($_ -match "\[SUCCESS\]") {
                    Write-Host "    $_" -ForegroundColor Green
                }
                else {
                    Write-Host "    $_" -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Host "    (empty log file)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "    (no log file found)" -ForegroundColor Gray
    }
}

# ==============================================================================
# FIX FUNCTIONS
# ==============================================================================

function Repair-StuckBeads {
    param([int]$ThresholdHours = 2)
    
    Write-Section "Resetting Stuck Beads"
    
    if (-not (Test-Path $script:BeadsDir)) {
        Write-Status "Beads Directory" "NOT FOUND" "Yellow"
        return 0
    }
    
    $resetCount = 0
    $beadFiles = Get-ChildItem -Path $script:BeadsDir -Filter "*.json" -ErrorAction SilentlyContinue
    
    foreach ($file in $beadFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") { $content = $content.Substring(1) }
            $bead = $content | ConvertFrom-Json
            
            if ($bead.status -eq "in_progress" -and $bead.ralph_meta.last_attempt) {
                $lastAttempt = [datetime]$bead.ralph_meta.last_attempt
                $hoursSince = ((Get-Date) - $lastAttempt).TotalHours
                
                if ($hoursSince -gt $ThresholdHours) {
                    Write-Host "  Resetting $($bead.id) (stuck for ${hoursSince:.1f}h)" -ForegroundColor Yellow
                    
                    $bead.status = "retry"
                    if (-not $bead.ralph_meta.stuck_count) { $bead.ralph_meta.stuck_count = 0 }
                    $bead.ralph_meta.stuck_count++
                    $bead.ralph_meta.reset_reason = "Stuck for ${hoursSince:.1f} hours"
                    $bead.ralph_meta.reset_at = Get-Date -Format "o"
                    
                    $json = $bead | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($file.FullName, $json, [System.Text.UTF8Encoding]::new($false))
                    
                    $resetCount++
                }
            }
        }
        catch {
            Write-Status "Bead $($file.Name)" "ERROR" "Red" "Cannot process"
        }
    }
    
    if ($resetCount -eq 0) {
        Write-Status "Result" "No stuck beads found" "Green"
    }
    else {
        Write-Status "Result" "Reset $resetCount stuck bead(s)" "Green"
    }
    
    return $resetCount
}

function Repair-OrphanedPidFile {
    $pidFile = Join-Path $script:ConfigDir "daemon.pid"
    
    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
        
        if (-not $process) {
            Write-Section "Cleaning Up Orphaned PID File"
            Remove-Item $pidFile -Force
            Write-Status "PID File" "REMOVED" "Green" "Process no longer exists"
        }
    }
}

function Repair-DirectoryStructure {
    Write-Section "Ensuring Directory Structure"
    
    @($script:ConfigDir, $script:LogDir, $script:BeadsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Force -Path $_ | Out-Null
            Write-Status "Directory $_" "CREATED" "Green"
        }
        else {
            Write-Status "Directory $_" "OK" "Green"
        }
    }
}

# ==============================================================================
# MAIN
# ==============================================================================

Write-Host ""
Write-Host "Ralph Health Check v$script:RalphVersion" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Workspace: $WorkspaceDir" -ForegroundColor Gray
Write-Host ""

# Handle specific modes
if ($ResetStuck) {
    Repair-DirectoryStructure
    Repair-StuckBeads
    exit 0
}

if ($Logs) {
    Test-Logs
    exit 0
}

if ($Beads) {
    Repair-DirectoryStructure
    Test-Beads
    exit 0
}

# Full health check
$prereqOk = Test-Prerequisites
$config = Test-Configuration
$daemonRunning = Test-Daemon
$beadStats = Test-Beads

if (-not $Quick) {
    Test-Logs
}

# Summary
Write-Section "Summary"

$issues = @()

if (-not $prereqOk) {
    $issues += "Missing prerequisites (Kimi CLI, Git, or PowerShell 7)"
}

if (-not $config.PrdFile) {
    $issues += "PRD file missing or invalid"
}

if (-not $config.PromptFile) {
    $issues += "Prompt file (KIMI.md) missing"
}

if ($beadStats.Stuck -gt 0) {
    $issues += "$($beadStats.Stuck) stuck bead(s) detected"
}

if ($beadStats.Failed -gt 0) {
    $issues += "$($beadStats.Failed) failed bead(s)"
}

if ($issues.Count -eq 0) {
    Write-Status "Overall Status" "HEALTHY" "Green"
    
    if ($daemonRunning) {
        Write-Host "`n  The daemon is running and processing beads." -ForegroundColor Green
    }
    elseif ($beadStats.Pending -gt 0) {
        Write-Host "`n  Tip: Start the daemon to process pending beads:" -ForegroundColor Yellow
        Write-Host "       .\ralph.ps1 -Daemon" -ForegroundColor White
    }
}
else {
    Write-Status "Overall Status" "ISSUES FOUND" "Red"
    Write-Host ""
    Write-Host "  Issues:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Red
    }
}

# Auto-fix mode
if ($Fix) {
    Write-Section "Applying Fixes"
    
    Repair-DirectoryStructure
    Repair-OrphanedPidFile
    
    if ($beadStats.Stuck -gt 0) {
        Repair-StuckBeads
    }
    
    Write-Host "`n  Fixes applied. Run health check again to verify." -ForegroundColor Green
}

Write-Host ""
