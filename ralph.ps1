#!/usr/bin/env powershell
# Ralph for Kimi Code CLI - Unified Command Interface
# Version: 2.2.2 - PowerShell 5.1+ Compatible
#
# REQUIREMENT: PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
#
# Usage: ralph <command> [options]
#
# Commands:
#   init        Initialize a new Ralph workspace
#   doctor      Run diagnostics and fix common issues
#   bead        Create a new task bead
#   run         Run the main Ralph loop
#   daemon      Manage the background daemon (start/stop/status)
#   status      Show current status
#   logs        View recent logs

#requires -Version 5.1

param(
    [Parameter(Position = 0)]
    [string]$Command = "",
    
    [Parameter(Position = 1)]
    [string]$Argument = "",
    
    [Parameter()]
    [string]$Template = "",
    
    [Parameter()]
    [string]$Verifier = "",
    
    [Parameter()]
    [int]$Timeout = 1200,
    
    [Parameter()]
    [switch]$Json,
    
    [Parameter()]
    [switch]$Help,
    
    [Parameter()]
    [switch]$Version
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RalphVersion = "2.2.2"
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:ScriptDir) { $script:ScriptDir = Get-Location }

# Import core module
$coreScript = Join-Path $script:ScriptDir "ralph-core.ps1"
if (Test-Path $coreScript) {
    . $coreScript
}

# ==============================================================================
# OUTPUT HELPERS
# ==============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERR] $Message" -ForegroundColor Red
}

function Write-Action {
    param([string]$Message)
    Write-Host "[>] $Message" -ForegroundColor White
}

# ==============================================================================
# HELP
# ==============================================================================

function Show-Help {
    $helpText = @"
Ralph for Kimi Code CLI v$script:RalphVersion

USAGE:
    ralph <command> [options]

COMMANDS:
    init [path] [--template <name>]     Initialize a new Ralph workspace
    doctor [--fix]                      Run diagnostics and fix issues
    bead "<intent>" [--verifier <cmd>]  Create a new task bead
    run [iterations]                    Run Ralph loop (default: 10)
    daemon <start|stop|status|logs>     Manage background daemon
    status                              Show current status
    logs [lines]                        View recent logs (default: 20)

OPTIONS:
    --template <name>    Use a project template (init)
    --verifier <cmd>     Add a verifier command (bead)
    --timeout <seconds>  Set verifier timeout (default: 1200)
    --json               Output JSON (for automation)
    --help               Show this help
    --version            Show version

EXAMPLES:
    # Initialize workspace
    ralph init
    ralph init ./my-project --template node-react

    # Check and fix issues
    ralph doctor
    ralph doctor --fix

    # Create and run beads
    ralph bead "Add user login"
    ralph bead "Fix API bug" --verifier "npm test"
    ralph run
    ralph run 20

    # Manage daemon
    ralph daemon start
    ralph daemon status
    ralph daemon stop

    # View status and logs
    ralph status
    ralph logs
    ralph logs 50

TEMPLATES:
    node-react      React + TypeScript + Vite
    node-next       Next.js application
    python-flask    Python Flask API
    python-django   Python Django app
    go-cli          Go CLI tool
    generic         Minimal setup (default)

For more information: https://github.com/nicklynch10/ralph-simple
"@
    Write-Host $helpText
}

# ==============================================================================
# COMMAND: INIT
# ==============================================================================

function Invoke-InitCommand {
    param([string]$Path, [string]$TemplateName)
    
    $targetPath = if ($Path) { Resolve-Path $Path -ErrorAction SilentlyContinue } else { Get-Location }
    if (-not $targetPath) {
        $targetPath = Join-Path (Get-Location) $Path
        New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
    }
    
    Write-Info "Initializing Ralph workspace..."
    Write-Action "Target: $targetPath"
    
    # Check prerequisites
    Write-Action "Checking prerequisites..."
    
    $checks = @{
        PowerShell = $PSVersionTable.PSVersion.Major -ge 5
        Git = [bool](Get-Command git -ErrorAction SilentlyContinue)
        Kimi = [bool](Get-Command kimi -ErrorAction SilentlyContinue)
    }
    
    if (-not $checks.PowerShell) {
        Write-Error "PowerShell 5.1+ required"
        exit 1
    }
    
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"
    
    if (-not $checks.Git) {
        Write-Error "Git not found"
        Write-Action "Install: winget install Git.Git"
        exit 1
    }
    Write-Success "Git installed"
    
    if (-not $checks.Kimi) {
        Write-Error "Kimi CLI not found"
        Write-Action "Install: pip install kimi-cli"
        Write-Action "Auth: kimi config set api_key <your-key>"
        exit 1
    }
    Write-Success "Kimi CLI installed"
    
    # Initialize git if needed
    $gitDir = Join-Path $targetPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Action "Initializing git repository..."
        git -C $targetPath init
        Write-Success "Git repository initialized"
    }
    
    # Create .ralph directory structure
    $ralphDir = Join-Path $targetPath ".ralph"
    $dirs = @(
        $ralphDir,
        (Join-Path $ralphDir "logs"),
        (Join-Path $ralphDir "beads")
    )
    
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
    Write-Success "Created .ralph/ directory structure"
    
    # Create prd.json if it doesn't exist
    $prdFile = Join-Path $targetPath "prd.json"
    if (-not (Test-Path $prdFile)) {
        Write-Action "Creating prd.json..."
        
        $projectName = Split-Path $targetPath -Leaf
        $branchName = "ralph/$projectName"
        
        $prd = @{
            project = $projectName
            branchName = $branchName
            description = "Project initialized with Ralph"
            userStories = @(
                @{
                    id = "INIT-001"
                    title = "Setup project structure"
                    description = "Initialize the project with basic structure and configuration"
                    acceptanceCriteria = @(
                        "Project builds successfully"
                        "Tests pass"
                        "Code is committed"
                    )
                    priority = 1
                    passes = $false
                }
            )
        } | ConvertTo-Json -Depth 10
        
        [System.IO.File]::WriteAllText($prdFile, $prd, [System.Text.UTF8Encoding]::new($false))
        Write-Success "Created prd.json"
    }
    else {
        Write-Warning "prd.json already exists, skipping"
    }
    
    # Create KIMI.md if it doesn't exist
    $kimiFile = Join-Path $targetPath "KIMI.md"
    if (-not (Test-Path $kimiFile)) {
        Write-Action "Creating KIMI.md..."
        
        $kimiContent = @'
# Ralph Agent Instructions

You are an autonomous coding agent working on this project.

## Your Task

1. Read the PRD at `prd.json`
2. Pick the highest priority story where `passes: false`
3. Implement the story
4. Run tests to verify
5. Commit changes
6. Update PRD to mark story complete

## Project Structure

- Source code in current directory
- Tests should pass before committing
- Commit message format: `feat: [Story ID] - [Title]`

## Stop Condition

When all stories are complete, reply with:
```
<promise>COMPLETE</promise>
```
'@
        
        [System.IO.File]::WriteAllText($kimiFile, $kimiContent, [System.Text.UTF8Encoding]::new($false))
        Write-Success "Created KIMI.md"
    }
    else {
        Write-Warning "KIMI.md already exists, skipping"
    }
    
    # Create progress.txt if it doesn't exist
    $progressFile = Join-Path $targetPath "progress.txt"
    if (-not (Test-Path $progressFile)) {
        @"
# Ralph Progress Log
Started: $(Get-Date)
---

"@ | Set-Content $progressFile -Encoding UTF8
        Write-Success "Created progress.txt"
    }
    
    # Create .gitignore if it doesn't exist
    $gitignore = Join-Path $targetPath ".gitignore"
    if (-not (Test-Path $gitignore)) {
        @'
# Ralph
.ralph/logs/
.ralph/beads/*.json
archive/
.last-branch

# Dependencies
node_modules/
__pycache__/
*.pyc
vendor/

# Build outputs
dist/
build/
*.exe
*.dll

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
'@ | Set-Content $gitignore -Encoding UTF8
        Write-Success "Created .gitignore"
    }
    
    Write-Host ""
    Write-Success "Ralph workspace initialized!"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Action "1. Edit prd.json to define your user stories"
    Write-Action "2. Run: ralph doctor"
    Write-Action "3. Run: ralph run"
}

# ==============================================================================
# COMMAND: DOCTOR
# ==============================================================================

function Invoke-DoctorCommand {
    param([switch]$Fix)
    
    Write-Info "Ralph Diagnostics"
    Write-Host "=================" -ForegroundColor Cyan
    
    $issues = @()
    $fixes = @()
    
    # Check 1: PowerShell version
    Write-Host ""
    Write-Action "Checking PowerShell version..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Success "PowerShell $($PSVersionTable.PSVersion)"
    }
    else {
        Write-Error "PowerShell $($PSVersionTable.PSVersion) (7.0+ required)"
        Write-Action "Fix: winget install Microsoft.PowerShell"
        $issues += "PowerShell version"
    }
    
    # Check 2: Kimi CLI
    Write-Host ""
    Write-Action "Checking Kimi CLI..."
    $kimi = Get-Command kimi -ErrorAction SilentlyContinue
    if ($kimi) {
        $version = kimi --version 2>&1 | Select-Object -First 1
        Write-Success "Kimi CLI ($version)"
    }
    else {
        Write-Error "Kimi CLI not found"
        Write-Action "Fix: pip install kimi-cli"
        Write-Action "Fix: kimi config set api_key <your-key>"
        $issues += "Kimi CLI"
    }
    
    # Check 3: Git
    Write-Host ""
    Write-Action "Checking Git..."
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $version = git --version 2>&1
        Write-Success "$version"
        
        # Check git config
        $gitName = git config user.name 2>&1
        $gitEmail = git config user.email 2>&1
        
        if (-not $gitName -or -not $gitEmail) {
            Write-Warning "Git user not configured"
            Write-Action "Fix: git config --global user.name 'Your Name'"
            Write-Action "Fix: git config --global user.email 'you@example.com'"
            if ($Fix) {
                Write-Action "Applying fix..."
                git config user.name "Ralph Agent" 2>$null
                git config user.email "ralph@localhost" 2>$null
                Write-Success "Git user configured"
            }
            else {
                $fixes += "Git config"
            }
        }
    }
    else {
        Write-Error "Git not found"
        Write-Action "Fix: winget install Git.Git"
        $issues += "Git"
    }
    
    # Check 4: Workspace structure
    Write-Host ""
    Write-Action "Checking workspace structure..."
    
    $prdFile = Join-Path (Get-Location) "prd.json"
    $kimiFile = Join-Path (Get-Location) "KIMI.md"
    $ralphDir = Join-Path (Get-Location) ".ralph"
    
    if (-not (Test-Path $prdFile)) {
        Write-Error "prd.json not found"
        Write-Action "Fix: ralph init"
        $issues += "PRD file"
    }
    else {
        Write-Success "prd.json exists"
        
        # Validate JSON
        try {
            $content = Get-Content $prdFile -Raw -Encoding UTF8
            if ($content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
            $prd = $content | ConvertFrom-Json
            
            if ($prd.userStories) {
                $total = $prd.userStories.Count
                $completed = ($prd.userStories | Where-Object { $_.passes -eq $true }).Count
                Write-Success "PRD valid ($completed/$total stories complete)"
            }
            else {
                Write-Warning "PRD missing userStories"
            }
        }
        catch {
            Write-Error "prd.json is invalid JSON"
            Write-Action "Fix: Check file encoding and syntax"
            $issues += "PRD JSON"
        }
    }
    
    if (-not (Test-Path $kimiFile)) {
        Write-Error "KIMI.md not found"
        Write-Action "Fix: ralph init"
        $issues += "KIMI.md"
    }
    else {
        Write-Success "KIMI.md exists"
    }
    
    if (-not (Test-Path $ralphDir)) {
        Write-Warning ".ralph/ directory not found"
        Write-Action "Fix: ralph init"
        if ($Fix) {
            New-Item -ItemType Directory -Force -Path $ralphDir | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $ralphDir "logs") | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $ralphDir "beads") | Out-Null
            Write-Success "Created .ralph/ directory"
        }
        else {
            $fixes += ".ralph directory"
        }
    }
    else {
        Write-Success ".ralph/ directory exists"
    }
    
    # Check 5: Daemon status
    Write-Host ""
    Write-Action "Checking daemon status..."
    $pidFile = Join-Path $ralphDir "daemon.pid"
    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -Raw
        $process = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
        if ($process) {
            Write-Success "Daemon running (PID: $daemonPid)"
        }
        else {
            Write-Warning "Daemon PID file exists but process not running"
            if ($Fix) {
                Remove-Item $pidFile -Force
                Write-Success "Cleaned up stale PID file"
            }
            else {
                $fixes += "Stale PID file"
            }
        }
    }
    else {
        Write-Info "Daemon not running"
    }
    
    # Summary
    Write-Host ""
    Write-Host "=================" -ForegroundColor Cyan
    
    if ($issues.Count -eq 0 -and $fixes.Count -eq 0) {
        Write-Success "All checks passed! Ralph is ready."
        exit 0
    }
    elseif ($issues.Count -gt 0) {
        Write-Error "Found $($issues.Count) critical issue(s)"
        Write-Action "Run 'ralph doctor --fix' to attempt automatic fixes"
        exit 1
    }
    else {
        Write-Warning "Found $($fixes.Count) fixable issue(s)"
        Write-Action "Run 'ralph doctor --fix' to apply fixes"
        exit 2
    }
}

# ==============================================================================
# COMMAND: BEAD
# ==============================================================================

function Invoke-BeadCommand {
    param(
        [string]$Intent,
        [string]$Verifier,
        [int]$Timeout
    )
    
    if (-not $Intent) {
        Write-Error "Bead intent required"
        Write-Action "Usage: ralph bead `"Your task description`""
        exit 1
    }
    
    Write-Info "Creating new bead..."
    Write-Action "Intent: $Intent"
    
    # Ensure .ralph/beads directory exists
    $beadsDir = Join-Path (Get-Location) ".ralph\beads"
    if (-not (Test-Path $beadsDir)) {
        New-Item -ItemType Directory -Force -Path $beadsDir | Out-Null
    }
    
    # Generate bead ID
    $random = Get-Random -Minimum 1000 -Maximum 9999
    $beadId = "ralph-$random"
    
    # Build verifiers array
    $verifiers = @()
    
    # Auto-detect project type and add default verifiers
    if (Test-Path "package.json") {
        $verifiers += @{
            name = "Build succeeds"
            command = "npm run build"
            expect = @{ exit_code = 0 }
            timeout_seconds = 120
        }
        $verifiers += @{
            name = "Tests pass"
            command = "npm test"
            expect = @{ exit_code = 0 }
            timeout_seconds = 120
        }
    }
    elseif (Test-Path "go.mod") {
        $verifiers += @{
            name = "Build succeeds"
            command = "go build ./..."
            expect = @{ exit_code = 0 }
            timeout_seconds = 60
        }
        $verifiers += @{
            name = "Tests pass"
            command = "go test ./..."
            expect = @{ exit_code = 0 }
            timeout_seconds = 120
        }
    }
    elseif ((Test-Path "requirements.txt") -or (Test-Path "pyproject.toml")) {
        $verifiers += @{
            name = "Python syntax check"
            command = "python -m py_compile (Get-ChildItem *.py | Select-Object -First 1).FullName"
            expect = @{ exit_code = 0 }
            timeout_seconds = 30
        }
    }
    
    # Add custom verifier if provided
    if ($Verifier) {
        $verifiers += @{
            name = "Custom verifier"
            command = $Verifier
            expect = @{ exit_code = 0 }
            timeout_seconds = $Timeout
        }
    }
    
    # Create bead object
    $now = Get-Date -Format "o"
    $bead = @{
        id = $beadId
        title = $Intent
        intent = $Intent
        status = "pending"
        created_at = $now
        updated_at = $now
        priority = 2
        lane = "feature"
        dod = @{
            verifiers = $verifiers
            evidence_required = $true
        }
        constraints = @{
            max_iterations = 10
            time_budget_minutes = 60
            allowed_dirs = @()
        }
        ralph_meta = @{
            attempt_count = 0
            retry_backoff_seconds = 30
        }
    }
    
    # Save bead
    $beadFile = Join-Path $beadsDir "$beadId.json"
    $json = $bead | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($beadFile, $json, [System.Text.UTF8Encoding]::new($false))
    
    Write-Success "Created bead: $beadId"
    Write-Info "Verifiers: $($verifiers.Count)"
    Write-Action "Run: ralph run"
}

# ==============================================================================
# COMMAND: DAEMON
# ==============================================================================

function Invoke-DaemonCommand {
    param([string]$Action)
    
    $daemonScript = Join-Path $script:ScriptDir "ralph-daemon.ps1"
    
    switch ($Action.ToLower()) {
        "start" {
            Write-Info "Starting Ralph daemon..."
            if (Test-Path $daemonScript) {
                Start-Process powershell -ArgumentList "-WindowStyle Hidden -File `"$daemonScript`"" -WindowStyle Hidden
                Start-Sleep -Seconds 2
                Write-Success "Daemon started"
                Write-Action "Check status: ralph daemon status"
            }
            else {
                Write-Error "Daemon script not found"
                exit 1
            }
        }
        "stop" {
            Write-Info "Stopping Ralph daemon..."
            $pidFile = Join-Path (Get-Location) ".ralph\daemon.pid"
            if (Test-Path $pidFile) {
                $daemonPid = Get-Content $pidFile -Raw
                Stop-Process -Id $daemonPid -Force -ErrorAction SilentlyContinue
                Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
                Write-Success "Daemon stopped"
            }
            else {
                Write-Warning "Daemon not running"
            }
        }
        "status" {
            $pidFile = Join-Path (Get-Location) ".ralph\daemon.pid"
            if (Test-Path $pidFile) {
                $daemonPid = Get-Content $pidFile -Raw
                $process = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Success "Daemon running (PID: $daemonPid)"
                }
                else {
                    Write-Warning "Daemon PID file exists but process not running"
                }
            }
            else {
                Write-Info "Daemon not running"
            }
        }
        "logs" {
            $logFile = Join-Path (Get-Location) ".ralph\logs\ralph-daemon.log"
            if (Test-Path $logFile) {
                Get-Content $logFile -Tail 20
            }
            else {
                Write-Warning "No daemon log found"
            }
        }
        default {
            Write-Error "Unknown daemon action: $Action"
            Write-Action "Usage: ralph daemon <start|stop|status|logs>"
            exit 1
        }
    }
}

# ==============================================================================
# COMMAND: STATUS
# ==============================================================================

function Invoke-StatusCommand {
    param([switch]$Json)
    
    $workspace = Get-Location
    $prdFile = Join-Path $workspace "prd.json"
    $ralphDir = Join-Path $workspace ".ralph"
    
    if ($Json) {
        # Output JSON for automation
        $status = @{
            version = $script:RalphVersion
            workspace = $workspace
            prd_exists = Test-Path $prdFile
            ralph_exists = Test-Path $ralphDir
        }
        
        if (Test-Path $prdFile) {
            $content = Get-Content $prdFile -Raw -Encoding UTF8
            if ($content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
            $prd = $content | ConvertFrom-Json
            $status.total_stories = $prd.userStories.Count
            $status.completed_stories = ($prd.userStories | Where-Object { $_.passes -eq $true }).Count
        }
        
        $status | ConvertTo-Json
        return
    }
    
    Write-Info "Ralph Status"
    Write-Host "============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Workspace: $workspace" -ForegroundColor Gray
    Write-Host "Version: $script:RalphVersion" -ForegroundColor Gray
    Write-Host ""
    
    # PRD status
    if (Test-Path $prdFile) {
        $content = Get-Content $prdFile -Raw -Encoding UTF8
        if ($content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
        $prd = $content | ConvertFrom-Json
        
        Write-Host "PRD: $($prd.project)" -ForegroundColor White
        Write-Host "Branch: $($prd.branchName)" -ForegroundColor Gray
        Write-Host ""
        
        foreach ($story in $prd.userStories) {
            $icon = if ($story.passes) { "[PASS]" } else { "[PEND]" }
            $color = if ($story.passes) { "Green" } else { "Yellow" }
            Write-Host "  $icon $($story.id): $($story.title)" -ForegroundColor $color
        }
        
        $completed = ($prd.userStories | Where-Object { $_.passes -eq $true }).Count
        $total = $prd.userStories.Count
        Write-Host ""
        Write-Host "Progress: $completed / $total stories" -ForegroundColor Cyan
    }
    else {
        Write-Warning "No prd.json found"
        Write-Action "Run: ralph init"
    }
    
    # Daemon status
    Write-Host ""
    $pidFile = Join-Path $ralphDir "daemon.pid"
    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile -Raw
        $process = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
        if ($process) {
            Write-Success "Daemon running (PID: $daemonPid)"
        }
    }
}

# ==============================================================================
# COMMAND: LOGS
# ==============================================================================

function Invoke-LogsCommand {
    param([int]$Lines = 20)
    
    $logFile = Join-Path (Get-Location) ".ralph\logs\ralph-daemon.log"
    
    if (Test-Path $logFile) {
        Get-Content $logFile -Tail $Lines | ForEach-Object {
            # Color-code log entries
            if ($_ -match "\[ERROR\]") {
                Write-Host $_ -ForegroundColor Red
            }
            elseif ($_ -match "\[WARN\]") {
                Write-Host $_ -ForegroundColor Yellow
            }
            elseif ($_ -match "\[SUCCESS\]") {
                Write-Host $_ -ForegroundColor Green
            }
            else {
                Write-Host $_ -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Warning "No log file found"
    }
}

# ==============================================================================
# COMMAND: RUN (Main Loop)
# ==============================================================================

function Invoke-RunCommand {
    param([int]$Iterations = 10)
    
    # Pre-flight checks
    $prdFile = Join-Path (Get-Location) "prd.json"
    $promptFile = Join-Path (Get-Location) "KIMI.md"
    
    if (-not (Test-Path $prdFile)) {
        Write-Error "prd.json not found"
        Write-Action "Run: ralph init"
        exit 1
    }
    
    if (-not (Test-Path $promptFile)) {
        Write-Error "KIMI.md not found"
        Write-Action "Run: ralph init"
        exit 1
    }
    
    # Check prerequisites
    if (-not (Get-Command kimi -ErrorAction SilentlyContinue)) {
        Write-Error "Kimi CLI not found"
        Write-Action "Install: pip install kimi-cli"
        exit 1
    }
    
    # Run the loop
    Write-Info "Starting Ralph loop ($Iterations iterations)"
    Write-Host ""
    
    $cancelRequested = $false
    $cancelHandler = {
        param([object]$sender, [System.ConsoleCancelEventArgs]$e)
        $e.Cancel = $true
        $cancelRequested = $true
        Write-Warning "Interrupted by user"
    }
    [Console]::add_CancelKeyPress($cancelHandler)
    
    for ($i = 1; $i -le $Iterations -and -not $cancelRequested; $i++) {
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Iteration $i of $Iterations" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        try {
            $output = Get-Content $promptFile -Raw -Encoding UTF8 | kimi --print --final-message-only 2>&1
            
            if ($output) {
                $outputString = $output -join "`n"
                Write-Host $outputString
            }
            
            # Check for completion
            $outputString = $output -join "`n"
            if ($outputString -like "*<promise>COMPLETE</promise>*") {
                Write-Host ""
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                Write-Host "  ALL TASKS COMPLETE!" -ForegroundColor Green
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                exit 0
            }
            
            # Check PRD for completion
            $content = Get-Content $prdFile -Raw -Encoding UTF8
            if ($content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
            $prd = $content | ConvertFrom-Json
            
            $incomplete = $prd.userStories | Where-Object { $_.passes -ne $true }
            if ($incomplete.Count -eq 0) {
                Write-Host ""
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                Write-Host "  ALL STORIES COMPLETE!" -ForegroundColor Green
                Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
                exit 0
            }
        }
        catch {
            Write-Error "Iteration $i failed: $_"
        }
        
        if ($i -lt $Iterations -and -not $cancelRequested) {
            Start-Sleep -Seconds 2
        }
    }
    
    if ($cancelRequested) {
        Write-Warning "Stopped by user"
        exit 130
    }
    
    Write-Warning "Max iterations reached"
    exit 1
}

# ==============================================================================
# MAIN DISPATCH
# ==============================================================================

if ($Version) {
    Write-Host "Ralph v$script:RalphVersion"
    exit 0
}

if ($Help -or -not $Command) {
    Show-Help
    exit 0
}

switch ($Command.ToLower()) {
    "init" {
        Invoke-InitCommand -Path $Argument -TemplateName $Template
    }
    "doctor" {
        Invoke-DoctorCommand -Fix:$Fix
    }
    "bead" {
        Invoke-BeadCommand -Intent $Argument -Verifier $Verifier -Timeout $Timeout
    }
    "run" {
        $iterations = if ($Argument -match '^\d+$') { [int]$Argument } else { 10 }
        Invoke-RunCommand -Iterations $iterations
    }
    "daemon" {
        Invoke-DaemonCommand -Action $Argument
    }
    "status" {
        Invoke-StatusCommand -Json:$Json
    }
    "logs" {
        $lines = if ($Argument -match '^\d+$') { [int]$Argument } else { 20 }
        Invoke-LogsCommand -Lines $lines
    }
    default {
        Write-Error "Unknown command: $Command"
        Write-Action "Run 'ralph --help' for usage"
        exit 1
    }
}
