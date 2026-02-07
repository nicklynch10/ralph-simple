#!/usr/bin/env pwsh
# Ralph Build Loop - Phase 1
# Core build loop that implements tasks from backlog until verifiers pass
# 
# Architecture: Simple outer loop, fresh context each iteration, artifact-driven

param(
    [Parameter(Position = 0)]
    [int]$MaxIterations = 20,
    
    [Parameter()]
    [string]$BacklogPath = "backlog.json",
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [string]$PromptFile = "KIMI-BUILD.md"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# ============================================================================
# CONFIGURATION
# ============================================================================

$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Get-Location }

$BACKLOG_FILE = if ([System.IO.Path]::IsPathRooted($BacklogPath)) { 
    $BacklogPath 
} else { 
    Join-Path (Get-Location) $BacklogPath 
}

$PROMPT_FILE = Join-Path $SCRIPT_DIR $PromptFile
$ARTIFACTS_DIR = Join-Path (Get-Location) ".ralph/artifacts"
$LOG_FILE = Join-Path (Get-Location) ".ralph/build.log"

# Ensure directories exist
New-Item -ItemType Directory -Force -Path $ARTIFACTS_DIR | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $LOG_FILE) | Out-Null

# ============================================================================
# LOGGING
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LOG_FILE -Value $logEntry -Encoding UTF8
}

# ============================================================================
# BACKLOG MANAGEMENT
# ============================================================================

function Read-Backlog {
    if (-not (Test-Path $BACKLOG_FILE)) {
        throw "Backlog file not found: $BACKLOG_FILE"
    }
    
    # Read with BOM handling (same pattern as ralph-core.ps1)
    $content = Get-Content -Path $BACKLOG_FILE -Raw -Encoding UTF8
    
    # Remove BOM if present (0xEF 0xBB 0xBF)
    if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
        $content = $content.Substring(1)
    }
    
    return $content | ConvertFrom-Json
}

function Write-Backlog {
    param($Backlog)
    $Backlog.updatedAt = (Get-Date -Format "o")
    $json = $Backlog | ConvertTo-Json -Depth 20
    # Write with UTF8 no BOM (same pattern as ralph-core.ps1)
    [System.IO.File]::WriteAllText($BACKLOG_FILE, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-NextTask {
    param($Backlog)
    
    # Priority order: bugfix > hardening > feature > infrastructure
    $laneOrder = @("bugfix", "hardening", "feature", "infrastructure")
    
    foreach ($laneName in $laneOrder) {
        $lane = $Backlog.lanes.$laneName
        if (-not $lane) { continue }
        
        # Find highest priority pending task
        $task = $lane | 
            Where-Object { $_.status -eq "pending" -or $_.status -eq "failed" } |
            Sort-Object priority | 
            Select-Object -First 1
        
        if ($task) {
            return @{ Task = $task; Lane = $laneName }
        }
    }
    
    return $null
}

function Update-TaskStatus {
    param($Backlog, $TaskId, $Status, $Artifacts = $null, $Error = $null)
    
    # Find task in any lane
    foreach ($laneName in $Backlog.lanes.PSObject.Properties.Name) {
        $lane = $Backlog.lanes.$laneName
        $task = $lane | Where-Object { $_.id -eq $TaskId }
        
        if ($task) {
            $task.status = $Status
            
            if ($Status -eq "in_progress" -and -not $task.startedAt) {
                $task.startedAt = (Get-Date -Format "o")
            }
            
            if ($Status -eq "completed") {
                $task.completedAt = (Get-Date -Format "o")
            }
            
            if ($Status -eq "failed") {
                $task.attempts++
                if ($Error) {
                    $task.failureLog += @{
                        timestamp = (Get-Date -Format "o")
                        attempt = $task.attempts
                        error = $Error
                    }
                }
            }
            
            if ($Artifacts) {
                $task.artifacts = $Artifacts
            }
            
            return $true
        }
    }
    
    return $false
}

# ============================================================================
# VERIFICATION SYSTEM
# ============================================================================

function Invoke-Verifiers {
    param($Task)
    
    Write-Log "Running verification bundle for $($Task.id)" "VERIFY"
    
    $results = @{
        success = $true
        passed = @()
        failed = @()
        output = @()
    }
    
    $verifiers = $Task.definitionOfDone.verifierBundle
    if (-not $verifiers) {
        Write-Log "No verifiers defined, skipping" "WARN"
        return $results
    }
    
    foreach ($verifier in $verifiers) {
        Write-Log "Running: $verifier" "VERIFY"
        
        try {
            $output = Invoke-Expression $verifier 2>&1
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                $results.passed += $verifier
                Write-Log "✓ PASSED: $verifier" "SUCCESS"
            } else {
                $results.success = $false
                $results.failed += $verifier
                $results.output += "FAILED: $verifier`n$output"
                Write-Log "✗ FAILED: $verifier" "ERROR"
            }
        }
        catch {
            $results.success = $false
            $results.failed += $verifier
            $results.output += "ERROR: $verifier`n$_"
            Write-Log "✗ ERROR: $verifier - $_" "ERROR"
        }
    }
    
    return $results
}

function Test-DefinitionOfDone {
    param($Task)
    
    Write-Log "Checking Definition of Done for $($Task.id)" "VERIFY"
    
    $criteria = $Task.definitionOfDone.criteria
    if (-not $criteria) {
        Write-Log "No DoD criteria defined" "WARN"
        return @{ met = $false; reason = "No criteria defined" }
    }
    
    # For Phase 1, we rely on verifierBundle to check criteria
    # In future phases, we can have AI verify each criterion
    
    return @{ 
        met = $true 
        checked = $criteria.Count
    }
}

# ============================================================================
# BUILD EXECUTION
# ============================================================================

function Invoke-Build {
    param($Task)
    
    Write-Log "Starting build for $($Task.id): $($Task.title)" "BUILD"
    Write-Log "Intent: $($Task.intent)" "BUILD"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would execute Kimi with task context" "DRY"
        return @{ success = $true; output = "Dry run - no execution" }
    }
    
    # Prepare build context for Kimi
    $buildContext = @{
        task = $Task
        timestamp = Get-Date -Format "o"
        workingDirectory = (Get-Location).Path
    } | ConvertTo-Json -Depth 10
    
    # Save build context for Kimi to read
    $contextFile = Join-Path $ARTIFACTS_DIR "$($Task.id)-context.json"
    # Write with UTF8 no BOM
    [System.IO.File]::WriteAllText($contextFile, $buildContext, [System.Text.UTF8Encoding]::new($false))
    
    # Check if prompt file exists
    if (-not (Test-Path $PROMPT_FILE)) {
        throw "Prompt file not found: $PROMPT_FILE"
    }
    
    # Run Kimi with the build prompt
    # Kimi reads the task context and implements
    Write-Log "Spawning Kimi Code CLI..." "BUILD"
    
    try {
        $output = Get-Content $PROMPT_FILE | kimi --print --final-message-only 2>&1
        
        return @{
            success = ($output -notlike "*<error>*" -and $output -notlike "*FAILED*")
            output = $output
        }
    }
    catch {
        return @{
            success = $false
            output = $_.Exception.Message
        }
    }
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Start-RalphBuild {
    Write-Log "========================================" "INFO"
    Write-Log "Ralph Build Loop - Phase 1" "INFO"
    Write-Log "Max iterations: $MaxIterations" "INFO"
    Write-Log "Backlog: $BACKLOG_FILE" "INFO"
    Write-Log "========================================" "INFO"
    
    # Verify prerequisites
    if (-not (Get-Command kimi -ErrorAction SilentlyContinue)) {
        throw "Kimi CLI not found. Please install and authenticate."
    }
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git not found. Please install git."
    }
    
    # Main loop
    for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
        Write-Log "" "INFO"
        Write-Log "========================================" "INFO"
        Write-Log "Iteration $iteration of $MaxIterations" "INFO"
        Write-Log "========================================" "INFO"
        
        # Read current backlog
        $backlog = Read-Backlog
        
        # Get next task
        $next = Get-NextTask $backlog
        
        if (-not $next) {
            Write-Log "No pending tasks found. All work complete!" "SUCCESS"
            exit 0
        }
        
        $task = $next.Task
        $lane = $next.Lane
        
        Write-Log "Selected task: $($task.id) from $lane lane" "INFO"
        Write-Log "Title: $($task.title)" "INFO"
        Write-Log "Priority: $($task.priority) | Attempts: $($task.attempts)/$($task.maxAttempts)" "INFO"
        
        # Check max attempts
        if ($task.attempts -ge $task.maxAttempts) {
            Write-Log "Task has exceeded max attempts ($($task.maxAttempts)). Marking as blocked." "ERROR"
            Update-TaskStatus -Backlog $backlog -TaskId $task.id -Status "blocked"
            Write-Backlog $backlog
            continue
        }
        
        # Mark as in progress
        Update-TaskStatus -Backlog $backlog -TaskId $task.id -Status "in_progress"
        Write-Backlog $backlog
        
        # Create feature branch
        $branchName = "ralph/$($task.id)-$(($task.title -replace '\s+', '-').ToLower())"
        Write-Log "Working on branch: $branchName" "INFO"
        
        try {
            git checkout -b $branchName 2>&1 | Out-Null
        }
        catch {
            Write-Log "Branch may already exist, continuing..." "WARN"
            git checkout $branchName 2>&1 | Out-Null
        }
        
        # BUILD PHASE
        Write-Log "Starting build phase..." "BUILD"
        $buildResult = Invoke-Build -Task $task
        
        if (-not $buildResult.success) {
            Write-Log "Build failed for $($task.id)" "ERROR"
            Update-TaskStatus -Backlog $backlog -TaskId $task.id -Status "failed" -Error $buildResult.output
            Write-Backlog $backlog
            
            # Stay on this task for next iteration
            Write-Log "Will retry in next iteration" "INFO"
            Start-Sleep -Seconds 5
            continue
        }
        
        Write-Log "Build phase completed" "SUCCESS"
        
        # VERIFICATION PHASE
        Write-Log "Starting verification phase..." "VERIFY"
        
        $verifierResults = Invoke-Verifiers -Task $task
        $dodResults = Test-DefinitionOfDone -Task $task
        
        if ($verifierResults.success -and $dodResults.met) {
            Write-Log "All verifiers passed!" "SUCCESS"
            
            # Commit changes
            $commitMessage = "$($task.id): $($task.title)`n`n$($task.intent)"
            git add -A
            git commit -m $commitMessage 2>&1 | Out-Null
            
            # Mark as completed
            $artifacts = @{
                branch = $branchName
                commitHash = (git rev-parse HEAD)
                buildOutput = $buildResult.output
                verifierResults = $verifierResults.passed
            }
            
            Update-TaskStatus -Backlog $backlog -TaskId $task.id -Status "completed" -Artifacts $artifacts
            Write-Backlog $backlog
            
            Write-Log "Task $($task.id) completed successfully!" "SUCCESS"
        }
        else {
            Write-Log "Verification failed for $($task.id)" "ERROR"
            
            $errorMessage = ($verifierResults.output -join "`n")
            Update-TaskStatus -Backlog $backlog -TaskId $task.id -Status "failed" -Error $errorMessage
            Write-Backlog $backlog
            
            Write-Log "Feedback recorded for next iteration" "INFO"
        }
        
        # Back to main branch
        git checkout main 2>&1 | Out-Null
        
        Write-Log "Iteration $iteration complete" "INFO"
        Start-Sleep -Seconds 2
    }
    
    Write-Log "Max iterations ($MaxIterations) reached" "WARN"
    Write-Log "Run again to continue" "INFO"
    exit 1
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    Start-RalphBuild
}
catch {
    Write-Log "FATAL ERROR: $_" "FATAL"
    exit 1
}
