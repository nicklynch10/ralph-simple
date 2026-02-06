# Ralph - 24/7 Autonomous CI/CD Agent

**Version**: 2.2.2  
**Status**: Production-ready  
**Requirement**: PowerShell 7.0+ (Install: `winget install Microsoft.PowerShell`)

---

## ⚠️ CRITICAL: Daemon-First Architecture

**Ralph is designed to run continuously as a daemon, NOT as a cron job or scheduled task.**

### The Wrong Way (Don't Do This)

```bash
# ❌ WRONG: Cron job approach
crontab -e
*/5 * * * * /path/to/ralph.sh

# ❌ WRONG: Scheduled task with intervals
# Task Scheduler: Run every 5 minutes

# ❌ WRONG: Multiple manual starts
./ralph.ps1 run
./ralph.ps1 run  # Second instance conflicts!
```

**Why this is wrong:**
- Ralph has built-in polling (30s interval)
- Multiple instances conflict over beads
- No state awareness between runs
- Defeats exponential backoff recovery
- Wastes resources on start/stop

### The Right Way (Do This)

```powershell
# ✅ RIGHT: Start daemon once, runs forever
.\ralph.ps1 daemon start

# That's it. Ralph handles:
# - Polling for new beads
# - Processing each bead
# - Retry logic with backoff
# - Recovery from failures
# - Running until all work is done
```

---

## Project Overview

Ralph is a **continuous 24/7 CI/CD agent** that processes work items (beads) until all PRD requirements are complete. It manages its own scheduling, retry logic, and recovery.

**Core Philosophy**: Start once, run forever. Like a CI/CD pipeline that never sleeps.

**Key Design Principles**:
- **Daemon-first**: Designed for continuous operation
- **Self-healing**: Auto-restart on failure with exponential backoff
- **Process isolation**: Each bead in separate process
- **State-aware**: Tracks progress in PRD and bead files
- **Robust, not fragile**: Handles malformed data, crashes, concurrent access

---

## Architecture

### File Structure

```
.
├── ralph.ps1              # Main entry point (dispatcher)
├── ralph-core.ps1         # Core functions module (reusable)
├── ralph-daemon.ps1       # Production daemon for 24/7 operation
├── ralph-health.ps1       # Health monitoring and diagnostics
├── install-service.ps1    # Windows Service installer (NSSM)
├── ralph.sh               # Linux/Mac version
├── KIMI.md                # Prompt template for Kimi Code CLI
├── prd.json.example       # Example PRD format
├── test-plan.json.example # Example test plan format
├── README.md              # User documentation
├── AGENTS.md              # This file
├── IMPROVEMENTS.md        # Planned improvements
└── skills/                # Kimi skills
    ├── prd/
    │   └── SKILL.md
    └── ralph/
        └── SKILL.md
```

### Key Components

#### 1. ralph.ps1 (Main Entry Point)
- **Purpose**: Dispatcher that routes to appropriate sub-command
- **Usage**: `.\ralph.ps1 [iterations] [-Daemon] [-Health] [-Status]`
- **Design**: Thin wrapper that delegates to specialized scripts

#### 2. ralph-core.ps1 (Core Module)
- **Purpose**: Reusable functions for JSON, logging, git, PRD operations
- **Usage**: Import with `. ./ralph-core.ps1` or `Import-Module`
- **Key Functions**:
  - `Read-RalphJson` / `Write-RalphJson` - UTF-8 BOM safe JSON
  - `Write-RalphLog` - Centralized logging with file output
  - `Get-RalphPrd` / `Update-StoryStatus` - PRD operations
  - `Invoke-RalphGitCommit` - Automated git commits
  - `Invoke-RalphKimi` - Kimi CLI invocation with timeout
  - `Test-RalphVerifier` - Verifier execution with deadlock prevention
  - `Start-RalphLoop` - Main automation loop

#### 3. ralph-daemon.ps1 (Production Daemon)
- **Purpose**: 24/7 autonomous operation with process isolation
- **Key Features**:
  - Separate process per bead (2-hour timeout)
  - Automatic stuck bead detection (>2 hours)
  - Log rotation (10MB max, 5 files)
  - Windows Task Scheduler integration
  - Retry logic (max 3 attempts per bead)
  - **Auto-restart with exponential backoff** (daemon-level recovery)
  - **Atomic bead writes** with backup/restore
  - **Full bead schema validation** on load/save

#### 4. ralph-health.ps1 (Health Monitoring)
- **Purpose**: Diagnostics, troubleshooting, maintenance
- **Usage**: `.\ralph.ps1 -Health` or `.\ralph.ps1 -Status`
- **Features**:
  - Prerequisite checks (Kimi, Git, PowerShell 7)
  - PRD validation
  - Daemon status
  - Bead status with stuck detection
  - Auto-fix mode (`-Fix`)

#### 5. install-service.ps1 (Windows Service)
- **Purpose**: Install Ralph as a true Windows Service using NSSM
- **Advantages over Task Scheduler**:
  - Runs as SYSTEM (before user login)
  - Automatic restart on failure
  - Proper service management (start/stop/restart)
  - Logs to Windows Event Log

---

## Critical Implementation Details

### PowerShell 7 Requirement

**Ralph v2.2.2 requires PowerShell 7.0+**. This provides:
- Better cross-platform compatibility
- Improved performance
- Modern language features
- Consistent behavior across systems

**Install PowerShell 7**:
```powershell
winget install Microsoft.PowerShell
```

### UTF-8 BOM Handling

**Problem**: PowerShell's `ConvertFrom-Json` fails on files with UTF-8 BOM.

**Solution**: Always use `-Raw -Encoding UTF8` and strip BOM:

```powershell
$content = Get-Content -Path $file -Raw -Encoding UTF8
if ($content.Length -gt 0 -and $content[0] -eq "`u{feff}") {
    $content = $content.Substring(1)
}
$json = $content | ConvertFrom-Json
```

**Writing JSON (no BOM)**:
```powershell
$json = $data | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
```

### Ctrl+C Handling

**Problem**: `trap` catches ALL exceptions, not just Ctrl+C.

**Solution**: Use `Console.CancelKeyPress` event:

```powershell
$cancelHandler = {
    param([object]$sender, [System.ConsoleCancelEventArgs]$e)
    $e.Cancel = $true
    $script:CancelRequested = $true
    Write-RalphLog "Shutdown requested" -Level "WARN"
}
[Console]::add_CancelKeyPress($cancelHandler)
```

### Process Isolation (Daemon)

**Why**: Prevents memory leaks, file handle exhaustion, cascading failures.

**Implementation**:
```powershell
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "pwsh.exe"  # PowerShell 7
$psi.Arguments = "-File ralph.ps1 -MaxIterations 1"
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.UseShellExecute = $true  # Required for WindowStyle

$process = [System.Diagnostics.Process]::Start($psi)
$completed = $process.WaitForExit($timeoutMs)

if (-not $completed) {
    Stop-Process -Id $process.Id -Force
}
```

### Pipeline Deadlock Prevention

**Problem**: PowerShell pipeline buffer fills and blocks child processes.

**Solution**: Use file-based redirection:

```powershell
# BAD - Can deadlock
$output = & kimi --print 2>&1

# GOOD - File based
$stdoutFile = ".ralph/.verifier-stdout-$guid.txt"
$stderrFile = ".ralph/.verifier-stderr-$guid.txt"

$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
$process = [System.Diagnostics.Process]::Start($psi)
$process.WaitForExit($timeout * 1000)

$stdout = Get-Content $stdoutFile -Raw
```

### Verifier Timeout

**Default timeout increased to 20 minutes** for Kimi sessions:

```powershell
$script:RalphConfig.DefaultVerifierTimeout = 1200  # 20 minutes
```

This accommodates:
- Long Kimi invocations
- Complex implementations
- Context window building time

---

## Bead Schema (v2.2.2+)

Beads are the core work units in Ralph. Each bead is a JSON file with a complete schema.

### Core Fields

```json
{
  "id": "US-001",
  "type": "prd-story",
  "status": "pending",
  "priority": 1,
  "title": "Story title",
  "intent": "What to implement",
  "description": "Detailed description",
  "created_at": "2026-02-06T12:00:00Z",
  "updated_at": "2026-02-06T12:00:00Z"
}
```

### PRD Linkage

```json
{
  "prd_reference": {
    "story_id": "US-001",
    "project": "MyApp",
    "branch_name": "ralph/feature-branch"
  }
}
```

### Definition of Done (dod)

```json
{
  "dod": {
    "verifiers": [
      {
        "name": "Tests pass",
        "command": "npm test",
        "expect": { "exit_code": 0 },
        "timeout_seconds": 120
      }
    ],
    "evidence_required": true,
    "acceptance_criteria": ["Criterion 1", "Criterion 2"]
  }
}
```

### Constraints

```json
{
  "constraints": {
    "max_iterations": 10,
    "time_budget_minutes": 60,
    "allowed_dirs": [],
    "blocked_dirs": [".git", ".ralph", "node_modules"]
  }
}
```

### Ralph Metadata (ralph_meta)

This section is for internal tracking and is automatically managed:

```json
{
  "ralph_meta": {
    "attempt_count": 0,
    "timeout_count": 0,
    "stuck_count": 0,
    "last_attempt": null,
    "last_error": null,
    "status_detail": null,
    "last_updated": "2026-02-06T12:00:00Z",
    "created_by": "Convert-PrdToBeads",
    "version": "2.2.2"
  }
}
```

### Creating Beads Manually

If creating beads manually (not via `Convert-PrdToBeads`), you MUST include at minimum:

```json
{
  "id": "CUSTOM-001",
  "type": "prd-story",
  "status": "pending",
  "priority": 1,
  "title": "Your task title",
  "intent": "What to do",
  "created_at": "2026-02-06T12:00:00Z",
  "updated_at": "2026-02-06T12:00:00Z",
  "ralph_meta": {
    "attempt_count": 0,
    "timeout_count": 0,
    "stuck_count": 0
  }
}
```

The daemon's `Initialize-BeadSchema` function will populate missing fields automatically.

---

## Testing Changes

### Manual Testing Checklist

When modifying Ralph scripts:

1. **PowerShell 7 Compatibility**
   ```powershell
   # Test on PowerShell 7
   pwsh -File ralph.ps1 1
   ```

2. **UTF-8 BOM Handling**
   ```powershell
   # Create BOM file and test reading
   $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"test": true}')
   [System.IO.File]::WriteAllBytes("test-bom.json", [byte[]](0xEF, 0xBB, 0xBF) + $bytes)
   $result = Read-RalphJson -Path "test-bom.json"
   ```

3. **Ctrl+C Handling**
   - Start Ralph
   - Press Ctrl+C
   - Verify graceful shutdown message
   - Verify no false triggers on Kimi errors

4. **Daemon Mode**
   ```powershell
   # Start daemon
   .\ralph.ps1 -Daemon
   
   # Check it's running
   .\ralph.ps1 -Status
   
   # Stop daemon
   Get-Process *ralph* | Stop-Process
   ```

5. **Health Check**
   ```powershell
   .\ralph.ps1 -Health
   # Should show all green
   ```

### Integration Testing

Create a test PRD and run through full workflow:

```powershell
# Setup test
$testDir = "C:\Temp\RalphTest"
New-Item -ItemType Directory -Force -Path $testDir
Set-Location $testDir
git init

# Copy Ralph files
copy C:\path\to\ralph\*.ps1 .
copy C:\path\to\ralph\KIMI.md .

# Create minimal PRD
@'
{
  "project": "Test",
  "branchName": "ralph/test",
  "userStories": [
    {
      "id": "TEST-001",
      "title": "Test story",
      "description": "A test story",
      "priority": 1,
      "passes": false
    }
  ]
}
'@ | Set-Content prd.json

# Run test
.\ralph.ps1 1
```

---

## Code Style

### PowerShell Conventions

1. **Use full parameter names** (not aliases)
   ```powershell
   # Good
   Get-Content -Path $file -Raw
   
   # Bad
   gc $file -r
   ```

2. **Explicit error handling**
   ```powershell
   try {
       $result = Do-Something
   }
   catch {
       Write-RalphLog "Error: $_" -Level "ERROR"
       return $false
   }
   ```

3. **Consistent logging**
   ```powershell
   Write-RalphLog "Starting operation" -Level "INFO"
   Write-RalphLog "Warning condition" -Level "WARN"
   Write-RalphLog "Operation complete" -Level "SUCCESS"
   ```

4. **Function documentation**
   ```powershell
   <#
   .SYNOPSIS
       Brief description
   .DESCRIPTION
       Detailed description
   .PARAMETER Name
       Parameter description
   #>
   function My-Function {
       param([string]$Name)
       # ...
   }
   ```

### File Organization

1. **Shebang** (for direct execution)
   ```powershell
   #!/usr/bin/env pwsh
   #requires -Version 7.0
   ```

2. **Parameter block** at top
   ```powershell
   param(
       [Parameter(Mandatory = $true)]
       [string]$RequiredParam,
       
       [Parameter()]
       [int]$OptionalParam = 10
   )
   ```

3. **Configuration section**
   ```powershell
   # ==============================================================================
   # CONFIGURATION
   # ==============================================================================
   ```

4. **Function sections**
   ```powershell
   # ==============================================================================
   # LOGGING
   # ==============================================================================
   ```

---

## Common Tasks

### Adding a New Quality Check

1. Add check to `KIMI.md` in "Quality Requirements" section
2. Add verification logic in agent instructions
3. Update `test-plan.json.example` if relevant

### Modifying the Progress Format

Update both:
1. `KIMI.md` - Agent instructions for progress format
2. `ralph-core.ps1` - `Add-ProgressEntry` function

### Adding a New Running Mode

1. Add parameter to `ralph.ps1` param block
2. Add dispatch logic in main section
3. Create new script (e.g., `ralph-newmode.ps1`)
4. Update `README.md` with documentation

### Fixing Encoding Issues

If users report UTF-8/BOM issues:

1. Verify `Read-RalphJson` handles BOM correctly
2. Check all file reads use `-Encoding UTF8`
3. Ensure JSON writes use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`
4. Test with files created by different editors

---

## Known Limitations

1. **Windows Focused** - Daemon uses Windows-specific features
   - Linux/Mac use `ralph.sh` with different implementation
   - Cross-platform PowerShell Core support for daemon planned for v3.0

2. **Single Workspace** - One daemon instance per project
   - Multiple projects need separate daemon instances
   - No centralized multi-project management

3. **No Web UI** - All monitoring via command line
   - Use `ralph-health.ps1` for status
   - Logs are text files

4. **Manual PRD Creation** - No built-in PRD editor
   - Use skills (`/skill:prd`) to generate PRDs
   - Edit JSON manually for changes

---

## Future Improvements

See `IMPROVEMENTS.md` for planned enhancements.

Key areas:
- Web dashboard for monitoring
- Multi-project support
- PRD editor/validator
- Better Windows Service integration
- Cross-platform daemon (Python?)

---

## Debugging Tips

### Enable Verbose Logging

```powershell
$VerbosePreference = "Continue"
.\ralph.ps1
```

### Check All Log Files

```powershell
Get-ChildItem .ralph\logs\*.log | ForEach-Object {
    Write-Host "`n=== $($_.Name) ===" -ForegroundColor Cyan
    Get-Content $_.FullName -Tail 20
}
```

### Monitor Daemon in Real-Time

```powershell
# Terminal 1: Run daemon
.\ralph.ps1 -Daemon

# Terminal 2: Watch logs
Get-Content .ralph\logs\ralph-daemon.log -Wait
```

### Test Individual Functions

```powershell
# Import core module
. ./ralph-core.ps1

# Test JSON handling
$test = @{ test = $true; nested = @{ array = @(1, 2, 3) } }
Write-RalphJson -Path "test.json" -Data $test
$result = Read-RalphJson -Path "test.json"
$result | ConvertTo-Json -Depth 5
```

---

## Release Checklist

Before releasing a new version:

- [ ] Update version number in all scripts
- [ ] Test on clean Windows VM with PowerShell 7
- [ ] Test on Windows 10 and Windows 11
- [ ] Test Linux/Mac version (`ralph.sh`)
- [ ] Verify all examples in README work
- [ ] Update CHANGELOG.md
- [ ] Tag release in git

---

## Support

For issues or questions:
1. Check `README.md` troubleshooting section
2. Run `.\ralph.ps1 -Health` for diagnostics
3. Review logs in `.ralph\logs\`
4. Open issue on GitHub with log output
