#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Core Module
# This module contains the core functionality for Ralph automation
# Version: 2.1.0
#
# REQUIREMENT: PowerShell 7.0+ (Install: winget install Microsoft.PowerShell)
#
# Usage: Import-Module ./ralph-core.ps1
# Or: . ./ralph-core.ps1 (dot-source)
#
# Based on the Ralph pattern by Geoffrey Huntley
# Adapted for Kimi Code CLI with production-grade reliability

#requires -Version 7.0

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RalphVersion = "2.2.2"
$script:RalphConfig = @{
    # Default paths (can be overridden)
    PrdFile = "prd.json"
    ProgressFile = "progress.txt"
    ArchiveDir = "archive"
    LastBranchFile = ".last-branch"
    PromptFile = "KIMI.md"
    LogDir = ".ralph/logs"
    
    # Timing configuration
    DefaultMaxIterations = 10
    IterationDelaySeconds = 2
    DefaultVerifierTimeout = 1200  # 20 minutes for Kimi sessions
    
    # Encoding configuration
    Encoding = "UTF8"
    
    # Git configuration
    AutoCommit = $true
    CommitPrefix = "feat"
    
    # Daemon configuration
    BeadTimeoutMinutes = 120
    PollIntervalSeconds = 30
    MaxRetries = 3
    MaxLogSizeMB = 10
    MaxLogFiles = 5
}

# ==============================================================================
# LOGGING SYSTEM
# ==============================================================================

<#
.SYNOPSIS
    Writes a log message with timestamp and level.
.DESCRIPTION
    Centralized logging function that writes to console and optionally to file.
    Supports multiple log levels with color coding.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    The log level: INFO, WARN, ERROR, SUCCESS, DEBUG.
.PARAMETER NoFile
    Skip writing to log file.
#>
function Write-RalphLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",
        
        [Parameter()]
        [switch]$NoFile
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    # File logging
    if (-not $NoFile) {
        $logFile = Join-Path $script:RalphConfig.LogDir "ralph-$(Get-Date -Format 'yyyyMMdd').log"
        try {
            if (-not (Test-Path $script:RalphConfig.LogDir)) {
                New-Item -ItemType Directory -Force -Path $script:RalphConfig.LogDir | Out-Null
            }
            $logEntry | Out-File -FilePath $logFile -Append -Encoding $script:RalphConfig.Encoding
        }
        catch {
            # Silently fail on logging errors to avoid breaking execution
            Write-Host "[WARNING] Could not write to log file: $_" -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# JSON HANDLING (UTF-8 BOM Safe)
# ==============================================================================

<#
.SYNOPSIS
    Reads a JSON file with proper UTF-8 BOM handling.
.DESCRIPTION
    PowerShell's Get-Content with ConvertFrom-Json can fail on files with UTF-8 BOM.
    This function handles both BOM and non-BOM files correctly.
.PARAMETER Path
    Path to the JSON file.
#>
function Read-RalphJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    try {
        # Use -Raw to read entire file, -Encoding UTF8 handles BOM correctly
        $content = Get-Content -Path $Path -Raw -Encoding UTF8
        
        # Remove BOM if present (0xEF 0xBB 0xBF = `u{feff})
        if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") {
            $content = $content.Substring(1)
        }
        
        return $content | ConvertFrom-Json
    }
    catch {
        Write-RalphLog "Failed to read JSON from $Path`: $_" -Level "ERROR"
        return $null
    }
}

<#
.SYNOPSIS
    Writes a JSON file with proper encoding (no BOM).
.DESCRIPTION
    Writes JSON with consistent formatting and UTF-8 encoding without BOM.
    Uses System.IO.File.WriteAllText to ensure no BOM is written.
.PARAMETER Path
    Path to write the JSON file.
.PARAMETER Data
    The object to serialize to JSON.
.PARAMETER Depth
    Serialization depth (default: 10).
#>
function Write-RalphJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [Parameter()]
        [int]$Depth = 10
    )
    
    try {
        $json = $Data | ConvertTo-Json -Depth $Depth -Compress:$false
        
        # Ensure directory exists
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        
        # Write with UTF8 encoding (no BOM)
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
        return $true
    }
    catch {
        Write-RalphLog "Failed to write JSON to $Path`: $_" -Level "ERROR"
        return $false
    }
}

# ==============================================================================
# PRD OPERATIONS
# ==============================================================================

<#
.SYNOPSIS
    Converts PRD user stories to bead files for daemon processing.
.DESCRIPTION
    Reads prd.json and creates corresponding bead files in .ralph/beads/.
    Each user story becomes a bead with full schema initialization.
    Existing beads are not overwritten unless -Force is specified.
    
    The bead schema includes:
    - Core fields: id, type, status, priority, title, intent, description
    - dod (Definition of Done): verifiers, evidence_required
    - constraints: max_iterations, time_budget_minutes, allowed_dirs
    - ralph_meta: attempt_count, timeout_count, stuck_count, timestamps
.PARAMETER PrdPath
    Path to the PRD file.
.PARAMETER BeadsDir
    Directory to save bead files.
.PARAMETER Force
    Overwrite existing bead files.
.OUTPUTS
    Array of created bead objects.
.EXAMPLE
    Convert-PrdToBeads -PrdPath "prd.json" -BeadsDir ".ralph/beads"
.EXAMPLE
    Convert-PrdToBeads -Force  # Overwrite existing beads
#>
function Convert-PrdToBeads {
    param(
        [Parameter()]
        [string]$PrdPath = $script:RalphConfig.PrdFile,
        
        [Parameter()]
        [string]$BeadsDir = (Join-Path ".ralph" "beads"),
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-RalphLog "Converting PRD to beads..." -Level "INFO"
    
    # Load PRD
    $prd = Read-RalphJson -Path $PrdPath
    if (-not $prd) {
        throw "PRD file not found or invalid at $PrdPath"
    }
    
    if (-not $prd.userStories) {
        Write-RalphLog "PRD has no user stories" -Level "WARN"
        return @()
    }
    
    # Ensure beads directory exists
    if (-not (Test-Path $BeadsDir)) {
        New-Item -ItemType Directory -Force -Path $BeadsDir -ErrorAction SilentlyContinue | Out-Null
    }
    
    $createdBeads = @()
    $skippedBeads = 0
    
    foreach ($story in $prd.userStories) {
        $beadId = $story.id
        if (-not $beadId) {
            Write-RalphLog "Skipping story without id: $($story.title)" -Level "WARN"
            continue
        }
        
        $beadFile = Join-Path $BeadsDir "$beadId.json"
        
        # Skip if already exists and not forcing
        if ((Test-Path $beadFile) -and -not $Force) {
            Write-RalphLog "Bead already exists: $beadId" -Level "DEBUG"
            $skippedBeads++
            continue
        }
        
        # Build verifiers from acceptance criteria and test files
        $verifiers = @()
        
        # Add verifiers from acceptance criteria
        if ($story.acceptanceCriteria -and $story.acceptanceCriteria.Count -gt 0) {
            $verifiers += @{
                name = "Acceptance criteria met"
                command = "# Verify: $($story.acceptanceCriteria -join ', ')"
                expect = @{ exit_code = 0 }
                timeout_seconds = 60
            }
        }
        
        # Add test file verifiers if specified
        if ($story.testing -and $story.testing.testFiles) {
            foreach ($testFile in $story.testing.testFiles) {
                $verifiers += @{
                    name = "Test file exists: $testFile"
                    command = "Test-Path '$testFile'"
                    expect = @{ exit_code = 0 }
                    timeout_seconds = 30
                }
            }
        }
        
        # Default verifier if none specified
        if ($verifiers.Count -eq 0) {
            $verifiers += @{
                name = "Story completed"
                command = "# Manual verification required"
                expect = @{ exit_code = 0 }
                timeout_seconds = 60
            }
        }
        
        # Create bead object with FULL schema
        $now = Get-Date -Format "o"
        $bead = @{
            # Core fields
            id = $beadId
            type = "prd-story"
            status = if ($story.passes -eq $true) { "completed" } else { "pending" }
            priority = if ($story.priority) { $story.priority } else { 2 }
            title = if ($story.title) { $story.title } else { "Untitled Story" }
            intent = if ($story.description) { $story.description } else { "" }
            description = if ($story.description) { $story.description } else { "" }
            
            # PRD linkage
            prd_reference = @{
                story_id = $beadId
                project = if ($prd.project) { $prd.project } else { "unknown" }
                branch_name = if ($prd.branchName) { $prd.branchName } else { "main" }
            }
            
            # Definition of Done
            dod = @{
                verifiers = $verifiers
                evidence_required = $true
                acceptance_criteria = if ($story.acceptanceCriteria) { $story.acceptanceCriteria } else { @() }
            }
            
            # Constraints
            constraints = @{
                max_iterations = 10
                time_budget_minutes = 60
                allowed_dirs = @()
                blocked_dirs = @(".git", ".ralph", "node_modules", "__pycache__")
            }
            
            # Metadata
            created_at = $now
            updated_at = $now
            
            # Ralph tracking metadata
            ralph_meta = @{
                attempt_count = 0
                timeout_count = 0
                stuck_count = 0
                last_attempt = $null
                last_error = $null
                status_detail = $null
                last_updated = $now
                created_by = "Convert-PrdToBeads"
                version = $script:RalphVersion
            }
        }
        
        # Save bead atomically with backup
        $tempFile = "$beadFile.tmp"
        $backupFile = "$beadFile.bak"
        
        try {
            # Backup existing if present
            if (Test-Path $beadFile) {
                Copy-Item $beadFile $backupFile -Force -ErrorAction SilentlyContinue
            }
            
            # Write to temp then atomic move
            $json = $bead | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
            Move-Item $tempFile $beadFile -Force
            
            # Remove backup on success
            if (Test-Path $backupFile) {
                Remove-Item $backupFile -ErrorAction SilentlyContinue
            }
            
            Write-RalphLog "Created bead: $beadId" -Level "SUCCESS"
            $createdBeads += $bead
        }
        catch {
            Write-RalphLog "Failed to create bead $beadId`: $_" -Level "ERROR"
            
            # Restore from backup on failure
            if (Test-Path $backupFile) {
                Copy-Item $backupFile $beadFile -Force -ErrorAction SilentlyContinue
            }
            
            # Cleanup temp file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -ErrorAction SilentlyContinue
            }
        }
    }
    
    Write-RalphLog "Created $($createdBeads.Count) beads from PRD (skipped $skippedBeads existing)" -Level "SUCCESS"
    return $createdBeads
}

<#
.SYNOPSIS
    Loads and validates the PRD file.
.DESCRIPTION
    Reads prd.json and performs basic validation.
#>
function Get-RalphPrd {
    param(
        [Parameter()]
        [string]$Path = $script:RalphConfig.PrdFile
    )
    
    $prd = Read-RalphJson -Path $Path
    
    if (-not $prd) {
        throw "PRD file not found or invalid at $Path"
    }
    
    # Validate required fields
    if (-not $prd.userStories) {
        throw "PRD missing required field: userStories"
    }
    
    return $prd
}

<#
.SYNOPSIS
    Gets the next pending user story.
.DESCRIPTION
    Returns the highest priority story with passes: false.
#>
function Get-NextUserStory {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Prd
    )
    
    $pendingStories = $Prd.userStories | Where-Object { 
        $_.passes -eq $false -or $_.passes -eq $null 
    } | Sort-Object -Property priority
    
    return $pendingStories | Select-Object -First 1
}

<#
.SYNOPSIS
    Updates a user story's pass status.
.DESCRIPTION
    Sets passes: true for a specific story and writes back to PRD.
    Defensively handles missing properties.
#>
function Update-StoryStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StoryId,
        
        [Parameter(Mandatory = $true)]
        [bool]$Passed,
        
        [Parameter()]
        [string]$Notes = "",
        
        [Parameter()]
        [string]$Path = $script:RalphConfig.PrdFile
    )
    
    $prd = Get-RalphPrd -Path $Path
    
    $story = $prd.userStories | Where-Object { $_.id -eq $StoryId } | Select-Object -First 1
    if (-not $story) {
        Write-RalphLog "Story $StoryId not found in PRD" -Level "WARN"
        return $false
    }
    
    $story.passes = $Passed
    if ($Notes) {
        $story.notes = $Notes
    }
    
    # Ensure updated_at field exists (defensive programming)
    if (-not ($story.PSObject.Properties.Name -contains "updated_at")) {
        $story | Add-Member -NotePropertyName "updated_at" -NotePropertyValue (Get-Date -Format "o") -Force
    }
    else {
        $story.updated_at = Get-Date -Format "o"
    }
    
    return Write-RalphJson -Path $Path -Data $prd
}

<#
.SYNOPSIS
    Checks if all stories are complete.
#>
function Test-AllStoriesComplete {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Prd
    )
    
    $incompleteStories = $Prd.userStories | Where-Object { 
        $_.passes -ne $true 
    }
    
    return ($incompleteStories.Count -eq 0)
}

# ==============================================================================
# PROGRESS TRACKING
# ==============================================================================

<#
.SYNOPSIS
    Initializes the progress file.
#>
function Initialize-ProgressFile {
    param(
        [Parameter()]
        [string]$Path = $script:RalphConfig.ProgressFile
    )
    
    if (-not (Test-Path $Path)) {
        $content = @"
# Ralph Progress Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---

"@
        $content | Set-Content -Path $Path -Encoding $script:RalphConfig.Encoding
        Write-RalphLog "Initialized progress file: $Path" -Level "DEBUG"
    }
}

<#
.SYNOPSIS
    Appends a progress entry to the progress file.
#>
function Add-ProgressEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StoryId,
        
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter()]
        [string]$Implementation = "",
        
        [Parameter()]
        [string]$Testing = "",
        
        [Parameter()]
        [string]$Learnings = "",
        
        [Parameter()]
        [string]$Path = $script:RalphConfig.ProgressFile
    )
    
    Initialize-ProgressFile -Path $Path
    
    $entry = @"

## $(Get-Date -Format "yyyy-MM-dd HH:mm") - $StoryId - $Title

### Implementation
$Implementation

### Testing
$Testing

### Learnings
$Learnings

---
"@
    
    $entry | Add-Content -Path $Path -Encoding $script:RalphConfig.Encoding
}

# ==============================================================================
# GIT OPERATIONS
# ==============================================================================

<#
.SYNOPSIS
    Creates a git commit for the current changes.
.DESCRIPTION
    Stages all changes and creates a commit with a standardized message.
#>
function Invoke-RalphGitCommit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StoryId,
        
        [Parameter(Mandatory = $true)]
        [string]$StoryTitle,
        
        [Parameter()]
        [int]$Iteration = 1,
        
        [Parameter()]
        [string]$ProjectRoot = (Get-Location)
    )
    
    # Check if this is a git repository
    $gitDir = Join-Path $ProjectRoot ".git"
    if (-not (Test-Path $gitDir)) {
        Write-RalphLog "Not a git repository, skipping commit" -Level "DEBUG"
        return $false
    }
    
    # Check for changes
    $status = git -C $ProjectRoot status --porcelain 2>&1
    if (-not $status) {
        Write-RalphLog "No changes to commit" -Level "DEBUG"
        return $false
    }
    
    # Stage all changes
    $null = git -C $ProjectRoot add -A 2>&1
    
    # Create commit message
    $commitMessage = @"
$($script:RalphConfig.CommitPrefix): [$StoryId] $StoryTitle

- Completed in iteration $Iteration
- Auto-committed by Ralph v$script:RalphVersion
"@
    
    # Commit
    $result = git -C $ProjectRoot commit -m $commitMessage 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-RalphLog "Committed changes: $StoryId" -Level "SUCCESS"
        return $true
    }
    else {
        Write-RalphLog "Git commit failed: $result" -Level "WARN"
        return $false
    }
}

<#
.SYNOPSIS
    Archives the previous run if branch changed.
#>
function Invoke-RalphArchive {
    param(
        [Parameter()]
        [string]$PrdPath = $script:RalphConfig.PrdFile,
        
        [Parameter()]
        [string]$LastBranchPath = $script:RalphConfig.LastBranchFile,
        
        [Parameter()]
        [string]$ArchiveDir = $script:RalphConfig.ArchiveDir,
        
        [Parameter()]
        [string]$ProgressPath = $script:RalphConfig.ProgressFile
    )
    
    if (-not (Test-Path $PrdPath) -or -not (Test-Path $LastBranchPath)) {
        return
    }
    
    try {
        $prd = Read-RalphJson -Path $PrdPath
        $currentBranch = $prd.branchName
        $lastBranch = Get-Content $LastBranchPath -Raw -Encoding UTF8
        
        # Clean up potential BOM
        $lastBranch = $lastBranch -replace "^`u{feff}", ""
        $lastBranch = $lastBranch.Trim()
        
        if ($currentBranch -and $lastBranch -and ($currentBranch -ne $lastBranch)) {
            $date = Get-Date -Format "yyyy-MM-dd"
            $folderName = $lastBranch -replace '^ralph/', ''
            $archiveFolder = Join-Path $ArchiveDir "$date-$folderName"
            
            Write-RalphLog "Archiving previous run: $lastBranch" -Level "INFO"
            New-Item -ItemType Directory -Force -Path $archiveFolder | Out-Null
            
            if (Test-Path $PrdPath) {
                Copy-Item $PrdPath $archiveFolder
            }
            if (Test-Path $ProgressPath) {
                Copy-Item $ProgressPath $archiveFolder
            }
            
            Write-RalphLog "Archived to: $archiveFolder" -Level "SUCCESS"
            
            # Reset progress file
            Initialize-ProgressFile -Path $ProgressPath
        }
    }
    catch {
        Write-RalphLog "Could not check/archive previous run: $_" -Level "WARN"
    }
}

<#
.SYNOPSIS
    Tracks the current branch.
#>
function Set-RalphBranchTracking {
    param(
        [Parameter()]
        [string]$PrdPath = $script:RalphConfig.PrdFile,
        
        [Parameter()]
        [string]$LastBranchPath = $script:RalphConfig.LastBranchFile
    )
    
    try {
        if (Test-Path $PrdPath) {
            $prd = Read-RalphJson -Path $PrdPath
            if ($prd.branchName) {
                $prd.branchName | Set-Content -Path $LastBranchPath -Encoding $script:RalphConfig.Encoding -NoNewline
            }
        }
    }
    catch {
        Write-RalphLog "Could not track current branch: $_" -Level "WARN"
    }
}

# ==============================================================================
# KIMI CLI OPERATIONS
# ==============================================================================

<#
.SYNOPSIS
    Invokes Kimi CLI with the Ralph prompt.
.DESCRIPTION
    Runs Kimi in --print mode for autonomous operation.
    Handles output capture and error handling properly.
    Uses file-based approach to avoid pipeline deadlocks.
.PARAMETER PromptFile
    Path to the prompt file.
.PARAMETER TimeoutMinutes
    Timeout in minutes (default: 30).
#>
function Invoke-RalphKimi {
    param(
        [Parameter()]
        [string]$PromptFile = $script:RalphConfig.PromptFile,
        
        [Parameter()]
        [int]$TimeoutMinutes = 30
    )
    
    # Verify Kimi is available
    $kimiPath = Get-Command kimi -ErrorAction SilentlyContinue
    if (-not $kimiPath) {
        throw "Kimi CLI not found. Please install Kimi Code CLI first."
    }
    
    # Verify prompt file exists
    if (-not (Test-Path $PromptFile)) {
        throw "Prompt file not found at $PromptFile"
    }
    
    Write-RalphLog "Starting Kimi invocation..." -Level "INFO"
    
    try {
        # Use file-based approach to avoid pipeline deadlocks
        # This is critical for long-running Kimi sessions
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "kimi"
        $psi.Arguments = "--print --final-message-only"
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = (Get-Location)
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        # Write prompt to stdin
        $promptContent = Get-Content $PromptFile -Raw -Encoding UTF8
        $process.StandardInput.Write($promptContent)
        $process.StandardInput.Close()
        
        # Read output asynchronously to prevent deadlocks
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        
        # Wait with timeout
        $timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
        $completed = $process.WaitForExit($timeout.TotalMilliseconds)
        
        if (-not $completed) {
            Write-RalphLog "Kimi process timed out after $TimeoutMinutes minutes" -Level "ERROR"
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Kimi invocation timed out"
        }
        
        $output = $outputTask.Result
        $errorOutput = $errorTask.Result
        
        if ($errorOutput) {
            Write-RalphLog "Kimi stderr: $errorOutput" -Level "DEBUG"
        }
        
        # Check for completion signal
        $isComplete = $output -like "*<promise>COMPLETE</promise>*"
        
        return @{
            Output = $output
            ExitCode = $process.ExitCode
            IsComplete = $isComplete
            Success = ($process.ExitCode -eq 0) -or $isComplete
        }
    }
    catch {
        Write-RalphLog "Kimi invocation failed: $_" -Level "ERROR"
        return @{
            Output = $_.Exception.Message
            ExitCode = -1
            IsComplete = $false
            Success = $false
        }
    }
}

# ==============================================================================
# VERIFIER EXECUTION (Pipeline Deadlock Safe)
# ==============================================================================

<#
.SYNOPSIS
    Executes a verifier command with timeout and deadlock prevention.
.DESCRIPTION
    Uses file-based output redirection to avoid PowerShell pipeline deadlocks.
    This is critical for long-running processes like Playwright tests.
.PARAMETER Verifier
    The verifier object containing command, expect, and timeout.
#>
function Test-RalphVerifier {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Verifier
    )
    
    $name = $Verifier.name
    $command = $Verifier.command
    $expect = $Verifier.expect
    
    # Default timeout: 20 minutes for Kimi sessions
    $timeout = if ($Verifier.timeout_seconds) { 
        $Verifier.timeout_seconds 
    } else { 
        $script:RalphConfig.DefaultVerifierTimeout 
    }
    
    Write-RalphLog "Running verifier: $name" -Level "INFO"
    Write-RalphLog "  Command: $command" -Level "DEBUG"
    
    $stdoutFile = $null
    $stderrFile = $null
    $scriptFile = $null
    
    try {
        # Create temp files in .ralph directory (avoids space issues in temp paths)
        $ralphDir = Join-Path (Get-Location) ".ralph"
        if (-not (Test-Path $ralphDir)) {
            New-Item -ItemType Directory -Force -Path $ralphDir | Out-Null
        }
        
        $guid = [Guid]::NewGuid().ToString().Substring(0, 8)
        $stdoutFile = Join-Path $ralphDir ".verifier-stdout-$guid.txt"
        $stderrFile = Join-Path $ralphDir ".verifier-stderr-$guid.txt"
        $scriptFile = Join-Path $ralphDir ".verifier-script-$guid.ps1"
        
        # Create wrapper script
        $scriptContent = @"
`$ErrorActionPreference = "Stop"
try {
    $command
    exit `$LASTEXITCODE
} catch {
    Write-Error "`$_"
    exit 1
}
"@
        [System.IO.File]::WriteAllText($scriptFile, $scriptContent, [System.Text.UTF8Encoding]::new($false))
        
        # Start process with file redirection (no pipeline)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`" > `"$stdoutFile`" 2> `"$stderrFile`""
        $psi.RedirectStandardOutput = $false  # Critical: don't redirect to PowerShell
        $psi.RedirectStandardError = $false
        $psi.UseShellExecute = $false
        $psi.WorkingDirectory = (Get-Location)
        $psi.CreateNoWindow = $true
        
        $process = [System.Diagnostics.Process]::Start($psi)
        $completed = $process.WaitForExit($timeout * 1000)
        
        if (-not $completed) {
            try { $process.Kill() } catch {}
            return @{ 
                Passed = $false; 
                Reason = "Timeout after ${timeout}s"; 
                Output = "" 
            }
        }
        
        # Capture exit code BEFORE disposing process
        $exitCode = $process.ExitCode
        $process.Dispose()
        
        # Read output from files (no deadlock risk)
        $stdout = if (Test-Path $stdoutFile) { 
            Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue 
        } else { "" }
        
        $stderr = if (Test-Path $stderrFile) { 
            Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue 
        } else { "" }
        
        # Check exit code
        $expectedExit = if ($expect.exit_code) { $expect.exit_code } else { 0 }
        if ($exitCode -ne $expectedExit) {
            return @{
                Passed = $false
                Reason = "Exit code $exitCode (expected $expectedExit)"
                Output = ($stdout + $stderr)
            }
        }
        
        # Check stdout contains
        if ($expect.stdout_contains) {
            if ($stdout -notlike "*$($expect.stdout_contains)*") {
                return @{
                    Passed = $false
                    Reason = "Output missing: $($expect.stdout_contains)"
                    Output = $stdout
                }
            }
        }
        
        return @{ Passed = $true; Output = $stdout }
    }
    catch {
        return @{ Passed = $false; Reason = "Exception: $_"; Output = "" }
    }
    finally {
        # Cleanup temp files
        if ($scriptFile -and (Test-Path $scriptFile)) { 
            Remove-Item $scriptFile -ErrorAction SilentlyContinue 
        }
        if ($stdoutFile -and (Test-Path $stdoutFile)) { 
            Remove-Item $stdoutFile -ErrorAction SilentlyContinue 
        }
        if ($stderrFile -and (Test-Path $stderrFile)) { 
            Remove-Item $stderrFile -ErrorAction SilentlyContinue 
        }
    }
}

# ==============================================================================
# STATUS DISPLAY
# ==============================================================================

<#
.SYNOPSIS
    Displays the current PRD status in a formatted table.
#>
function Show-RalphStatus {
    param(
        [Parameter()]
        [object]$Prd = $null,
        
        [Parameter()]
        [string]$PrdPath = $script:RalphConfig.PrdFile
    )
    
    if (-not $Prd) {
        $Prd = Get-RalphPrd -Path $PrdPath
    }
    
    Write-Host ""
    Write-Host "Current PRD Status:" -ForegroundColor Green
    Write-Host "===================" -ForegroundColor Green
    
    foreach ($story in $Prd.userStories) {
        $status = if ($story.passes -eq $true) { "✓ PASS" } else { "○ PENDING" }
        $color = if ($story.passes -eq $true) { "Green" } else { "Yellow" }
        Write-Host "[$status] $($story.id): $($story.title)" -ForegroundColor $color
    }
    
    $completed = ($Prd.userStories | Where-Object { $_.passes -eq $true }).Count
    $total = $Prd.userStories.Count
    Write-Host ""
    Write-Host "Progress: $completed / $total stories complete" -ForegroundColor Cyan
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

<#
.SYNOPSIS
    Runs the main Ralph loop.
.DESCRIPTION
    The core automation loop that iterates until all stories are complete
    or max iterations reached.
#>
function Start-RalphLoop {
    param(
        [Parameter()]
        [int]$MaxIterations = $script:RalphConfig.DefaultMaxIterations,
        
        [Parameter()]
        [string]$PrdPath = $script:RalphConfig.PrdFile,
        
        [Parameter()]
        [string]$PromptFile = $script:RalphConfig.PromptFile,
        
        [Parameter()]
        [switch]$AutoCommit = $script:RalphConfig.AutoCommit
    )
    
    # Pre-flight checks
    Write-RalphLog "Starting Ralph v$script:RalphVersion" -Level "INFO"
    Write-RalphLog "Max iterations: $MaxIterations" -Level "INFO"
    
    # Check prerequisites
    if (-not (Get-Command kimi -ErrorAction SilentlyContinue)) {
        throw "Kimi CLI not found. Please install Kimi Code CLI first."
    }
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git not found. Please install git."
    }
    
    if (-not (Test-Path $PrdPath)) {
        throw "PRD file not found at $PrdPath"
    }
    
    # Archive previous run if needed
    Invoke-RalphArchive -PrdPath $PrdPath
    
    # Track current branch
    Set-RalphBranchTracking -PrdPath $PrdPath
    
    # Initialize progress file
    Initialize-ProgressFile
    
    # Display initial status
    Show-RalphStatus -PrdPath $PrdPath
    
    $completedIterations = 0
    $allComplete = $false
    
    # Set up Ctrl+C handler (using Console event, NOT trap)
    $script:CancelRequested = $false
    $cancelHandler = {
        param([object]$sender, [System.ConsoleCancelEventArgs]$e)
        $e.Cancel = $true
        $script:CancelRequested = $true
        Write-RalphLog "Shutdown requested (Ctrl+C)" -Level "WARN"
    }
    [Console]::add_CancelKeyPress($cancelHandler)
    
    for ($i = 1; $i -le $MaxIterations -and -not $script:CancelRequested; $i++) {
        Write-Host ""
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "  Ralph Iteration $i of $MaxIterations" -ForegroundColor Cyan
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-RalphLog "Starting iteration $i" -Level "INFO"
        
        # Run Kimi
        $result = Invoke-RalphKimi -PromptFile $PromptFile
        
        # Display output
        if ($result.Output) {
            Write-Host $result.Output
        }
        
        $completedIterations++
        
        # Check for completion signal
        if ($result.IsComplete) {
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host "  RALPH COMPLETED ALL TASKS!" -ForegroundColor Green
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host ""
            Write-RalphLog "All tasks completed at iteration $i" -Level "SUCCESS"
            
            Show-RalphStatus -PrdPath $PrdPath
            return 0
        }
        
        # Check if all stories are actually complete
        $prd = Get-RalphPrd -Path $PrdPath
        if (Test-AllStoriesComplete -Prd $prd) {
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host "  ALL STORIES COMPLETE!" -ForegroundColor Green
            Write-Host "===============================================================" -ForegroundColor Green
            Write-Host ""
            Write-RalphLog "All stories marked complete at iteration $i" -Level "SUCCESS"
            return 0
        }
        
        Write-RalphLog "Iteration $i complete. Checking for more work..." -Level "INFO"
        Show-RalphStatus -Prd $prd
        
        # Delay between iterations
        if ($i -lt $MaxIterations -and -not $script:CancelRequested) {
            Start-Sleep -Seconds $script:RalphConfig.IterationDelaySeconds
        }
    }
    
    # Max iterations reached
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Yellow
    Write-Host "  RALPH REACHED MAX ITERATIONS" -ForegroundColor Yellow
    Write-Host "===============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-RalphLog "Max iterations ($MaxIterations) reached without completion" -Level "WARN"
    
    Show-RalphStatus -PrdPath $PrdPath
    
    return 1
}

# ==============================================================================
# EXPORTS
# ==============================================================================

# Export functions if used as a module (only when actually imported as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Write-RalphLog',
        'Read-RalphJson',
        'Write-RalphJson',
        'Get-RalphPrd',
        'Get-NextUserStory',
        'Update-StoryStatus',
        'Test-AllStoriesComplete',
        'Initialize-ProgressFile',
        'Add-ProgressEntry',
        'Invoke-RalphGitCommit',
        'Invoke-RalphArchive',
        'Set-RalphBranchTracking',
        'Invoke-RalphKimi',
        'Test-RalphVerifier',
        'Show-RalphStatus',
        'Start-RalphLoop',
        'Convert-PrdToBeads'
    )
}

Write-RalphLog "Ralph Core Module v$script:RalphVersion loaded" -Level "DEBUG" -NoFile
