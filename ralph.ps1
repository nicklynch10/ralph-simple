#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Main Entry Point
# Version: 2.1.0 - Production-Ready CI/CD Agent
#
# REQUIREMENT: PowerShell 7.0+ (Install: winget install Microsoft.PowerShell)
#
# Usage: .\ralph.ps1 [max_iterations] [-Daemon] [-Health] [-Status]
#
# Examples:
#   .\ralph.ps1                    # Run 10 iterations (default)
#   .\ralph.ps1 20                 # Run 20 iterations
#   .\ralph.ps1 -Daemon            # Start production daemon
#   .\ralph.ps1 -Health            # Run health check
#   .\ralph.ps1 -Status            # Show daemon status
#
# Based on the Ralph pattern by Geoffrey Huntley
# Adapted for Kimi Code CLI with production-grade reliability

#requires -Version 7.0

param(
    [Parameter(Position = 0)]
    [int]$MaxIterations = 10,
    
    [Parameter()]
    [switch]$Daemon,
    
    [Parameter()]
    [switch]$Health,
    
    [Parameter()]
    [switch]$Status,
    
    [Parameter()]
    [switch]$InstallTask,
    
    [Parameter()]
    [switch]$UninstallTask,
    
    [Parameter()]
    [switch]$ResetStuck,
    
    [Parameter()]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RalphVersion = "2.1.0"
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:ScriptDir) { $script:ScriptDir = Get-Location }

# Import core module
$coreScript = Join-Path $script:ScriptDir "ralph-core.ps1"
if (Test-Path $coreScript) {
    . $coreScript
}
else {
    Write-Error "Core module not found at $coreScript"
    exit 1
}

# ==============================================================================
# HELP
# ==============================================================================

if ($Help) {
    @"
Ralph for Kimi Code CLI - Autonomous AI Agent Loop v$script:RalphVersion

USAGE:
    .\ralph.ps1 [options] [max_iterations]

COMMANDS:
    (no args)           Run Ralph loop with default 10 iterations
    <number>            Run Ralph loop with specified iterations
    -Daemon             Start production daemon for 24/7 operation
    -Health             Run health check and diagnostics
    -Status             Show daemon and bead status
    -InstallTask        Install daemon as Windows scheduled task
    -UninstallTask      Remove daemon scheduled task
    -ResetStuck         Reset beads stuck for >2 hours
    -Help               Show this help message

EXAMPLES:
    # Run 10 iterations (default)
    .\ralph.ps1

    # Run 20 iterations
    .\ralph.ps1 20

    # Start production daemon
    .\ralph.ps1 -Daemon

    # Check system health
    .\ralph.ps1 -Health

    # Install daemon to run on startup
    .\ralph.ps1 -InstallTask

PRODUCTION DEPLOYMENT:
    For 24/7 operation, use the daemon mode which provides:
    - Process isolation (each bead in separate process)
    - Automatic restart on failure
    - Stuck bead detection and recovery
    - Log rotation
    - Health monitoring

FILES:
    prd.json            Product requirements (user stories)
    KIMI.md             Agent instructions
    progress.txt        Execution log
    .ralph/             Ralph configuration directory
    .ralph/logs/        Log files
    .ralph/beads/       Bead files (daemon mode)

For more information, see README.md
"@ | Write-Host
    exit 0
}

# ==============================================================================
# DISPATCH TO SUB-COMMANDS
# ==============================================================================

# Health check
if ($Health) {
    $healthScript = Join-Path $script:ScriptDir "ralph-health.ps1"
    if (Test-Path $healthScript) {
        & $healthScript -WorkspaceDir (Get-Location)
        exit $LASTEXITCODE
    }
    else {
        Write-Error "Health script not found at $healthScript"
        exit 1
    }
}

# Status check
if ($Status) {
    $healthScript = Join-Path $script:ScriptDir "ralph-health.ps1"
    if (Test-Path $healthScript) {
        & $healthScript -WorkspaceDir (Get-Location) -Beads
        exit 0
    }
    else {
        Write-Error "Health script not found at $healthScript"
        exit 1
    }
}

# Reset stuck beads
if ($ResetStuck) {
    $healthScript = Join-Path $script:ScriptDir "ralph-health.ps1"
    if (Test-Path $healthScript) {
        & $healthScript -WorkspaceDir (Get-Location) -ResetStuck
        exit 0
    }
    else {
        Write-Error "Health script not found at $healthScript"
        exit 1
    }
}

# Daemon mode
if ($Daemon) {
    $daemonScript = Join-Path $script:ScriptDir "ralph-daemon.ps1"
    if (Test-Path $daemonScript) {
        & $daemonScript -WorkspaceDir (Get-Location)
        exit $LASTEXITCODE
    }
    else {
        Write-Error "Daemon script not found at $daemonScript"
        exit 1
    }
}

# Install/Uninstall task
if ($InstallTask -or $UninstallTask) {
    $daemonScript = Join-Path $script:ScriptDir "ralph-daemon.ps1"
    if (Test-Path $daemonScript) {
        if ($InstallTask) {
            & $daemonScript -InstallTask
        }
        else {
            & $daemonScript -UninstallTask
        }
        exit $LASTEXITCODE
    }
    else {
        Write-Error "Daemon script not found at $daemonScript"
        exit 1
    }
}

# ==============================================================================
# MAIN RALPH LOOP (Simple Mode)
# ==============================================================================

# Set UTF-8 encoding for proper Unicode support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# File paths
$PrdFile = Join-Path (Get-Location) "prd.json"
$ProgressFile = Join-Path (Get-Location) "progress.txt"
$ArchiveDir = Join-Path (Get-Location) "archive"
$LastBranchFile = Join-Path (Get-Location) ".last-branch"
$PromptFile = Join-Path (Get-Location) "KIMI.md"
$LogDir = Join-Path (Get-Location) ".ralph\logs"

# ==============================================================================
# LOGGING
# ==============================================================================

function Write-RalphLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
    
    # Also write to log file
    try {
        if (-not (Test-Path $LogDir)) {
            New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
        }
        $logFile = Join-Path $LogDir "ralph-$(Get-Date -Format 'yyyyMMdd').log"
        $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
    catch { }
}

# ==============================================================================
# JSON HANDLING (UTF-8 BOM Safe)
# ==============================================================================

function Read-RalphJson {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) { return $null }
    
    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8
        
        # Remove BOM if present (0xEF 0xBB 0xBF = `ufeff)
        if ($content.Length -gt 0 -and $content[0] -eq "`ufeff") {
            $content = $content.Substring(1)
        }
        
        return $content | ConvertFrom-Json
    }
    catch {
        Write-RalphLog "Failed to read JSON from $Path`: $_" -Level "ERROR"
        return $null
    }
}

# ==============================================================================
# STATUS DISPLAY
# ==============================================================================

function Show-Status {
    try {
        $prd = Read-RalphJson -Path $PrdFile
        if ($prd -and $prd.userStories) {
            Write-Host ""
            Write-Host "Current PRD Status:" -ForegroundColor Green
            Write-Host "===================" -ForegroundColor Green
            
            foreach ($story in $prd.userStories) {
                $status = if ($story.passes -eq $true) { "✓ PASS" } else { "○ PENDING" }
                $color = if ($story.passes -eq $true) { "Green" } else { "Yellow" }
                Write-Host "[$status] $($story.id): $($story.title)" -ForegroundColor $color
            }
            
            $completed = ($prd.userStories | Where-Object { $_.passes -eq $true }).Count
            $total = $prd.userStories.Count
            Write-Host ""
            Write-Host "Progress: $completed / $total stories complete" -ForegroundColor Cyan
        }
    }
    catch {
        Write-RalphLog "Could not display status: $_" -Level "WARN"
    }
}

# ==============================================================================
# PREREQUISITE CHECKS
# ==============================================================================

Write-RalphLog "Ralph for Kimi Code CLI v$script:RalphVersion" -Level "INFO"
Write-RalphLog "Max iterations: $MaxIterations" -Level "INFO"

if (-not (Get-Command kimi -ErrorAction SilentlyContinue)) {
    Write-Error "Error: Kimi CLI not found. Please install Kimi Code CLI first.`nVisit: https://github.com/moonshotai/kimi-cli"
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Error: git not found. Please install git."
    exit 1
}

if (-not (Test-Path $PrdFile)) {
    Write-Error "Error: prd.json not found at $PrdFile`nPlease create a prd.json file or use the PRD skill to generate one."
    exit 1
}

# ==============================================================================
# ARCHIVE PREVIOUS RUN
# ==============================================================================

if ((Test-Path $PrdFile) -and (Test-Path $LastBranchFile)) {
    try {
        $prd = Read-RalphJson -Path $PrdFile
        $currentBranch = $prd.branchName
        $lastBranch = Get-Content $LastBranchFile -Raw -Encoding UTF8
        
        # Clean up potential BOM
        $lastBranch = $lastBranch -replace "^`ufeff", ""
        $lastBranch = $lastBranch.Trim()
        
        if ($currentBranch -and $lastBranch -and ($currentBranch -ne $lastBranch)) {
            $date = Get-Date -Format "yyyy-MM-dd"
            $folderName = $lastBranch -replace '^ralph/', ''
            $archiveFolder = Join-Path $ArchiveDir "$date-$folderName"
            
            Write-RalphLog "Archiving previous run: $lastBranch" -Level "INFO"
            New-Item -ItemType Directory -Force -Path $archiveFolder | Out-Null
            
            if (Test-Path $PrdFile) { Copy-Item $PrdFile $archiveFolder }
            if (Test-Path $ProgressFile) { Copy-Item $ProgressFile $archiveFolder }
            
            Write-RalphLog "Archived to: $archiveFolder" -Level "SUCCESS"
            
            # Reset progress file
            "# Ralph Progress Log" | Set-Content $ProgressFile -Encoding UTF8
            "Started: $(Get-Date)" | Add-Content $ProgressFile -Encoding UTF8
            "---" | Add-Content $ProgressFile -Encoding UTF8
        }
    }
    catch {
        Write-RalphLog "Could not check/archive previous run: $_" -Level "WARN"
    }
}

# Track current branch
try {
    if (Test-Path $PrdFile) {
        $prd = Read-RalphJson -Path $PrdFile
        if ($prd.branchName) {
            $prd.branchName | Set-Content $LastBranchFile -Encoding UTF8 -NoNewline
        }
    }
}
catch {
    Write-RalphLog "Could not track current branch: $_" -Level "WARN"
}

# Initialize progress file
if (-not (Test-Path $ProgressFile)) {
    "# Ralph Progress Log" | Set-Content $ProgressFile -Encoding UTF8
    "Started: $(Get-Date)" | Add-Content $ProgressFile -Encoding UTF8
    "---" | Add-Content $ProgressFile -Encoding UTF8
}

Show-Status

# ==============================================================================
# MAIN LOOP
# ==============================================================================

# Set up Ctrl+C handler (using Console event, NOT trap)
# This is critical: trap catches ALL exceptions, not just Ctrl+C
$script:CancelRequested = $false
$cancelHandler = {
    param([object]$sender, [System.ConsoleCancelEventArgs]$e)
    $e.Cancel = $true
    $script:CancelRequested = $true
    Write-RalphLog "Interrupted by user (Ctrl+C)" -Level "WARN"
}
[Console]::add_CancelKeyPress($cancelHandler)

$completedIterations = 0

for ($i = 1; $i -le $MaxIterations -and -not $script:CancelRequested; $i++) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  Ralph Iteration $i of $MaxIterations" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-RalphLog "Starting iteration $i" -Level "INFO"
    
    $output = ""
    $success = $false
    
    try {
        # Run Kimi with the Ralph prompt
        # Use --print for non-interactive mode (auto-approves actions)
        # Use --final-message-only for clean output
        
        $output = Get-Content $PromptFile -Raw -Encoding UTF8 | kimi --print --final-message-only 2>&1
        
        # Also write output to console
        if ($output) {
            # Handle case where output is an array (from 2>&1 redirection)
            $outputString = $output -join "`n"
            Write-Host $outputString
        }
        
        $success = $true
    }
    catch {
        # Don't let Kimi errors stop the loop
        Write-RalphLog "Iteration $i encountered an error: $_" -Level "WARN"
        $output = $_.Exception.Message
    }
    
    $completedIterations++
    
    # Check for completion signal
    $outputString = $output -join "`n"
    if ($outputString -like "*<promise>COMPLETE</promise>*") {
        Write-Host ""
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host "  RALPH COMPLETED ALL TASKS!" -ForegroundColor Green
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host ""
        Write-RalphLog "Completed at iteration $i of $MaxIterations" -Level "SUCCESS"
        
        Show-Status
        exit 0
    }
    
    # Also check if all stories are complete in the PRD
    try {
        $prd = Read-RalphJson -Path $PrdFile
        if ($prd -and $prd.userStories) {
            $incomplete = $prd.userStories | Where-Object { $_.passes -ne $true }
            if ($incomplete.Count -eq 0) {
                Write-Host ""
                Write-Host "===============================================================" -ForegroundColor Green
                Write-Host "  ALL STORIES COMPLETE!" -ForegroundColor Green
                Write-Host "===============================================================" -ForegroundColor Green
                Write-Host ""
                Write-RalphLog "All stories marked complete at iteration $i" -Level "SUCCESS"
                exit 0
            }
        }
    }
    catch { }
    
    Write-RalphLog "Iteration $i complete. Checking for more work..." -Level "INFO"
    Show-Status
    
    # Delay between iterations
    if ($i -lt $MaxIterations -and -not $script:CancelRequested) {
        Start-Sleep -Seconds 2
    }
}

# ==============================================================================
# COMPLETION
# ==============================================================================

if ($script:CancelRequested) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Yellow
    Write-Host "  RALPH STOPPED BY USER" -ForegroundColor Yellow
    Write-Host "===============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-RalphLog "Stopped after $completedIterations iteration(s)" -Level "WARN"
    exit 130
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host "  RALPH REACHED MAX ITERATIONS" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host ""
Write-RalphLog "Max iterations ($MaxIterations) reached without completion" -Level "WARN"
Write-Host "Check $ProgressFile for status." -ForegroundColor Yellow
Write-Host ""

Show-Status

exit 1
